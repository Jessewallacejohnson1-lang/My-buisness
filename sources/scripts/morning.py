#!/usr/bin/env python3
"""
morning.py: the parts of the morning job that need no model (BP app
docs/plans/watch-every-place, ticket 05). The routine's steps are sources/models/morning.md.

  prepare   fetch every watched page the polite way (run.fetch_watched; yesterday's
            fingerprints are in the database), read the feeds and data sources (read_events.py),
            and lay out only the changed pages in batches of 12 for the cheap model (batch.py), with
            the events already listed for the judge; a changed page of a seasonal place (its
            `places.hours` has a season) goes to seasons.txt with its lines that name a month,
            for the routine to flag new season dates (BP app business-hours, Jesse 2026-10-26).
            It works in parts of about 6 minutes, since the cloud stops a command at 10 (BP app
            smooth-mornings 03): run it again while it prints "run again". A page failing three
            mornings' reads in a row is set aside, skipped except on Mondays, and named only the
            morning it is set aside and the morning it is back; one line a morning counts the pages
            that failed, naming the town's own (smooth-mornings 04)
  titles    list the event titles still over 40 characters once tidied (games aside), then the News titles
            past their card's 2 lines, in .runs/morning/titles.txt, for the routine's model to shorten into
            titles.json (.claude/skills/title-and-place; Jesse, 2026-10-21; BP app inside-cards 13)
  save      once the judge is done: merge the feed items with the judge's items, give long titles their
            short ones (titles.json), write them (public.apply_judged over the service role key), put a post's
            new lasting week on its place (save_hours: the judge's `hours` items, social.md), then save
            the changed pages' new fingerprints (fingerprints.json) and print the morning's summary: a
            morning that stops before this reads the same pages again tomorrow. Its new counts are what the
            database did (apply_judged's answer), and it lists each new Event (date, time, title, place;
            soonest first, 40 at most, the rest counted by source) and News title, names News folded into
            their post's News (BP app smooth-mornings 05), the pairs the writer kept apart under "Maybe
            the same", and the morning's also tells yesterday's SJU and CSB games: how far each live score got
            and where its final came from (Jesse, 2026-10-29). The summary waits in report.json for finish, and a second save the same morning
            writes nothing again (Oct 22's job wrote twice). Then it lays out the helpers' work: the Events
            no tagger has read yet (or that have no draw, or no words saying what they are), upcoming or
            still running, in batches of 40 for the cheap model (town-feed tickets 33 and 34, BP app
            event-card 05; sources/models/tag.md), and the upcoming Events found in the last two days whose
            About is empty or under a sentence (feed and catalog events skip the judge), at most 30, in
            batches of 10 for the routine's helpers to research (sources/models/describe.md; Jesse,
            2026-10-24), never a game (write_judged.is_game: its reader wrote its About) or an Event laid
            out before (smooth-mornings 06), and each campus Event linking to its sign-up page once even with a
            full About (event-details), each with the text of its own link, read politely within the
            rest of the part's 6 minutes (Jesse, 2026-10-29). A social check (social.py prepare) only writes
  today     once every helper has answered: lay out today's Events as the Town feed takes them, with the
            helpers' tags and Abouts not saved yet, for the routine's model to pick the day's standouts (BP
            app docs/plans/daily-tab, ticket 14; sources/models/standouts.md)
  finish    once every helper has answered: write the cheap model's tags (.runs/morning/tags.jsonl)
            onto those Events: only ids from the shared interest list, a draw of 1, 2 or 3, an Event's
            first interest becomes its category when it has none, and what it is in one to three words; an
            Event tagged before only gets its words, so nobody's feed reshuffles. One write per Event (901
            on 2026-10-27), so it works in parts like prepare. Then the helpers' Abouts
            (.runs/morning/describe.jsonl), each only when longer than the one it has, marking every Event
            they answered as researched (club_events.described_at), and the model's standouts
            (.runs/morning/standouts.jsonl) as today's daily_standouts, best first. It ends with the whole
            morning report: save's summary, the tag, describe (with its CHECK lines) and standouts lines,
            every Event added since the last report (the social watch's and a chat's too) whose card shows no
            photo of what it is (BP app event-photos 08), the social watch's Apify spend (social.py spend; Jesse, 2026-10-22), asked here so no
            step can skip it (Oct 29's run did), and Firecrawl's credits left (BP app backlog 12). The routine answers with it (BP app smooth-mornings 07).
            A save that fails is one line in the report, and finish run again writes only what is left

Everything lands in .runs/morning/, which morning_run.py owns: each step takes a Run (its folder, day,
town, part's clock and database). Every command needs SUPABASE_URL and a key in the environment (db.py);
`save --dry-run`, then `finish --dry-run`, write nothing.

  python3 sources/scripts/morning.py prepare [--today YYYY-MM-DD] [--town T]
  python3 sources/scripts/morning.py titles
  python3 sources/scripts/morning.py save [--dry-run] [--town T]
  python3 sources/scripts/morning.py today
  python3 sources/scripts/morning.py finish [--dry-run] [--town T]
  python3 sources/scripts/morning.py --selftest

--town names a sources/towns/ file (default st-joseph-mn, towns.DEFAULT).
"""

import argparse, collections, contextlib, json, math, re, shutil, subprocess, sys, time, urllib.error
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL, CAMPUS_HOSTS
from batch import layout, page_id
import write_judged
import accounts
import social
import spots
import find_spots
import apple_maps
from towns import TOWNS, DEFAULT, lookup
from run import Supabase, fetch, fetch_watched, firecrawl_credits, to_text, deadline, late, minutes_left, part_state, resume_part, aside_lines
from morning_run import Run, FakeDb
from db import DbError

SCRIPTS = Path(__file__).resolve().parent
TAG_BATCH = 40
TAG_MAX = 5  # interests an Event carries at most (onboarding 21)
STANDOUTS = 9
THIN = 120        # characters: an About under this says less than a sentence
DESCRIBE_MAX = 30  # Events a morning; the rest wait for tomorrow
DESCRIBE_BATCH = 10
PAGE_MAX = 3000    # characters of an Event's own page its helper reads
ABOUT_MAX = 1000   # as write_judged.clip
PRICE_MAX = 60     # characters: a price is one short line under the place ("$22, $20 seniors, $15 students")
# An About naming a cost: its helper moves the cost to `price` (inside-cards 14), so the judge's blurbs come clean too.
COST = re.compile(r"\$\s?\d|\bfree\b", re.I)
LIST_MAX = 40  # new Events listed one by one; the rest as a count per source (a first read can add hundreds)
FEEDS = {"ical"}  # the feed reader's; an RSS feed is posts, read like a page (run.py keeps their dates)


def to_model(entry, source):
    """A changed page goes to the cheap model only when no reader or calendar feed covers it.
    An RSS feed has no reader: its items are a place's posts, which the judge has to sort like
    any page (watch-every-place 06, amending the spec's feeds-never-a-model rule)."""
    return (entry.get("tier", "listed") == "watched" and not source.get("reader")
            and source.get("kind") not in FEEDS and source.get("method") == "fetch")


def pages_to_read(changed, entries):
    """run.py's changed pages, as the batches want them: an id, the URL, the text. A page seen
    for the first time only gets its starting copy (Jesse, 2026-10-15), so a batch of newly
    watched places doesn't send hundreds of pages to the model at once."""
    by_source = {(e["id"], s.get("url")): (e, s) for e in entries for s in e.get("sources") or []}
    out = []
    for c in changed:
        e, s = by_source.get((c["entry_id"], c["url"]), (None, None))
        if e and to_model(e, s) and c.get("snapshot") and not c.get("first_seen"):
            out.append({"file": Path(c["snapshot"]).stem, "url": c["url"], "snapshot": c["snapshot"],
                        "entry_id": e["id"], "name": e["_name"], "category": e.get("category"),
                        "trust": s.get("trust") or "official"})
    return out


MONTH = re.compile(r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2}\b|\b\d{1,2}/\d{1,2}\b", re.I)


def season_pages(pages, seasons):
    """Each changed page of a seasonal place: the season the app shows, then the page's lines that
    name a date, for the routine to compare. Empty when none changed."""
    out = []
    for p in pages:
        place = seasons.get(p["entry_id"])
        if not place:
            continue
        start, end = place["hours"]["season"]
        lines = [ln.strip() for ln in p["text"].splitlines() if MONTH.search(ln)][:40]
        out.append(f"## {place['name']}\nThe app's season: {start} to {end} (month-day)\nPage: {p['url']}\n"
                   + "\n".join(lines) + "\n")
    return "\n".join(out)


def snapshot_text(path):
    """run.py's snapshot without its frontmatter."""
    text = Path(path).read_text()
    return text.split("\n---\n", 1)[1].lstrip() if text.startswith("---\n") else text


def start_reader(out, today, name, which, stop):
    """read_events.py for one group of readers, as a part of `prepare` that starts no source after
    `stop`: its output in <name>.log, its items in <name>-items.jsonl once every source is read."""
    with open(out / f"{name}.log", "w") as log:
        return subprocess.Popen([sys.executable, str(SCRIPTS / "read_events.py"), *which,
                                 "--items", str(out / f"{name}-items.jsonl"), "--today", str(today),
                                 "--part", str(out / f"{name}-part.json"),
                                 *(["--minutes", f"{(stop - time.monotonic()) / 60:.3f}"] if stop else [])],
                                stdout=log, stderr=subprocess.STDOUT, text=True, cwd=find_root())


def reader_lines(proc, out, name):
    """A group of readers' [read] lines once it is through (its items written, or it failed), else None."""
    code, log = proc.wait(), (out / f"{name}.log").read_text()
    if code:
        (out / f"{name}-items.jsonl").write_text("")
        return [f"[read] FAILED read_events.py itself: {log.strip()[-300:]}"]
    if (out / f"{name}-items.jsonl").exists():
        return [ln for ln in log.splitlines() if ln.startswith("[read] ok") or ln.startswith("[read] FAILED")]
    return None


def prepare(run):
    """In timed parts: each starts no new page or reader after the part's minutes, saves what it read in
    prepare-part.json and says "run again" with what is left; the next part carries on, each page
    fetched once a morning. The part that finishes lays out the batches and prints the summary.
    Only the run's town's registry entries are fetched and laid out; the sync still covers every town's."""
    out, today, town, db, stop = run.folder, run.today, run.town, run.db, run.stop
    state, part = run.begin("prepare-part.json", {"pages": [], "readers": {}, "state": {}})
    if state == "busy":
        return print("[morning] another prepare is still running in this copy: let it finish, and start no second one")
    if state == "prepared":
        print("[morning] prepared already this morning: nothing fetched again")  # before finish, never start over
        return say_prepared(run.summary(), out)
    saved = part.saved
    resume_part(saved["state"])
    root = find_root()
    every, errors = load(root)
    if errors:
        sys.exit("[morning] registry invalid:\n" + "\n".join(errors))
    entries = [e for e in every if e.get("status") == "active" and e["_town"] == town]

    # The league's site is slow and no other source's server (twelve minutes for the schools
    # on 2026-10-25, with its retries), so the schools are read while the pages are fetched.
    done = saved["readers"]
    games = None if "games" in done else start_reader(out, today, "games", ["--reader", "mshsl", "--town", town], stop)
    try:
        with open(out / "fetch.log", "a") as log, contextlib.redirect_stdout(log):
            report = fetch_watched(every, db, picked=[e for e in entries if e.get("tier", "listed") == "watched"],
                                   done=saved["pages"], stop=stop, run_dir=out / "fetch", today=today)
    except BaseException:
        if games:
            games.kill()
        raise
    saved.update(pages=report["results"], state=part_state())
    # ponytail: a part killed after fetch_watched recorded its pages but before this line loses their results:
    # the next part fetches them again (a morning counts once, run.set_aside) but a page set aside or back
    # in the lost part goes unnamed. Save each result as it is recorded if that is ever seen.
    part.save()  # before waiting on the readers: a stopped part keeps its pages
    # The feeds share servers with the pages, so they are read after them.
    feeds = None
    if not report["left"] and "feeds" not in done and not late(stop):
        feeds = reader_lines(start_reader(out, today, "feeds", ["--skip-reader", "mshsl", "--town", town], stop), out, "feeds")
    for name, lines in (("feeds", feeds), ("games", games and reader_lines(games, out, "games"))):
        if lines is not None:
            done[name] = lines
    saved.update(pages=report["results"], state=part_state())
    part.save()
    left = [what for name, what in (("games", "the school schedules"), ("feeds", "the feeds")) if name not in done]
    if report["left"] or left:
        print(f"[morning] run again: {report['fetched']} of {report['fetched'] + report['left']} pages fetched"
              + (f"; still to read: {' and '.join(left)}" if left else ""))
        return
    run_dir = Path(report["run_dir"])
    # Saved by `write` once the events are in (db.commit_fingerprints), never here.
    (out / "fingerprints.json").write_text(json.dumps(
        [{k: c[k] for k in ("entry_id", "url", "hash", "first_seen")} for c in report["changed"]], indent=1))
    readers = done["feeds"] + done["games"]
    (out / "feeds.jsonl").write_text((out / "feeds-items.jsonl").read_text() + (out / "games-items.jsonl").read_text())

    pages = pages_to_read(report["changed"], entries)
    for p in pages:
        p["text"] = snapshot_text(run_dir / "snapshots" / p["snapshot"])
    for i, text in enumerate(layout(pages, today, TOWNS[town]["display"]), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(text)
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in pages], indent=1))
    (out / "existing.json").write_text(json.dumps(write_judged.listed_in_db(db), indent=1, default=str))
    seasons = {r["entry_id"]: r for r in db.rest(
        "GET", "places?select=name,entry_id,hours&entry_id=not.is.null&hours->season=not.is.null")}
    (out / "seasons.txt").write_text(season_pages(pages, seasons))

    summary = {"today": str(today), "fetched": report["fetched"], "changed": len(report["changed"]),
               "first_seen": sum(1 for c in report["changed"] if c.get("first_seen")),
               "to_read": len(pages), "batches": len(list((out / "batches").iterdir())),
               "aside": aside_lines(report, today),  # a failing page is named only when set aside or back (smooth-mornings 04)
               "unrecorded": report["unrecorded"],
               "readers": readers, "interests": write_judged.interest_ids()}
    run.prepared(summary)
    say_prepared(summary, out)


def say_prepared(s, out):
    print(f"[morning] fetched {s['fetched']} watched pages, {s['changed']} changed, "
          f"{s['to_read']} for the cheap model in {s['batches']} batches ({out / 'batches'})")
    for ln in s["readers"]:
        print(ln)
    for a in s["aside"]:
        print(f"[morning] {a}")
    for ln in not_recorded_lines(s):
        print(ln)
    print(f"[morning] interests: {', '.join(s['interests'])}")


def not_recorded_lines(prep):
    """A page whose check the database refused (run.fetch_watched carries on past it), worded as a
    failed step so the 8 AM check (private.morning_problems) emails it."""
    return [f"[morning] recording {u['entry_id']} {u['url']} failed: {' '.join(u['error'].split())[:300]}"
            for u in prep.get("unrecorded", [])]


def read_items(path):
    items = []
    if path.exists():
        for ln in path.read_text().splitlines():
            if ln.strip():
                try:
                    items.append(json.loads(ln))
                except ValueError:
                    items.append(f"unreadable line: {ln[:60]}")
    return items


def summary_lines(prep, result, written):
    """The new counts are what the database did (apply_judged's `added`: smooth-mornings 05), and the new
    Events and News are listed from the rows it added. A dry run's are the plan's."""
    count = {}
    for what, _ in result["outcomes"]:
        count[what] = count.get(what, 0) + 1
    sent = write_judged.payloads(result)
    answered = isinstance((written or {}).get("added"), dict)
    added = written["added"] if answered else {"events": [i for i, g in enumerate(g for g in result["events"] if g["row"])
                                                          if not g["old"]], "news": range(len(sent["p_news"]))}
    events, news = [sent["p_events"][i] for i in added["events"]], [sent["p_news"][i] for i in added["news"]]
    lines = [f"Social watch ({prep['run']}), {prep['today']}" if prep.get("run") else f"Morning watch, {prep['today']}",
             f"- Pages: {prep['fetched']} fetched, {prep['changed']} changed, {prep['to_read']} read by the cheap model"
             + (f", {prep['first_seen']} new kept as a starting copy" if prep.get("first_seen") else ""),
             f"- Events: {len(events)} new, {count.get('published', 0) + count.get('merged', 0) - len(events)} already listed",
             f"- News: {len(news)} new, {count.get('news', 0) + count.get('repeat', 0) - len(news)} repeats left out"
             + (f", {count['folded']} folded into the News of the post they came in" if count.get("folded") else ""),
             f"- Skipped: {count.get('skipped', 0)} (past, outside the area or unreadable)"]
    lines += [f"- Source failed: {f}" for f in prep.get("failed", [])]
    lines += [f"- {a}" for a in prep.get("aside", [])]
    lines += not_recorded_lines(prep)
    lines += [f"- Reader failed: {r.split('FAILED', 1)[1].strip()}" for r in prep["readers"] if "FAILED" in r]
    lines += [f"- Folded: {detail}" for what, detail in result["outcomes"] if what == "folded"]
    lines += [f"- Still over {write_judged.TITLE_MAX} characters: {g['row']['title']}" for g in result["events"]
              if g["row"] and len(g["row"]["title"]) > write_judged.TITLE_MAX]
    lines += [f"- Still past its 2 lines: {n['title']}" for n in news if not write_judged.headline_fits(n["title"])]
    lines += [f"- Cancelled: {str(o['event_date'])[:10]} {o['title']}, gone from its schedule" for o in result.get("cancelled", [])]
    lines += [f"- Back on: {str(o['event_date'])[:10]} {o['title']}" for o in result.get("restored", [])]
    if written is None:
        lines.append("- Dry run: nothing written")
    elif answered:
        lines.append(f"- Written: {written['mentions']} mentions, {written['published_by_mention']} published by a "
                     f"mention, {written['cancelled']} cancelled, {written['restored']} back on")
    else:
        lines.append(f"- Written: {json.dumps(written)}; the save didn't say which items it added, so the "
                     "counts above are what was sent (apply_judged from before smooth-mornings 05)")
    lines += ["New Events:"] * bool(events) + event_lines(events)
    lines += ["New News:"] * bool(news) + [f"- {n['title']} ({n['source_name']})" for n in news]
    notes = result.get("notes", [])
    pairs, rest = maybe_same(notes), [n for n in notes if not n.startswith("kept apart: ")]
    lines += ["Maybe the same:"] * bool(pairs) + [f"- {p}" for p in pairs]
    rest = short_notes(rest, events)
    lines += ["Notes:"] * bool(rest) + [f"- {n}" for n in rest]
    return lines


ROUTINE_NOTES = ("place not in the registry: ", "who is this: ")


def short_notes(notes, events):
    """The writer says these of every calendar item it re-reads, the same ones each morning: 1,104 of the report's 1,198
    lines on Nov 5, 125 KB of its 133. Those on today's new Events stay by name, the rest are a count."""
    titles, places = {repr(e["title"]) for e in events}, "\n".join(e.get("location") or "" for e in events)

    def on_new_event(n):
        if n.startswith("who is this: "):
            return any(t in n for t in titles)
        return n.split(": ", 1)[1].rsplit(" (", 1)[0][1:-1] in places

    kept = [n for n in notes if not n.startswith(ROUTINE_NOTES) or on_new_event(n)]
    older = {n for n in notes if n.startswith(ROUTINE_NOTES)} - set(kept)
    missing = sum(n.startswith(ROUTINE_NOTES[0]) for n in older)
    return list(dict.fromkeys(kept)) + [f"On Events already listed, places not in the registry: {missing}, "
                                        f"names that are no team's: {len(older) - missing}"] * bool(older)


def maybe_same(notes):
    """The pairs the writer kept apart but can't be sure of (same day, same place or title), for Jesse to
    settle once. watch-every-place 14 gives the writer its own "Maybe the same" notes: take those here."""
    return [n.removeprefix("kept apart: ").split("; if they are one event", 1)[0] for n in notes
            if n.startswith("kept apart: ")]


def event_lines(rows):
    """The new Events soonest first, each with its date, time, title and place (Jesse's morning-report
    rule, 2026-10-22); past LIST_MAX, the rest as a count for each source."""
    rows = sorted(rows, key=lambda r: r["event_date"])
    rest = collections.Counter(r["source_name"] for r in rows[LIST_MAX:])
    return [f"- {new_event(r)}" for r in rows[:LIST_MAX]] + [f"- {n} more from {s}" for s, n in rest.most_common()]


def new_event(row):
    """One new Event's line. A run over days says its last day ("Mon Oct 26 to Fri Oct 30"): its end less
    6 hours, so a run that ends at the midnight after its last day, or a night that ends at 1 AM, reads right."""
    day = date.fromisoformat(row["event_date"])
    last = row.get("end_at") and (datetime.fromisoformat(row["end_at"]).astimezone(LOCAL) - timedelta(hours=6)).date()
    when = f"{day:%a %b} {day.day}" + (f" to {last:%a %b} {last.day}" if last and last > day else "")
    return " · ".join(x for x in (when, "all day" if row["all_day"] else row["start_time"],
                                  row["title"], row["location"]) if x)


def waiting_lines(db):
    """Games held back until both teams have logos (Jesse, 2026-11-05, game-card 16), so a logo never found is seen:
    they show nowhere else. A read that fails is one line, never a lost report."""
    try:
        rows = db.rest("GET", "club_events?select=team_ids&status=eq.waiting_logo&kind=eq.event&cancelled_at=is.null") or []
        bare = {t["id"]: t["name"] for t in db.rest("GET", "teams?select=id,name&logo_url=is.null") or []}
    except Exception as e:
        return [f"- Waiting on a logo: couldn't read them ({e})"]
    teams = collections.Counter(t for r in rows for t in r["team_ids"] or [] if t in bare)
    named = ", ".join(f"{bare[t]} {n}" for t, n in teams.most_common(10))
    return [f"- Waiting on a logo: {len(rows)} games, teams {named}" + (", and more" if len(teams) > 10 else "")] if rows else []


def since_lines(db, today):
    """What the evening's social watches and any chat wrote after the last report and before this morning's run, still
    showing: Nov 4's evening wrote 5 Events and 5 News, 2 of them doubles, and no list named them. A read that fails is
    one line, never a lost report."""
    head = "Since the last report:"
    try:
        last = db.rest("GET", f"morning_reports?select=saved_at&day=lt.{today}&order=day.desc&limit=1") or []
        if not last:
            return []
        day = date.fromisoformat(str(today))
        span = (f"&created_at=gt.{quote(last[0]['saved_at'])}"
                f"&created_at=lt.{quote(datetime(day.year, day.month, day.day, 5, tzinfo=LOCAL).isoformat())}")
        events = db.rest("GET", "club_events?select=event_date,end_at,all_day,start_time,title,location,source_name"
                                f"&status=eq.approved&kind=eq.event&cancelled_at=is.null&event_date=gte.{day}{span}") or []
        news = db.rest("GET", f"board_items?select=title,source_name&status=eq.published{span}") or []
        # A week a post changed (save_hours): its mark's time, in UTC as saved
        before = datetime(day.year, day.month, day.day, 5, tzinfo=LOCAL).astimezone(timezone.utc).isoformat()
        hours = [f"- Hours: {accounts.change_words(p['name'], p['hours'])}" for p in db.rest(
            "GET", f"places?select=name,hours&hours->from->>at=gt.{quote(last[0]['saved_at'])}"
                   f"&hours->from->>at=lt.{quote(before)}") or []]
    except Exception as e:
        return [f"{head} not read ({' '.join(str(e).split())[:200]})"]
    return [head] * bool(events or news or hours) + event_lines(events) + [f"- {n['title']} ({n['source_name']})" for n in news] + hours


def place_lines(db):
    """The place pages' counts (BP app place-pages 01): every open place, and how many have an Apple id, hours, a
    logo in Search and a live photo, so the gap to a complete directory is one line. A read that fails is one line."""
    try:
        rows = db.rest("GET", "places?select=entry_id,apple_place_id,hours,search_logo&closed_at=is.null") or []
        photos = {r["entry_id"] for r in db.rest("GET", "place_photos?select=entry_id&status=eq.live&kind=eq.photo") or []}
    except Exception as e:
        return [f"- Places: not counted ({' '.join(str(e).split())[:200]})"]
    return [f"- Places: {len(rows)} open, {sum(1 for r in rows if r.get('apple_place_id'))} with an Apple id, "
            f"{sum(1 for r in rows if r.get('hours'))} with hours, {sum(1 for r in rows if r.get('search_logo'))} with a logo, "
            f"{sum(1 for r in rows if r.get('entry_id') in photos)} with a photo"]


def photo_lines(db, today):
    """Every Event added since the last morning's report whose card shows its place's photo or logo, not a photo
    of what it is: this morning's, the social watch's of the evening before, and any a chat added (Jesse,
    2026-11-02: Pizza night, a boutique's Holiday Collection and the Snowflake Shuffle slipped by a list that
    named only the morning's own). Read at finish, after the Helpers saved each Event's photo: none of its own
    (event_photos.py, event-photos 09), no flyer of its own, and no live scene of its place fits its subject
    and season (BP app event-photos 08), so each is a place and subject for the next photo round (the
    place-photos skill's scenes.py). A game is left out, by the card's own rule (place_photos.game_card): the
    white game card has no photo. A read that fails is one line, never a lost report."""
    head = "No event photo yet:"
    try:
        import place_photos  # here, as event_photos does: it loads Pillow, and a failed import is one line
        last = db.rest("GET", f"morning_reports?select=saved_at&day=lt.{today}&order=day.desc&limit=1") or []
        since = last[0]["saved_at"] if last else (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        rows = [r for r in db.rest("GET", "club_events?select=id,event_date,end_at,all_day,start_time,title,location,"
                                          "source_name,sport,team_ids&status=eq.approved&kind=eq.event&cancelled_at=is.null"
                                          f"&created_at=gt.{quote(since)}&event_date=gte.{today}") or []
                if not place_photos.game_card(r)]
        # An Event with its own live photo (kind 'event', event-photos 09) is done, whatever URL its card read; a
        # retired one doesn't count.
        done = {p["event_id"] for p in db.rest("GET", "place_photos?select=event_id&kind=eq.event&status=eq.live"
                                                     f"&event_id=in.({','.join(r['id'] for r in rows)})") or []} if rows else set()
        rows = [r for r in rows if r["id"] not in done]
        shown = {r["id"]: (db.rest("POST", "rpc/event_picture", {"p_event": r["id"]}) or {}).get("url") for r in rows}
        urls = ",".join(f'"{u}"' for u in set(shown.values()) if u)
        own = {s["url"] for s in db.rest("GET", f"place_photos?select=url&kind=in.(scene,event,flyer)&url=in.({quote(urls)})")
               or []} if urls else set()
    except Exception as e:
        return [f"{head} not read ({' '.join(str(e).split())[:200]})"]
    bare = [r for r in rows if shown[r["id"]] not in own]
    return [head] * bool(bare) + event_lines(bare)


# The games the live-scores job follows: private.sidearm_file's pairs, compared by a self-test with the newest
# migration that defines it. live_games reads only a start like these, and one such game a school plays a day.
LIVE_SPORTS = {"SJU Athletics/Football", "SJU Athletics/Soccer", "SJU Athletics/Basketball", "SJU Athletics/Hockey",
               "CSB Athletics/Soccer", "CSB Athletics/Volleyball", "CSB Athletics/Basketball", "CSB Athletics/Hockey"}
CLOCK_START = re.compile(r"^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$")


def live_lines(db, day, rows=None, marks=None):
    """A day's games the live-scores job follows, one line each: how far its live score got, which source carried
    it, which reads failed and why, and where its final came from, so a game that went blind shows in the morning
    report with no chat watching it (Jesse, 2026-10-29; game-card 22). A read that fails is one line, never a lost
    report. marks: public.live_marks's rows by Event id."""
    head = f"Live games {day:%a %b} {day.day}:"
    if rows is None:
        try:
            schools = ",".join(sorted({f'"{p.split("/")[0]}"' for p in LIVE_SPORTS}))
            rows = db.rest("GET", "club_events?select=id,title,start_time,source_name,sport,live_score,scoring_plays,"
                                  f"final_score&event_date=eq.{day}&source_name=in.({quote(schools)})"
                                  "&team_ids=not.is.null&status=eq.approved&cancelled_at=is.null&order=start_time") or []
        except Exception as e:
            return [f"{head} not read ({' '.join(str(e).split())[:200]})"]
        try:
            marks = {m["event_id"]: m for m in db.rest("POST", "rpc/live_marks", {"p_events": [r["id"] for r in rows]}) or []}
        except Exception as e:
            head += f" (which source carried each not read: {' '.join(str(e).split())[:200]})"
    games = [(f"{r['source_name']}/{r['sport']}", r) for r in rows if f"{r['source_name']}/{r['sport']}" in LIVE_SPORTS]
    that_day = collections.Counter(sport for sport, _ in games)
    lines = [head] * bool(games)
    for sport, r in games:
        live, final = r.get("live_score"), r.get("final_score")
        score = final and "-".join(map(str, final))
        backup = f"final {score} from the backup check" if final else "no final"
        mark = (marks or {}).get(r.get("id")) or {}
        sources = mark.get("sources") or []
        carried = [s["name"] for s in sorted(sources, key=lambda s: -s["wrote"]) if s["wrote"]]
        by = f" from {' and '.join(carried)}" if carried else ""
        if live and live.get("complete") and final == live.get("score"):
            plays = len(r.get("scoring_plays") or [])
            how = f"live to the final{by}, {score}" + (f" ({plays} scoring plays)" if plays else "")
        elif live:
            at = datetime.fromisoformat(live["at"]).astimezone(LOCAL)
            how = f"live until {at:%-I:%M %p}{by}, then {backup}"
        elif that_day[sport] > 1:
            how = f"not followed live, {that_day[sport]} games that day; {backup}"
        elif not CLOCK_START.match((r.get("start_time") or "").strip().lower()):
            how = f"not followed live, no start time; {backup}"
        else:
            how = f"never went live; {backup}"
        failed = [f"{s['name']} {s['failed']} ({s['why']})" for s in sources if s["failed"]]
        how += f"; failed reads: {', '.join(failed)}" if failed else ""
        if mark.get("alerted_at"):
            how += f"; dark alert {datetime.fromisoformat(mark['alerted_at']).astimezone(LOCAL):%-I:%M %p}"
        elif mark.get("alert_why"):
            how += f"; dark alert not sent ({mark['alert_why']})"
        lines.append(f"- {r['title']}, {r.get('start_time') or 'no time'}: {how}")
    return lines


def long_titles(run):
    out = run.folder
    items = read_items(out / "feeds.jsonl") + read_items(out / "judged.jsonl")
    titles = write_judged.long_titles(items, write_judged.listed_in_db(run.db))
    news = write_judged.long_headlines(items, write_judged.news_titles_in_db(run.db))
    heading = [f"News, {write_judged.NEWS_TITLE_MAX} characters at most:"] if news else []
    (out / "titles.txt").write_text("".join(t + "\n" for t in titles + heading + news))
    print(f"[morning] {len(titles)} titles over {write_judged.TITLE_MAX} characters"
          + (f", {len(news)} News past their 2 lines" if news else "") + f" ({out / 'titles.txt'})")


def short_titles(out):
    """titles.json, {long: short}: only shorter ones, so a slip never makes a title longer."""
    path = out / "titles.json"
    try:
        got = json.loads(path.read_text()) if path.exists() else {}
    except ValueError:
        print(f"[morning] {path} unreadable: titles kept as they are")
        return {}
    return {k: v.strip() for k, v in got.items() if isinstance(k, str) and isinstance(v, str)
            and 0 < len(v.strip()) < len(k)} if isinstance(got, dict) else {}


def write(run, dry_run):
    out, today, db = run.folder, run.today, run.db
    prep = run.summary()
    feeds, judged = read_items(out / "feeds.jsonl"), read_items(out / "judged.jsonl")
    hours = [x for x in judged if isinstance(x, dict) and x.get("kind") == "hours"]
    items = feeds + [x for x in judged if not (isinstance(x, dict) and x.get("kind") == "hours")]
    existing = write_judged.listed_in_db(db)
    result = write_judged.plan(items, existing, today, write_judged.interest_ids(), TOWNS[run.town], titles=short_titles(out),
                               teams=write_judged.known_teams(db), recent_news=write_judged.news_in_db(db=db))
    write_judged.report(items, result)
    try:
        written = None if dry_run else write_judged.apply(result, db)
        if not dry_run:  # saved before the summary, so a slip in printing it never re-reads these pages tomorrow
            save_fingerprints(run)
        # A social check's summary leaves the games to the morning's.
        lines = summary_lines(prep, result, written) + save_hours(run, hours, dry_run) \
            + ([] if prep.get("run") else waiting_lines(db)) + ([] if prep.get("run") else live_lines(db, today - timedelta(days=1)))
        print("\n".join(lines))
        return lines
    except DbError as e:  # one line naming what refused it (smooth-mornings 02), not a traceback
        sys.exit(f"[morning] save refused: {' '.join(str(e).split())}")


def save_hours(run, items, dry_run):
    """A place's new lasting week, from its own post (social.md; BP app business-hours 02, Jesse 2026-11-07: it goes
    live on its own and Jesse is told after, as the monthly Google check's does). Each `hours` item's days, in
    Google's words, go on the place that posted (its page in pages.json), over the week it has: its season and
    the days the post doesn't name stay. The week is marked `from` that post, so the monthly Google check leaves
    it (accounts.new_hours). One line per change, before and after; an item it can't read, two posts of one place
    that disagree, and a few days over a place with no whole week are each a line, and written nowhere."""
    if not items:
        return []
    pages = {page_id(p["file"]): p for p in json.loads((run.folder / "pages.json").read_text())}
    at, found, lines = datetime.now(timezone.utc).isoformat(), {}, []
    for x in items:
        page, days = pages.get(page_id(x.get("page") or "")), x.get("days")
        days = {d: accounts.day_ranges(str(t)) for d, t in days.items()} if isinstance(days, dict) else {}
        if not page or not page.get("entry_id") or not days or set(days) - set(accounts.DAY_KEYS) or None in days.values():
            lines.append(f"- Hours not read: {json.dumps(x, ensure_ascii=False)[:200]}")
            continue
        # One place's posts on two sites, one week: the first post names it. Two weeks that disagree: neither.
        got = found.setdefault(page["entry_id"], {"entry_id": page["entry_id"], "name": page["name"],
                                                  "hours": {"from": {"post": page["url"], "at": at}}})
        if any(got["hours"].get(d, t) != t for d, t in days.items()):
            got["clash"] = True
        got["hours"] = {**days, **got["hours"]}
    lines += [f"- Hours not written: {f['name']}'s posts give two different weeks" for f in found.values() if f.get("clash")]
    try:
        changes, _ = accounts.write_hours([f for f in found.values() if not f.get("clash")], run.db.rest, write=not dry_run)
    except DbError as e:  # the 8 AM check reads a "[morning] ... failed:" line
        return lines + [f"[morning] hours failed: {' '.join(str(e).split())[:300]}"]
    return lines + [f"- Hours not written: {c['name']}, from its post {c['hours']['from']['post']}: it names only "
                    f"{', '.join(d.title() for d in accounts.DAY_KEYS if d not in c['short'])}, and the app has no hours "
                    f"for {', '.join(d.title() for d in c['short'])}" if c.get("short")
                    else f"- Hours: {accounts.change_words(c['name'], c['hours'])}" for c in changes]


def save_fingerprints(run):
    """After the write: the changed pages' new fingerprints, so tomorrow sees them unchanged.
    No file (a social check) has none."""
    path = run.folder / "fingerprints.json"
    changed = json.loads(path.read_text()) if path.exists() else []
    if changed:
        run.db.commit_fingerprints(changed)
        print(f"[morning] {sum(not c.get('first_seen') for c in changed)} changed pages' fingerprints saved")


def to_tag(db, today):
    """Approved Events no tagger has read or rated, or with no words saying what they are, still to
    come or still running, as the tagger reads them. `tagged`: read and rated before, so only its
    words are written."""
    rows = db.rest("GET", "club_events?select=id,title,location,description,category,source_name,"
                          "interests_tagged_at,draw,clubs(name)"
                   "&status=eq.approved&kind=eq.event"
                   f"&and={quote(f'(or(interests_tagged_at.is.null,draw.is.null,what.is.null),or(event_date.gte.{today},end_at.gte.{today}))')}"
                   "&order=event_date&limit=1000")
    return [{"id": r["id"], "title": r["title"], "host": (r.get("clubs") or {}).get("name") or r.get("source_name") or "",
             "place": r.get("location") or "", "about": " ".join((r.get("description") or "").split())[:300],
             "category": r.get("category"),
             "tagged": bool(r.get("interests_tagged_at") and r.get("draw"))} for r in rows]


def tag_message(events, interests):
    return ("Interests: " + ", ".join(interests) + "\n\nEvents:\n"
            + "\n".join(json.dumps({k: v for k, v in e.items() if k != "tagged"}, ensure_ascii=False)
                        for e in events) + "\n")


WHAT_MAX = 24  # characters, as club_events_what_short


def what_words(what):
    """What an Event is, in one to three words, its first letter a capital ("Cross country meet"),
    else None."""
    if not isinstance(what, str):
        return None
    w = " ".join(what.split()).strip(" .")
    if not w or len(w) > WHAT_MAX or len(w.split()) > 3:
        return None
    return w[0].upper() + w[1:]


def untagged(run):
    tag_dir = run.folder / "tag"
    if tag_dir.exists():
        shutil.rmtree(tag_dir)
    tag_dir.mkdir(parents=True)
    events, interests = to_tag(run.db, run.today), write_judged.interest_ids()
    for i in range(0, len(events), TAG_BATCH):
        (tag_dir / f"batch-{i // TAG_BATCH + 1}.txt").write_text(tag_message(events[i:i + TAG_BATCH], interests))
    (tag_dir / "events.json").write_text(json.dumps(events, indent=1, ensure_ascii=False))
    print(f"[morning] {len(events)} events to tag in {len(list(tag_dir.glob('batch-*.txt')))} batches ({tag_dir})")


def plan_tags(lines, events, known):
    """The cheap model's lines as writes: only Events it was given, only known interests, each
    once, in the model's order, at most TAG_MAX, and a draw of 1, 2 or 3. An Event it didn't answer stays untagged
    for tomorrow; one with no usable draw is read again tomorrow for it."""
    given, known, writes = {e["id"]: e for e in events}, set(known), {}
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("id") not in given:
            continue
        what = what_words(ln.get("what"))
        if given[ln["id"]].get("tagged"):
            # Read and rated before: only its words, so its interests and draw stay as they were.
            # ponytail: one with no usable words is asked again each morning; mark it if that grows.
            if what:
                writes[ln["id"]] = {"what": what}
            continue
        if not isinstance(ln.get("interests"), list):
            continue
        tags = list(dict.fromkeys(t for t in ln["interests"] if t in known))[:TAG_MAX]
        write = {"interests": tags}
        if ln.get("draw") in (1, 2, 3):
            write["draw"] = ln["draw"]
        if not given[ln["id"]].get("category") and tags:
            write["category"] = tags[0]
        if what:
            write["what"] = what
        writes[ln["id"]] = write
    return writes


def tag(run, dry_run):
    out = run.folder
    events = json.loads((out / "tag" / "events.json").read_text())
    writes = plan_tags(read_items(out / "tags.jsonl"), events, write_judged.interest_ids())
    if not dry_run:
        now = datetime.now(LOCAL).isoformat()

        def save_tags(event_id):
            stamp = {} if set(writes[event_id]) == {"what"} else {"interests_tagged_at": now}
            run.db.rest("PATCH", f"club_events?id=eq.{event_id}", {**writes[event_id], **stamp}, prefer="return=minimal")
        left = run.part("tag/written.json").each(writes, save_tags)  # `untagged` clears it
        if left:
            return [f"[morning] run again: {len(writes) - left} of {len(writes)} events tagged"]
    empty = sum(1 for w in writes.values() if "interests" in w and not w["interests"])
    words = sum(1 for w in writes.values() if "what" in w)
    draws = {d: sum(1 for w in writes.values() if w.get("draw") == d) for d in (3, 2, 1)}
    return [f"[morning] tagged {len(writes)} events ({empty} with no interest; draw 3/2/1: "
            f"{draws[3]}/{draws[2]}/{draws[1]}), {words} with what they are in words, "
            f"{len(events) - len(writes)} left for tomorrow" + (" (dry run: nothing written)" if dry_run else "")]


def to_describe(db, today):
    """Approved upcoming Events found in the last two days and never laid out before, soonest
    first. Older ones were researched already (the 2026-10-24 backfill), and one laid out before
    was researched on its morning (described_at), so a thin one stays thin rather than being
    searched again every day (smooth-mornings 06)."""
    since = (today - timedelta(days=2)).isoformat()
    ask = ("club_events?select=id,title,event_date,start_time,location,description,price,source_name,source_url,"
           "sport,category,clubs(name)&status=eq.approved&kind=eq.event"
           f"&event_date=gte.{today}&described_at=is.null&order=event_date&limit=1000")
    found = db.rest("GET", f"{ask}&created_at=gte.{since}")
    # A campus Event with a sign-up page is laid out once whenever it was found (event-details), after
    # the newly found, which have only two days to be read; it waits for a morning with room.
    hosts = quote(",".join(f'"{h}"' for h in sorted(CAMPUS)))
    known = {r["id"] for r in found}
    later = [r for r in db.rest("GET", f"{ask}&source_name=in.({hosts})&source_url=not.like.{quote(CALENDAR_PAGE)}")
             if r["id"] not in known]
    return to_research(found + later)


# The campus calendar's hosts. Their Event links to the calendar's own page unless the calendar names
# a sign-up page (read_events.pathify_items; BP app event-details).
CAMPUS = set(CAMPUS_HOSTS.values())
CALENDAR_PAGE = "*/public/events/*"


def signs_up(row):
    """A campus Event linking to its sign-up page: its About is laid out even when it is a sentence or
    more, since the calendar's text leaves out the fee, the limits and "registration is filled"."""
    return row.get("source_name") in CAMPUS and "/public/events/" not in (row.get("source_url") or "")


def to_research(rows):
    """The rows whose About is empty or under a sentence, that link to a campus sign-up page, or whose About
    names a cost with no `price` yet (the judge's blurb keeps the cost; the helper moves it, inside-cards 14),
    games left out (write_judged.is_game: a game's reader wrote its About from the schedule, and there is
    nothing more to find), as the helpers read them, at most DESCRIBE_MAX."""
    def picked(r):
        about = (r.get("description") or "").strip()
        return len(about) < THIN or signs_up(r) or (COST.search(about) and not r.get("price"))
    thin = [r for r in rows if picked(r) and not write_judged.is_game(r)]
    return [{"id": r["id"], "title": r["title"], "date": r["event_date"], "start": r.get("start_time") or "",
             "place": r.get("location") or "", "host": (r.get("clubs") or {}).get("name") or r.get("source_name") or "",
             "link": r.get("source_url") or "", "about": (r.get("description") or "").strip(),
             "price": (r.get("price") or "").strip()}
            for r in thin[:DESCRIBE_MAX]]


def page_excerpt(text, title, limit=PAGE_MAX):
    """The part of an Event's own page about it: the stretch around the line naming most of its
    title's words (a league's full schedule lists every game). Nothing when no line names two of
    them: a page built by JavaScript reads as its menu (MSHSL's schedules, the CSB SJU calendar)."""
    want = set(re.findall(r"[a-z]{4,}", title.lower()))
    lines = text.split("\n")
    hits = [sum(w in ln.lower() for w in want) for ln in lines]
    best = max(range(len(lines)), key=hits.__getitem__)
    if hits[best] < min(2, len(want)):
        return ""
    if len(text) <= limit:
        return text
    start = max(0, sum(len(ln) + 1 for ln in lines[:best]) - limit // 3)
    return text[start:start + limit]


# Bound's server refuses a name that doesn't start the way crawlers' names do: 403 to
# "BlockPartyBot/1.0", 200 to the same name in Googlebot's form (2026-10-29). Still our own name,
# never a browser's (ADR-014).
CRAWLER_UA = "Mozilla/5.0 (compatible; BlockPartyBot/1.0; +https://blockpartystjoe.com)"
_crawler_form = set()  # hosts that answered only that form
# The league reader links a game to its school's whole MSHSL schedule, which JavaScript builds: no
# page of the game's own to read.
SCHEDULE_LINK = re.compile(r"/full-schedule$")


def own_page(url, get=fetch):
    host = urlparse(url).netloc
    if host in _crawler_form:
        return get(url, headers={"User-Agent": CRAWLER_UA})
    try:
        return get(url)
    except urllib.error.HTTPError as ex:
        if ex.code != 403:
            raise
        _crawler_form.add(host)
        return get(url, headers={"User-Agent": CRAWLER_UA})


def own_pages(events, get=None, stop=None):
    """Each Event's own page, read once per link the polite way (robots, Crawl-delay): the school's
    Bound page, the league's schedule, the college calendar. Its helper reads it before searching,
    since a search finds old seasons (Jesse, 2026-10-29: "go off Bound and open links"). A page that
    can't be read, or isn't reached before the part's `stop`, stays empty and the helper searches."""
    get, read = get or own_page, {}
    for e in events:
        url = e["link"]
        if url and not SCHEDULE_LINK.search(url) and url not in read and not late(stop):
            try:
                read[url] = to_text(get(url)[1])
            except Exception as ex:
                read[url] = ""
                print(f"[morning] page not read: {url} ({str(ex)[:100]})")
        e["page"] = page_excerpt(read.get(url) or "", e["title"])
    return sum(1 for e in events if e["page"])


def thin(run, get=None):
    d = run.folder / "describe"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    events = to_describe(run.db, run.today)
    pages = own_pages(events, get, stop=run.stop)
    for i in range(0, len(events), DESCRIBE_BATCH):
        (d / f"batch-{i // DESCRIBE_BATCH + 1}.txt").write_text(
            "\n".join(json.dumps(e, ensure_ascii=False) for e in events[i:i + DESCRIBE_BATCH]) + "\n")
    (d / "events.json").write_text(json.dumps([{k: v for k, v in e.items() if k != "page"} for e in events],
                                              indent=1, ensure_ascii=False))
    print(f"[morning] {len(events)} events to describe in {len(list(d.glob('batch-*.txt')))} batches, "
          f"{pages} with their own page read ({d})")


def plan_descriptions(lines, events):
    """The helpers' lines as writes, the columns to save per Event (`description`, `price`): only Events they
    were given, each once. An About that is text and longer than the one it has (a fuller About is never
    shortened), unless the line says it was cleaned (`cleaned`, or a `price` moved out of it: inside-cards 14),
    when a shorter About is the point; a price whenever given, one short line. CHECK lines are kept for the
    answer, never written."""
    given, writes, checks = {e["id"]: e for e in events}, {}, []
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("id") not in given:
            continue
        e = given[ln["id"]]
        if isinstance(ln.get("check"), str) and ln["check"].strip():
            checks.append(f"{e['title']} ({e['date']}): {ln['check'].strip()}")
        if ln["id"] in writes:
            continue
        words = lambda key: " ".join(ln[key].split()) if isinstance(ln.get(key), str) else ""
        about, price = words("about"), words("price")
        write = {}
        if about and about != " ".join(e["about"].split()) and (len(about) > len(e["about"]) or price or ln.get("cleaned") is True):
            write["description"] = write_judged.clip(about, ABOUT_MAX)
        if price:
            write["price"] = write_judged.clip(price, PRICE_MAX)
        if write:
            writes[ln["id"]] = write
    return writes, checks


def describe(run, dry_run):
    out = run.folder
    events = json.loads((out / "describe" / "events.json").read_text())
    lines = read_items(out / "describe.jsonl")
    writes, checks = plan_descriptions(lines, events)
    # Every Event a helper answered, filled or not, is researched: thin never lays it out again. One
    # nobody answered waits for tomorrow's helpers. An About they wrote is marked written too, so a re-read
    # of its listing never puts the longer words back (apply_judged, inside-cards 14).
    given = {e["id"] for e in events}
    answered = {ln["id"] for ln in lines if isinstance(ln, dict) and ln.get("id") in given}
    if not dry_run:
        now = datetime.now(LOCAL).isoformat()

        def save_about(event_id):
            write = writes.get(event_id, {})
            run.db.rest("PATCH", f"club_events?id=eq.{event_id}",
                        {"described_at": now, **write, **({"about_written_at": now} if "description" in write else {})},
                        prefer="return=minimal")
        left = run.part("describe/written.json").each(sorted(answered), save_about)  # thin clears it
        if left:
            return [f"[morning] run again: {len(answered) - left} of {len(answered)} Abouts saved"]
    return ([f"[morning] described {len(writes)} of {len(events)} events given" + (" (dry run: nothing written)" if dry_run else "")]
            + [f"[check] {c}" for c in checks])


def todays_events(db, today, tags=None, abouts=None):
    """Today's Events as the Town feed takes them (approved, posted by a neighbour or found by a
    source, not called off), with what the model weighs: interests, draw, Going and hearts. The
    feed's function itself reads private helpers the service key can't reach. `tags` and `abouts`: the
    helpers' answers finish has yet to save, so an Event found this morning carries them too."""
    rows = db.rest("GET", "club_events?select=id,title,start_time,all_day,location,source_name,description,"
                          "interests,interests_tagged_at,category,draw,clubs(name)"
                          f"&status=eq.approved&kind=eq.event&event_date=eq.{today}&cancelled_at=is.null"
                          "&or=(submitted_by.not.is.null,source_name.not.is.null)&order=start_time") or []
    if not rows:
        return []
    for r in rows:
        t = (tags or {}).get(r["id"]) or {}
        r.update(t, **({"interests_tagged_at": str(today)} if "interests" in t else {}))
        r["description"] = (abouts or {}).get(r["id"]) or r.get("description")
    ids = ",".join(r["id"] for r in rows)
    count = lambda table: [x["event_id"] for x in db.rest("GET", f"{table}?select=event_id&event_id=in.({ids})") or []]
    going, hearts = count("event_rsvps"), count("event_likes")
    return [event_line(r, going.count(r["id"]), hearts.count(r["id"])) for r in rows]


def event_line(row, going, hearts):
    """One Event as the model reads it. Its interests are the tagger's, else its writer's one, as
    the feed matches them."""
    interests = row.get("interests") if row.get("interests_tagged_at") else [c for c in [row.get("category")] if c]
    return {"id": row["id"], "title": row["title"],
            "start": "all day" if row.get("all_day") else (row.get("start_time") or "no time given"),
            "place": row.get("location") or "", "host": (row.get("clubs") or {}).get("name") or row.get("source_name") or "",
            "interests": interests or [], "draw": row.get("draw"), "going": going, "hearts": hearts,
            "about": " ".join((row.get("description") or "").split())[:300]}


def lay_out_today(run):
    out, today = run.folder, run.today
    out.mkdir(parents=True, exist_ok=True)
    given = lambda d: json.loads((out / d / "events.json").read_text()) if (out / d / "events.json").exists() else []
    tags = plan_tags(read_items(out / "tags.jsonl"), given("tag"), write_judged.interest_ids())
    writes, _ = plan_descriptions(read_items(out / "describe.jsonl"), given("describe"))
    abouts = {i: w["description"] for i, w in writes.items() if "description" in w}
    events = todays_events(run.db, today, tags, abouts)
    (out / "today.txt").write_text(f"Today: {today}\n\nEvents:\n"
                                   + "".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
    print(f"[morning] {len(events)} events today for the standouts ({out / 'today.txt'})")


def plan_standouts(lines, events, today, town=DEFAULT):
    """The model's lines as today's daily_standouts rows: only Events it was given, each once, with
    a reason, best first (rank is the line's place), nine at most."""
    given, rows = {e["id"] for e in events}, []
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("id") not in given or any(r["event_id"] == ln["id"] for r in rows):
            continue
        why = " ".join(str(ln.get("why") or "").split())[:200]
        if why and len(rows) < STANDOUTS:
            rows.append({"town": town, "day": str(today), "event_id": ln["id"], "rank": len(rows) + 1, "why": why})
    return rows


def standouts(run, dry_run):
    out, today, town = run.folder, run.today, run.town
    # today.txt's Event lines, as the model read them.
    events = [e for e in read_items(out / "today.txt") if isinstance(e, dict)]
    rows = plan_standouts(read_items(out / "standouts.jsonl"), events, today, town)
    # No usable line keeps whatever today has: with no rows Daily shows the Town feed's top pick.
    kept = run.part("standouts-saved.json")  # these picks, once written: a finish run again doesn't write them twice
    if rows and not dry_run and kept.saved != rows:
        run.db.rest("DELETE", f"daily_standouts?town=eq.{town}&day=eq.{today}", prefer="return=minimal")
        run.db.rest("POST", "daily_standouts", rows, prefer="return=minimal")
        kept.save(rows)
    by_id = {e["id"]: e for e in events}
    return ([f"[morning] standouts: {len(rows)} of {len(events)} events today"
             + (" (dry run: nothing written)" if dry_run else "")
             + ("" if rows or not events else "; none written, so Daily shows the Town feed's top pick")]
            + [f"[morning] #{r['rank']} {by_id[r['event_id']]['title']} ({by_id[r['event_id']]['start']}): {r['why']}"
               for r in rows])


def save(run, dry_run):
    """write, once a morning, then lay out the helpers' work within the rest of the part's minutes. The
    summary waits in report.json for finish; a save run again the same morning writes nothing again (the
    Oct 22 job wrote twice) and only lays the batches out again."""
    kept = kept_report(run, dry_run)
    if kept.saved is not None and not dry_run:
        print("[morning] saved already this morning: nothing written again; finish prints its summary")
    else:
        kept.save(write(run, dry_run))
    if run.summary().get("run"):
        return  # a social check: social.py done finishes it
    untagged(run)
    thin(run)


def kept_report(run, dry_run):
    """save's summary for finish; a dry run's apart, so a real save after it still writes."""
    return run.part("report-dry-run.json" if dry_run else "report.json")


def finish(run, dry_run):
    """In timed parts while the tags and Abouts are written, then the standouts, then the whole report,
    always: a save that fails (one timeout among 900 tag writes) is one line in it, and a finish run again
    writes only what is left."""
    today, db, kept = run.today, run.db, kept_report(run, dry_run).saved
    if kept is None:
        sys.exit("[morning] nothing saved this morning: run save first")
    failed = lambda what, e: f"[morning] {what} failed: {' '.join(str(e).split())[:300]}"
    lines = list(kept)
    # After the helpers' saves, the Events since the last report showing no photo of what they are, each new
    # Event's spot on the map, and the ones with none listed (BP app references/map-reset),
    # then the places Apple Maps calls closed for good, hidden (Jesse, 2026-11-01).
    for what, step in (("tags", lambda: tag(run, dry_run)), ("Abouts", lambda: describe(run, dry_run)),
                       ("standouts", lambda: standouts(run, dry_run)),
                       ("since the last report", lambda: since_lines(db, today)),
                       ("event photos", lambda: photo_lines(db, today)),
                       ("map spots", lambda: map_spots(run, dry_run)),
                       ("places", lambda: place_lines(db)),
                       ("Apple Maps", lambda: apple_maps.check(db, not dry_run, today))):
        waited = run.part("apple-waited-dry-run.json" if dry_run else "apple-waited.json")
        if what == "Apple Maps" and late(run.stop) and not waited.saved:  # the maps took this part's time, once
            waited.save(True)
            return print("[morning] run again: the Apple Maps check waits for a part of its own")
        try:
            got = step()
        except DbError as e:
            got = [failed(what, e)]
        if got and got[0].startswith("[morning] run again"):
            return print(got[0])
        lines += got
    report = "\n".join(lines + social_lines() + [spend_line(), credits_line()])
    if not dry_run:
        try:  # one row a morning, so the chat that reports to Jesse reads it, not the run's log (smooth-mornings 10)
            db.rest("POST", "morning_reports?on_conflict=day", {"day": str(today), "report": report,
                    "saved_at": datetime.now(timezone.utc).isoformat()},
                    prefer="resolution=merge-duplicates,return=minimal")
        except Exception as e:  # never a lost report: it is still printed, and the log has it
            report += "\n" + failed("report row", e)
    print(report)
    run.finished()


def map_spots(run, dry_run):
    """Each upcoming Event's spot: the registry's, else where Overture and OpenStreetMap agree (spots.fill,
    find_spots.py; BP app inside-cards 20). Reading the two maps takes 2 to 5 minutes, so it gets what is left of
    the part before its 9th minute (the cloud stops a command at 10), less a minute and a half for the writes, at
    most 7. A part with under 4 left, or whose read ran out of time, hands it to the next part, once. Whatever
    happens is kept as the step's lines, so a finish run again neither writes, reports nor fails twice."""
    tag = "-dry-run" if dry_run else ""
    done, waited = run.part(f"spots{tag}.json"), run.part(f"spots-waited{tag}.json")
    if done.saved is not None:
        return done.saved
    left = minutes_left(run.stop, 180)  # a part ends by its 9th minute
    again = ["[morning] run again: the map spots wait for a part with time to read the maps"]
    if left is not None and left < 4 and not waited.saved:
        waited.save(True)
        return again
    try:
        maps, note = find_spots.read(run.folder / "spots", minutes=7 if left is None else max(min(left - 1.5, 7), 0.1)), []
    except subprocess.TimeoutExpired:
        if not waited.saved:
            waited.save(True)
            return again
        maps, note = None, ["- Map spots: Overture and OpenStreetMap ran out of time, so the spots they found before "
                            "stay as they were"]
    except Exception as e:  # no network, no library, no memory: the spots they found before stay (spots.fill)
        maps, note = None, [f"- Map spots: Overture and OpenStreetMap not read ({' '.join(str(e).split())[:200]}), "
                            "so the spots they found before stay as they were"]
    try:
        lines = spots.fill(run.db, run.today, not dry_run, maps=maps) + note
    except Exception as e:  # a refused write or a bad hand file: a line in the report, never a lost report
        lines = [f"[morning] map spots failed: {' '.join(str(e).split())[:300]}"] + note
    done.save(lines)
    return lines


def social_lines():
    """A social check that should have finished and didn't, for the report and so the 8 AM email, which reads any
    "[morning] ... failed: ..." line (BP app loopholes 09; Jesse, 2026-11-05). Asked by finish itself, as spend_line."""
    try:
        missed = social.missed_checks()
    except Exception as e:  # no network, no key: a line, never a lost report
        missed = [f"couldn't read its mark ({' '.join(str(e).split())[:120]})"]
    return [f"[morning] social check failed: {m}" for m in missed]


def spend_line():
    """The social watch's Apify spend for the report (Jesse, 2026-10-22), asked by finish itself: the
    Oct 29 morning skipped the step that asked for it."""
    try:
        return social.spend()
    except Exception as e:  # no network, no key: a line, never a lost report
        return f"Apify: spend unknown ({' '.join(str(e).split())[:120]})"


def credits_words(d, now):
    """Firecrawl's line in the report. The heads-up goes by pace, as a flat 3/4 would fire late in every month, the
    job spends so steadily (BP app backlog 12). Days are whole Chicago dates: the job spends a day's credits in one
    lump at 6 AM, so counted by the clock a steady cycle's first week would read as too fast."""
    day = lambda stamp: datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(LOCAL).date()
    left, plan, today, end = d["remainingCredits"], d["planCredits"], now.astimezone(LOCAL).date(), day(d["billingPeriodEnd"])
    line = f"Firecrawl: {left:,} of {plan:,} credits left (resets after {end:%b %-d})"
    if left <= 0:
        return line + ". Out of credits: pages read through Firecrawl will fail until the reset."
    used, days_gone = plan - left, (today - day(d["billingPeriodStart"])).days
    if used > 0 and days_gone > 0 and left * days_gone / used < (end - today).days:
        out = today + timedelta(days=math.ceil(left * days_gone / used))
        return line + f". Heads-up: at this pace they run out around {out:%b %-d}."
    return line


def credits_line():
    """Firecrawl's credits for the report (Jesse, 2026-11-05), asked by finish itself, as spend_line."""
    try:
        return credits_words(firecrawl_credits(), datetime.now(timezone.utc))
    except Exception as e:  # no network, no key: a line, never a lost report
        return f"Firecrawl: credits unknown ({' '.join(str(e).split())[:120]})"


def credits_told():
    """Firecrawl's line: the plain one, the pace heads-up, no credits left, and a failed call."""
    global firecrawl_credits
    cycle = {"planCredits": 1000, "billingPeriodStart": "2026-10-21T01:45:31.463Z",
             "billingPeriodEnd": "2026-11-21T01:45:31.463Z"}
    first = datetime(2026, 10, 21, 12, 30, tzinfo=timezone.utc)  # 6:30 AM on the cycle's first morning here
    on = lambda left, n: credits_words({**cycle, "remainingCredits": left}, first + timedelta(days=n))
    # This cycle has 31 mornings: 32 a morning spends 992 and lasts, 33 runs out on the last one.
    steady = lambda a_day: [on(1000 - a_day * (n + 1), n) for n in range(31)]
    saved = firecrawl_credits

    def told(answer):
        global firecrawl_credits
        firecrawl_credits = answer
        return credits_line()

    def refused():
        raise urllib.error.HTTPError("u", 401, "Unauthorized", None, None)
    try:
        failed, odd = told(refused), told(lambda: {})
    finally:
        firecrawl_credits = saved
    return [
        (on(600, 16) == "Firecrawl: 600 of 1,000 credits left (resets after Nov 20)",
         "the plain credits line, its reset in Chicago's date"),
        (on(200, 11) == "Firecrawl: 200 of 1,000 credits left (resets after Nov 20). "
                        "Heads-up: at this pace they run out around Nov 4.",
         "spending too fast: the heads-up names the day they run out"),
        (not any("Heads-up" in line for line in steady(32)), "a pace that lasts never warns, from its first morning on"),
        (all("Heads-up" in line for line in steady(33)[:-1]) and "Out of credits" in steady(33)[-1],
         "a pace that runs out warns from its first morning"),
        (on(0, 26) == "Firecrawl: 0 of 1,000 credits left (resets after Nov 20). "
                      "Out of credits: pages read through Firecrawl will fail until the reset.",
         "no credits left says pages will fail until the reset"),
        (failed == "Firecrawl: credits unknown (HTTP Error 401: Unauthorized)", f"a failed call is a line: {failed}"),
        (odd == "Firecrawl: credits unknown ('remainingCredits')", f"an answer without the number is a line: {odd}"),
    ]


def map_spots_in_parts():
    """The map spots step gives the maps what is left of the part, hands a short part's turn on once, keeps its
    lines for a finish run again, and reports maps it couldn't read without emptying what they found (spots.fill
    keeps those)."""
    import tempfile
    real = spots.fill, find_spots.read
    fills, reads, checks = [], [], []

    def broken(folder, minutes):
        raise OSError("download.geofabrik.de unreachable")
    try:
        spots.fill = lambda db, today, write, maps: fills.append(maps) or ["- Map spots: set 1"]
        find_spots.read = lambda folder, minutes: reads.append(minutes) or "maps"
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            short = lambda: Run(out, date(2026, 11, 7), FakeDb(), minutes=0.5)  # a part 5½ minutes in: 3½ left
            checks.append((map_spots(short(), False)[0].startswith("[morning] run again") and not fills,
                           "a part with under 4 minutes left hands the maps to the next part"))
            first = map_spots(short(), False)
            again = map_spots(Run(out, date(2026, 11, 7), FakeDb(), minutes=6), False)
            checks.append((first == again == ["- Map spots: set 1"] and fills == ["maps"] and 1.9 < reads[0] < 2.1,
                           f"once only, then the maps get what is left; a finish run again repeats the lines "
                           f"without filling twice: {fills} {reads}"))
        with tempfile.TemporaryDirectory() as tmp:
            find_spots.read = broken
            lines = map_spots(Run(Path(tmp), date(2026, 11, 7), FakeDb(), minutes=None), False)
            checks.append((fills[-1] is None and "not read (download.geofabrik.de unreachable)" in lines[-1],
                           f"maps that can't be read are a line, and the fill keeps what they found: {lines}"))
        with tempfile.TemporaryDirectory() as tmp:
            def slow(folder, minutes):
                raise subprocess.TimeoutExpired("find_spots.py", minutes * 60)
            find_spots.read = slow
            part = lambda: map_spots(Run(Path(tmp), date(2026, 11, 7), FakeDb(), minutes=6), False)
            first, second, third = part(), part(), part()
            checks.append((first[0].startswith("[morning] run again") and "ran out of time" in second[-1]
                           and second == third, f"maps out of time get one more part, then are a line: {first} {second}"))
        with tempfile.TemporaryDirectory() as tmp:
            find_spots.read = lambda folder, minutes: "maps"
            def refused(db, today, write, maps):
                raise DbError("GET", "club_events?select=no_place", 400, "column club_events.no_place does not exist")
            spots.fill = refused
            part = lambda: map_spots(Run(Path(tmp), date(2026, 11, 7), FakeDb(), minutes=6), False)
            first, again = part(), part()
            checks.append((first == again and first[0].startswith("[morning] map spots failed:") and "no_place does not exist" in first[0],
                           f"a refused fill is one kept line, never a finish that runs again forever: {first}"))
    finally:
        spots.fill, find_spots.read = real
    return checks


def selftest():
    entries = [{"id": "milk", "_name": "Milk & Honey Ciders", "tier": "watched", "category": "cidery",
                "sources": [{"url": "https://m/events", "method": "fetch", "trust": "official"}]},
               {"id": "city", "_name": "City", "tier": "watched",
                "sources": [{"url": "https://c/ical", "method": "fetch", "kind": "ical"}]},
               {"id": "kennedy", "_name": "Kennedy", "tier": "watched",
                "sources": [{"url": "https://k/calendar", "method": "fetch", "reader": "finalsite-calendar"}]},
               {"id": "shop", "_name": "Shop", "tier": "listed",
                "sources": [{"url": "https://s/", "method": "fetch"}]},
               {"id": "sals", "_name": "Sal's", "tier": "watched",
                "sources": [{"url": "https://sals/feed/", "method": "fetch", "kind": "rss"}]},
               {"id": "new", "_name": "New place", "tier": "watched",
                "sources": [{"url": "https://n/events", "method": "fetch"}]}]
    changed = [{"entry_id": e["id"], "url": e["sources"][0]["url"], "snapshot": f"{e['id']}--abc123.md",
                "first_seen": e["id"] == "new"} for e in entries]
    pages = pages_to_read(changed, entries)
    checks = [
        ([p["entry_id"] for p in pages] == ["milk", "sals"],
         "only watched pages no reader or calendar feed covers, never one seen for the first time"),
        (pages[0]["file"] == "milk--abc123" and pages[0]["name"] == "Milk & Honey Ciders", "named by its snapshot"),
    ]
    market = [{"entry_id": "fm", "url": "https://fm/", "text": "Fresh food\nOur 2027 season begins Friday, May 7.\nFridays 3 to 6 pm through 10/15\n"},
              {"entry_id": "other", "url": "https://o/", "text": "Open May 1"}]
    seasons = season_pages(market, {"fm": {"name": "Farmers' Market", "hours": {"season": ["05-08", "10-16"]}}})
    checks.append(("05-08 to 10-16" in seasons and "May 7" in seasons and "10/15" in seasons
                   and "Fresh food" not in seasons and "https://o/" not in seasons,
                   "a seasonal place's changed page lists its dated lines beside the app's season"))
    checks.append((season_pages(market, {}) == "", "no seasonal place changed, nothing to compare"))
    waiting = lambda rows: type("Db", (), {"rest": staticmethod(
        lambda m, p: rows if p.startswith("club_events") else [{"id": "pierz", "name": "Pierz"}])})
    checks.append((waiting_lines(waiting([{"team_ids": ["a", "pierz"]}, {"team_ids": ["pierz", "b"]}]))
                   == ["- Waiting on a logo: 2 games, teams Pierz 2"] and waiting_lines(waiting([])) == [],
                   "the morning report names the games waiting on a logo, and says nothing with none"))
    tmp = Path(__file__).resolve().parents[2] / ".runs" / "morning-selftest.md"
    tmp.parent.mkdir(exist_ok=True)
    tmp.write_text("---\nentry_id: milk\nurl: https://m\n---\n\nPlant Bingo Oct 24\n")
    checks.append((snapshot_text(tmp) == "Plant Bingo Oct 24\n", "the snapshot's text without its header"))
    tmp.unlink()
    tmp.write_text('{"Anniversary of the Dedication of Sacred Heart Chapel": "Sacred Heart Chapel Anniversary", '
                   '"Short": "Longer than it was", "Kept": 3}')
    tmp.rename(tmp.with_name("titles.json"))
    checks.append((short_titles(tmp.parent) == {"Anniversary of the Dedication of Sacred Heart Chapel":
                                                "Sacred Heart Chapel Anniversary"},
                   "only shorter titles are taken from titles.json"))
    tmp.with_name("titles.json").unlink()
    prep = {"today": "2026-10-15", "fetched": 12, "changed": 3, "to_read": 1, "failed": ["x https://x: HTTP 403"],
            "readers": ["[read] ok     City (ical): 6 items", "[read] FAILED Stearns County (civicplus-hcms): TimeoutError"]}
    result = {"outcomes": [("published", ""), ("repeat", "of 'x'"), ("news", ""), ("merged", "into x"),
                           ("folded", "'Wrinkle-Free Wednesdays' into 'Molly now at Well & Company', the News of the post they share")],
              "events": [], "news": []}
    lines = summary_lines(prep, result, None)
    checks.append((lines[3].endswith(", 1 folded into the News of the post they came in")
                   and "- Folded: 'Wrinkle-Free Wednesdays' into 'Molly now at Well & Company', the News of the post "
                       "they share" in lines, "the summary names each News folded into its post's News"))
    long_news, short_news = "Pumpkin Crafted Cold Brew at Caribou", "Pumpkin Cold Brew at Caribou"
    told = summary_lines(prep, {**result, "news": [{"title": long_news, "source_name": "Caribou"},
                                                   {"title": short_news, "source_name": "Caribou"}]}, None)
    checks.append(([ln for ln in told if ln.startswith("- Still past")] == [f"- Still past its 2 lines: {long_news}"],
                   "the summary names each News title still past its card's 2 lines (BP app inside-cards 13)"))
    checks.append((summary_lines({**prep, "first_seen": 2}, result, None)[1].endswith(", 2 new kept as a starting copy"),
                   "the summary counts new pages kept as a starting copy"))
    called = summary_lines(prep, {**result, "cancelled": [{"id": "c", "event_date": "2026-10-30", "title": "Fall Play"}],
                                  "restored": [{"id": "r", "event_date": "2026-11-02", "title": "Bingo"}],
                                  "notes": ["place not in the registry: 'Barn' (Sal's picture stands in)"]}, None)
    checks.append(("- Cancelled: 2026-10-30 Fall Play, gone from its schedule" in called and "- Back on: 2026-11-02 Bingo" in called
                   and called[-2:] == ["Notes:", "- On Events already listed, places not in the registry: 1, "
                                                 "names that are no team's: 0"],
                   "the summary names what its schedules called off or brought back, and counts the writer's routine notes"))
    routine = ["place not in the registry: 'Barn' (Sal's picture stands in)",
               "place not in the registry: \"Ben's Mall\" (CSB's picture stands in)",
               "place not in the registry: 'Far Gym' (Apollo's picture stands in)",
               "place not in the registry: 'Far Gym' (Apollo's picture stands in)",
               "who is this: 'Anoka' ('Anoka Hockey vs Apollo') is no team's name, so a normal card until it's added",
               "who is this: 'Roseau' ('Roseau Hockey vs Apollo') is no team's name, so a normal card until it's added",
               "interest 'bars' is not on the list ('Holiday Market'): left empty"]
    new_today = [{"title": "Anoka Hockey vs Apollo", "location": "Anoka Ice Arena"}, {"title": "Bingo", "location": "Barn, Albany"},
                 {"title": "Lights", "location": "Ben's Mall"}]
    checks.append((short_notes(routine, new_today) == routine[:2] + routine[4:5] + routine[6:] + [
                       "On Events already listed, places not in the registry: 1, names that are no team's: 1"],
                   "routine notes on today's new Events stay by name, any other note stays, and the rest are one count"))
    checks.append((short_notes(routine[6:], []) == routine[6:] and short_notes([], new_today) == [], "no routine notes, no count line"))

    class SinceDb:
        def __init__(self, last=True, down=False):
            self.last, self.down, self.asked = last, down, []

        def rest(self, method, path, body=None, prefer=None):
            if self.down:
                raise DbError("GET", "club_events", 503, "Service\n Unavailable")
            self.asked.append(path)
            if path.startswith("morning_reports?"):
                return [{"saved_at": "2026-11-04T12:15:00+00:00"}] if self.last else []
            if path.startswith("club_events?"):
                return [{"event_date": "2026-11-12", "end_at": None, "all_day": False, "start_time": "7 PM",
                         "title": "Youth Dodgeball", "location": None, "source_name": "City of St. Joseph"}]
            if path.startswith("places?"):
                return [{"name": "Milk & Honey Ciders", "hours": {"tue": [], "wed": [], "from": {
                    "post": "https://www.facebook.com/x/posts/1", "at": "2026-11-04T23:31:00+00:00",
                    "was": {"tue": [["16:00", "21:00"]], "wed": [["16:00", "21:00"]]}}}}]
            return [{"title": "Krewe's Brussels Sprouts", "source_name": "Krewe"}]
    since = SinceDb()
    checks.append((since_lines(since, date(2026, 11, 5)) == ["Since the last report:", "- Thu Nov 12 · 7 PM · Youth Dodgeball",
                                                             "- Krewe's Brussels Sprouts (Krewe)",
                                                             "- Hours: Milk & Honey Ciders, from its post https://www.facebook.com/x/posts/1: "
                                                             "Tue 4–9 PM, now closed; Wed 4–9 PM, now closed"],
                   "the report names what was written after the last report, a week a post changed too"))
    checks.append((all(f"created_at=gt.{quote('2026-11-04T12:15:00+00:00')}" in p and f"created_at=lt.{quote('2026-11-05T05:00:00-06:00')}" in p
                       for p in since.asked[1:3])
                   and f"at=gt.{quote('2026-11-04T12:15:00+00:00')}&hours->from->>at=lt.{quote('2026-11-05T11:00:00+00:00')}" in since.asked[3],
                   "from the last report's save to before this morning's run, Chicago time"))
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "pages.json").write_text(json.dumps([{"file": "facebook-1", "url": "https://www.facebook.com/x/posts/1",
                                                            "entry_id": "mh", "name": "Milk & Honey Ciders"},
                                                           {"file": "facebook-3", "url": "https://n/3", "entry_id": "new", "name": "New Cafe"},
                                                           {"file": "facebook-4", "url": "https://t/4", "entry_id": "two", "name": "Two Weeks"},
                                                           {"file": "facebook-5", "url": "https://t/5", "entry_id": "two", "name": "Two Weeks"},
                                                           {"file": "instagram-2", "url": "https://www.instagram.com/p/2/",
                                                            "entry_id": "mh", "name": "Milk & Honey Ciders"}]))
        had = {**{d: [] for d in accounts.DAY_KEYS}, "tue": [["16:00", "21:00"]], "wed": [["16:00", "21:00"]], "season": ["03-01", "12-23"]}
        hdb = FakeDb(answers={"places?select=entry_id,hours": [{"entry_id": "mh", "hours": had}, {"entry_id": "new", "hours": None},
                                                               {"entry_id": "two", "hours": had}]})
        r = type("R", (), {"folder": Path(tmp), "db": hdb})()
        winter = {"page": "facebook-1", "kind": "hours", "days": {"tue": "Closed", "wed": "Closed", "thu": "4 PM to 9 PM"}}
        said = save_hours(r, [winter, {**winter, "page": "instagram-2"}, {**winter, "days": {"tue": "by appointment"}},
                              {**winter, "page": "facebook-9"}, {**winter, "page": "facebook-3"}, {**winter, "page": "facebook-4"},
                              {**winter, "page": "facebook-5", "days": {"thu": "5 PM to 9 PM"}}], False)
        [(_, where, body)] = hdb.writes("places")
        dry = FakeDb(answers=hdb.answers)
        checks.append((where == "places?entry_id=eq.mh" and {k: v for k, v in body["hours"].items() if k != "from"}
                       == {**had, "tue": [], "wed": [], "thu": [["16:00", "21:00"]]}
                       and body["hours"]["from"]["post"] == "https://www.facebook.com/x/posts/1"
                       and said == ['- Hours not read: {"page": "facebook-1", "kind": "hours", "days": {"tue": "by appointment"}}',
                                    '- Hours not read: {"page": "facebook-9", "kind": "hours", "days": {"tue": "Closed", "wed": "Closed", "thu": "4 PM to 9 PM"}}',
                                    "- Hours not written: Two Weeks's posts give two different weeks",
                                    "- Hours: Milk & Honey Ciders, from its post https://www.facebook.com/x/posts/1: "
                                    "Tue 4–9 PM, now closed; Wed 4–9 PM, now closed; Thu closed, now 4–9 PM",
                                    "- Hours not written: New Cafe, from its post https://n/3: it names only Tue, Wed, Thu, and the app "
                                    "has no hours for Mon, Fri, Sat, Sun"]
                       and save_hours(type("R", (), {"folder": Path(tmp), "db": dry})(), [winter], True)[-1].startswith("- Hours: Milk")
                       and not dry.writes() and save_hours(r, [], False) == [],
                       f"a post's new week goes on the place that posted, once for its two sites, over its season, and says so; "
                       f"two weeks for one place, or a few days over none, go nowhere: {said}"))
    checks.append((since_lines(SinceDb(last=False), date(2026, 11, 5)) == [], "no earlier report, no such list"))
    checks.append((since_lines(SinceDb(down=True), date(2026, 11, 5)) == [
                       "Since the last report: not read (Supabase GET club_events failed 503: Service Unavailable)"],
                   "a read that fails is one line"))
    counted = FakeDb(answers={"places?": [{"entry_id": "a", "apple_place_id": "I1", "hours": {"mon": []}, "search_logo": {"url": "u"}},
                                          {"entry_id": "b", "apple_place_id": None, "hours": None, "search_logo": None}],
                              "place_photos?": [{"entry_id": "b"}, {"entry_id": "b"}, {"entry_id": "z"}]})
    checks.append((place_lines(counted) == ["- Places: 2 open, 1 with an Apple id, 1 with hours, 1 with a logo, 1 with a photo"]
                   and "closed_at=is.null" in counted.calls[0][1] and "status=eq.live&kind=eq.photo" in counted.calls[1][1]
                   and place_lines(SinceDb(down=True))[0].startswith("- Places: not counted (Supabase GET"),
                   f"the report counts the place pages and what each still lacks: {place_lines(counted)}"))
    checks.append(("- Source failed: x https://x: HTTP 403" in lines
                   and "- Reader failed: Stearns County (civicplus-hcms): TimeoutError" in lines, "the summary names what failed"))
    refused = {"entry_id": "b", "url": "https://b/",
               "error": 'Supabase PATCH sources?entry_id=eq.b failed 500: {"message":"canceling statement\n due to statement timeout"}'}
    report_ = "\n".join(summary_lines({**prep, "unrecorded": [refused]}, result, None))
    # The 8 AM check's own pattern (private.morning_problems), one line per refused row.
    alerts = re.findall(r"^\[morning\] (.+ failed: .*)$", report_, re.M)
    checks.append((alerts == ['recording b https://b/ failed: Supabase PATCH sources?entry_id=eq.b failed 500: '
                              '{"message":"canceling statement due to statement timeout"}']
                   and not re.findall(r"^\[morning\]", "\n".join(lines), re.M),
                   "a page the database refused to record is one line in the saved report, and the 8 AM check reads it"))
    real_missed = social.missed_checks
    try:
        social.missed_checks = lambda: ["last evening's check didn't finish (read up to Wed Nov 4 6:01 PM)"]
        missed = re.findall(r"^\[morning\] (.+ failed: .*)$", "\n".join(social_lines()), re.M)
        social.missed_checks = lambda: 1 / 0
        unread = social_lines()
    finally:
        social.missed_checks = real_missed
    checks.append((missed == ["social check failed: last evening's check didn't finish (read up to Wed Nov 4 6:01 PM)"]
                   and unread == ["[morning] social check failed: couldn't read its mark (division by zero)"],
                   "a social check that didn't finish is one line the 8 AM check reads, and an unreadable mark never loses the report"))
    run_ = {"event_date": "2026-10-26", "end_at": "2026-10-31T00:00:00-05:00", "all_day": True, "start_time": None,
            "title": "Bootique Week", "location": "White Peony Boutique", "source_name": "White Peony Boutique"}
    night = {"event_date": "2026-10-24", "end_at": "2026-10-25T01:00:00-05:00", "all_day": False, "start_time": "9 PM",
             "title": "Live music", "location": "Bo-Diddley's", "source_name": "Bo-Diddley's"}
    game = lambda day, school: {"event_date": day, "end_at": None, "all_day": False, "start_time": "7 PM",
                                "title": "Football", "location": "", "source_name": school}
    games = ([game(f"2026-11-{d % 28 + 1:02d}", "Sartell High School") for d in range(38)]
             + [game("2026-12-10", "Sartell High School")] * 2 + [game("2026-12-11", "Apollo High School")] * 3)
    listed = event_lines([run_, *games, night])
    checks.append((listed[:2] == ["- Sat Oct 24 · 9 PM · Live music · Bo-Diddley's",
                                  "- Mon Oct 26 to Fri Oct 30 · all day · Bootique Week · White Peony Boutique"]
                   and listed[2] == "- Sun Nov 1 · 7 PM · Football" and len(listed) == LIST_MAX + 2
                   and listed[-2:] == ["- 3 more from Apollo High School", "- 2 more from Sartell High School"],
                   "new Events soonest first, a run with its last day, and past 40 a count for each source"))
    checks.append((counts_what_the_database_did(), "the new counts are what the save did: 3 new and 2 listed Events, "
                   "1 new and 25 re-read News say 3 and 1 new, and list each new Event (date, time, title, place) "
                   "and News"))
    import gzip, run as runner
    checks.append((runner.decoded(gzip.compress(b"Trivia Oct 24"), "") == b"Trivia Oct 24"
                   and runner.decoded(gzip.compress(b"Trivia Oct 24" * 50)[:60], "gzip").startswith(b"Trivia")
                   and runner.decoded(b"<html>plain</html>", "") == b"<html>plain</html>",
                   "a gzip body is decoded, even unasked or cut off"))
    runner._server.update({"a.weebly-site.com": "199.34.228.77", "b.weebly-site.com": "199.34.228.77"})
    checks.append((runner.server_of("a.weebly-site.com") == runner.server_of("b.weebly-site.com"),
                   "two sites on one server share its one-at-a-time lock"))
    from run import fingerprint
    checks.append((fingerprint("Trivia Oct 24 7:00 PM\nPage generated at 10/16/2026, 3:45:35 AM")
                   == fingerprint("Trivia Oct 24 7:00 PM\nPage generated at 10/17/2026, 3:48:48 AM")
                   and fingerprint("Wed, 14 Oct 2026 11:47:19 -0600\nFish fry") == fingerprint("Thu, 15 Oct 2026 06:01:02 -0600\nFish fry")
                   and fingerprint("Trivia Oct 24 7:00 PM") != fingerprint("Trivia Oct 24 8:00 PM"),
                   "a page's own clock doesn't change its fingerprint; an event's time does"))
    events = [{"id": "e1", "category": None}, {"id": "e2", "category": "live_music"}, {"id": "e3", "category": None}]
    writes = plan_tags([{"id": "e1", "interests": ["dining", "faith", "dining", "made_up"], "draw": 3},
                        {"id": "e2", "interests": ["bars", "live_music"], "draw": 7}, {"id": "zz", "interests": ["dining"]},
                        "unreadable line: {", {"id": "e3"}], events, ["dining", "faith", "bars", "live_music"])
    checks.append((writes == {"e1": {"interests": ["dining", "faith"], "draw": 3, "category": "dining"},
                              "e2": {"interests": ["bars", "live_music"]}},
                   "tags keep known interests once each and a draw of 1-3, fill an empty category, and skip Events not given or not answered"))
    checks.append((plan_tags([{"id": "e1", "interests": [], "draw": 1}], events, ["dining"]) == {"e1": {"interests": [], "draw": 1}},
                   "an Event nothing fits is tagged with none, so it isn't read again"))
    checks.append((plan_tags([{"id": "e2", "interests": ["bars", "live_music", "dining", "faith", "games", "talks"]}], events,
                             ["bars", "live_music", "dining", "faith", "games", "talks"])["e2"]["interests"]
                   == ["bars", "live_music", "dining", "faith", "games"], "an Event keeps 5 interests at most, the model's first"))
    words = plan_tags([{"id": "e1", "interests": ["dining"], "draw": 2, "what": "  cross  country meet. "},
                       {"id": "t1", "interests": ["faith"], "draw": 3, "what": "Lecture"},
                       {"id": "t2", "interests": ["faith"], "draw": 3, "what": "A talk about a lot of things"},
                       {"id": "e3", "interests": [], "draw": 1, "what": 7}],
                      events + [{"id": "t1", "tagged": True}, {"id": "t2", "tagged": True}], ["dining", "faith"])
    checks.append((words == {"e1": {"interests": ["dining"], "draw": 2, "category": "dining", "what": "Cross country meet"},
                             "t1": {"what": "Lecture"}, "e3": {"interests": [], "draw": 1}},
                   "what it is: one to three words, tidied; an Event tagged before only gets its words"))
    checks.append(('"tagged"' not in tag_message([{"id": "e1", "tagged": True}], ["dining"]),
                   "the model never sees the tagged mark"))
    checks.append(("Interests: dining, faith" in tag_message([{"id": "e1"}], ["dining", "faith"]),
                   "each batch carries the interest list"))
    today = [{"id": "g"}, {"id": "t"}, {"id": "b"}]
    rows = plan_standouts([{"id": "g", "why": " Rivals,  under the lights "}, {"id": "zz", "why": "not today"},
                           {"id": "t", "why": ""}, "unreadable line: {", {"id": "g", "why": "again"},
                           {"id": "b", "why": "Bingo"}], today, "2026-10-20")
    checks.append(([(r["event_id"], r["rank"], r["why"]) for r in rows] == [("g", 1, "Rivals, under the lights"), ("b", 2, "Bingo")]
                   and rows[0]["town"] == "st-joseph-mn" and rows[0]["day"] == "2026-10-20",
                   "standouts keep given Events once each with a reason, ranked in the model's order"))
    many = [{"id": str(i)} for i in range(12)]
    checks.append((len(plan_standouts([{"id": str(i), "why": "x"} for i in range(12)], many, "2026-10-20")) == STANDOUTS,
                   "nine standouts at most"))
    line = event_line({"id": "g", "title": "Home game", "all_day": False, "start_time": "7 PM", "location": "Field",
                       "clubs": None, "source_name": "Sartell High School", "description": "  Rivals\n night  ",
                       "interests": [], "interests_tagged_at": None, "category": "watch_sports", "draw": 3}, 3, 1)
    checks.append((line["interests"] == ["watch_sports"] and line["host"] == "Sartell High School"
                   and line["start"] == "7 PM" and line["about"] == "Rivals night" and line["draw"] == 3
                   and (line["going"], line["hearts"]) == (3, 1),
                   "an untagged Event's interest is its category, as the feed matches it"))
    checks.append((event_line({"id": "x", "title": "Fair", "all_day": True, "interests": ["festivals"],
                               "interests_tagged_at": "2026-10-20", "clubs": {"name": "Fair board"}}, 0, 0)
                   == {"id": "x", "title": "Fair", "start": "all day", "place": "", "host": "Fair board",
                       "interests": ["festivals"], "draw": None, "going": 0, "hearts": 0, "about": ""},
                   "an all-day Event says so, and a group's name is its host"))
    given = [{"id": "a", "title": "Pilates", "date": "2026-10-26", "about": "$10."},
             {"id": "b", "title": "Game", "date": "2026-10-27", "about": "A long About already here."}]
    writes, found = plan_descriptions([{"id": "a", "about": "  Weekly Pilates\n at City Hall. "},
                                       {"id": "a", "about": "a second answer"},
                                       {"id": "b", "about": "Short.", "check": "Starts at 4, not 7."},
                                       {"id": "z", "about": "not given"}, "junk"], given)
    checks.append((writes == {"a": {"description": "Weekly Pilates at City Hall."}} and found == ["Game (2026-10-27): Starts at 4, not 7."],
                   "Abouts are written once, only for given Events and only when longer; CHECK lines are kept"))
    # The About cleaned under inside-cards 14 (what it is and what to expect) is shorter than the one it had, so a
    # shorter About is taken when the line says it was cleaned, or moves the cost to `price`; the price alone is a write.
    writes, _ = plan_descriptions([{"id": "b", "about": "A cleaned About.", "cleaned": True},
                                   {"id": "a", "about": "$10.", "price": " $10 a class "}], given)
    checks.append((writes == {"b": {"description": "A cleaned About."}, "a": {"price": "$10 a class"}},
                   "a shorter About is written when the line says cleaned; a price is written on its own, tidied"))
    writes, _ = plan_descriptions([{"id": "b", "about": "Short.", "price": "Free"}, {"id": "a", "about": "", "cleaned": True}], given)
    checks.append((writes == {"b": {"description": "Short.", "price": "Free"}},
                   "a price makes a shorter About a cleaned one; an empty About is never written"))
    checks += games_aside() + described_once() + sign_up_pages() + live_games_told() + photos_told() + credits_told()
    asked = []

    def get(url):
        asked.append(url)
        if url == "https://bad/":
            raise RuntimeError("HTTP Error 403")
        return 200, ("<p>Sartell vs. Alexandria Area</p><p>Section 8AAAAA Football Semifinal</p>" if url == "https://b/1"
                     else "<p>Kimball vs Eden Valley-Watkins Oct 31</p>")
    linked = [{"title": "Sartell Football vs Alexandria", "link": "https://b/1"},
              {"title": "Sartell Football vs Alexandria", "link": "https://b/1"},
              {"title": "Kimball Football vs Eden Valley-Watkins", "link": "https://mshsl/full-schedule"},
              {"title": "Banquet", "link": "https://bad/"}, {"title": "Posted", "link": ""}]
    read = own_pages(linked, get)
    checks.append((asked == ["https://b/1", "https://bad/"] and read == 2 and "Semifinal" in linked[1]["page"]
                   and linked[2]["page"] == linked[3]["page"] == linked[4]["page"] == "",
                   "each Event gets its own link's page, a link read once; a league schedule, one that fails "
                   "or none stays empty"))
    asked.clear()
    late_ones = [{"title": "Game", "link": "https://b/1"}]
    checks.append((own_pages(late_ones, get, stop=deadline(-1)) == 0 and asked == [] and late_ones[0]["page"] == "",
                   "past the part's minutes no page is asked for, so the step ends before the cloud stops it"))
    schedule = "\n".join([f"Oct {d} Somebody vs Someone Else at 7 PM" for d in range(1, 200)]
                         + ["Oct 31 Kimball vs Eden Valley-Watkins 2 PM"] + ["Nov 1 Other vs Team"] * 200)
    part = page_excerpt(schedule, "Kimball Football vs Eden Valley-Watkins", 600)
    checks.append((len(part) == 600 and "Kimball vs Eden Valley-Watkins" in part and page_excerpt("short", "x") == "short",
                   "a long schedule page is cut to the stretch naming the Event"))
    menu = "News\nTickets\nSports & Activities\nFootball\nVolleyball\nContact"
    checks.append((page_excerpt(menu, "Kimball Football vs Eden Valley-Watkins") == "",
                   "a page that never names the Event (a JavaScript page's menu) is no page"))
    tries = []

    def bound(url, headers=None):
        tries.append((url, (headers or {}).get("User-Agent")))
        if not headers:
            raise urllib.error.HTTPError(url, 403, "Forbidden", {}, None)
        return 200, "<p>Sartell vs. Alexandria Area</p>"
    first, second = own_page("https://bound.test/1", bound), own_page("https://bound.test/2", bound)
    checks.append((first == second == (200, "<p>Sartell vs. Alexandria Area</p>")
                   and tries == [("https://bound.test/1", None), ("https://bound.test/1", CRAWLER_UA),
                                 ("https://bound.test/2", CRAWLER_UA)],
                   "a site that refuses our name answers it in the crawlers' form, asked that way from then on"))
    checks.append((fingerprints_wait_for_write(), "a page's new fingerprint moves only after its events are "
                   "written: a write that fails stops with one line naming what refused it and leaves it, so "
                   "prepare finds the same pages again; once written, it is saved even if the summary then breaks"))
    checks += in_parts()
    checks += map_spots_in_parts()
    checks += steps_alone()
    checks += set_aside_across_days()
    checks += one_town()
    checks += instructions() + whole_morning()
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def counts_what_the_database_did():
    """write against a fake database that answers as apply_judged does, item by item: the plan sends 5
    Events and 26 News, and the database already has 2 of the Events and 25 of the News (BP app
    smooth-mornings 05: on Oct 28 the report said "26 new" and the database got 1 new row)."""
    import io, tempfile
    global live_lines
    listed = [write_judged.listed(id=f"0000000{k}-0000-0000-0000-000000000000", title=t, event_date=d, start_time="6 PM",
                                  location="Milk & Honey Ciders", source_name="Milk & Honey Ciders", source_uid=f"mh-{k}",
                                  shows_from="2026-10-10") for k, t, d in [(1, "Yoga, Sauna & Cider", "2026-10-27"),
                                                                           (2, "Pumpkin Carving", "2026-10-28")]]
    held_events = {(e["source_name"], e["source_uid"]) for e in listed}
    held_news = {f"post number {k}" for k in range(25)}
    news = lambda title: write_judged.item(kind="news", title=title, start=None, category="business",
                                           source_url="https://www.instagram.com/p/" + title.replace(" ", ""))
    items = ([write_judged.item(), write_judged.item(title="Cider Tasting", start="2026-10-25T18:00:00-05:00", end=None),
              write_judged.item(title="Harvest Market", start="2026-10-26", end=None, all_day=True)]
             + [write_judged.item(title=e["title"], start=f"{e['event_date']}T18:00:00-05:00", end=None,
                                  source_uid=e["source_uid"]) for e in listed]
             + [news("Thanksgiving pies")] + [news(f"Post number {k}") for k in range(25)])
    answers = []

    def apply(method, path, p):  # the database's half: what it already has is merged or a repeat, the rest added
        answers.append({"events": len(p["p_events"]), "news": len(p["p_news"]), "mentions": 5, "published_by_mention": 0,
                        "cancelled": 0, "restored": 0,
                        "added": {"events": [i for i, e in enumerate(p["p_events"])
                                             if (e["source_name"], e["source_uid"]) not in held_events],
                                  "news": [i for i, n in enumerate(p["p_news"]) if n["title"].lower() not in held_news]}})
        return answers[-1]
    saved, games, asked = write_judged.interest_ids, live_lines, []
    try:
        write_judged.interest_ids = lambda: ["bars"]
        live_lines = lambda db, day: asked.append(day) or []
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            (out / "prepare.json").write_text(json.dumps({"today": "2026-10-20", "fetched": 9, "changed": 2,
                                                          "to_read": 2, "failed": [], "readers": []}))
            (out / "judged.jsonl").write_text("".join(json.dumps(it) + "\n" for it in items))
            printed = io.StringIO()
            with contextlib.redirect_stdout(printed):
                write(Run(out, date(2026, 10, 20), FakeDb(answers={"rpc/listed_for_writer": listed, "rpc/apply_judged": apply})), False)
            lines = printed.getvalue().splitlines()
            result = write_judged.plan(items, listed, date(2026, 10, 20), ["bars"], teams={})
    finally:
        write_judged.interest_ids, live_lines = saved, games
    old = summary_lines({"today": "2026-10-20", "fetched": 9, "changed": 2, "to_read": 2, "failed": [], "readers": []},
                        result, {"events": 5, "news": 26})
    at = lines.index("New Events:") if "New Events:" in lines else len(lines)
    return ("- Events: 3 new, 2 already listed" in lines and "- News: 1 new, 25 repeats left out" in lines
            and "- Written: 5 mentions, 0 published by a mention, 0 cancelled, 0 back on" in lines
            and lines[at:] == ["New Events:",
                               "- Sat Oct 24 · 4 PM · Plant Bingo · Milk & Honey Ciders",
                               "- Sun Oct 25 · 6 PM · Cider Tasting · Milk & Honey Ciders",
                               "- Mon Oct 26 · all day · Harvest Market · Milk & Honey Ciders",
                               "New News:", "- Thanksgiving pies (Milk & Honey Ciders)"]
            # An apply_judged from before this answers counts only: the plan's counts, said so, no crash.
            and "- News: 26 new, 0 repeats left out" in old and any("the save didn't say" in ln for ln in old)
            # The morning's summary tells yesterday's games.
            and asked == [date(2026, 10, 19)])


def fingerprints_wait_for_write():
    """prepare's fetch and write's save against a fake database and fake sites, offline."""
    import io, tempfile, run as runner
    global summary_lines
    db = FakeDb({"milk|https://m/events": {"last_hash": "old", "last_checked_at": "2026-10-24"}})
    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "sources": [{"url": u, "method": "fetch"}]} for i, u in [("milk", "https://m/events"), ("new", "https://n/")]]
    saved = (runner.read_page, runner.validate, runner.find_root, write_judged.interest_ids)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            runner.read_page = lambda url, kind: (200, f"Plant Bingo Oct 24 at {url}", "fetch")
            runner.validate, runner.find_root = (lambda e: []), (lambda *a: Path(tmp))
            write_judged.interest_ids = lambda: []
            out = Path(tmp) / "morning"
            out.mkdir()
            (out / "prepare.json").write_text(json.dumps({"today": "2026-10-25", "fetched": 2, "changed": 1,
                                                          "to_read": 1, "failed": [], "readers": []}))

            def prepare_fetch():
                with contextlib.redirect_stdout(io.StringIO()):
                    report = runner.fetch_watched(entries, db)
                (out / "fingerprints.json").write_text(json.dumps(report["changed"]))
                return sorted(c["entry_id"] for c in report["changed"] if not c["first_seen"])

            def write_with(apply):
                db.answers["rpc/apply_judged"] = apply
                with contextlib.redirect_stdout(io.StringIO()):
                    write(Run(out, date(2026, 10, 25), db), False)

            def boom(method, path, body):
                raise DbError("POST", "rpc/apply_judged", 403,
                              '{"code":"42501",\n"message":"permission denied for schema private"}')
            first = prepare_fetch()
            try:
                write_with(boom)
                refused = None
            except SystemExit as e:
                refused = e.code
            unmoved = db.rows["milk|https://m/events"]["last_hash"] == "old"
            starting_copy = db.rows["new|https://n/"].get("last_hash") is not None
            again = prepare_fetch()
            printing = summary_lines

            def breaks(*args):
                raise RuntimeError("the summary broke")
            summary_lines = breaks  # the write lands, then printing its summary breaks
            try:
                write_with(lambda method, path, body: {"events": 0})
                broke = False
            except RuntimeError:
                broke = True
            finally:
                summary_lines = printing
            one_line = refused == ('[morning] save refused: Supabase POST rpc/apply_judged failed 403: '
                                   '{"code":"42501", "message":"permission denied for schema private"}')
            return (first == again == ["milk"] and unmoved and starting_copy and one_line and broke
                    and prepare_fetch() == [])
    finally:
        runner.read_page, runner.validate, runner.find_root, write_judged.interest_ids = saved


def games_aside():
    """The titles step, the save's [long title] check and the describe layout agree, offline: Oct 28's
    long game titles as Bound's calendars give them now (each read by its reader, so short), a
    campus game and a judge's game still over 40 (both go to the titles step, review of 06d3b8e0),
    and Events that aren't games. No game is ever laid out to describe (write_judged.is_game)."""
    import ast, io
    from read_events import bound_items, pathify_items

    def ev(uid, summary, act, level, place):
        a = act.replace(",", "\\,")
        return (f"BEGIN:VEVENT\r\nDTSTART;TZID=America/Chicago:20261201T174500\r\nGEO:45.4;-94.6\r\nLOCATION:{place}\r\n"
                f"SUMMARY:{a}: {summary} ({level})\r\nUID:{uid}\r\nX-BND-ACTIVITYKEY:{act.split(',')[0].lower()}\r\n"
                f"X-BND-ACTIVITYLEVEL:{level}\r\nX-BND-ACTIVITYNAME:{a}\r\nEND:VEVENT\r\n")
    oct28 = {"Kennedy Community School": [ev("k", "North Junior High vs Kennedy Community MS", "Basketball, Boys", "Middle School",
                                             "Kennedy Community School Kennedy Gym")],
             "Sauk Rapids-Rice High School": [ev("s", "St. Cloud Apollo vs Sauk Rapids-Rice", "Basketball, Boys", "C",
                                                 "Sauk Rapids-Rice High School Auxiliary Gym")],
             "Sartell High School": [ev("t", "Sauk Rapids-Rice vs Sartell", "Basketball, Boys", "8th Grade", "Sartell Middle School Gym")],
             "ROCORI High School": [ev(f"r{i}", f"{them} vs River Lakes", "Hockey, Boys", "Junior Varsity", "River Lakes Civic Arena")
                                    for i, them in enumerate(("Prairie Centre", "Hutchinson", "Litchfield"))]}
    games = [i for school, evs in oct28.items() for i in bound_items("".join(evs), {"_name": school}, {"url": "u"},
                                                                    date(2026, 10, 28)) if i["kind"] == "event"]
    games += pathify_items([{"id": 7, "title": "Saint John's University Basketball vs University of Wisconsin-Eau Claire",
                             "location": "Collegeville, Minn., Sexton Arena", "calendar": {"name": "SJU Athletics"},
                             "start_date": "2026-12-02T01:00:00Z", "all_day": False}], {"_name": "x"},
                           {"url": "https://my.csbsju.edu/api"}, date(2026, 10, 28))
    other = lambda title, host, interest=None, about=None: {
        "kind": "event", "title": title, "start": "2026-11-21T19:00:00-06:00", "place": "Sacred Heart Chapel",
        "town": "St. Joseph", "area": "town", "source_name": host, "source_url": "https://x/e", "source_uid": title,
        "trust": "official", "size": "everyday", "interest": interest, "blurb": about}
    judge = other("Cathedral Boys Hockey vs Academy of Holy Angels: Senior Night", "Cathedral High School", "watch_sports")
    others = [other("Anniversary of the Dedication of Sacred Heart Chapel", "Saint Benedict's Monastery", "faith"),
              other("Plant Bingo", "Milk & Honey Ciders", "markets", "$10."),
              other("Vikings vs Colts Game Day at Neighbors Route 75 Bar and Grill", "Neighbors Route 75", "dining"),
              other("Fall Play", "Apollo High School", None, "Varsity")]
    items = games + [judge] + others
    titles = write_judged.long_titles(items)
    result = write_judged.plan(items, [], date(2026, 10, 28), write_judged.interest_ids(), teams={})
    said = io.StringIO()
    with contextlib.redirect_stdout(said):
        write_judged.report(items, result)
    flagged = [ast.literal_eval(ln[len("[long title] "):].rsplit(": over", 1)[0]) for ln in said.getvalue().splitlines()
               if ln.startswith("[long title]")]
    rows = [dict(g["row"], id=g["row"]["source_uid"]) for g in result["events"]]
    laid = [e["title"] for e in to_research(rows)]
    return [(len(games) == 7 and all("game" in i or "Athletics" in i["source_name"] for i in games) and len(rows) == len(items)
             and titles == flagged == ["SJU Basketball vs University of Wisconsin-Eau Claire",
                                       "Cathedral Boys Hockey vs Academy of Holy Angels",
                                       "Anniversary of the Dedication of Sacred Heart Chapel",
                                       "Vikings vs Colts Game Day at Neighbors Route 75 Bar and Grill"]
             and laid == [write_judged.tidy_title(i["title"]) for i in others],
             "the titles step, the save's long-title check and the describe layout agree: Oct 28's games come short from "
             "their readers, every title over 40 (a game's too) is in both, no game is laid out to describe")]


def sign_up_pages():
    """A campus Event linking to its sign-up page is laid out with a full About; one linking to the
    calendar's own page, or another host's, is not. Newly found Events come first, and an Event both
    reads give is laid out once."""
    long = "Explore the Benedictine practice of stability by learning self-compassion. " * 3

    def row(i, host, link, about=long, made="2026-10-28"):
        return {"id": i, "title": f"Event {i}", "event_date": "2026-11-03", "start_time": "9 AM", "location": "x",
                "description": about, "source_name": host, "source_url": link, "sport": None, "category": None,
                "clubs": None, "created_at": made}
    retreat = row("r", "Saint Benedict's Monastery", "https://sbm.osb.org/event/grounding/2026-11-03/", made="2026-09-01")
    talk = row("t", "CSB SJU Libraries", "https://my.csbsju.edu/public/events/5")
    other = row("o", "Sisters of the Order of Saint Benedict", "https://sbm.osb.org/event/deep-waters/")
    new = row("n", "City of St. Joseph", "https://c/1", about="")
    both = row("b", "CSB SJU Campus Events", "https://forms.csbsju.edu/x")
    asked = []

    class Db:
        def rest(self, method, path, body=None, prefer=None):
            asked.append(path)
            return [new, both] if "created_at=gte." in path else [both, retreat]
    laid = [e["id"] for e in to_describe(Db(), date(2026, 10, 29))]
    picked = [e["id"] for e in to_research([retreat, talk, other])]
    costs = [row("c1", "Church of St. Joseph", "https://c/1", about=long + " Tickets $12, kids $6."),
             row("c2", "Church of St. Joseph", "https://c/2", about=long + " Free and open to all."),
             {**row("c3", "Church of St. Joseph", "https://c/3", about=long + " $12 at the door."), "price": "$12"},
             row("c4", "Church of St. Joseph", "https://c/4", about=long + " Feel welcome to bring a dish.")]
    moved = [(e["id"], e["price"]) for e in to_research(costs)]
    return [(picked == ["r"], "a campus Event with a sign-up page is researched though its About is full; the "
                              "calendar's own page or another host's page is not"),
            (moved == [("c1", ""), ("c2", "")],
             "a full About naming a cost is laid out until its price is moved out of it (inside-cards 14)"),
            (laid == ["n", "b", "r"] and "source_name=in.(" in asked[1] and "Saint%20Benedict" in asked[1]
             and "source_url=not.like." in asked[1],
             "the newly found come first, then the campus sign-up pages from any morning, each Event once")]


def described_once():
    """thin and describe across two mornings against a fake database: an Event the helpers answered
    (filled or not) is never laid out again, one they didn't answer is, and a game never is."""
    import io, tempfile
    rows = [{"id": i, "title": t, "event_date": "2026-11-05", "start_time": "7 PM", "location": "Field", "description": d,
             "source_name": "Host", "source_url": "https://h", "sport": None, "category": c, "clubs": None,
             "described_at": None, "created_at": "2026-10-28"}
            for i, t, d, c in [("a", "Harvest Supper", "", "dining"), ("b", "Fix-It Clinic", "Bring it.", None),
                               ("c", "Kennedy Girls Basketball vs Holdingford", "", "watch_sports")]]

    class Db:
        def rest(self, method, path, body=None, prefer=None):
            if method == "PATCH":
                next(r for r in rows if path == f"club_events?id=eq.{r['id']}").update(body)
                return None
            return [dict(r) for r in rows if "described_at=is.null" not in path or r["described_at"] is None]

    def morning(answers):
        run = Run(out, date(2026, 10, 29), Db(), minutes=None)
        with contextlib.redirect_stdout(io.StringIO()):
            thin(run, get=lambda url: (200, ""))
            given = [e["id"] for e in json.loads((out / "describe" / "events.json").read_text())]
            (out / "describe.jsonl").write_text("".join(json.dumps(a) + "\n" for a in answers if a["id"] in given))
            describe(run, False)
        return given
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        first = morning([{"id": "a", "about": "", "check": ""}])  # b: no helper answered it
        second = morning([{"id": "b", "about": "Bring a broken lamp or toaster; volunteers fix it for free."}])
        third = morning([])
    return [(first == ["a", "b"] and second == ["b"] and third == [] and rows[1]["description"].startswith("Bring a broken")
             and rows[0]["described_at"] and not rows[2]["described_at"],
             "an Event laid out and answered is researched: the next morning lays out only the one nobody answered, "
             "and never the game"),
            (not rows[0].get("about_written_at") and rows[1].get("about_written_at"),
             "only an About the helpers wrote is marked written: one researched with nothing found stays the source's, "
             "so a fuller listing can still fill it (apply_judged, inside-cards 14)")]


def live_games_told():
    """A day's games as the morning report tells them, offline: each way a live score can go, a sport the job
    doesn't follow, and a database that can't be read."""
    game = lambda title, start, source, sport, live=None, final=None, plays=None: {
        "id": title, "title": title, "start_time": start, "source_name": source, "sport": sport, "live_score": live,
        "final_score": final, "scoring_plays": plays}
    rows = [game("CSB Soccer vs Carleton", "1 PM", "CSB Athletics", "Soccer", final=[2, 1]),
            game("SJU Swimming and Diving vs Macalester", "1 PM", "SJU Athletics", "Swimming and Diving"),
            game("SJU Football vs Bethel", "TBA", "SJU Athletics", "Football"),
            game("CSB Basketball vs Augsburg", "2 PM", "CSB Athletics", "Basketball"),
            game("CSB Basketball vs Carleton", "4 PM", "CSB Athletics", "Basketball", final=[60, 58]),
            game("SJU Basketball vs St. Cloud State", "6 PM", "SJU Athletics", "Basketball", plays=[{}] * 23, final=[78, 71],
                 live={"score": [78, 71], "complete": True, "at": "2026-10-30T01:58:00+00:00"}),
            game("CSB Volleyball vs Augsburg", "7 PM", "CSB Athletics", "Volleyball", final=[3, 1],
                 live={"score": [2, 1], "complete": False, "at": "2026-10-30T01:12:00+00:00"}),
            game("SJU Soccer vs Carleton", "7:30 p.m.", "SJU Athletics", "Soccer")]

    class Unread:
        def rest(self, *args, **kw):
            raise DbError("GET", "club_events", 503, "Service\n Unavailable")
    newest = [m for m in sorted((Path(__file__).resolve().parents[2] / "supabase" / "migrations").glob("*.sql"))
              if "function private.sidearm_file(" in m.read_text()][-1].read_text()
    followed = re.findall(r"when '([^']+/[^']+)' then",
                          newest.split("function private.sidearm_file(", 1)[1].split("$$", 2)[1])
    unread = live_lines(Unread(), date(2026, 10, 29))
    # As public.live_marks gives them (game-card 22): each source's reads, the one that carried the game, and the alert.
    school = lambda wrote, failed=0, why=None: {"name": "gobennies.com", "reads": wrote + failed, "failed": failed,
                                                "wrote": wrote, "why": why}
    push = {"name": "SIDEARM's push", "reads": 434, "failed": 434, "wrote": 0, "why": "certificate expired"}
    marks = {"SJU Basketball vs St. Cloud State": {"sources": [school(118, 2, "timed out"), push]},
             "CSB Volleyball vs Augsburg": {"sources": [school(40, 6, "HTTP 503"),
                                                        {"name": "sidearmstats.com", "reads": 2, "failed": 0, "wrote": 2}],
                                            "alerted_at": "2026-10-30T01:24:00+00:00"},
             "SJU Soccer vs Carleton": {"sources": [push], "alert_why": "ntfy answered 503: busy"}}

    class NoMarks:
        def rest(self, method, path, *args, **kw):
            if path.startswith("rpc/"):
                raise DbError("POST", "rpc/live_marks", 404, "Not Found")
            return rows[:1]
    return [(live_lines(None, date(2026, 10, 29), rows, marks) == [
                "Live games Thu Oct 29:",
                "- CSB Soccer vs Carleton, 1 PM: never went live; final 2-1 from the backup check",
                "- SJU Football vs Bethel, TBA: not followed live, no start time; no final",
                "- CSB Basketball vs Augsburg, 2 PM: not followed live, 2 games that day; no final",
                "- CSB Basketball vs Carleton, 4 PM: not followed live, 2 games that day; final 60-58 from the backup check",
                "- SJU Basketball vs St. Cloud State, 6 PM: live to the final from gobennies.com, 78-71 (23 scoring plays); "
                "failed reads: gobennies.com 2 (timed out), SIDEARM's push 434 (certificate expired)",
                "- CSB Volleyball vs Augsburg, 7 PM: live until 8:12 PM from gobennies.com and sidearmstats.com, then final "
                "3-1 from the backup check; failed reads: gobennies.com 6 (HTTP 503); dark alert 8:24 PM",
                "- SJU Soccer vs Carleton, 7:30 p.m.: never went live; no final; failed reads: SIDEARM's push 434 "
                "(certificate expired); dark alert not sent (ntfy answered 503: busy)"],
             "each followed game says how far its live score got, which source carried it, which reads failed and why, "
             "and the dark alert"),
            (live_lines(NoMarks(), date(2026, 10, 29)) == [
                "Live games Thu Oct 29: (which source carried each not read: Supabase POST rpc/live_marks failed 404: "
                "Not Found)",
                "- CSB Soccer vs Carleton, 1 PM: never went live; final 2-1 from the backup check"],
             "sources that can't be read leave the lines as they were, saying so once"),
            (live_lines(None, date(2026, 10, 29), rows) == [
                "Live games Thu Oct 29:",
                "- CSB Soccer vs Carleton, 1 PM: never went live; final 2-1 from the backup check",
                "- SJU Football vs Bethel, TBA: not followed live, no start time; no final",
                "- CSB Basketball vs Augsburg, 2 PM: not followed live, 2 games that day; no final",
                "- CSB Basketball vs Carleton, 4 PM: not followed live, 2 games that day; final 60-58 from the backup check",
                "- SJU Basketball vs St. Cloud State, 6 PM: live to the final, 78-71 (23 scoring plays)",
                "- CSB Volleyball vs Augsburg, 7 PM: live until 8:12 PM, then final 3-1 from the backup check",
                "- SJU Soccer vs Carleton, 7:30 p.m.: never went live; no final"],
             "each followed game says how far its live score got and where its final came from; a game the job "
             "skips says why, and a sport it doesn't follow isn't listed"),
            (live_lines(None, date(2026, 10, 30), rows[1:2]) == [], "a day with no followed game adds no lines"),
            (unread == ["Live games Thu Oct 29: not read (Supabase GET club_events failed 503: Service Unavailable)"],
             "a database that can't be read is one line, never a lost report"),
            (set(followed) == LIVE_SPORTS, "the report follows the games private.sidearm_file names, as its newest migration says")]


def photos_told():
    """photo_lines against a fake database: of the Events added since the last report (the morning's, the social
    watch's, a chat's), one its card shows a scene or its own flyer for isn't listed, one showing its place's photo
    or logo is, a game never is, and a database that can't be read is one line."""
    row = lambda title, i, **more: {"id": i, "event_date": "2026-12-05", "end_at": None, "all_day": False,
                                    "start_time": "10 AM", "title": title, "location": "Sunny Mary Meadow",
                                    "source_name": "Sunny Mary Meadow", **more}
    rows = [row("Holiday Market", "m"), row("Winter Yoga", "y"), row("Football", "g", sport="Football", team_ids=["a", "b"]),
            row("Boys Swim vs Brainerd", "s", sport=None, team_ids=None), row("Pizza night", "p"),
            row("Reflection: Selected Works", "r"), row("Pumpkin Walk", "w")]
    shown = {"m": "https://x/scene-market.jpg", "y": "https://x/meadow.jpg", "s": "https://x/pool.jpg",
             "p": "https://x/flyer.jpg", "r": "https://x/reflection.jpg", "w": "https://x/meadow.jpg"}
    # Reflection has its own live photo, whatever URL its card read; Pumpkin Walk's own photo was retired.
    own = [{"event_id": "r", "kind": "event", "status": "live"}, {"event_id": "w", "kind": "event", "status": "retired"}]
    asked = []

    class Db:
        def rest(self, method, path, body=None, prefer=None):
            asked.append(path)
            if path.startswith("morning_reports?"):
                return [{"saved_at": "2026-12-01T12:15:00+00:00"}]
            if path.startswith("club_events?"):
                return rows if quote("2026-12-01T12:15:00+00:00") in path else []
            if path == "rpc/event_picture":
                return {"url": shown.get(body["p_event"]), "kind": "photo"}
            if path.startswith("place_photos?select=event_id"):
                return [{"event_id": o["event_id"]} for o in own if o["event_id"] in path
                        and all(f"{k}=eq." not in path or f"{k}=eq.{o[k]}" in path for k in ("kind", "status"))]
            return ([{"url": "https://x/scene-market.jpg"}, {"url": "https://x/flyer.jpg"}]
                    if "kind=in.(scene,event,flyer)" in path else [])

    class Unread:
        def rest(self, *args, **kw):
            raise DbError("GET", "club_events", 503, "Service\n Unavailable")
    told, unread = photo_lines(Db(), date(2026, 12, 2)), photo_lines(Unread(), date(2026, 12, 2))
    return [(told == ["No event photo yet:", "- Sat Dec 5 · 10 AM · Winter Yoga · Sunny Mary Meadow",
                      "- Sat Dec 5 · 10 AM · Boys Swim vs Brainerd · Sunny Mary Meadow",
                      "- Sat Dec 5 · 10 AM · Pumpkin Walk · Sunny Mary Meadow"],
             "an Event added since the last report whose card shows its place's photo is listed, a meet with no two "
             "teams too, and one whose own photo was retired; one showing a scene or its own flyer isn't, nor one "
             "with its own live photo"),
            ("rpc/event_picture" in asked and asked.count("rpc/event_picture") == 5,
             "a game's white card has no photo: never listed or asked"),
            (unread == ["No event photo yet: not read (Supabase GET club_events failed 503: Service Unavailable)"],
             "a database that can't be read is one line, never a lost report")]


def in_parts():
    """prepare and tag in timed parts against fake slow sites (50 seconds a page) and a fake database,
    offline on a fake clock: one long morning, then the same morning in 2-minute parts."""
    import functools, io, tempfile, run as runner
    global load, start_reader, fetch_watched
    clock = type("Clock", (), {"t": 1000.0, "monotonic": lambda self: self.t, "time": lambda self: self.t})()
    entries = [{"id": f"p{i}", "_name": f"Place {i}", "_town": "st-joseph-mn", "_extra": {}, "status": "active",
                "tier": "watched", "sources": [{"url": f"https://site{i}.example/events", "method": "fetch"}]} for i in range(7)]
    asked, starts = [], []

    class SlowDb(FakeDb):
        def rest(self, method, path, body=None, prefer=None):
            if method == "PATCH":
                asked.append(path)
                clock.t += 50
            return []
    db, day = SlowDb(), date(2026, 10, 28)

    def slow_site(url, kind):
        asked.append(url)
        clock.t += 50
        if "site3" in url:
            raise RuntimeError("HTTP Error 500: Internal Server Error")
        return 200, f"Harvest supper Oct 30 at {url}", "fetch"

    def reader(out, today, name, which, stop):  # the schools take two parts in the parted morning
        starts.append(name)
        (out / f"{name}.log").write_text(f"[read] ok     {name} (fake): 1 items\n")
        if name == "feeds" or starts.count(name) == (1 if stop is None else 2):
            (out / f"{name}-items.jsonl").write_text(json.dumps({"kind": "news", "title": name}) + "\n")
        return type("Done", (), {"wait": lambda self: 0, "kill": lambda self: None})()

    def morning(minutes):
        """One morning's prepare, in parts: what each part fetched and printed, the batches, the database."""
        db.rows = {f"p{i}|https://site{i}.example/events": {"last_hash": "old", "last_checked_at": "2026-10-27"}
                   for i in range(6)}
        starts.clear()
        parts = []
        if (out / "prepare.json").exists():
            Run(out, day).finished()  # the last morning's finish
        while len(parts) < 5 and (not parts or "run again" in parts[-1][1]):
            n, said = len(asked), io.StringIO()
            with contextlib.redirect_stdout(said):
                prepare(Run(out, day, db, minutes=minutes))
            parts.append((asked[n:], said.getvalue()))
        return parts, {f.name: f.read_text() for f in (out / "batches").iterdir()}, dict(db.rows)
    saved = (runner.read_page, runner.validate, runner.find_root, runner.time, load, start_reader,
             fetch_watched, write_judged.interest_ids)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "morning"
            runner.read_page, runner.validate, runner.find_root, runner.time = slow_site, (lambda e: []), (lambda *a: Path(tmp)), clock
            load, start_reader = (lambda root: (entries, [])), reader
            fetch_watched = functools.partial(runner.fetch_watched, workers=1)  # one page at a time, as the clock counts
            write_judged.interest_ids = lambda: ["dining"]
            (one,), one_batches, _ = morning(None)
            parts, batches, rows = morning(2)
            fetched = [u for got, _ in parts for u in got]
            (out / "flags.jsonl").write_text("{}\n")  # the helpers' flags, already in
            again, n = io.StringIO(), len(asked)
            with contextlib.redirect_stdout(again):  # run again before finish: nothing fetched, nothing lost
                prepare(Run(out, day, db, minutes=2))
            again = (again.getvalue().split("\n")[:2] == ["[morning] prepared already this morning: nothing fetched again",
                                                          parts[2][1].split("\n")[0]]
                     and len(asked) == n and (out / "flags.jsonl").exists())
            (out / "tag").mkdir()
            (out / "tag" / "events.json").write_text(json.dumps([{"id": f"e{i}", "category": None} for i in range(5)]))
            (out / "tags.jsonl").write_text("".join(json.dumps({"id": f"e{i}", "interests": ["dining"], "draw": 2}) + "\n"
                                                    for i in range(5)))
            tagged, n = [], len(asked)
            while len(tagged) < 3 and "[morning] tagged" not in "".join(tagged):
                tagged += tag(Run(out, day, db, minutes=2), False)
            patched = asked[n:]
            (out / "tag" / "written.json").unlink(missing_ok=True)  # a new morning's tagging
            n, real = len(asked), SlowDb.rest

            def dies(self, method, path, body=None, prefer=None):
                if len(asked) - n == 2:
                    raise KeyboardInterrupt  # the cloud stops the command mid-way
                return real(self, method, path, body, prefer)
            SlowDb.rest = dies
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    tag(Run(out, day, db, minutes=None), False)
            except KeyboardInterrupt:
                pass
            SlowDb.rest = real
            with contextlib.redirect_stdout(io.StringIO()):
                tag(Run(out, day, db, minutes=None), False)
            stopped = asked[n:]
    finally:
        (runner.read_page, runner.validate, runner.find_root, runner.time, load, start_reader,
         fetch_watched, write_judged.interest_ids) = saved
    three, parts = len(parts) == 3, parts + [([], "")] * 3  # so a failing check reads as one
    left = [got for got, _ in parts]
    return [
        (three and sorted(fetched) == sorted(e["sources"][0]["url"] for e in entries)
         and len(fetched) == len(set(fetched)), "prepare in three parts fetches every page exactly once"),
        (batches == one_batches and len(batches) == 1 and one[1].split("\n")[0] == parts[2][1].split("\n")[0]
         == "[morning] fetched 7 watched pages, 6 changed, 5 for the cheap model in 1 batches "
            f"({out / 'batches'})", "the batches and the summary match one long run"),
        (all(r["last_hash"] == "old" for k, r in rows.items() if not k.startswith("p6|"))
         and rows.get("p6|https://site6.example/events", {}).get("last_hash") is not None,
         "no part moves a fingerprint; only a new page keeps its starting copy"),
        (parts[0][1] == "[morning] run again: 3 of 7 pages fetched; still to read: the school schedules and the feeds\n"
         and parts[1][1] == "[morning] run again: 6 of 7 pages fetched; still to read: the feeds\n"
         and [u[8:13] for u in left[1]] == ["site3", "site4", "site5"] and [u[8:13] for u in left[2]] == ["site6"],
         "a part whose time is spent says run again with what is left, and the next part reads just that"),
        (tagged[0] == "[morning] run again: 3 of 5 events tagged" and tagged[1].startswith("[morning] tagged 5 events")
         and sorted(patched) == [f"club_events?id=eq.e{i}" for i in range(5)], "tag in parts writes each Event once"),
        (sorted(stopped) == [f"club_events?id=eq.e{i}" for i in range(5)],
         "a tag run the cloud stops keeps what it wrote: the next run writes only the rest"),
        (again, "prepare run again before finish says its summary again and starts nothing over"),
    ]


def steps_alone():
    """Titles, save, today and finish, each alone through a Run with a fake database (BP app
    codebase-health-2 11; prepare's are in_parts and one_town): what each writes, and what it writes when it
    is refused or stopped part way and run again."""
    import io, tempfile
    global own_page
    day = date(2026, 10, 20)
    rows = [{"id": f"e{i}", "title": f"Supper {i}", "event_date": str(day), "start_time": "7 PM", "location": "Hall",
             "description": "", "category": None, "source_name": "Hall", "source_url": "https://hall.example/", "sport": None,
             "team_ids": None, "clubs": None, "interests_tagged_at": None, "draw": None, "end_at": None, "all_day": False}
            for i in range(3)]
    added = {"events": 1, "news": 0, "mentions": 0, "published_by_mention": 0, "cancelled": 0, "restored": 0,
             "added": {"events": [0], "news": []}}
    long_title = "Anniversary of the Dedication of Sacred Heart Chapel"
    long_news = "Pumpkin Crafted Cold Brew at Caribou"  # past its card's 2 lines (BP app inside-cards 13)
    about = "A harvest supper of roast turkey and pie, open to all; $12 a plate, kids under 10 free, at the parish hall downtown."
    stopped = []

    def refuse(method, path, body):
        raise DbError(method, path, 403, "permission denied")

    def stops_once(method, path, body):  # the cloud stops the command as this write goes out, the first time
        if path not in stopped:
            stopped.append(path)
            raise KeyboardInterrupt

    def said(step, *args):
        printed = io.StringIO()
        try:
            with contextlib.redirect_stdout(printed):
                step(*args)
        except SystemExit as e:
            printed.write(f"exit {e.code}\n")
        return printed.getvalue()
    saved = spots.fill, apple_maps.check, social.limits, social.missed_checks, write_judged.interest_ids, own_page, find_spots.read
    spots.fill, apple_maps.check = (lambda db, today, write, maps: ["- Map spots"]), (lambda db, write, today: ["- Apple Maps"])
    find_spots.read = lambda folder, minutes: None
    social.limits, social.missed_checks = (lambda: {"current": {"monthlyUsageUsd": 1}, "limits": {"maxMonthlyUsageUsd": 25}}), (lambda: [])
    write_judged.interest_ids, own_page = (lambda: ["dining"]), (lambda url: (200, "<p>nothing about it</p>"))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "morning"
            out.mkdir()
            db = FakeDb({"milk|https://m/events": {"last_hash": "old", "last_checked_at": "2026-10-19"}},
                        {"club_events?select=team_ids": lambda *a: [], "club_events?select=": lambda *a: [dict(r) for r in rows],
                         "rpc/apply_judged": added, "rpc/event_picture": {}})
            run = lambda minutes=None: Run(out, day, db, minutes=minutes)
            run().prepared({"today": str(day), "fetched": 2, "changed": 1, "to_read": 1, "failed": [], "readers": []})
            (out / "judged.jsonl").write_text(json.dumps(write_judged.item(title=long_title)) + "\n")
            (out / "feeds.jsonl").write_text(json.dumps(write_judged.item(kind="news", title=long_news, start=None,
                                                                          category="business")) + "\n")
            (out / "fingerprints.json").write_text(json.dumps([{"entry_id": "milk", "url": "https://m/events", "hash": "new",
                                                                "first_seen": False}]))
            titled = said(long_titles, run()), said(long_titles, run())
            listed, titled_wrote = (out / "titles.txt").read_text(), db.writes()

            said(save, run(), True)
            dry = db.writes(), (out / "report.json").exists(), (out / "report-dry-run.json").exists()
            db.answers["rpc/apply_judged"] = refuse
            refused = said(save, run(), False)
            refused_left = db.rows["milk|https://m/events"]["last_hash"], (out / "report.json").exists()
            db.answers["rpc/apply_judged"] = added
            first, second = said(save, run(), False), said(save, run(), False)
            applied, moved = len(db.writes("rpc/apply_judged")), db.rows["milk|https://m/events"]["last_hash"]
            laid = [len(json.loads((out / d / "events.json").read_text())) for d in ("tag", "describe")]

            (out / "tags.jsonl").write_text("".join(json.dumps({"id": r["id"], "interests": ["dining"], "draw": 2, "what": "Supper"}) + "\n"
                                                    for r in rows))
            (out / "describe.jsonl").write_text(json.dumps({"id": "e0", "about": about}) + "\n" + json.dumps({"id": "e1", "about": ""}) + "\n")
            n = len(db.writes())
            today_said = said(lay_out_today, run()), said(lay_out_today, run())
            today_lines = [e for e in read_items(out / "today.txt") if isinstance(e, dict)]
            today_wrote = db.writes()[n:]

            (out / "standouts.jsonl").write_text(json.dumps({"id": "e0", "why": "A church supper open to all"}) + "\n")
            db.answers = {"club_events?id=eq.e1": stops_once, **db.answers}
            n = len(db.writes())
            first_part = said(finish, run(-1), False)  # out of time before its first write
            over_early = run().summary().get("done")
            try:
                said(finish, run(), False)
            except KeyboardInterrupt:
                pass
            part_way, over_stopped = db.writes()[n:], run().summary().get("done")
            report = said(finish, run(), False)
            finished, over = db.writes()[n:], run().summary().get("done")
            n = len(db.writes())
            again = said(finish, run(), False)
            finished_again = db.writes()[n:]
            (out / "describe" / "written.json").unlink()  # a morning whose Abouts are still to save
            n = len(db.writes())
            out_of_time = said(finish, run(-1), False)
            late_wrote = db.writes()[n:]
            said(finish, run(), False)
            caught_up = db.writes()[n:]
    finally:
        spots.fill, apple_maps.check, social.limits, social.missed_checks, write_judged.interest_ids, own_page, find_spots.read = saved
    ids = lambda calls, key: [p.rsplit("=", 1)[1][-2:] for _, p, b in calls if p.startswith("club_events?id=eq.") and key in b]
    return [
        (listed == f"{long_title}\nNews, 30 characters at most:\n{long_news}\n" and titled[0] == titled[1]
         and "1 News past their 2 lines" in titled[0] and not titled_wrote,
         f"titles alone lists the long title, then the long News under its own line, and writes nothing; run again "
         f"the same: {listed!r}, {titled_wrote}"),
        (dry == ([], False, True), f"save alone, dry: nothing written, and a real save still to come: {dry}"),
        (refused.rstrip().endswith("exit [morning] save refused: Supabase POST rpc/apply_judged failed 403: permission denied")
         and refused_left == ("old", False), f"a save refused is one line, moves no fingerprint and can be run again: {refused[-200:]}, {refused_left}"),
        (applied == 2 and moved == "new" and "saved already this morning" in second and "saved already" not in first and laid == [3, 3],
         f"save alone writes once (one refused, one written), moves the fingerprint and lays out the helpers; run again it writes "
         f"nothing and lays them out again: {applied}, {moved}, {laid}"),
        (today_said[0] == today_said[1] and not today_wrote
         and [(e["interests"], e["about"]) for e in today_lines] == [(["dining"], about[:300]), (["dining"], ""), (["dining"], "")],
         f"today alone carries the helpers' answers and writes nothing: {today_lines}"),
        (first_part == "[morning] run again: 0 of 3 events tagged\n" and not over_early and not over_stopped and over,
         f"the morning is over only once finish has printed the report: {first_part!r}, {over_early}, {over_stopped}, {over}"),
        (ids(part_way, "interests") == ["e0", "e1"] and not ids(part_way, "described_at") and not [c for c in part_way if "morning_reports" in c[1]],
         f"finish stopped at a tag has written up to it, and no report: {part_way}"),
        (ids(finished, "interests") == ["e0", "e1", "e1", "e2"] and ids(finished, "described_at") == ["e0", "e1"]
         and [c[0] for c in finished if c[1].startswith("daily_standouts")] == ["DELETE", "POST"]
         and [c[1] for c in finished if c[1].startswith("morning_reports")] == ["morning_reports?on_conflict=day"] and report.startswith("Morning watch"),
         f"finish run again sends only what was left (the stopped write again), then the Abouts, standouts and report: {finished}"),
        ([c[1] for c in finished_again] == ["morning_reports?on_conflict=day"] and again == report,
         f"finish once more writes nothing new but the report's one row, and says the same: {finished_again}"),
        (out_of_time == "[morning] run again: 0 of 2 Abouts saved\n" and not late_wrote and ids(caught_up, "described_at") == ["e0", "e1"],
         f"Abouts out of time say run again with no report, and the next part saves them: {out_of_time!r}, {late_wrote}"),
    ]


def set_aside_across_days():
    """Eight mornings, Tuesday Oct 20 to Tuesday Oct 27, on a fake clock against fake sites and a fake
    database, offline: each morning's prepare and write as the routine runs them. Tuesday's morning is
    run twice, Wednesday's never runs (as Oct 29's refused 6 AM run), and on Thursday the network is
    down. `dsl` fails until Saturday and reads whenever it is asked after; `gone` always fails; `late`
    fails Saturday to Monday; the City's page fails Tuesday the 27th; the rest always read. An error
    row from the first test waits in the table for a page no longer watched (smooth-mornings 04)."""
    import io, tempfile, run as runner
    from datetime import timezone
    global load, start_reader
    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "category": "gov" if i == "city" else None, "sources": [{"url": f"https://{i}.example/", "method": "fetch"}]}
               for i in ("dsl", "gone", "late", "city", "ok1", "ok2", "ok3", "ok4")]
    asked = []
    db = FakeDb({"old|https://old.example/": {"last_error": "HTTP Error 500", "last_checked_at": "2026-10-14T16:00:00+00:00"}})

    def site(url, kind):
        d, page = runner.NOW.day, url[8:url.index(".")]
        asked.append((d, page))
        if d == 22:
            raise RuntimeError("<urlopen error [Errno 8] nodename nor servname provided, or not known>")
        if page == "gone" or (page == "dsl" and d <= 24) or (page == "late" and d in (24, 25, 26)) or (page, d) == ("city", 27):
            raise RuntimeError("HTTP Error 500: Internal Server Error")
        return 200, f"Harvest supper Oct 30 at {url}", "fetch"

    def reader(out, today, name, which, stop):
        (out / f"{name}.log").write_text("")
        (out / f"{name}-items.jsonl").write_text("")
        return type("Done", (), {"wait": lambda self: 0, "kill": lambda self: None})()
    saved = (runner.read_page, runner.validate, runner.find_root, runner.NOW, load, start_reader, write_judged.interest_ids)
    mornings, said, cleared = [20, 20, 22, 23, 24, 25, 26, 27], [], None
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "morning"
            runner.read_page, runner.validate, runner.find_root = site, (lambda e: []), (lambda *a: Path(tmp))
            load, start_reader = (lambda root: (entries, [])), reader
            write_judged.interest_ids = lambda: []
            for d in mornings:
                runner.NOW, report = datetime(2026, 10, d, 11, tzinfo=timezone.utc), io.StringIO()
                run = Run(out, date(2026, 10, d), db, minutes=None)
                with contextlib.redirect_stdout(io.StringIO()):
                    prepare(run)
                with contextlib.redirect_stdout(report):
                    write(run, True)
                run.finished()
                said.append([ln for ln in report.getvalue().splitlines() if ln.startswith("- ") and any(
                    w in ln for w in (".example/", "aside", "Failed", "not counted"))])
                cleared = cleared if cleared is not None else dict(db.rows["old|https://old.example/"])
    finally:
        runner.read_page, runner.validate, runner.find_root, runner.NOW, load, start_reader, write_judged.interest_ids = saved
    on = lambda page: [d for d, p in asked if p == page]
    named = lambda page: [d for d, lines in zip(mornings, said) if any(f" {page} " in ln for ln in lines)]
    with_line = lambda start: [d for d, lines in zip(mornings, said) for ln in lines if ln.startswith(start)]
    monday = ("- Pages set aside: 1, tried again today and still failing. Fixing a page's address or retiring a place "
              "is the registry job's, with Jesse's yes (source-registry skill)")
    quiet = {"failed": [], "fetched": 8, "uncounted": False, "set_aside": [], "back": [], "still": []}
    return [
        (on("dsl") == [20, 20, 22, 23, 24, 26, 27] and on("gone") == [20, 20, 22, 23, 24, 26]
         and on("late") == [20, 20, 22, 23, 24, 25, 26] and on("ok1") == mornings,
         "a page failing three mornings' reads in a row is set aside: skipped after, tried on Monday, read daily once back"),
        (named("dsl") == [24, 26] and named("gone") == [24] and named("late") == [26] and named("ok1") == []
         and "- Set aside: dsl https://dsl.example/: HTTP Error 500: Internal Server Error (failing since Oct 20); "
             "tried again on Mondays" in said[4] and "- Back: dsl https://dsl.example/ reads again (set aside since Oct 24)" in said[6],
         "reads, not days: a rerun, a morning that never ran and a morning the network was down count for nothing; "
         "the report names a page the morning it is set aside and the morning it is back, and no other"),
        ([ln[2:].split(",")[0] for lines in said for ln in lines if ln.startswith("- Failed today")] == [f"Failed today: {n}" for n in (2, 2, 8, 2, 3, 1, 2, 1)]
         and with_line("- 8 of 8 pages failed, not counted") == [22]
         and said[7][0] == "- Failed today: 1, the town's own among them: city https://city.example/ (HTTP Error 500: "
                           "Internal Server Error)" and named("city") == [22, 27],
         "a daily line counts the pages that failed, naming the town's own; most pages failing at once is one line, not counted"),
        (with_line(monday) == [26] and runner.aside_lines(quiet, date(2026, 11, 2)) == ["Failed today: 0"],
         "on Mondays one line counts the set-aside pages tried again and still failing, never one set aside that "
         "Monday, and none when there are none"),
        (cleared == {"last_error": None, "failing_since": None, "failing_reads": 0, "set_aside_at": None,
                     "last_checked_at": "2026-10-14T16:00:00+00:00"}, "the sync clears the error row of a page no longer watched"),
    ]

def one_town():
    """prepare --town with a second town in the registry (BP app codebase-health 15): only that town's
    pages are fetched and laid out, its readers are told the town, and its batches name it; the sync
    still gets every town's entries. With no --town it is St. Joseph's, as before."""
    import io, tempfile
    global load, fetch_watched, find_root
    entries = [{"id": f"{t}{i}", "_name": f"{t} place {i}", "_town": town, "_extra": {}, "status": "active",
                "tier": "watched", "sources": [{"url": f"https://{t}{i}.example/events", "method": "fetch"}]}
               for t, town in (("joe", "st-joseph-mn"), ("cloud", "st-cloud-mn")) for i in range(3)]
    synced, fetched, readers = [], [], []

    def fake_fetch(every, db, picked=None, done=(), stop=None, run_dir=None, today=None):
        synced.append(len(every))
        (run_dir / "snapshots").mkdir(parents=True, exist_ok=True)
        changed = []
        for e in picked:
            (run_dir / "snapshots" / f"{e['id']}.txt").write_text(f"Harvest supper at {e['_name']}")
            changed.append({"entry_id": e["id"], "url": e["sources"][0]["url"], "hash": "h", "first_seen": False,
                            "snapshot": f"{e['id']}.txt"})
        fetched.append([e["id"] for e in picked])
        return {"results": [], "left": 0, "fetched": len(changed), "changed": changed, "run_dir": str(run_dir),
                "failed": [], "uncounted": False, "set_aside": [], "back": [], "still": [], "unrecorded": []}

    def fake_popen(cmd, **kw):
        readers.append(cmd)
        Path(cmd[cmd.index("--items") + 1]).write_text("")
        return type("Done", (), {"wait": lambda self: 0, "kill": lambda self: None})()

    def morning(tmp, *town):
        out = Path(tmp) / (town[0] if town else "default") / "morning"
        out.parent.mkdir()
        readers.clear()
        with contextlib.redirect_stdout(io.StringIO()):
            prepare(Run(out, date(2026, 10, 28), FakeDb(), *town, minutes=None))
        pages = [p["entry_id"] for p in json.loads((out / "pages.json").read_text())]
        return pages, "".join(f.read_text() for f in (out / "batches").iterdir()), [c[c.index("--town") + 1] for c in readers]

    saved = load, fetch_watched, find_root, subprocess.Popen, write_judged.interest_ids
    TOWNS["st-cloud-mn"] = {"label": "St. Cloud MN", "zips": ["56301"], "display": "St. Cloud", "photo_slug": "st-cloud"}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            load, fetch_watched, find_root = (lambda root: (entries, [])), fake_fetch, (lambda *a: Path(tmp))
            subprocess.Popen = fake_popen
            write_judged.interest_ids = lambda: ["dining"]
            cloud = morning(tmp, "st-cloud-mn")
            joe = morning(tmp)
    finally:
        load, fetch_watched, find_root, subprocess.Popen, write_judged.interest_ids = saved
        del TOWNS["st-cloud-mn"]
    return [
        (fetched[0] == ["cloud0", "cloud1", "cloud2"] and cloud[0] == fetched[0] and synced == [len(entries)] * 2
         and cloud[2] == ["st-cloud-mn", "st-cloud-mn"],
         f"prepare --town st-cloud-mn fetches and lays out only St. Cloud's pages, tells its readers the town, "
         f"and syncs every town's entries: {fetched}, {cloud[0]}, {cloud[2]}, {synced}"),
        ("The town is St. Cloud, Minnesota." in cloud[1] and "joe" not in cloud[1],
         "a second town's batches name it, and carry none of the first town's pages"),
        (fetched[1] == ["joe0", "joe1", "joe2"] and joe[0] == fetched[1] and joe[2] == ["st-joseph-mn", "st-joseph-mn"]
         and "The town is St. Joseph, Minnesota." in joe[1] and "cloud" not in joe[1],
         f"prepare with no --town is St. Joseph's, as before: {fetched}, {joe[2]}"),
    ]


ROUTINE_FILES = ("morning.md", "social.md", "photos.md")  # sources/models/: what the routines follow


def wrong_in(texts):
    """What the routines' instruction files get wrong (BP app smooth-mornings 07): a step number (a
    renumbering sent the morning routine to the wrong steps on Oct 21-24), or a script command the
    script doesn't have, `x.py word` in backticks where word isn't one of x.py's commands."""
    wrong = []
    for name, text in texts.items():
        wrong += [f"{name}: {m.group(0).strip()!r}" for m in re.finditer(r"\b[Ss]teps?\s+\d+|^\s*\d+\.\s+\*\*", text, re.M)]
        for span in re.findall(r"`([^`]+)`", text):
            for script, word in re.findall(r"\b([\w-]+)\.py\s+([a-z][\w-]*)", span):
                path = SCRIPTS / f"{script}.py"
                if word not in (commands_of(path) if path.exists() else set()):
                    wrong.append(f"{name}: {script}.py {word}")
    return wrong


def commands_of(path):
    """A script's commands: its first positional argument's argparse choices, else (a script reading sys.argv
    itself) the words its __main__ block compares the arguments with, a list it names included (ready.py's
    ROUTINES)."""
    import ast
    tree = ast.parse(path.read_text())
    for n in ast.walk(tree):
        if (isinstance(n, ast.Call) and getattr(n.func, "attr", "") == "add_argument" and n.args
                and isinstance(n.args[0], ast.Constant) and not n.args[0].value.startswith("-")):
            return {e.value for k in n.keywords if k.arg == "choices" for e in k.value.elts}
    lists = {t.id: n.value for n in tree.body if isinstance(n, ast.Assign) for t in n.targets if isinstance(t, ast.Name)}
    block = [n for n in tree.body if isinstance(n, ast.If) and "__main__" in ast.unparse(n.test)]
    found = [lists.get(n.id) if isinstance(n, ast.Name) else n for b in block for n in ast.walk(b)]
    return {c.value for n in found if n is not None for c in ast.walk(n) if isinstance(c, ast.Constant) and isinstance(c.value, str)}


def instructions():
    texts = {n: (SCRIPTS.parent / "models" / n).read_text() for n in ROUTINE_FILES}
    made_up = dict(texts, **{"morning.md": texts["morning.md"] + "\nRun `python3 sources/scripts/morning.py frobnicate`.\n"})
    gone = {"old.md": "`morning.py tag`, `morning.py describe`, `morning.py run`, `ready.py photos`, `place_photos.py check`"}
    numbered = {"social.md": "Follow steps 3 to 6 of `sources/models/morning.md`.\n1. **Ready.** Run `ready.py social`.\n"}
    return [(wrong_in(texts) == [], f"the routines' files name only commands the scripts have, and no step number: {wrong_in(texts)}"),
            (wrong_in(made_up) == ["morning.md: morning.py frobnicate"] and wrong_in(numbered) == ["social.md: 'steps 3'", "social.md: '1. **'"],
             "a made-up command or a step number fails it"),
            (wrong_in(gone) == ["old.md: morning.py tag", "old.md: morning.py describe", "old.md: morning.py run"],
             f"a command is one of the script's own, not any word it spells: {wrong_in(gone)}")]


def whole_morning():
    """One whole morning as the routine runs it, each step through its command, offline (BP app
    smooth-mornings 07): Ready, Prepare in parts, the titles step, Save and Finish dry, Save (twice, as on
    Oct 22), the standouts' layout, and Finish in parts with a timeout in each of its saves, then twice
    more, over fake sites (one failing its third morning in a row, so set aside), a fake database, a fake
    clock and fake Apify, with the helpers' and the judge's lines written here. A command taken out of
    main fails it."""
    import functools, io, tempfile, ready, run as runner
    from datetime import timezone
    global Supabase, load, start_reader, fetch_watched, find_root, own_page, firecrawl_credits
    # The spots step reads the real registry; spots.py's own self-test covers it.
    real_fill, spots.fill = spots.fill, lambda db, today, write, maps: ["- Map spots: set 4, 0 with no spot"]
    real_read, find_spots.read = find_spots.read, lambda folder, minutes: None
    real_check, apple_maps.check = apple_maps.check, lambda db, write, today: ["- Apple Maps: 60 places checked, 0 closed for good, 24 with no Apple Maps place"]
    clock = type("Clock", (), {"t": 1000.0, "monotonic": lambda self: self.t, "time": lambda self: self.t})()
    sites = ["p0", "p1", "p2", "p3", "dsl"]
    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "sources": [{"url": f"https://{i}.example/", "method": "fetch"}]} for i in sites]

    class Db(FakeDb):
        rows = {f"{i}|https://{i}.example/": {"last_hash": "old", "last_checked_at": "2026-11-02T11:00:00+00:00"} for i in sites}
        rows["dsl|https://dsl.example/"].update(last_error="HTTP Error 500", failing_reads=2,
                                                 failing_since="2026-10-31T11:00:00+00:00")
        events, standouts, saves, writes, reports, hours = [], [], [], [], {}, []
        breaks, tries = {}, collections.Counter()  # breaks: the nth write of a kind fails once (a timeout)

        def __init__(self):  # main makes one per command; they share the class's rows, as one database
            pass

        def rest(self, method, path, body=None, prefer=None):
            if path == "rpc/apply_judged":
                return save_items(body)
            if path.startswith("places?select=entry_id,hours") or path.startswith("places?entry_id"):  # a post's week: p0 closed all week
                return self.hours.append((method, path, body)) if method == "PATCH" else [{"entry_id": "p0", "hours": {d: [] for d in accounts.DAY_KEYS}}]
            kind = ("standouts" if method == "POST" and path.startswith("daily_standouts")
                    else "describe" if method == "PATCH" and "described_at" in body else "tag" if method == "PATCH" else None)
            if kind:
                self.tries[kind] += 1
                if self.breaks.get(kind) == self.tries[kind]:
                    raise DbError(method, path, None, "timed out")
                self.writes.append((kind, path))
            if method == "PATCH":
                clock.t += 150  # a write takes long enough that finish's tags take two parts
                next(e for e in self.events if path == f"club_events?id=eq.{e['id']}").update(body)
            elif path.startswith("daily_standouts"):
                self.standouts[:] = body if method == "POST" else []
            elif path.startswith("morning_reports?on_conflict=day"):
                self.reports[body["day"]] = body["report"]
            elif path.startswith("club_events"):
                return [dict(e) for e in self.events if "status=eq.waiting_logo" not in path and
                        ("event_date=eq.2026-11-03" not in path or e["event_date"] == "2026-11-03")
                        and ("described_at=is.null" not in path or not e["described_at"])
                        and ("interests_tagged_at.is.null" not in path or not (e["interests_tagged_at"] and e["what"]))]
            return []

    def save_items(p):  # apply_judged: every Event and News new
        Db.saves.append(p)
        Db.events += [dict(row, id=f"e{len(Db.events) + i}", status="approved", clubs=None, interests=None,
                               interests_tagged_at=None, draw=None, what=None, described_at=None)
                          for i, row in enumerate(p["p_events"])]
        return {"events": len(p["p_events"]), "news": len(p["p_news"]), "mentions": 0, "published_by_mention": 0,
                "cancelled": 0, "restored": 0, "added": {"events": list(range(len(p["p_events"]))),
                                                         "news": list(range(len(p["p_news"])))}}

    def site(url, kind):
        clock.t += 100  # four pages to a part
        if "dsl" in url:
            raise RuntimeError("HTTP Error 500: Internal Server Error")
        return 200, f"Harvest Supper Nov 3 at {url}", "fetch"

    chapel = write_judged.item(title="Anniversary of the Dedication of Sacred Heart Chapel", start="2026-11-21T19:00:00-06:00",
                               end=None, place="Sacred Heart Chapel", source_name="Saint Benedict's Monastery",
                               source_url="https://sbm.example/events", interest="faith", blurb=None, size="everyday")

    def reader(out, today, name, which, stop):
        (out / f"{name}.log").write_text(f"[read] ok     {name} (fake): {int(name == 'feeds')} items\n")
        (out / f"{name}-items.jsonl").write_text(json.dumps(chapel) + "\n" if name == "feeds" else "")
        return type("Done", (), {"wait": lambda self: 0, "kill": lambda self: None})()
    long_about = ("Vendors from around St. Joseph fill the hall with crafts, baking and gifts; free to walk "
                  "through, with coffee and cider for sale.")
    judged = [write_judged.item(title="Harvest Supper", start="2026-11-03T17:00:00-06:00", end=None, blurb="", interest="dining"),
              write_judged.item(title="Holiday Market", start="2026-11-07T09:00:00-06:00", end=None, blurb=long_about),
              write_judged.item(title="Holiday Market Bake Sale", start="2026-11-07T14:00:00-06:00", end=None, blurb=long_about),
              write_judged.item(kind="news", title="Pumpkin pie pre-orders open", start=None, category="business",
                                source_url="https://www.instagram.com/p/pies", interest="dining")]

    def command(*argv):
        said = io.StringIO()
        try:
            with contextlib.redirect_stdout(said), contextlib.redirect_stderr(io.StringIO()):
                main([*argv, "--today", "2026-11-03"])
        except SystemExit as e:
            said.write(f"exit {e.code}\n")
        except Exception as e:  # a step that broke, as one line of what it said
            said.write(f"broke: {type(e).__name__}: {e}\n")
        return said.getvalue()

    def parts(*argv):
        said = [command(*argv)]
        while "run again" in said[-1] and len(said) < 4:
            said.append(command(*argv))
        return said
    saved = (runner.read_page, runner.validate, runner.find_root, runner.time, runner.NOW, social.limits, social.missed_checks,
             Supabase, load, start_reader, fetch_watched, find_root, own_page, write_judged.interest_ids, firecrawl_credits)
    social.missed_checks = lambda: []
    firecrawl_credits = lambda: {"remainingCredits": 1000, "planCredits": 1000,  # none used, so the real clock can't change the line
                                 "billingPeriodStart": "2026-10-21T01:45:31.463Z", "billingPeriodEnd": "2026-11-21T01:45:31.463Z"}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / ".runs" / "morning"
            runner.read_page, runner.validate, runner.find_root, runner.time = site, (lambda e: []), (lambda *a: Path(tmp)), clock
            runner.NOW = datetime(2026, 11, 3, 11, tzinfo=timezone.utc)  # a Tuesday: no weekly try
            social.limits = lambda: {"current": {"monthlyUsageUsd": 4.2}, "limits": {"maxMonthlyUsageUsd": 25},
                                     "monthlyUsageCycle": {"endAt": "2026-11-18T00:00:00.000Z"}}
            Supabase, load, start_reader, find_root = Db, (lambda root: (entries, [])), reader, (lambda *a: Path(tmp))
            fetch_watched = functools.partial(runner.fetch_watched, workers=1)  # one page at a time, as the clock counts
            own_page = lambda url: (200, f"<p>Harvest Supper, a church supper open to all, at {url}</p>")
            write_judged.interest_ids = lambda: ["dining", "faith", "markets"]
            env = {"SUPABASE_URL": "u", "SUPABASE_PUBLISHABLE_KEY": "k", "FIRECRAWL_API_KEY": "f"}
            readied = "morning" in ready.ROUTINES and ready.ready("morning", env, probe=lambda modules: [],
                                                                  reach=lambda: "")[0]
            prepared = parts("prepare")
            out.mkdir(parents=True, exist_ok=True)  # prepare made it, unless its command is gone
            (out / "flags.jsonl").write_text("")  # the cheap model's flags, then the judge's items
            (out / "judged.jsonl").write_text("".join(json.dumps(i) + "\n" for i in judged))
            titled = command("titles")
            listed = (out / "titles.txt").read_text() if (out / "titles.txt").exists() else ""
            (out / "titles.json").write_text(json.dumps({"Anniversary of the Dedication of Sacred Heart Chapel":
                                                         "Sacred Heart Chapel Anniversary"}))
            dry = [command("save", "--dry-run"), command("finish", "--dry-run")]
            dry_wrote = bool(Db.saves or Db.writes) or (out / "report.json").exists()
            saves = [command("save"), command("save")]
            given = lambda d: json.loads((out / d / "events.json").read_text()) if (out / d / "events.json").exists() else []
            is_supper = lambda e: e["title"] == "Harvest Supper"
            about = "A harvest supper of roast turkey and pie, open to all; $12 a plate, kids under 10 free."
            tags = [{"id": e["id"], "interests": ["dining"], "draw": 3 if is_supper(e) else 2, "what": "Supper"}
                    for e in given("tag")]
            # The supper's About, the markets' Abouts with their "free" moved to the price (inside-cards 14), a check.
            told = [{"id": e["id"], "about": about} if is_supper(e)
                    else {"id": e["id"], "about": e["about"].replace("; free to walk through", ""), "price": "Free"} if e["about"]
                    else {"id": e["id"], "about": "", "check": "Starts at 7:30, not 7."}
                    for e in given("describe")]
            for name, lines in (("tags.jsonl", tags), ("describe.jsonl", told)):
                (out / name).write_text("".join(json.dumps(x) + "\n" for x in lines))
            laid = command("today")
            today_txt = [e for e in read_items(out / "today.txt") if isinstance(e, dict)]
            (out / "standouts.jsonl").write_text("".join(json.dumps({"id": e["id"], "why": "A church supper open to all"}) + "\n"
                                                         for e in today_txt))
            Db.breaks = {"tag": 4, "describe": 2, "standouts": 1}  # the last tag, the second About, the standouts
            broken = parts("finish")
            finished = parts("finish")  # again: it writes only what the timeouts left
            third = command("finish")  # and once more: nothing left to write
            supper = next((e for e in Db.events if is_supper(e)), {})
            market = next((e for e in Db.events if e["title"] == "Holiday Market"), {})
            stored = (len(Db.saves) == 1 and all(e["interests_tagged_at"] for e in Db.events)
                      and supper.get("description", "").startswith("A harvest supper")
                      and (market.get("price"), "free" in market.get("description", "")) == ("Free", False)
                      and [r["event_id"] for r in Db.standouts] == [supper.get("id")]
                      and all(r["last_hash"] != "old" for k, r in Db.rows.items() if not k.startswith("dsl")))
            # A social check's save (its prepare.json names the run) only writes: no batches for helpers.
            prep = json.loads((out / "prepare.json").read_text()) if (out / "prepare.json").exists() else {}
            (out / "prepare.json").write_text(json.dumps({**prep, "run": "busy"}))
            (out / "report.json").unlink(missing_ok=True)
            shutil.rmtree(out / "tag", ignore_errors=True), shutil.rmtree(out / "describe", ignore_errors=True)
            with (out / "judged.jsonl").open("a") as f:  # and the judge read new lasting hours in a post
                p0 = next(p["file"] for p in json.loads((out / "pages.json").read_text()) if p["entry_id"] == "p0")
                f.write(json.dumps({"kind": "hours", "page": p0, "days": {"mon": "9 AM to 5 PM"}}) + "\n")
            evening = command("save")
            evening_laid = (out / "tag").exists() or (out / "describe").exists()
    finally:
        spots.fill, find_spots.read = real_fill, real_read
        apple_maps.check = real_check
        (runner.read_page, runner.validate, runner.find_root, runner.time, runner.NOW, social.limits, social.missed_checks,
         Supabase, load, start_reader, fetch_watched, find_root, own_page, write_judged.interest_ids, firecrawl_credits) = saved
    report = finished[-1].splitlines()
    return [
        (readied == "[ready] ready", f"Ready says ready: {readied}"),
        (len(prepared) == 2 and prepared[0] == "[morning] run again: 4 of 5 pages fetched; still to read: the feeds\n"
         and prepared[1].startswith("[morning] fetched 5 watched pages, 4 changed, 4 for the cheap model in 1 batches"),
         f"Prepare takes two parts and says run again between: {prepared}"),
        (titled.startswith("[morning] 1 titles over 40") and listed == "Anniversary of the Dedication of Sacred Heart Chapel\n",
         f"the titles step lists the feed's long title: {titled}"),
        ("saved already this morning" in saves[1] and "Morning watch, 2026-11-03" in saves[0] and "events to tag in 1 batches" in saves[0]
         and "events to describe in 1 batches, 1 with their own page read" in saves[0],
         f"Save writes once, then lays out the tag and describe batches; run again it writes nothing: {saves}"),
        (not dry_wrote and "Morning watch, 2026-11-03" in dry[0] and dry[1].startswith("Morning watch, 2026-11-03")
         and "(dry run: nothing written)" in dry[1] and "Apify: $4.20" in dry[1],
         f"a dry save and a dry finish chain, write nothing, and leave the real save to write: {dry}"),
        (laid.startswith("[morning] 1 events today") and [(e["title"], e["interests"], e["draw"], e["about"][:16]) for e in today_txt]
         == [("Harvest Supper", ["dining"], 3, "A harvest supper")],
         f"today's Events carry the helpers' tags and Abouts before finish saves them: {today_txt}"),
        (len(broken) == 2 and broken[0] == "[morning] run again: 3 of 4 events tagged\n"
         and broken[1].startswith("Morning watch, 2026-11-03\n") and "New Events:" in broken[1]
         and all(f"[morning] {w} failed: Supabase " in broken[1] for w in ("tags", "Abouts", "standouts"))
         and broken[1].rstrip().endswith("(resets after Nov 20)"),
         f"Finish takes two parts while the tags are written, and a timeout in any save is a line in the whole report: {broken}"),
        (list(Db.reports) == ["2026-11-03"] and Db.reports["2026-11-03"] + "\n" == third
         and "[morning] tags failed" not in third, "each finish saves its report as the morning's one row, the last one kept"),
        # Four Abouts now (two markets' prices, inside-cards 14): the part's clock runs out after three, so run again
        # takes two parts, and once more writes nothing.
        (finished == ["[morning] run again: 3 of 4 Abouts saved\n", third] and sorted(collections.Counter(Db.writes).values()) == [1] * 9
         and [k for k, _ in Db.writes].count("tag") == 4 and [k for k, _ in Db.writes].count("describe") == 4,
         f"finish run again writes only what the timeouts left, and once more nothing: {finished[:1]} {Db.writes}"),
        (report == ["Morning watch, 2026-11-03",
                    "- Pages: 5 fetched, 4 changed, 4 read by the cheap model",
                    "- Events: 4 new, 0 already listed",
                    "- News: 1 new, 0 repeats left out",
                    "- Skipped: 0 (past, outside the area or unreadable)",
                    "- Failed today: 1",
                    "- Set aside: dsl https://dsl.example/: HTTP Error 500: Internal Server Error (failing since Oct 31); "
                    "tried again on Mondays",
                    "- Written: 0 mentions, 0 published by a mention, 0 cancelled, 0 back on",
                    "New Events:",
                    "- Tue Nov 3 · 5 PM · Harvest Supper · Milk & Honey Ciders",
                    "- Sat Nov 7 · 9 AM · Holiday Market · Milk & Honey Ciders",
                    "- Sat Nov 7 · 2 PM · Holiday Market Bake Sale · Milk & Honey Ciders",
                    "- Sat Nov 21 · 7 PM · Sacred Heart Chapel Anniversary · Sacred Heart Chapel",
                    "New News:",
                    "- Pumpkin pie pre-orders open (Milk & Honey Ciders)",
                    "Maybe the same:",
                    "- 'Holiday Market Bake Sale' and 'Holiday Market' on 2026-11-07",
                    "Notes:",
                    "- interest 'bars' is not on the list ('Holiday Market'): left empty",
                    "- interest 'bars' is not on the list ('Holiday Market Bake Sale'): left empty",
                    "[morning] tagged 4 events (0 with no interest; draw 3/2/1: 1/3/0), 4 with what they are in words, "
                    "0 left for tomorrow",
                    "[morning] described 3 of 4 events given",
                    "[check] Sacred Heart Chapel Anniversary (2026-11-21): Starts at 7:30, not 7.",
                    "[morning] standouts: 1 of 1 events today",
                    "[morning] #1 Harvest Supper (5 PM): A church supper open to all",
                    "No event photo yet:",
                    "- Tue Nov 3 · 5 PM · Harvest Supper · Milk & Honey Ciders",
                    "- Sat Nov 7 · 9 AM · Holiday Market · Milk & Honey Ciders",
                    "- Sat Nov 7 · 2 PM · Holiday Market Bake Sale · Milk & Honey Ciders",
                    "- Sat Nov 21 · 7 PM · Sacred Heart Chapel Anniversary · Sacred Heart Chapel",
                    "- Map spots: set 4, 0 with no spot",
                    "- Places: 0 open, 0 with an Apple id, 0 with hours, 0 with a logo, 0 with a photo",
                    "- Apple Maps: 60 places checked, 0 closed for good, 24 with no Apple Maps place",
                    "Apify: $4.20 of $25 this month (resets after 2026-11-18)",
                    "Firecrawl: 1,000 of 1,000 credits left (resets after Nov 20)"],
         "Finish prints the whole report:\n" + "\n".join(report)),
        (stored, "Save wrote once and moved the changed pages' fingerprints; Finish saved the tags, the About and "
                 "the standout"),
        ("Social watch (busy), 2026-11-03" in evening and len(Db.saves) == 2 and not evening_laid,
         f"a social check's save writes and lays out nothing for helpers: {evening[-300:]}"),
        ("- Skipped: 0 " in evening and "- Hours: p0, from its post https://p0.example/: Mon closed, now 9 AM–5 PM" in evening
         and [(m, p, b["hours"]["mon"]) for m, p, b in Db.hours] == [("PATCH", "places?entry_id=eq.p0", [["09:00", "17:00"]])],
         f"a post's new hours go on its place, not to the Events and News writer: {evening[-400:]}"),
    ]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["prepare", "titles", "save", "today", "finish"])
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--dry-run", action="store_true", help="save, finish: print what would be written, write nothing")
    ap.add_argument("--town", default=DEFAULT, help="prepare, save, finish: the town (a sources/towns/ file's name)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if not args.step:
        ap.error("prepare, titles, save, today or finish")
    lookup(args.town)
    today = date.fromisoformat(args.today) if args.today else datetime.now(LOCAL).date()
    run = Run(find_root() / ".runs" / "morning", today, Supabase(), args.town)
    if args.step == "prepare":
        prepare(run)
    elif args.step == "titles":
        long_titles(run)
    elif args.step == "save":
        save(run, args.dry_run)
    elif args.step == "today":
        lay_out_today(run)
    else:
        finish(run, args.dry_run)


if __name__ == "__main__":
    main()
