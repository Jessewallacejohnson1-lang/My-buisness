#!/usr/bin/env python3
"""
importance.py: how many of the town would make a point of going to an Event, 1 (routine business) to 5 (the whole town
turns out), from two helpers that rate it apart (BP app feed-learns 04; Jesse, 2026-11-22 and 2026-11-25: both Sonnet).

The level goes in club_events.importance: the Town feed's score, the top five, what is live, the board pages. When the
helpers disagree the lower level wins, so a 4 or 5 needs both. Held on top of that, whatever they say: a weekly Event is a 3
at most (town-feed 74), and a City's Event is a 1 only when it is a meeting (from a City, 1 hides it as one). An Event with
no level yet counts as 3 in the feed.

`prepare` lays out the upcoming Events with no level, the same thing on several dates once, in batches of BATCH for two
helpers each (sources/models/importance.md). `keep`, a step of `morning.py finish`, saves the levels both answered; one either
left out waits for tomorrow. A level once saved is never written again here.

  python3 sources/scripts/importance.py prepare
  python3 sources/scripts/importance.py keep --dry-run
  python3 sources/scripts/importance.py --selftest
"""

import argparse
import collections
import json
import re
import shutil
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402
import run  # noqa: E402
import write_judged  # noqa: E402
from db import DbError  # noqa: E402

BATCH = 40
SAVE = 100  # Events to a save: their ids are in its address
LEVELS = (1, 2, 3, 4, 5)
WEEKLY_MOST, CITY_LEAST = 3, 2
READINGS = ("importance.jsonl", "importance-2.jsonl")  # the two helpers' answers, in the run's folder
MEETING = re.compile(r"\b(council|board|commission|committee|authority|meeting|work session|hearing)\b", re.I)


def series_key(r):
    """An Event's series as the Town feed keys it: its title and who puts it on."""
    return (" ".join((r.get("title") or "").split()).lower(),
            r.get("club_id") or r.get("source_name") or r.get("submitted_by") or "")


def is_weekly(days):
    """A series that comes back every week (a weekly class, bingo night): 3 or more dates over 3 weeks or more, most of
    them a week or less apart. A show's run of nights spans less; a monthly meeting's dates are further apart."""
    days = sorted(set(days))
    if len(days) < 3 or (days[-1] - days[0]).days < 21:
        return False
    gaps = sorted((b - a).days for a, b in zip(days, days[1:]))
    return gaps[len(gaps) // 2] <= 9


def pages(db, path):
    """Every row of a read, in pages: the windows here hold more than one."""
    rows = []
    while True:
        got = db.rest("GET", f"{path}&limit=1000&offset={len(rows)}") or []
        rows += got
        if len(got) < 1000:
            return rows


def weekly_series(db, today):
    """The series with dates every week, from 4 weeks back to 4 weeks ahead (BP app town-feed 74)."""
    days = collections.defaultdict(list)
    for r in pages(db, "club_events?select=title,club_id,source_name,submitted_by,event_date&status=eq.approved&kind=eq.event"
                       f"&event_date=gte.{today - timedelta(days=28)}&event_date=lte.{today + timedelta(days=28)}&order=id"):
        if r.get("event_date"):
            days[series_key(r)].append(date.fromisoformat(r["event_date"][:10]))
    return {k for k, d in days.items() if is_weekly(d)}


def lay(rows, weeks):
    """The Events as the helpers read them, the same thing on several dates once (its other dates are its `same`)."""
    things = {}
    for r in rows:
        host = (r.get("clubs") or {}).get("name") or r.get("source_name") or ""
        about = " ".join((r.get("description") or "").split())[:300]
        key = (*series_key(r), host, about)
        if key in things:
            things[key]["same"].append(r["id"])
            continue
        things[key] = {"id": r["id"], "title": r["title"], "host": host, "place": r.get("location") or "", "about": about,
                       "category": r.get("category"), **({"game": True} if write_judged.is_game(r) else {}),
                       **({"weekly": True} if series_key(r) in weeks else {}),
                       **({"city": True} if (r.get("source_name") or "").startswith("City of ") else {}), "same": []}
    return list(things.values())


def todo(db, today):
    """Approved upcoming Events with no level, but a private Group's and a friends-only one."""
    rows = pages(db, "club_events?select=id,title,location,description,category,sport,source_name,club_id,"
                     "submitted_by,clubs(name,status,private)&status=eq.approved&kind=eq.event&importance=is.null"
                     f"&friends_only=is.false&and={quote(f'(or(event_date.gte.{today},end_at.gte.{today}))')}&order=event_date,id")
    rows = [r for r in rows if not (r.get("clubs") or {}).get("private")]
    return lay(rows, weekly_series(db, today)) if rows else []


def message(events):
    return "".join(json.dumps({k: v for k, v in e.items() if k != "same"}, ensure_ascii=False) + "\n" for e in events)


def prepare(run_):
    folder = run_.folder / "importance"
    for name in READINGS:  # an earlier prepare's answers
        (run_.folder / name).unlink(missing_ok=True)
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    try:
        events = todo(run_.db, run_.today)
    except DbError as e:  # the morning goes on without levels
        (folder / "skipped.txt").write_text(why := f"[importance] skipped: {' '.join(str(e).split())[:150]}")
        return print(why)
    (folder / "events.json").write_text(json.dumps(events, indent=1, ensure_ascii=False))
    for i in range(0, len(events), BATCH):
        (folder / f"batch-{i // BATCH + 1}.txt").write_text(message(events[i:i + BATCH]))
    print(f"[importance] {sum(1 + len(e['same']) for e in events)} Events to rate in {len(events)} lines, "
          f"{len(list(folder.glob('batch-*.txt')))} batches ({folder})")


def answers_in(text):
    """A helper's JSON lines, {Event id: level}; a line that isn't one is skipped."""
    out = {}
    for ln in text.splitlines():
        try:
            a = json.loads(ln.strip().strip(","))
        except ValueError:
            continue
        if isinstance(a, dict) and isinstance(a.get("id"), str) and type(a.get("importance")) is int and a["importance"] in LEVELS:
            out[a["id"]] = a["importance"]
    return out


def held(level, event, interests=()):
    """A level within what always holds: weekly at most WEEKLY_MOST, a City's at least CITY_LEAST unless it's a meeting."""
    if event.get("weekly"):
        level = min(level, WEEKLY_MOST)
    if event.get("city") and level < CITY_LEAST and "town_meetings" not in interests and not MEETING.search(event["title"]):
        level = CITY_LEAST
    return level


def decide(events, first, second, interests=None):
    """{Event id: level}, each line's other dates too: the lower of the two helpers' levels, held. A line either helper left
    out isn't there."""
    out = {}
    for e in events:
        if e["id"] in first and e["id"] in second:
            level = held(min(first[e["id"]], second[e["id"]]), e, (interests or {}).get(e["id"]) or ())
            out.update({i: level for i in (e["id"], *e["same"])})
    return out


def agreement(events, first, second):
    """(lines both rated, lines they rated the same)."""
    both = [e["id"] for e in events if e["id"] in first and e["id"] in second]
    return len(both), sum(first[i] == second[i] for i in both)


def readings(folder):
    return [answers_in(f.read_text() if f.exists() else "") for f in (folder / n for n in READINGS)]


def given(folder):
    f = folder / "importance" / "events.json"
    return json.loads(f.read_text()) if f.exists() else []


def levels(folder):
    """The levels this morning's helpers gave, before they are saved, for the day's standouts."""
    return decide(given(folder), *readings(folder))


def save(db, by_id):
    """Writes the levels, an Event that has one already left alone."""
    for level in LEVELS:
        ids = sorted(i for i, n in by_id.items() if n == level)
        for at in range(0, len(ids), SAVE):
            db.rest("PATCH", f"club_events?id=in.({','.join(ids[at:at + SAVE])})&importance=is.null", {"importance": level},
                    prefer="return=minimal")


def keep(run_, dry_run=False):
    """Saves the levels; its report lines. Anything that breaks is one line."""
    try:
        return kept_lines(run_, dry_run)
    except Exception as e:
        return [f"[morning] importance failed: {' '.join(str(e).split())[:200]}"]


def kept_lines(run_, dry_run):
    skipped = run_.folder / "importance" / "skipped.txt"
    if skipped.exists():
        return [skipped.read_text()]
    events = given(run_.folder)
    if not events:
        return []
    done = run_.part(f"importance/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    first, second = readings(run_.folder)
    cities = [e["id"] for e in events if e.get("city")]
    rows = run_.db.rest("GET", f"club_events?select=id,interests&id=in.({','.join(cities)})") or [] if cities else []
    by_id = decide(events, first, second, {r["id"]: r.get("interests") for r in rows})
    if not dry_run:
        save(run_.db, by_id)
    n = collections.Counter(by_id.values())
    both, same = agreement(events, first, second)
    lines = [f"[importance] rated {len(by_id)} Events (5/4/3/2/1: {'/'.join(str(n[v]) for v in reversed(LEVELS))}); the helpers "
             f"agreed on {same} of {both} lines" + (f" ({same / both:.0%})" if both else "")
             + f", {len(events) - both} wait for tomorrow" + (" (dry run: nothing written)" if dry_run else "")]
    lines += [f"- {e['title']}: {by_id[e['id']]}" for e in events if by_id.get(e["id"], 0) >= 4]
    done.save(lines)
    return lines


def selftest():
    from morning_run import FakeDb, Run
    import tempfile
    checks = []
    ok = lambda good, why: checks.append((bool(good), why))

    d = lambda *off: [date(2026, 11, 1) + timedelta(days=o) for o in off]
    ok(is_weekly(d(0, 7, 14, 21)) and is_weekly(d(0, 3, 7, 10, 14, 17, 21, 24)) and not is_weekly(d(0, 1, 7, 8))
       and not is_weekly(d(0, 28, 56)) and not is_weekly(d(0, 7, 14)), "weekly: 3 dates or more over 3 weeks, a week apart")

    ev = lambda i, **more: {"id": i, "title": i, "same": [], **more}
    events = [ev("a"), ev("b"), ev("c", same=["c2"]), ev("w", weekly=True), ev("d"), ev("e")]
    first = {"a": 4, "b": 5, "c": 2, "w": 5, "d": 3}
    second = {"a": 5, "b": 5, "c": 3, "w": 4, "e": 3}
    got = decide(events, first, second)
    ok(got == {"a": 4, "b": 5, "c": 2, "c2": 2, "w": 3},
       f"the lower level wins, a 5 needs both, weekly holds at 3, other dates too, one left out waits: {got}")
    ok(agreement(events, first, second) == (4, 1), "agreement is on the lines both rated")
    city = [ev("Pilates Class", city=True), ev("Planning Commission", city=True), ev("Joint Powers", city=True), ev("Mass")]
    ones = {e["id"]: 1 for e in city}
    ok(decide(city, ones, ones, {"Joint Powers": ["town_meetings"]})
       == {"Pilates Class": 2, "Planning Commission": 1, "Joint Powers": 1, "Mass": 1},
       "a City's own class is never a 1; its meeting is, by its title or its interests; another host's 1 stays")
    ok(answers_in('{"id": "a", "importance": 4}\nprose\n{"id": "b", "importance": 6}\n{"id": "c", "importance": true}\n'
                  '{"id": "d", "importance": "3"}\n{"id": "e"},\n{"id": "f", "importance": 1},') == {"a": 4, "f": 1},
       "only a whole level from 1 to 5 is an answer")

    row = lambda i, title, day, **more: {"id": i, "title": title, "event_date": day, "source_name": "Sal's", "club_id": None,
                                         "submitted_by": None, "clubs": None, "description": " Win\n meat ", **more}
    raffle = [row(f"r{n}", "Meat Raffle", f"2026-11-{7 * n:02}") for n in range(1, 5)]
    with tempfile.TemporaryDirectory() as tmp:
        db = FakeDb(answers={"club_events?select=id,title": [
            raffle[2], raffle[3], row("s", "Secret", "2026-11-18", clubs={"name": "Hush", "private": True}),
            row("p", "Pilates Class", "2026-11-19", source_name="City of St. Joseph")],
            "club_events?select=title,club_id": raffle, "club_events?select=id,interests": [{"id": "p", "interests": ["health"]}]})
        r = Run(Path(tmp), date(2026, 11, 17), db)
        prepare(r)
        laid = given(r.folder)
        ok([(e["id"], e["same"], e.get("weekly"), e.get("city")) for e in laid] == [("r3", ["r4"], True, None), ("p", [], None, True)],
           f"one line for the same thing on two dates, weekly and city marked, a private Group's left out: {laid}")
        ok('"same"' not in (r.folder / "importance/batch-1.txt").read_text() and "importance=is.null" in db.calls[0][1]
           and "friends_only=is.false" in db.calls[0][1], "the helpers never see the other dates; only Events with no level")
        ok(keep(r, dry_run=True)[0].startswith("[importance] rated 0 Events") and not db.writes("club_events"), "no answers, nothing rated")
        (r.folder / READINGS[0]).write_text('{"id": "r3", "importance": 4}\n{"id": "p", "importance": 1}\n')
        (r.folder / READINGS[1]).write_text('{"id": "r3", "importance": 4}\n{"id": "p", "importance": 1}\n')
        ok(levels(r.folder) == {"r3": 3, "r4": 3, "p": 2}, "the standouts read the levels before they are saved")
        lines = keep(r)
        w = db.writes("club_events")
        ok([(c[1], c[2]) for c in w] == [("club_events?id=in.(p)&importance=is.null", {"importance": 2}),
                                         ("club_events?id=in.(r3,r4)&importance=is.null", {"importance": 3})],
           f"a save per level, never over a level it has: {w}")
        ok("(5/4/3/2/1: 0/0/2/1/0)" in lines[0] and "2 of 2 lines (100%)" in lines[0] and keep(r) == lines
           and len(db.writes("club_events")) == 2, f"a finish run again neither writes nor counts twice: {lines}")

    with tempfile.TemporaryDirectory() as tmp:
        class Down:
            def rest(self, *a, **k):
                raise DbError("GET", "club_events", 400, "column club_events.importance does not exist")
        r = Run(Path(tmp), date(2026, 11, 17), Down())
        prepare(r)
        ok(keep(r)[0].startswith("[importance] skipped: "), "no column yet: the morning goes on, and says so")

    failed = [why for good, why in checks if not good]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    return not failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["prepare", "keep"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    from morning_run import Run
    from read_events import LOCAL
    r = Run(registry.find_root() / ".runs" / "morning", datetime.now(LOCAL).date(), run.Supabase())
    if a.step == "prepare":
        prepare(r)
    elif a.step == "keep":
        print("\n".join(keep(r, a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
