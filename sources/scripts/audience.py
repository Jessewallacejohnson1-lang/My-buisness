#!/usr/bin/env python3
"""
audience.py: who each Event is made for, Older adults, Families, Kids, Teens or Adults, when two helpers agree (BP app
inside-cards 35; Jesse, 2026-11-17: "i want this for every event like some could be family event", "if it's not
certain, it can be more broad, like for everyone").

The word goes in club_events.ages, where a source's age goes (inside-cards 30), so it shows where the age shows: "Older
adults | $5" under the place on the Event page, "Tue · 1 PM · Older adults" on the Town card. A source's age wins: only
an Event with no age is judged, and the morning's judge writes a later age over the word.

`prepare` lays out the upcoming Events no helper has judged (club_events.audience_at), games aside, in batches of
BATCH for two helpers each (sources/models/audience.md). `keep`, a step of `morning.py finish`, writes the word where
both helpers gave the same one and it isn't Everyone, and marks every Event both answered as judged, so it is judged
once. A disagreement or Everyone shows nothing.

  python3 sources/scripts/audience.py prepare
  python3 sources/scripts/audience.py keep --dry-run
  python3 sources/scripts/audience.py --selftest
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402
import run  # noqa: E402
import write_judged  # noqa: E402
from db import DbError  # noqa: E402

BATCH = 40
WORDS = ("Older adults", "Families", "Kids", "Teens", "Adults")  # club_events_ages_shape takes these; Everyone shows nothing
READINGS = ("audience.jsonl", "audience-2.jsonl")  # the two helpers' answers, in the run's folder


def todo(db, today):
    """Approved upcoming Events with no age and not judged yet, games aside, as the helpers read them."""
    rows, got = [], None
    while got is None or len(got) == 1000:
        got = db.rest("GET", "club_events?select=id,title,location,description,category,sport,source_name,clubs(name)"
                             "&status=eq.approved&kind=eq.event&ages=is.null&audience_at=is.null"
                             f"&and={quote(f'(or(event_date.gte.{today},end_at.gte.{today}))')}"
                             f"&order=event_date,id&limit=1000&offset={len(rows)}") or []
        rows += got
    return [{"id": r["id"], "title": r["title"], "host": (r.get("clubs") or {}).get("name") or r.get("source_name") or "",
             "place": r.get("location") or "", "about": " ".join((r.get("description") or "").split())[:300],
             "category": r.get("category")} for r in rows if not write_judged.is_game(r)]


def prepare(folder, db, today):
    for name in READINGS:  # an earlier morning's answers: other Events'
        (folder.parent / name).unlink(missing_ok=True)
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    try:
        events = todo(db, today)
    except DbError as e:  # club_events.audience_at isn't applied yet: the morning goes on without this step
        print(f"[audience] skipped: {' '.join(str(e).split())[:150]}")
        return []
    (folder / "events.json").write_text(json.dumps(events, indent=1, ensure_ascii=False))
    for i in range(0, len(events), BATCH):
        (folder / f"batch-{i // BATCH + 1}.txt").write_text(
            "\n".join(json.dumps(e, ensure_ascii=False) for e in events[i:i + BATCH]) + "\n")
    print(f"[audience] {len(events)} Events to judge in {len(list(folder.glob('batch-*.txt')))} batches ({folder})")
    return events


def answers_in(text):
    """A helper's JSON lines, by Event id; a line that isn't one is skipped."""
    out = {}
    for ln in text.splitlines():
        try:
            a = json.loads(ln.strip().strip(","))
        except ValueError:
            continue
        if isinstance(a, dict) and isinstance(a.get("id"), str) and isinstance(a.get("for"), str):
            out[a["id"]] = a["for"].strip()
    return out


def plan(events, first, second):
    """{id: word or None} for each Event both helpers answered: the word when they agree on one of WORDS, else None
    (Everyone, a disagreement or a word not on the list). An Event either left out waits for tomorrow."""
    return {e["id"]: (first[e["id"]] if first[e["id"]] == second[e["id"]] and first[e["id"]] in WORDS else None)
            for e in events if e["id"] in first and e["id"] in second}


def keep(run_, dry_run=False):
    """Writes the agreed words; one report line, plus one per word put live. Anything that breaks is one line."""
    try:
        return kept_lines(run_, dry_run)
    except Exception as e:
        return [f"[morning] audience failed: {' '.join(str(e).split())[:200]}"]


def kept_lines(run_, dry_run):
    folder = run_.folder / "audience"
    if not (folder / "events.json").exists():
        return []
    done = run_.part(f"audience/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    events = json.loads((folder / "events.json").read_text())
    first, second = (answers_in(f.read_text() if f.exists() else "") for f in (run_.folder / n for n in READINGS))
    words, now = plan(events, first, second), datetime.now(timezone.utc).isoformat()
    titles = {e["id"]: e["title"] for e in events}
    if not dry_run:
        for event_id, word in words.items():  # ages=is.null: a source's age that came meanwhile wins
            run_.db.rest("PATCH", f"club_events?id=eq.{event_id}&ages=is.null",
                         {"audience_at": now, **({"ages": word} if word else {})}, prefer="return=minimal")
    put = [f"- {titles[i]}: {w}" for i, w in words.items() if w]
    lines = ([f"[morning] who it's for: {len(put)} of {len(words)} Events judged got a word, {len(events) - len(words)} "
              f"wait for tomorrow" + (" (dry run: nothing written)" if dry_run else "")] + put)
    done.save(lines)
    return lines


def selftest():
    from morning_run import FakeDb, Run
    import tempfile
    checks = []
    ok = lambda good, why: checks.append((bool(good), why))

    events = [{"id": i, "title": t} for i, t in (("a", "Enhanced Fitness"), ("b", "Mass"), ("c", "Kid's Night Out"),
                                                    ("d", "Benedictine Certificate"), ("e", "Late"))]
    first = {"a": "Older adults", "b": "Everyone", "c": "Kids", "d": "Adults", "e": "Teens"}
    second = {"a": "Older adults", "b": "Everyone", "c": "Kids", "d": "Everyone"}
    p = plan(events, first, second)
    ok(p == {"a": "Older adults", "b": None, "c": "Kids", "d": None}, f"agree, Everyone, disagree, one missing: {p}")
    ok(plan([{"id": "x"}], {"x": "Grown-ups"}, {"x": "Grown-ups"}) == {"x": None}, "a word off the list shows nothing")
    ok(answers_in('{"id": "a", "for": "Kids"}\nnot json\n{"id": "b"},\n') == {"a": "Kids"}, "a broken line is skipped")

    with tempfile.TemporaryDirectory() as tmp:
        db = FakeDb(answers={"club_events?select=": [
            {"id": "a", "title": "Enhanced Fitness", "description": "  A weekly\nclass ", "clubs": {"name": "Church"}},
            {"id": "g", "title": "Cathedral vs Sauk Rapids", "sport": "hockey", "category": "watch_sports"}]})
        r = Run(Path(tmp), datetime(2026, 11, 17).date(), db)
        got = prepare(r.folder / "audience", db, r.today)
        ok([e["id"] for e in got] == ["a"] and got[0]["about"] == "A weekly class" and got[0]["host"] == "Church",
           f"a game is left out, the About is one line: {got}")
        ok((r.folder / "audience" / "batch-1.txt").exists() and "ages=is.null&audience_at=is.null" in db.calls[0][1],
           "one batch, only Events with no age and not judged")
        (r.folder / READINGS[0]).write_text('{"id": "a", "for": "Older adults"}\n')
        (r.folder / READINGS[1]).write_text('{"id": "a", "for": "Older adults"}\n')
        lines = keep(r)
        w = db.writes("club_events")
        ok(len(w) == 1 and w[0][1] == "club_events?id=eq.a&ages=is.null" and w[0][2]["ages"] == "Older adults"
           and w[0][2]["audience_at"], f"the agreed word is written where no age came meanwhile: {w}")
        ok(lines[1] == "- Enhanced Fitness: Older adults" and keep(r) == lines and len(db.writes("club_events")) == 1,
           "a finish run again neither writes nor reports twice")

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
        prepare(r.folder / "audience", r.db, r.today)
    elif a.step == "keep":
        print("\n".join(keep(r, a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
