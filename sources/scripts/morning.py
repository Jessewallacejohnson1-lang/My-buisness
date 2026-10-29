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
  titles    list the event titles still over 40 characters once tidied (games aside) in
            .runs/morning/titles.txt, for the routine's model to shorten into titles.json
            (.claude/skills/title-and-place; Jesse, 2026-10-21)
  write     merge the feed items with the judge's items, give long titles their short ones
            (titles.json), write them (public.apply_judged over the service role key), then save
            the changed pages' new fingerprints (fingerprints.json) and print the morning's
            summary: a morning that stops before this reads the same pages again tomorrow. Its new
            counts are what the database did (apply_judged's answer), and it lists each new Event
            (date, time, title, place; soonest first, 40 at most, the rest counted by source) and
            News title, and names News folded into their post's News (BP app smooth-mornings 05)
  untagged  lay out the Events no tagger has read yet (or that have no draw, or no words saying
            what they are), upcoming or still running, in batches of 40 for the cheap model
            (town-feed tickets 33 and 34, BP app event-card 05; sources/models/tag.md)
  tag       write the cheap model's tags (.runs/morning/tags.jsonl) onto those Events: only
            ids from the shared interest list, a draw of 1, 2 or 3, an Event's first interest
            becomes its category when it has none, and what it is in one to three words; an
            Event tagged before only gets its words, so nobody's feed reshuffles. One write per
            Event (901 on 2026-10-27), so it works in parts like prepare
  thin      lay out the upcoming Events found in the last two days whose About is empty or under a
            sentence (feed and catalog events skip the judge), at most 30 a morning, in batches of 10 for the
            routine's helpers to research (sources/models/describe.md; Jesse, 2026-10-24). Never a game
            (write_judged.is_game: its reader wrote its About) or an Event laid out before (smooth-mornings 06)
  describe  write the helpers' Abouts (.runs/morning/describe.jsonl) onto those Events, each
            only when longer than the one it has, mark every Event they answered as researched
            (club_events.described_at), and print how many it was given and filled, and their CHECK lines
  today     lay out today's Events as the Town feed takes them, for the routine's model to pick
            the day's standouts (BP app docs/plans/daily-tab, ticket 14; sources/models/standouts.md)
  standouts write the model's standouts (.runs/morning/standouts.jsonl) as today's
            daily_standouts, best first, and print each with its reason

Everything lands in .runs/morning/. Both steps need SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY in the environment; `write --dry-run` writes nothing.

  python3 sources/scripts/morning.py prepare [--today YYYY-MM-DD]
  python3 sources/scripts/morning.py titles
  python3 sources/scripts/morning.py write [--dry-run]
  python3 sources/scripts/morning.py untagged
  python3 sources/scripts/morning.py tag [--dry-run]
  python3 sources/scripts/morning.py thin
  python3 sources/scripts/morning.py describe [--dry-run]
  python3 sources/scripts/morning.py today
  python3 sources/scripts/morning.py standouts [--dry-run]
  python3 sources/scripts/morning.py --selftest
"""

import argparse, collections, contextlib, json, re, shutil, subprocess, sys, time
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
from batch import layout
import write_judged
from run import Supabase, fetch_watched, deadline, late, part_state, resume_part, aside_lines
from db import DbError

SCRIPTS = Path(__file__).resolve().parent
TAG_BATCH = 40
TOWN = "st-joseph-mn"  # daily_standouts.town, as town_status names it
STANDOUTS = 9
THIN = 120        # characters: an About under this says less than a sentence
DESCRIBE_MAX = 30  # Events a morning; the rest wait for tomorrow
DESCRIBE_BATCH = 10
ABOUT_MAX = 1000   # as write_judged.clip
LIST_MAX = 40  # new Events listed one by one; the rest as a count per source (a first read can add hundreds)
PART_MINUTES = 6  # a part starts nothing new after this, so it ends within 9: the cloud stops a command at 10
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


def prepare(today, out, minutes=PART_MINUTES):
    """In timed parts: each starts no new page or reader after `minutes`, saves what it read in
    prepare-part.json and says "run again" with what is left; the next part carries on, each page
    fetched once a morning. The part that finishes lays out the batches and prints the summary."""
    stop = deadline(minutes)
    part_f = out / "prepare-part.json"
    part = json.loads(part_f.read_text()) if part_f.exists() else {}
    if part.get("today") != str(today) or (out / "prepare.json").exists():  # a new morning
        if out.exists():
            shutil.rmtree(out)
        (out / "batches").mkdir(parents=True)
        part = {"today": str(today), "pages": [], "readers": {}, "state": {}}
    resume_part(part["state"])
    root = find_root()
    every, errors = load(root)
    if errors:
        sys.exit("[morning] registry invalid:\n" + "\n".join(errors))
    entries = [e for e in every if e.get("status") == "active"]

    # The league's site is slow and no other source's server (twelve minutes for the schools
    # on 2026-10-25, with its retries), so the schools are read while the pages are fetched.
    done = part["readers"]
    games = None if "games" in done else start_reader(out, today, "games", ["--reader", "mshsl"], stop)
    db = Supabase()
    try:
        with open(out / "fetch.log", "a") as log, contextlib.redirect_stdout(log):
            report = fetch_watched(every, db, done=part["pages"], stop=stop, run_dir=out / "fetch", today=today)
    except BaseException:
        if games:
            games.kill()
        raise
    part.update(pages=report["results"], state=part_state())
    # ponytail: a part killed after fetch_watched recorded its pages but before this line loses their results:
    # the next part fetches them again (a morning counts once, run.set_aside) but a page set aside or back
    # in the lost part goes unnamed. Save each result as it is recorded if that is ever seen.
    part_f.write_text(json.dumps(part))  # before waiting on the readers: a stopped part keeps its pages
    # The feeds share servers with the pages, so they are read after them.
    feeds = None
    if not report["left"] and "feeds" not in done and not late(stop):
        feeds = reader_lines(start_reader(out, today, "feeds", ["--skip-reader", "mshsl"], stop), out, "feeds")
    for name, lines in (("feeds", feeds), ("games", games and reader_lines(games, out, "games"))):
        if lines is not None:
            done[name] = lines
    part.update(pages=report["results"], state=part_state())
    part_f.write_text(json.dumps(part))
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
    for i, text in enumerate(layout(pages, today), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(text)
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in pages], indent=1))
    (out / "existing.json").write_text(json.dumps(write_judged.listed_in_db(), indent=1, default=str))
    seasons = {r["entry_id"]: r for r in Supabase().rest(
        "GET", "places?select=name,entry_id,hours&entry_id=not.is.null&hours->season=not.is.null")}
    (out / "seasons.txt").write_text(season_pages(pages, seasons))

    summary = {"today": str(today), "fetched": report["fetched"], "changed": len(report["changed"]),
               "first_seen": sum(1 for c in report["changed"] if c.get("first_seen")),
               "to_read": len(pages), "batches": len(list((out / "batches").iterdir())),
               "aside": aside_lines(report, today),  # a failing page is named only when set aside or back (smooth-mornings 04)
               "readers": readers, "interests": write_judged.interest_ids()}
    (out / "prepare.json").write_text(json.dumps(summary, indent=1))
    print(f"[morning] fetched {summary['fetched']} watched pages, {summary['changed']} changed, "
          f"{summary['to_read']} for the cheap model in {summary['batches']} batches ({out / 'batches'})")
    for ln in readers:
        print(ln)
    for a in summary["aside"]:
        print(f"[morning] {a}")
    print(f"[morning] interests: {', '.join(summary['interests'])}")


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
    lines += [f"- Reader failed: {r.split('FAILED', 1)[1].strip()}" for r in prep["readers"] if "FAILED" in r]
    lines += [f"- Folded: {detail}" for what, detail in result["outcomes"] if what == "folded"]
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
    return lines


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


def long_titles(out):
    items = read_items(out / "feeds.jsonl") + read_items(out / "judged.jsonl")
    titles = write_judged.long_titles(items, write_judged.listed_in_db())
    (out / "titles.txt").write_text("".join(t + "\n" for t in titles))
    print(f"[morning] {len(titles)} titles over {write_judged.TITLE_MAX} characters ({out / 'titles.txt'})")


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


def write(out, dry_run, today):
    prep = json.loads((out / "prepare.json").read_text())
    feeds, judged = read_items(out / "feeds.jsonl"), read_items(out / "judged.jsonl")
    items = feeds + judged
    existing = write_judged.listed_in_db()
    result = write_judged.plan(items, existing, today, write_judged.interest_ids(), titles=short_titles(out),
                               teams=write_judged.known_teams(), recent_news=write_judged.news_in_db())
    write_judged.report(items, result)
    try:
        written = None if dry_run else write_judged.apply(result)
        if not dry_run:  # saved before the summary, so a slip in printing it never re-reads these pages tomorrow
            save_fingerprints(out)
        print("\n".join(summary_lines(prep, result, written)))
    except DbError as e:  # one line naming what refused it (smooth-mornings 02), not a traceback
        sys.exit(f"[morning] save refused: {' '.join(str(e).split())}")


def save_fingerprints(out):
    """After the write: the changed pages' new fingerprints, so tomorrow sees them unchanged.
    No file (a social check) has none."""
    path = out / "fingerprints.json"
    changed = json.loads(path.read_text()) if path.exists() else []
    if changed:
        Supabase().commit_fingerprints(changed)
        print(f"[morning] {sum(not c.get('first_seen') for c in changed)} changed pages' fingerprints saved")


def to_tag(today):
    """Approved Events no tagger has read or rated, or with no words saying what they are, still to
    come or still running, as the tagger reads them. `tagged`: read and rated before, so only its
    words are written."""
    rows = Supabase().rest("GET", "club_events?select=id,title,location,description,category,source_name,"
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


def untagged(out, today):
    tag_dir = out / "tag"
    if tag_dir.exists():
        shutil.rmtree(tag_dir)
    tag_dir.mkdir(parents=True)
    events, interests = to_tag(today), write_judged.interest_ids()
    for i in range(0, len(events), TAG_BATCH):
        (tag_dir / f"batch-{i // TAG_BATCH + 1}.txt").write_text(tag_message(events[i:i + TAG_BATCH], interests))
    (tag_dir / "events.json").write_text(json.dumps(events, indent=1, ensure_ascii=False))
    print(f"[morning] {len(events)} events to tag in {len(list(tag_dir.glob('batch-*.txt')))} batches ({tag_dir})")


def plan_tags(lines, events, known):
    """The cheap model's lines as writes: only Events it was given, only known interests, each
    once, in the model's order, and a draw of 1, 2 or 3. An Event it didn't answer stays untagged
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
        tags = list(dict.fromkeys(t for t in ln["interests"] if t in known))
        write = {"interests": tags}
        if ln.get("draw") in (1, 2, 3):
            write["draw"] = ln["draw"]
        if not given[ln["id"]].get("category") and tags:
            write["category"] = tags[0]
        if what:
            write["what"] = what
        writes[ln["id"]] = write
    return writes


def tag(out, dry_run, minutes=PART_MINUTES):
    events = json.loads((out / "tag" / "events.json").read_text())
    writes = plan_tags(read_items(out / "tags.jsonl"), events, write_judged.interest_ids())
    if not dry_run:
        stop, done_f = deadline(minutes), out / "tag" / "written.json"  # `untagged` clears it
        written = set(json.loads(done_f.read_text())) if done_f.exists() else set()
        db, now = Supabase(), datetime.now(LOCAL).isoformat()
        for event_id, write in writes.items():
            if event_id in written:
                continue
            if late(stop):
                return print(f"[morning] run again: {len(written)} of {len(writes)} events tagged")
            stamp = {} if set(write) == {"what"} else {"interests_tagged_at": now}
            db.rest("PATCH", f"club_events?id=eq.{event_id}", {**write, **stamp}, prefer="return=minimal")
            written.add(event_id)
            done_f.write_text(json.dumps(sorted(written)))  # each write kept, so a stopped part loses none
    empty = sum(1 for w in writes.values() if "interests" in w and not w["interests"])
    words = sum(1 for w in writes.values() if "what" in w)
    draws = {d: sum(1 for w in writes.values() if w.get("draw") == d) for d in (3, 2, 1)}
    print(f"[morning] tagged {len(writes)} events ({empty} with no interest; draw 3/2/1: "
          f"{draws[3]}/{draws[2]}/{draws[1]}), {words} with what they are in words, "
          f"{len(events) - len(writes)} left for tomorrow" + (" (dry run: nothing written)" if dry_run else ""))


def to_describe(today):
    """Approved upcoming Events found in the last two days and never laid out before, soonest
    first. Older ones were researched already (the 2026-10-24 backfill), and one laid out before
    was researched on its morning (described_at), so a thin one stays thin rather than being
    searched again every day (smooth-mornings 06)."""
    since = (today - timedelta(days=2)).isoformat()
    return to_research(Supabase().rest(
        "GET", "club_events?select=id,title,event_date,start_time,location,description,source_name,source_url,"
               "sport,category,clubs(name)&status=eq.approved&kind=eq.event"
               f"&event_date=gte.{today}&created_at=gte.{since}&described_at=is.null&order=event_date&limit=1000"))


def to_research(rows):
    """The rows whose About is empty or under a sentence, games left out (write_judged.is_game: a
    game's reader wrote its About from the schedule, and there is nothing more to find), as the
    helpers read them, at most DESCRIBE_MAX."""
    thin = [r for r in rows if len((r.get("description") or "").strip()) < THIN and not write_judged.is_game(r)]
    return [{"id": r["id"], "title": r["title"], "date": r["event_date"], "start": r.get("start_time") or "",
             "place": r.get("location") or "", "host": (r.get("clubs") or {}).get("name") or r.get("source_name") or "",
             "link": r.get("source_url") or "", "about": (r.get("description") or "").strip()}
            for r in thin[:DESCRIBE_MAX]]


def thin(out, today):
    d = out / "describe"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    events = to_describe(today)
    for i in range(0, len(events), DESCRIBE_BATCH):
        (d / f"batch-{i // DESCRIBE_BATCH + 1}.txt").write_text(
            "\n".join(json.dumps(e, ensure_ascii=False) for e in events[i:i + DESCRIBE_BATCH]) + "\n")
    (d / "events.json").write_text(json.dumps(events, indent=1, ensure_ascii=False))
    print(f"[morning] {len(events)} events to describe in {len(list(d.glob('batch-*.txt')))} batches ({d})")


def plan_descriptions(lines, events):
    """The helpers' lines as writes: only Events they were given, each once, an About that is
    text and longer than the one it has (a fuller About is never shortened). CHECK lines are
    kept for the answer, never written."""
    given, writes, checks = {e["id"]: e for e in events}, {}, []
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("id") not in given:
            continue
        e = given[ln["id"]]
        if isinstance(ln.get("check"), str) and ln["check"].strip():
            checks.append(f"{e['title']} ({e['date']}): {ln['check'].strip()}")
        about = " ".join(ln["about"].split()) if isinstance(ln.get("about"), str) else ""
        if len(about) > len(e["about"]) and ln["id"] not in writes:
            writes[ln["id"]] = write_judged.clip(about, ABOUT_MAX)
    return writes, checks


def describe(out, dry_run):
    events = json.loads((out / "describe" / "events.json").read_text())
    lines = read_items(out / "describe.jsonl")
    writes, checks = plan_descriptions(lines, events)
    # Every Event a helper answered, filled or not, is researched: thin never lays it out again. One
    # nobody answered waits for tomorrow's helpers.
    given = {e["id"] for e in events}
    answered = {ln["id"] for ln in lines if isinstance(ln, dict) and ln.get("id") in given}
    if not dry_run:
        db, now = Supabase(), datetime.now(LOCAL).isoformat()
        for event_id in sorted(answered):
            db.rest("PATCH", f"club_events?id=eq.{event_id}",
                    {"described_at": now, **({"description": writes[event_id]} if event_id in writes else {})},
                    prefer="return=minimal")
    print(f"[morning] described {len(writes)} of {len(events)} events given" + (" (dry run: nothing written)" if dry_run else ""))
    for c in checks:
        print(f"[check] {c}")


def todays_events(today):
    """Today's Events as the Town feed takes them (approved, posted by a neighbour or found by a
    source, not called off), with what the model weighs: interests, draw, Going and hearts. The
    feed's function itself reads private helpers the service key can't reach."""
    db = Supabase()
    rows = db.rest("GET", "club_events?select=id,title,start_time,all_day,location,source_name,description,"
                          "interests,interests_tagged_at,category,draw,clubs(name)"
                          f"&status=eq.approved&kind=eq.event&event_date=eq.{today}&cancelled_at=is.null"
                          "&or=(submitted_by.not.is.null,source_name.not.is.null)&order=start_time") or []
    if not rows:
        return []
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


def lay_out_today(out, today):
    out.mkdir(parents=True, exist_ok=True)
    events = todays_events(today)
    (out / "today.txt").write_text(f"Today: {today}\n\nEvents:\n"
                                   + "".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
    print(f"[morning] {len(events)} events today for the standouts ({out / 'today.txt'})")


def plan_standouts(lines, events, today):
    """The model's lines as today's daily_standouts rows: only Events it was given, each once, with
    a reason, best first (rank is the line's place), nine at most."""
    given, rows = {e["id"] for e in events}, []
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("id") not in given or any(r["event_id"] == ln["id"] for r in rows):
            continue
        why = " ".join(str(ln.get("why") or "").split())[:200]
        if why and len(rows) < STANDOUTS:
            rows.append({"town": TOWN, "day": str(today), "event_id": ln["id"], "rank": len(rows) + 1, "why": why})
    return rows


def standouts(out, dry_run, today):
    # today.txt's Event lines, as the model read them.
    events = [e for e in read_items(out / "today.txt") if isinstance(e, dict)]
    rows = plan_standouts(read_items(out / "standouts.jsonl"), events, today)
    # No usable line keeps whatever today has: with no rows Daily shows the Town feed's top pick.
    if rows and not dry_run:
        db = Supabase()
        db.rest("DELETE", f"daily_standouts?town=eq.{TOWN}&day=eq.{today}", prefer="return=minimal")
        db.rest("POST", "daily_standouts", rows, prefer="return=minimal")
    print(f"[morning] standouts: {len(rows)} of {len(events)} events today"
          + (" (dry run: nothing written)" if dry_run else "")
          + ("" if rows or not events else "; none written, so Daily shows the Town feed's top pick"))
    by_id = {e["id"]: e for e in events}
    for r in rows:
        e = by_id[r["event_id"]]
        print(f"[morning] #{r['rank']} {e['title']} ({e['start']}): {r['why']}")


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
    checks.append((summary_lines({**prep, "first_seen": 2}, result, None)[1].endswith(", 2 new kept as a starting copy"),
                   "the summary counts new pages kept as a starting copy"))
    checks.append(("- Source failed: x https://x: HTTP 403" in lines
                   and "- Reader failed: Stearns County (civicplus-hcms): TimeoutError" in lines, "the summary names what failed"))
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
    checks.append((writes == {"a": "Weekly Pilates at City Hall."} and found == ["Game (2026-10-27): Starts at 4, not 7."],
                   "Abouts are written once, only for given Events and only when longer; CHECK lines are kept"))
    checks += games_aside() + described_once()
    checks.append((fingerprints_wait_for_write(), "a page's new fingerprint moves only after its events are "
                   "written: a write that fails stops with one line naming what refused it and leaves it, so "
                   "prepare finds the same pages again; once written, it is saved even if the summary then breaks"))
    checks += in_parts()
    checks += set_aside_across_days()
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

    def apply(result):  # the database's half: what it already has is merged or a repeat, the rest added
        p = write_judged.payloads(result)
        answers.append({"events": len(p["p_events"]), "news": len(p["p_news"]), "mentions": 5, "published_by_mention": 0,
                        "cancelled": 0, "restored": 0,
                        "added": {"events": [i for i, e in enumerate(p["p_events"])
                                             if (e["source_name"], e["source_uid"]) not in held_events],
                                  "news": [i for i, n in enumerate(p["p_news"]) if n["title"].lower() not in held_news]}})
        return answers[-1]
    names = ("apply", "listed_in_db", "interest_ids", "known_teams", "news_in_db")
    saved = tuple(getattr(write_judged, n) for n in names)
    try:
        write_judged.apply, write_judged.listed_in_db, write_judged.interest_ids = apply, (lambda: listed), (lambda: ["bars"])
        write_judged.known_teams, write_judged.news_in_db = dict, (lambda today=None: [])
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            (out / "prepare.json").write_text(json.dumps({"today": "2026-10-20", "fetched": 9, "changed": 2,
                                                          "to_read": 2, "failed": [], "readers": []}))
            (out / "judged.jsonl").write_text("".join(json.dumps(it) + "\n" for it in items))
            printed = io.StringIO()
            with contextlib.redirect_stdout(printed):
                write(out, False, date(2026, 10, 20))
            lines = printed.getvalue().splitlines()
            result = write_judged.plan(items, listed, date(2026, 10, 20), ["bars"], teams={})
    finally:
        for n, f in zip(names, saved):
            setattr(write_judged, n, f)
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
            and "- News: 26 new, 0 repeats left out" in old and any("the save didn't say" in ln for ln in old))


def fingerprints_wait_for_write():
    """prepare's fetch and write's save against a fake database and fake sites, offline."""
    import io, tempfile, run as runner
    global Supabase, summary_lines

    class FakeDb(runner.Supabase):
        rows = {"milk|https://m/events": {"last_hash": "old", "last_checked_at": "2026-10-24"}}

        def __init__(self):
            pass

        def upsert_registry(self, rows):
            pass

        def state(self):
            return ({k: r.get("last_hash") for k, r in self.rows.items()},
                    {k for k, r in self.rows.items() if r.get("last_checked_at")},
                    {k: dict(r) for k, r in self.rows.items() if any(r.get(c) for c in runner.CLEAR)})

        def record(self, entry_id, url, fields):
            self.rows.setdefault(f"{entry_id}|{url}", {}).update(fields)

    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "sources": [{"url": u, "method": "fetch"}]} for i, u in [("milk", "https://m/events"), ("new", "https://n/")]]
    names = ("apply", "listed_in_db", "interest_ids", "known_teams", "news_in_db")
    saved = (runner.read_page, runner.validate, runner.find_root, Supabase, *(getattr(write_judged, n) for n in names))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            runner.read_page = lambda url, kind: (200, f"Plant Bingo Oct 24 at {url}", "fetch")
            runner.validate, runner.find_root, Supabase = (lambda e: []), (lambda *a: Path(tmp)), FakeDb
            write_judged.listed_in_db, write_judged.interest_ids, write_judged.known_teams = (lambda: []), (lambda: []), dict
            write_judged.news_in_db = lambda today=None: []
            out = Path(tmp) / "morning"
            out.mkdir()
            (out / "prepare.json").write_text(json.dumps({"today": "2026-10-25", "fetched": 2, "changed": 1,
                                                          "to_read": 1, "failed": [], "readers": []}))

            def prepare_fetch():
                with contextlib.redirect_stdout(io.StringIO()):
                    report = runner.fetch_watched(entries, FakeDb())
                (out / "fingerprints.json").write_text(json.dumps(report["changed"]))
                return sorted(c["entry_id"] for c in report["changed"] if not c["first_seen"])

            def write_with(apply):
                write_judged.apply = apply
                with contextlib.redirect_stdout(io.StringIO()):
                    write(out, False, date(2026, 10, 25))

            def boom(result):
                raise DbError("POST", "rpc/apply_judged", 403,
                              '{"code":"42501",\n"message":"permission denied for schema private"}')
            first = prepare_fetch()
            try:
                write_with(boom)
                refused = None
            except SystemExit as e:
                refused = e.code
            unmoved = FakeDb.rows["milk|https://m/events"]["last_hash"] == "old"
            starting_copy = FakeDb.rows["new|https://n/"].get("last_hash") is not None
            again = prepare_fetch()
            printing = summary_lines

            def breaks(*args):
                raise RuntimeError("the summary broke")
            summary_lines = breaks  # the write lands, then printing its summary breaks
            try:
                write_with(lambda result: {"events": 0})
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
        (runner.read_page, runner.validate, runner.find_root, Supabase,
         write_judged.apply, write_judged.listed_in_db, write_judged.interest_ids, write_judged.known_teams,
         write_judged.news_in_db) = saved


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


def described_once():
    """thin and describe across two mornings against a fake database: an Event the helpers answered
    (filled or not) is never laid out again, one they didn't answer is, and a game never is."""
    import io, tempfile
    global Supabase
    rows = [{"id": i, "title": t, "event_date": "2026-11-05", "start_time": "7 PM", "location": "Field", "description": d,
             "source_name": "Host", "source_url": "https://h", "sport": None, "category": c, "clubs": None,
             "described_at": None, "created_at": "2026-10-28"}
            for i, t, d, c in [("a", "Harvest Supper", "", "dining"), ("b", "Fix-It Clinic", "Bring it.", None),
                               ("c", "Kennedy Girls Basketball vs Holdingford", "", "watch_sports")]]

    class FakeDb:
        def rest(self, method, path, body=None, prefer=None):
            if method == "PATCH":
                next(r for r in rows if path == f"club_events?id=eq.{r['id']}").update(body)
                return None
            return [dict(r) for r in rows if "described_at=is.null" not in path or r["described_at"] is None]

    def morning(answers):
        with contextlib.redirect_stdout(io.StringIO()):
            thin(out, date(2026, 10, 29))
            given = [e["id"] for e in json.loads((out / "describe" / "events.json").read_text())]
            (out / "describe.jsonl").write_text("".join(json.dumps(a) + "\n" for a in answers if a["id"] in given))
            describe(out, False)
        return given
    saved = Supabase
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out, Supabase = Path(tmp), FakeDb
            first = morning([{"id": "a", "about": "", "check": ""}])  # b: no helper answered it
            second = morning([{"id": "b", "about": "Bring a broken lamp or toaster; volunteers fix it for free."}])
            third = morning([])
    finally:
        Supabase = saved
    return [(first == ["a", "b"] and second == ["b"] and third == [] and rows[1]["description"].startswith("Bring a broken")
             and rows[0]["described_at"] and not rows[2]["described_at"],
             "an Event laid out and answered is researched: the next morning lays out only the one nobody answered, "
             "and never the game")]


def in_parts():
    """prepare and tag in timed parts against fake slow sites (50 seconds a page) and a fake database,
    offline on a fake clock: one long morning, then the same morning in 2-minute parts."""
    import functools, io, tempfile, run as runner
    global Supabase, load, start_reader, fetch_watched
    clock = type("Clock", (), {"t": 1000.0, "monotonic": lambda self: self.t, "time": lambda self: self.t})()
    entries = [{"id": f"p{i}", "_name": f"Place {i}", "_town": "st-joseph-mn", "_extra": {}, "status": "active",
                "tier": "watched", "sources": [{"url": f"https://site{i}.example/events", "method": "fetch"}]} for i in range(7)]
    asked, starts = [], []

    class FakeDb(runner.Supabase):
        def __init__(self):
            pass

        def upsert_registry(self, rows):
            pass

        def state(self):
            return ({k: r.get("last_hash") for k, r in self.rows.items()},
                    {k for k, r in self.rows.items() if r.get("last_checked_at")},
                    {k: dict(r) for k, r in self.rows.items() if any(r.get(c) for c in runner.CLEAR)})

        def record(self, entry_id, url, fields):
            self.rows.setdefault(f"{entry_id}|{url}", {}).update(fields)

        def rest(self, method, path, body=None, prefer=None):
            if method == "PATCH":
                asked.append(path)
                clock.t += 50
            return []

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
        FakeDb.rows = {f"p{i}|https://site{i}.example/events": {"last_hash": "old", "last_checked_at": "2026-10-27"}
                       for i in range(6)}
        starts.clear()
        parts = []
        while len(parts) < 5 and (not parts or "run again" in parts[-1][1]):
            n, said = len(asked), io.StringIO()
            with contextlib.redirect_stdout(said):
                prepare(date(2026, 10, 28), out, minutes)
            parts.append((asked[n:], said.getvalue()))
        return parts, {f.name: f.read_text() for f in (out / "batches").iterdir()}, dict(FakeDb.rows)
    names = ("listed_in_db", "interest_ids")
    saved = (runner.read_page, runner.validate, runner.find_root, runner.time, Supabase, load, start_reader,
             fetch_watched, *(getattr(write_judged, n) for n in names))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "morning"
            runner.read_page, runner.validate, runner.find_root, runner.time = slow_site, (lambda e: []), (lambda *a: Path(tmp)), clock
            Supabase, load, start_reader = FakeDb, (lambda root: (entries, [])), reader
            fetch_watched = functools.partial(runner.fetch_watched, workers=1)  # one page at a time, as the clock counts
            write_judged.listed_in_db, write_judged.interest_ids = (lambda: []), (lambda: ["dining"])
            (one,), one_batches, _ = morning(None)
            parts, batches, rows = morning(2)
            fetched = [u for got, _ in parts for u in got]
            (out / "tag").mkdir()
            (out / "tag" / "events.json").write_text(json.dumps([{"id": f"e{i}", "category": None} for i in range(5)]))
            (out / "tags.jsonl").write_text("".join(json.dumps({"id": f"e{i}", "interests": ["dining"], "draw": 2}) + "\n"
                                                    for i in range(5)))
            tagged, n = [], len(asked)
            while len(tagged) < 3 and "[morning] tagged" not in "".join(tagged):
                said = io.StringIO()
                with contextlib.redirect_stdout(said):
                    tag(out, False, 2)
                tagged.append(said.getvalue())
            patched = asked[n:]
            (out / "tag" / "written.json").unlink(missing_ok=True)  # a new morning's tagging
            n, real = len(asked), FakeDb.rest

            def dies(self, method, path, body=None, prefer=None):
                if len(asked) - n == 2:
                    raise KeyboardInterrupt  # the cloud stops the command mid-way
                return real(self, method, path, body, prefer)
            FakeDb.rest = dies
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    tag(out, False, None)
            except KeyboardInterrupt:
                pass
            FakeDb.rest = real
            with contextlib.redirect_stdout(io.StringIO()):
                tag(out, False, None)
            stopped = asked[n:]
    finally:
        (runner.read_page, runner.validate, runner.find_root, runner.time, Supabase, load, start_reader,
         fetch_watched, write_judged.listed_in_db, write_judged.interest_ids) = saved
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
        (tagged[0] == "[morning] run again: 3 of 5 events tagged\n" and tagged[1].startswith("[morning] tagged 5 events")
         and sorted(patched) == [f"club_events?id=eq.e{i}" for i in range(5)], "tag in parts writes each Event once"),
        (sorted(stopped) == [f"club_events?id=eq.e{i}" for i in range(5)],
         "a tag run the cloud stops keeps what it wrote: the next run writes only the rest"),
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
    global Supabase, load, start_reader
    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "category": "gov" if i == "city" else None, "sources": [{"url": f"https://{i}.example/", "method": "fetch"}]}
               for i in ("dsl", "gone", "late", "city", "ok1", "ok2", "ok3", "ok4")]
    asked = []

    class FakeDb(runner.Supabase):
        rows = {"old|https://old.example/": {"last_error": "HTTP Error 500", "last_checked_at": "2026-10-14T16:00:00+00:00"}}

        def __init__(self):
            pass

        def upsert_registry(self, rows):
            pass

        def state(self):
            return ({k: r.get("last_hash") for k, r in self.rows.items()},
                    {k for k, r in self.rows.items() if r.get("last_checked_at")},
                    {k: dict(r) for k, r in self.rows.items() if any(r.get(c) for c in runner.CLEAR)})

        def record(self, entry_id, url, fields):
            self.rows.setdefault(f"{entry_id}|{url}", {}).update(fields)

        def rest(self, method, path, body=None, prefer=None):
            return []

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
    names = ("listed_in_db", "interest_ids", "known_teams", "news_in_db")
    saved = (runner.read_page, runner.validate, runner.find_root, runner.NOW, Supabase, load, start_reader,
             *(getattr(write_judged, n) for n in names))
    mornings, said, cleared = [20, 20, 22, 23, 24, 25, 26, 27], [], None
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "morning"
            runner.read_page, runner.validate, runner.find_root = site, (lambda e: []), (lambda *a: Path(tmp))
            Supabase, load, start_reader = FakeDb, (lambda root: (entries, [])), reader
            write_judged.listed_in_db, write_judged.interest_ids, write_judged.known_teams = (lambda: []), (lambda: []), dict
            write_judged.news_in_db = lambda today=None: []
            for d in mornings:
                runner.NOW, report = datetime(2026, 10, d, 11, tzinfo=timezone.utc), io.StringIO()
                with contextlib.redirect_stdout(io.StringIO()):
                    prepare(date(2026, 10, d), out, None)
                with contextlib.redirect_stdout(report):
                    write(out, True, date(2026, 10, d))
                said.append([ln for ln in report.getvalue().splitlines() if ln.startswith("- ") and any(
                    w in ln for w in (".example/", "aside", "Failed", "not counted"))])
                cleared = cleared if cleared is not None else dict(FakeDb.rows["old|https://old.example/"])
    finally:
        (runner.read_page, runner.validate, runner.find_root, runner.NOW, Supabase, load, start_reader,
         write_judged.listed_in_db, write_judged.interest_ids, write_judged.known_teams, write_judged.news_in_db) = saved
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

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["prepare", "titles", "write", "untagged", "tag", "thin", "describe", "today", "standouts"])
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--dry-run", action="store_true", help="write, tag, describe, standouts: print what would be written, write nothing")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.step:
        ap.error("prepare, titles, write, untagged, tag, thin, describe, today or standouts")
    today = date.fromisoformat(args.today) if args.today else datetime.now(LOCAL).date()
    out = find_root() / ".runs" / "morning"
    if args.step == "prepare":
        prepare(today, out)
    elif args.step == "titles":
        long_titles(out)
    elif args.step == "write":
        write(out, args.dry_run, today)
    elif args.step == "untagged":
        untagged(out, today)
    elif args.step == "thin":
        thin(out, today)
    elif args.step == "describe":
        describe(out, args.dry_run)
    elif args.step == "today":
        lay_out_today(out, today)
    elif args.step == "standouts":
        standouts(out, args.dry_run, today)
    else:
        tag(out, args.dry_run)


if __name__ == "__main__":
    main()
