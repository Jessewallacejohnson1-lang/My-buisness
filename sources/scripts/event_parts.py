#!/usr/bin/env python3
"""
event_parts.py: the parts of a long Event at a time its host wrote: an artist talk, a reception, a speaker (BP app
docs/plans/happening-now, ticket 03). An Event running 12 hours or longer (an exhibit, a festival, an all-day market)
gets its own page and its host's read each morning; while a part is on, the app shows its Event as live (ticket 04).

`prepare` takes the long Events still running or starting within LOOKAHEAD days, at most MAX, and reads each one's
pages through the registry's polite fetch: its own page, the pages that mentioned it, and its host's watched pages.
Facebook and Instagram are left out (Apify is paid; the morning's social reads already turn their posts into Events).
A long page keeps only the passages naming the Event. They go on one batch for two helpers (sources/models/event-part.md),
each on its own.

`keep`, a step of `morning.py finish`, writes a part only where both helpers found it on the same day at the same start,
each quoting the host's words with that time, inside the Event's days. Never a guess (Jesse, 2026-11-09: two separate
agent checks agreeing may write live). A part on the day, start and place of an Event already listed points at it
(`same_as`) rather than making a double (Jesse, 2026-11-05). The part's day must be the host's too: the quote names its
date, or a weekday the Event's days hold once, or the Event has one day only. Each Event read has its new parts
written, then its old ones taken away; one only a helper named parts for is left as it was. A part with no end runs 1
hour: get_event_parts applies it.

  python3 sources/scripts/event_parts.py prepare
  python3 sources/scripts/event_parts.py keep --dry-run
  python3 sources/scripts/event_parts.py --selftest
"""

import argparse
import json
import re
import sys
import urllib.parse
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402
import run  # noqa: E402
from db import DbError  # noqa: E402
from read_events import LOCAL  # noqa: E402
from write_judged import PLACE_STOP, parse_clock, same_place, words  # noqa: E402

# "3 PM", "3:30 p.m.", "3pm", and a range's first time taking the second's half of the day ("3-5 PM", "3 to 5 p.m.")
CLOCK = re.compile(r"\b(\d{1,2})(?::(\d\d))?\s*(?:(?:-|–|—|to)\s*(\d{1,2})(?::(\d\d))?\s*)?([ap])\.?\s?m\b\.?", re.I)


def times_in(text):
    """Every clock time the words state: a time is read only where the host wrote it, never from "afternoon"."""
    out = set()
    for h, m, h2, m2, half in CLOCK.findall(text or ""):
        pm = half.lower() == "p"
        for hh, mm in ((h, m), (h2, m2)):
            if hh and 1 <= int(hh) <= 12 and int(mm or 0) < 60:
                out.add(time(int(hh) % 12 + (12 if pm else 0), int(mm or 0)))
    if re.search(r"\bnoon\b", text or "", re.I):
        out.add(time(12))
    return out


MONTHS = ("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
DATE = re.compile(r"\b(" + "|".join(MONTHS) + r")[a-z]*\.?\s+(\d{1,2})(?!\d)|\b(\d{1,2})/(\d{1,2})\b", re.I)
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def days_in(text):
    """Every (month, day) the words state: "Nov. 12", "November 12", "11/12"."""
    out = set()
    for mon, d, m2, d2 in DATE.findall(text or ""):
        month, day = (MONTHS.index(mon.lower()[:3]) + 1, int(d)) if mon else (int(m2), int(d2))
        if 1 <= month <= 12 and 1 <= day <= 31:
            out.add((month, day))
    return out


def day_pinned(day, quote, event):
    """Whether the host's words give the part's day, never a guess: they name its date; or a weekday the Event's days
    hold only once; or the Event has one day only and the words name no other. A date for another day is no part."""
    dates = days_in(quote)
    if dates:
        return (day.month, day.day) in dates
    first, last = event["starts"].date(), (event["ends"] - timedelta(microseconds=1)).date()
    if first == last:
        return not re.search(r"\b(" + "|".join(WEEKDAYS) + r")\b", quote or "", re.I) \
            or re.search(rf"\b{WEEKDAYS[day.weekday()]}\b", quote, re.I) is not None
    named = re.search(rf"\b{WEEKDAYS[day.weekday()]}\b", quote or "", re.I)
    return bool(named) and sum((first + timedelta(i)).weekday() == day.weekday()
                               for i in range((last - first).days + 1)) == 1


def stated(answer, event):
    """(day, start, end or None) of one helper's part when its quote states the start and gives the day; else None."""
    try:
        day = date.fromisoformat(str(answer.get("day"))[:10])
    except ValueError:
        return None
    start, end = parse_clock(answer.get("start")), parse_clock(answer.get("end") or "")
    said = times_in(answer.get("quote"))
    if not start or start not in said or not day_pinned(day, answer.get("quote"), event):
        return None
    return day, start, end if end in said and end > start else None


def same_as(event, starts, existing):
    """The id of an Event already listed on the part's day, at its start and place, else None: that Event stays, and
    the part points at it rather than making a double (Jesse, 2026-11-05). No place on either side counts as the long
    Event's own."""
    here = words(event.get("location"), PLACE_STOP)
    for e in existing:
        there = words(e.get("location"), PLACE_STOP)
        if (str(e.get("event_date"))[:10] == starts.date().isoformat() and parse_clock(e.get("start_time")) == starts.time()
                and (not (here and there) or same_place(here, there)
                     or bool(e.get("place_entry_id")) and e.get("place_entry_id") == event.get("place_entry_id"))):
            return e["id"]
    return None


def judge(event, a, b, existing=()):
    """(parts to write, report lines) for one long Event from its two helpers' answers. A part is kept only where both
    helpers found it on the same day at the same start, each quoting the host's words with that time and that day."""
    seen = {}
    for x in b:
        got = stated(x, event)
        if got:
            seen.setdefault(got[:2], (x, got))
    kept, left = [], []
    for x in a:
        got = stated(x, event)
        if not got:
            left.append(f"no stated time and day in {x.get('quote')!r}")
            continue
        if got[:2] not in seen:
            left.append(f"only one helper found {x.get('title')!r} on {got[0]} at {x.get('start')}")
            continue
        day, start, end = got
        other_end = seen[got[:2]][1][2]
        starts = datetime.combine(day, start)
        if not event["starts"] <= starts < event["ends"]:
            left.append(f"{x.get('title')!r} on {day} at {x.get('start')} is outside the Event's days")
            continue
        kept.append({"event_id": event["id"], "title": str(x.get("title")).strip(),
                     "starts_at": starts.replace(tzinfo=LOCAL).isoformat(),
                     "ends_at": datetime.combine(day, end).replace(tzinfo=LOCAL).isoformat() if end and end == other_end else None,
                     "source_url": x.get("page") or "", "source_line": str(x.get("quote")).strip(),
                     "same_as": same_as(event, starts, existing)})
    return kept, left


# --- Which Events, and their pages ------------------------------------------------------------------------------

LONG = timedelta(hours=12)  # the spec's long Event
LOOKAHEAD = 7               # days ahead a long Event starting soon is read
MAX = 10                    # long Events read a morning, the soonest first
PAGE_CHARS = 6000           # a page's words a helper gets
AROUND = 3                  # lines kept either side of one naming the Event, on a page longer than PAGE_CHARS
READINGS = ("parts.jsonl", "parts-2.jsonl")  # the two helpers' answers
SOCIAL = re.compile(r"(facebook|instagram)\.com/", re.I)


def span(row):
    """(start, end) of an Event as local naive datetimes; end None when it has none."""
    day = date.fromisoformat(str(row["event_date"])[:10])
    at = None if row.get("all_day") else parse_clock(row.get("start_time"))
    end = row.get("end_at") and datetime.fromisoformat(str(row["end_at"]))
    return datetime.combine(day, at or time(0)), end and end.astimezone(LOCAL).replace(tzinfo=None)


def long_events(db, today):
    """The approved long Events on today or within LOOKAHEAD days, soonest end first, at most MAX."""
    rows = db.rest("GET", "club_events?select=id,title,event_date,start_time,end_at,all_day,location,place_entry_id,source_url"
                          f"&status=eq.approved&cancelled_at=is.null&end_at=gte.{today}"
                          f"&event_date=lte.{today + timedelta(LOOKAHEAD)}&order=end_at,id") or []
    out = []
    for r in rows:
        starts, ends = span(r)
        if ends and ends - starts >= LONG and ends.date() >= today:
            out.append({**r, "starts": starts, "ends": ends})
    return out[:MAX]


def passages(text, title):
    """A short page whole; a long one only the lines naming the Event (two of its title's words) and AROUND either side."""
    if len(text) <= PAGE_CHARS:
        return text
    want = words(title)
    lines = text.splitlines()
    near = {j for i, ln in enumerate(lines) if len(want & words(ln)) >= min(2, len(want))
            for j in range(i - AROUND, i + AROUND + 1)}
    return "\n".join(lines[i] for i in sorted(near) if 0 <= i < len(lines))[:PAGE_CHARS]


def polite(url):
    return run.read_page(url, "website")[1]


def pages_of(db, events, read=polite):
    """Each Event's pages to read, as [{url, text}]: its own, those that mentioned it, its host's watched ones."""
    ids = ",".join(e["id"] for e in events)
    mentioned = db.rest("GET", f"event_mentions?select=event_id,source_url&event_id=in.({ids})") or []
    hosts = ",".join(sorted({e["place_entry_id"] for e in events if e.get("place_entry_id")})) or "none"
    hosted = db.rest("GET", f"sources?select=entry_id,url&entry_id=in.({hosts})&status=eq.active") or []
    out = {}
    for e in events:
        urls = [e.get("source_url")] + [m["source_url"] for m in mentioned if m["event_id"] == e["id"]] \
            + [h["url"] for h in hosted if h["entry_id"] == e.get("place_entry_id")]
        got = []
        for u in dict.fromkeys(u for u in urls if u and not SOCIAL.search(u)):
            try:
                text = passages(read(u), e["title"])
            except Exception as ex:  # a page that can't be read is one line, the Event's others are still read
                print(f"[parts] {u}: {' '.join(str(ex).split())[:120]}")
                continue
            if text.strip():
                got.append({"url": u, "text": text})
        out[e["id"]] = got
    return out


def prepare(folder, db, today, read=polite):
    """Lays out the helpers' batch and found.json (the Events read, by key)."""
    for name in READINGS:  # an earlier prepare's answers: their keys were other Events'
        (folder.parent / name).unlink(missing_ok=True)
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    try:
        db.rest("GET", "event_parts?select=id&limit=1")  # not applied yet: the morning goes on without this step
        events = long_events(db, today)
        pages = pages_of(db, events, read) if events else {}
    except DbError as e:
        print(f"[parts] skipped: {' '.join(str(e).split())[:150]}")
        return []
    events = [e for e in events if pages.get(e["id"])]
    found = {}
    lines = []
    for i, e in enumerate(events, 1):
        key = f"p{i}"
        found[key] = {"id": e["id"], "title": e["title"], "starts": e["starts"].isoformat(), "ends": e["ends"].isoformat(),
                      "location": e.get("location"), "place_entry_id": e.get("place_entry_id")}
        lines.append(json.dumps({"event": key, "title": e["title"], "from": e["starts"].isoformat(),
                                 "to": e["ends"].isoformat(), "place": e.get("location") or "",
                                 "pages": pages[e["id"]]}, ensure_ascii=False))
    (folder / "found.json.new").write_text(json.dumps({"today": str(today), "events": found}, indent=1, ensure_ascii=False))
    (folder / "found.json.new").replace(folder / "found.json")  # whole or not at all
    if lines:
        (folder / "batch.txt").write_text("\n".join(lines) + "\n")
    print(f"[parts] {len(lines)} long Events to read for parts" + (f" ({folder / 'batch.txt'})" if lines else ""))
    return events


# --- Keep -------------------------------------------------------------------------------------------------------

def answers_in(text):
    """The helper's JSON lines, by Event key; a line that isn't one is skipped."""
    out = {}
    for ln in text.splitlines():
        try:
            a = json.loads(ln.strip().strip(","))
        except ValueError:
            continue
        if isinstance(a, dict) and isinstance(a.get("event"), str):
            out.setdefault(a["event"], []).append(a)
    return out


def take_down(part):
    """The migration line that takes a wrong part down: a migration takes no bound values, so each is quoted as a SQL
    literal and cast to its column's type."""
    q = lambda v: "'" + str(v).replace("'", "''") + "'"
    return (f"delete from public.event_parts where event_id = {q(part['event_id'])}::uuid"
            f" and starts_at = {q(part['starts_at'])}::timestamptz and title = {q(part['title'])};")


def keep(run_, dry_run=False):
    """Each long Event both helpers answered for gets its parts replaced; one report line per part. Kept as the step's
    lines, so a finish run again neither writes nor reports twice. Anything that breaks is one line."""
    try:
        return kept_lines(run_, dry_run)
    except Exception as e:
        return [f"[morning] event parts failed: {' '.join(str(e).split())[:200]}"]


def kept_lines(run_, dry_run):
    folder = run_.folder / "parts"
    if not (folder / "found.json").exists():
        return []
    done = run_.part(f"parts/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    events = json.loads((folder / "found.json").read_text())["events"]
    files = [run_.folder / n for n in READINGS]
    if events and not all(f.exists() and f.read_text().strip() for f in files):
        lines = ["- Parts of long Events: a helper gave no answers; tried again tomorrow"]
        done.save(lines)
        return lines
    readings = [answers_in(f.read_text()) for f in files]
    put, left = [], []
    for key, e in events.items():
        e = {**e, "starts": datetime.fromisoformat(e["starts"]), "ends": datetime.fromisoformat(e["ends"])}
        listed = run_.db.rest("GET", f"club_events?select=id,event_date,start_time,location,place_entry_id&status=eq.approved"
                                     f"&event_date=gte.{e['starts'].date()}&event_date=lte.{e['ends'].date()}"
                                     f"&id=neq.{e['id']}") or []
        a, b = readings[0].get(key, []), readings[1].get(key, [])
        if bool(a) != bool(b):  # one names parts, the other none: no agreement either way
            left.append(f"- No change: {e['title']}: one helper named parts, the other none; its parts left as they were")
            continue
        kept, why = judge(e, a, b, listed)
        if not dry_run:
            # The new parts first, then the old ones away: a write that fails leaves the Event its old parts.
            stamp = datetime.now(timezone.utc).isoformat()
            if kept:
                run_.db.rest("POST", "event_parts?on_conflict=event_id,starts_at,title",
                             [{**p, "found_at": stamp} for p in kept], prefer="resolution=merge-duplicates,return=minimal")
            run_.db.rest("DELETE", f"event_parts?event_id=eq.{urllib.parse.quote(e['id'])}"
                                   f"&found_at=lt.{urllib.parse.quote(stamp)}", prefer="return=minimal")
        for p in kept:
            put.append(f"- Part: {e['title']}: {p['title']}, {p['starts_at'][:16].replace('T', ' ')}"
                       + (f" (the listed Event {p['same_as']})" if p["same_as"] else "")
                       + f", from {p['source_url']}: \"{p['source_line']}\". Wrong? Take it down with a migration: {take_down(p)}"
                       + (" (dry run: nothing written)" if dry_run else ""))
        left += [f"- No part: {e['title']}: {w}" for w in why]
    lines = ([f"- Parts of long Events: {len(put)}"] + put if put else []) + left
    done.save(lines)
    return lines


def selftest():
    checks = []
    ok = lambda good, why: checks.append((bool(good), why))

    show = {"id": "e1", "title": "Emily Sheehan Drawings Exhibition", "starts": datetime(2026, 10, 28),
            "ends": datetime(2026, 12, 15), "location": "Gorecki Gallery", "place_entry_id": "arts-benedicta-center"}

    def part(title, day, start, quote, end="", page="https://csbsju.edu/show"):
        return {"event": "p1", "title": title, "day": day, "start": start, "end": end, "page": page, "quote": quote}

    talk = part("Artist talk", "2026-11-12", "3 PM", "Artist talk with Emily Sheehan, Thursday Nov. 12 at 3 PM")
    kept, _ = judge(show, [talk], [dict(talk, title="Artist Talk")])
    ok(len(kept) == 1 and kept[0]["title"] == "Artist talk" and kept[0]["starts_at"] == "2026-11-12T15:00:00-06:00"
       and kept[0]["ends_at"] is None and kept[0]["source_line"] == talk["quote"] and kept[0]["event_id"] == "e1",
       f"a stated 'Artist talk 3 PM' both helpers found becomes a part: {kept}")

    vague = part("Afternoon activities", "2026-11-12", "2 PM", "Join us for afternoon activities in the gallery")
    kept, left = judge(show, [vague], [vague])
    ok(kept == [] and "no stated time" in left[0], f"'afternoon activities' with no time is no part: {left}")
    ok(times_in("Reception 5-7 p.m.") == {time(17), time(19)} and times_in("at noon") == {time(12)}
       and times_in("Room 101, 2026") == set(), "times the host wrote, and none from numbers that aren't times")
    ranged = part("Reception", "2026-11-12", "5 PM", "Closing reception 5-7 p.m. Thursday, Nov. 12", end="7 PM")
    ok(judge(show, [ranged], [ranged])[0][0]["ends_at"] == "2026-11-12T19:00:00-06:00", "the host's end wins")
    ok(judge(show, [ranged], [dict(ranged, end="")])[0][0]["ends_at"] is None, "an end the helpers don't agree on is none")
    ok(judge(show, [talk], [])[0] == [] and judge(show, [], [talk])[0] == [], "a part only one helper found is no part")
    late = part("Artist talk", "2026-12-20", "3 PM", "Artist talk Dec. 20 at 3 PM")
    ok(judge(show, [late], [late])[0] == [], "a part outside the Event's days is no part of it")

    # The part's day is the host's too: its words name the date, or a weekday the Event's days hold once, or the Event
    # has one day only. Never a guess.
    weekly = part("Artist talk", "2026-11-12", "3 PM", "Artist talk Thursday at 3 PM")
    ok(judge(show, [weekly], [weekly])[0] == [], "a weekday a 7-week show holds seven times doesn't pin the day")
    week = dict(show, starts=datetime(2026, 11, 9), ends=datetime(2026, 11, 16))
    ok(len(judge(week, [weekly], [weekly])[0]) == 1, "a weekday the Event's days hold once pins it")
    undated = part("Artist talk", "2026-11-12", "3 PM", "Artist talk at 3 PM")
    ok(judge(week, [undated], [undated])[0] == [], "no day in the host's words over several days: no part")
    market = dict(show, starts=datetime(2026, 11, 12, 8), ends=datetime(2026, 11, 13))
    ok(len(judge(market, [undated], [undated])[0]) == 1, "an Event of one day pins its parts' day")
    other = part("Artist talk", "2026-11-12", "3 PM", "Artist talk Friday, Nov. 13 at 3 PM")
    ok(judge(week, [other], [other])[0] == [], "the host's words naming another day: no part")
    ok(len(judge(show, [dict(talk, quote="Artist talk 11/12 at 3 PM")], [talk])[0]) == 1, "a date as 11/12 names the day")
    ok(take_down({"event_id": "e1", "starts_at": "2026-11-12T15:00:00-06:00", "title": "Rob's talk"})
       == "delete from public.event_parts where event_id = 'e1'::uuid and starts_at = '2026-11-12T15:00:00-06:00'::timestamptz"
          " and title = 'Rob''s talk';", "the take-down line quotes its values")

    gallery_talk = {"id": "e9", "title": "Emily Sheehan: Artist Talk", "event_date": "2026-11-12", "start_time": "3 PM",
                    "location": "Gorecki Gallery, CSB", "place_entry_id": "arts-benedicta-center"}
    elsewhere = dict(gallery_talk, id="e8", location="Pellegrene Auditorium", place_entry_id="sju")
    kept, _ = judge(show, [talk], [talk], [elsewhere, gallery_talk])
    ok(len(kept) == 1 and kept[0]["same_as"] == "e9",
       f"a part on the day, at the start and place of an Event already listed points at it, no double: {kept}")
    ok(judge(show, [talk], [talk], [elsewhere])[0][0]["same_as"] is None, "an Event at another place is another thing")
    ok(judge(show, [talk], [talk], [dict(gallery_talk, start_time="7 PM")])[0][0]["same_as"] is None,
       "an Event at another start is another thing")

    # prepare and keep, as the morning runs them
    import json
    import tempfile
    from morning_run import FakeDb, Run
    from db import DbError
    today = date(2026, 11, 10)
    rows = [{"id": "e1", "title": "Emily Sheehan Drawings Exhibition", "event_date": "2026-10-28", "start_time": None,
             "end_at": "2026-12-15 06:00:00+00", "all_day": True, "location": "Gorecki Gallery",
             "place_entry_id": "arts-benedicta-center", "source_url": "https://www.facebook.com/csbsju/posts/x"},
            {"id": "e2", "title": "Reflection: Selected Works", "event_date": "2026-11-10", "start_time": "10 AM",
             "end_at": "2026-11-11 03:00:00+00", "all_day": False, "location": "Benedicta Arts Center",
             "place_entry_id": "arts-benedicta-center", "source_url": "https://my.csbsju.edu/public/events/2"},
            {"id": "e3", "title": "Festival of Cultures", "event_date": "2026-11-09", "start_time": None,
             "end_at": "2026-11-15 06:00:00+00", "all_day": True, "location": None, "place_entry_id": "csbsju-events",
             "source_url": "https://my.csbsju.edu/public/events/3"}]
    answers = {"event_parts": [], "club_events?select=id,title": rows,
               "event_mentions": [{"event_id": "e1", "source_url": "https://www.csbsju.edu/fine-arts/sheehan"}],
               "sources": [{"entry_id": "arts-benedicta-center", "url": "https://www.instagram.com/bac/"},
                           {"entry_id": "csbsju-events", "url": "https://my.csbsju.edu/feed"}],
               "club_events?select=id,event_date": [gallery_talk]}
    pages = {"https://www.csbsju.edu/fine-arts/sheehan": "Emily Sheehan drawings.\nArtist talk Thursday Nov. 12 at 3 PM.",
             "https://my.csbsju.edu/public/events/3": "Festival of Cultures week. Keynote Nov. 11 at 7 PM.",
             "https://my.csbsju.edu/feed": "Other event, 5 PM\n" * 3000 + "Festival of Cultures: dance night Nov. 13 at 8 PM\n" + "Other event\n" * 3000}
    read = lambda url: pages[url]
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning"
        r = Run(folder, today, FakeDb(answers=answers))
        ok(keep(r) == [], "no parts step, no lines")
        got = prepare(folder / "parts", r.db, today, read)
        batch = [json.loads(l) for l in (folder / "parts" / "batch.txt").read_text().splitlines()]
        ok([b["title"] for b in batch] == ["Emily Sheehan Drawings Exhibition", "Festival of Cultures"] and len(got) == 2,
           f"only Events running 12 hours or longer are read (Reflection runs 11): {[b['title'] for b in batch]}")
        ok([p["url"] for p in batch[0]["pages"]] == ["https://www.csbsju.edu/fine-arts/sheehan"],
           f"the Event's own pages and its host's are read, Facebook and Instagram not: {batch[0]['pages']}")
        feed = next(p["text"] for p in batch[1]["pages"] if p["url"].endswith("feed"))
        ok("dance night Nov. 13 at 8 PM" in feed and len(feed) < 3000, "a long host page keeps the passages naming the Event")

        a = [dict(talk, event="p1"), dict(vague, event="p1")]
        (folder / "parts.jsonl").write_text("\n".join(json.dumps(x) for x in a) + "\nnot json\n")
        (folder / "parts-2.jsonl").write_text(json.dumps(dict(talk, event="p1")) + "\n")
        r.db.calls.clear()
        lines = keep(r, dry_run=True)
        ok(not r.db.writes() and any("Artist talk" in l and "dry run" in l for l in lines), f"a dry run writes nothing: {lines}")
        r2 = Run(folder, today, FakeDb(answers=answers))
        lines = keep(r2)
        w = r2.db.writes("event_parts")
        ok([m for m, p, b in w] == ["POST", "DELETE", "DELETE"] and w[0][2][0]["same_as"] == "e9"
           and "event_id=eq.e1" in w[1][1] and "found_at=lt." in w[1][1] and "event_id=eq.e3" in w[2][1],
           f"each Event read gets its new parts written, then its old ones taken away (a failed write never empties "
           f"it), a found one pointing at the listed Event: {w}")
        ok(lines[0] == "- Parts of long Events: 1" and any("Take it down" in l for l in lines), f"the report: {lines}")
        ok(keep(Run(folder, today, FakeDb(answers=answers))) == lines, "a finish run again neither writes nor reports twice")

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning"
        r = Run(folder, today, FakeDb(answers=answers))
        prepare(folder / "parts", r.db, today, read)
        (folder / "parts.jsonl").write_text(json.dumps(dict(talk, event="p1")) + "\n")
        r.db.calls.clear()
        ok(not keep(r) or not r.db.writes(), "a helper with no answers at all: nothing is replaced, tried tomorrow")

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning"
        r = Run(folder, today, FakeDb(answers=answers))
        prepare(folder / "parts", r.db, today, read)
        (folder / "parts.jsonl").write_text(json.dumps(dict(talk, event="p1")) + "\n")
        (folder / "parts-2.jsonl").write_text(json.dumps(dict(talk, event="p2", title="Keynote")) + "\n")
        r.db.calls.clear()
        lines = keep(r)
        ok(not r.db.writes("event_parts") and any("left as they were" in l for l in lines),
           f"one helper names parts and the other none: that Event's parts are left as they were: {r.db.writes()} {lines}")

    def broken(method, path, body):
        raise DbError("GET", path, 404, '{"message":"relation public.event_parts does not exist"}')
    with tempfile.TemporaryDirectory() as tmp:
        ok(prepare(Path(tmp) / "parts", FakeDb(answers={"event_parts": broken}), today, read) == [],
           "a database without the table skips the step: nothing is read, no helper runs")

    failed = [why for good_, why in checks if not good_]
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
    r = Run(registry.find_root() / ".runs" / "morning", datetime.now(LOCAL).date(), run.Supabase())
    if a.step == "prepare":
        prepare(r.folder / "parts", r.db, r.today)
    elif a.step == "keep":
        print("\n".join(keep(r, a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
