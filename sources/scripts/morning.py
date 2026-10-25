#!/usr/bin/env python3
"""
morning.py: the parts of the morning job that need no model (BP app
docs/plans/watch-every-place, ticket 05). The routine's steps are sources/models/morning.md.

  prepare   fetch every watched page the polite way (run.fetch_watched; yesterday's
            fingerprints are in the database), read the feeds and data sources (read_events.py),
            and lay out only the changed pages in batches of 12 for the cheap model (batch.py), with
            the events already listed for the judge
  titles    list the event titles still over 40 characters once tidied (games aside) in
            .runs/morning/titles.txt, for the routine's model to shorten into titles.json
            (.claude/skills/title-and-place; Jesse, 2026-10-21)
  write     merge the feed items with the judge's items, give long titles their short ones
            (titles.json), write them (public.apply_judged over the service role key), then save
            the changed pages' new fingerprints (fingerprints.json) and print the morning's
            summary: a morning that stops before this reads the same pages again tomorrow
  untagged  lay out the Events no tagger has read yet (or that have no draw, or no words saying
            what they are), upcoming or still running, in batches of 40 for the cheap model
            (town-feed tickets 33 and 34, BP app event-card 05; sources/models/tag.md)
  tag       write the cheap model's tags (.runs/morning/tags.jsonl) onto those Events: only
            ids from the shared interest list, a draw of 1, 2 or 3, an Event's first interest
            becomes its category when it has none, and what it is in one to three words; an
            Event tagged before only gets its words, so nobody's feed reshuffles
  thin      lay out the upcoming Events found in the last two days whose About is empty or under a
            sentence (feed, game and catalog events skip the judge), at most 30 a morning, in batches of 10 for the
            routine's helpers to research (sources/models/describe.md; Jesse, 2026-10-24)
  describe  write the helpers' Abouts (.runs/morning/describe.jsonl) onto those Events, each
            only when longer than the one it has, and print their CHECK lines
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

import argparse, contextlib, json, shutil, subprocess, sys
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
from batch import layout
import write_judged
from run import Supabase, fetch_watched

SCRIPTS = Path(__file__).resolve().parent
TAG_BATCH = 40
TOWN = "st-joseph-mn"  # daily_standouts.town, as town_status names it
STANDOUTS = 9
THIN = 120        # characters: an About under this says less than a sentence
DESCRIBE_MAX = 30  # Events a morning; the rest wait for tomorrow
DESCRIBE_BATCH = 10
ABOUT_MAX = 1000   # as write_judged.clip
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


def snapshot_text(path):
    """run.py's snapshot without its frontmatter."""
    text = Path(path).read_text()
    return text.split("\n---\n", 1)[1].lstrip() if text.startswith("---\n") else text


def run(cmd, out_dir, name):
    r = subprocess.run([sys.executable, *cmd], capture_output=True, text=True, cwd=find_root())
    (out_dir / f"{name}.log").write_text(r.stdout + r.stderr)
    return r


def prepare(today, out):
    if out.exists():
        shutil.rmtree(out)
    (out / "batches").mkdir(parents=True)
    root = find_root()
    every, errors = load(root)
    if errors:
        sys.exit("[morning] registry invalid:\n" + "\n".join(errors))
    entries = [e for e in every if e.get("status") == "active"]

    # The league's site is slow and no other source's server (twelve minutes for the schools
    # on 2026-10-25, with its retries), so the schools are read while the pages are fetched.
    games_log = open(out / "games.log", "w")
    games = subprocess.Popen([sys.executable, str(SCRIPTS / "read_events.py"), "--reader", "mshsl", "--items",
                              str(out / "games.jsonl"), "--today", str(today)],
                             stdout=games_log, stderr=subprocess.STDOUT, text=True, cwd=find_root())
    db = Supabase()
    try:
        with open(out / "fetch.log", "w") as log, contextlib.redirect_stdout(log):
            report = fetch_watched(every, db)
    except BaseException:
        games.kill()
        raise
    run_dir = Path(report["run_dir"])
    # Saved by `write` once the events are in (db.commit_fingerprints), never here.
    (out / "fingerprints.json").write_text(json.dumps(
        [{k: c[k] for k in ("entry_id", "url", "hash", "first_seen")} for c in report["changed"]], indent=1))

    feeds = run([str(SCRIPTS / "read_events.py"), "--skip-reader", "mshsl", "--items", str(out / "feeds.jsonl"),
                 "--today", str(today)], out, "feeds")
    games.wait()
    games_log.close()
    games_out = (out / "games.log").read_text()
    readers = []
    for code, stdout, stderr, items in ((feeds.returncode, feeds.stdout, feeds.stderr, out / "feeds.jsonl"),
                                        (games.returncode, games_out, games_out, out / "games.jsonl")):
        readers += [ln for ln in stdout.splitlines() if ln.startswith("[read] ok") or ln.startswith("[read] FAILED")]
        if code:
            readers.append(f"[read] FAILED read_events.py itself: {stderr.strip()[-300:]}")
            items.write_text("")
    with open(out / "feeds.jsonl", "a") as f:
        f.write((out / "games.jsonl").read_text())

    pages = pages_to_read(report["changed"], entries)
    for p in pages:
        p["text"] = snapshot_text(run_dir / "snapshots" / p["snapshot"])
    for i, text in enumerate(layout(pages, today), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(text)
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in pages], indent=1))
    (out / "existing.json").write_text(json.dumps(write_judged.listed_in_db(), indent=1, default=str))

    summary = {"today": str(today), "fetched": report["fetched"], "changed": len(report["changed"]),
               "first_seen": sum(1 for c in report["changed"] if c.get("first_seen")),
               "to_read": len(pages), "batches": len(list((out / "batches").iterdir())),
               "failed": [f"{f['entry_id']} {f['url']}: {f['error']}" for f in report["failed"]],
               "readers": readers, "interests": write_judged.interest_ids()}
    (out / "prepare.json").write_text(json.dumps(summary, indent=1))
    print(f"[morning] fetched {summary['fetched']} watched pages, {summary['changed']} changed, "
          f"{summary['to_read']} for the cheap model in {summary['batches']} batches ({out / 'batches'})")
    for ln in readers:
        print(ln)
    for f in summary["failed"]:
        print(f"[morning] FAILED {f}")
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


def summary_lines(prep, items, result, written):
    count = {}
    for what, _ in result["outcomes"]:
        count[what] = count.get(what, 0) + 1
    held = [it["title"] for it, (what, _) in zip(items, result["outcomes"]) if what in ("held", "news held")]
    lines = [f"Social watch ({prep['run']}), {prep['today']}" if prep.get("run") else f"Morning watch, {prep['today']}",
             f"- Pages: {prep['fetched']} fetched, {prep['changed']} changed, {prep['to_read']} read by the cheap model"
             + (f", {prep['first_seen']} new kept as a starting copy" if prep.get("first_seen") else ""),
             f"- Events: {count.get('published', 0)} new, {count.get('merged', 0)} already listed, "
             f"{count.get('held', 0)} held for Jesse",
             f"- News: {count.get('news', 0)} kept, {count.get('news held', 0)} held for Jesse",
             f"- Skipped: {count.get('skipped', 0)} (past, outside the area or unreadable)"]
    lines += [f"- Held: {t}" for t in held]
    lines += [f"- Source failed: {f}" for f in prep["failed"]]
    lines += [f"- Reader failed: {r.split('FAILED', 1)[1].strip()}" for r in prep["readers"] if "FAILED" in r]
    lines.append(f"- Written: {json.dumps(written)}" if written is not None else "- Dry run: nothing written")
    return lines


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
    result = write_judged.plan(items, existing, today, write_judged.interest_ids(), titles=short_titles(out))
    write_judged.report(items, result)
    written = None if dry_run else write_judged.apply(result)
    print("\n".join(summary_lines(prep, items, result, written)))
    if not dry_run:
        save_fingerprints(out)


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
    rows = Supabase().call("GET", "club_events?select=id,title,location,description,category,source_name,"
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


def tag(out, dry_run):
    events = json.loads((out / "tag" / "events.json").read_text())
    writes = plan_tags(read_items(out / "tags.jsonl"), events, write_judged.interest_ids())
    if not dry_run:
        db, now = Supabase(), datetime.now(LOCAL).isoformat()
        for event_id, write in writes.items():
            stamp = {} if set(write) == {"what"} else {"interests_tagged_at": now}
            db.call("PATCH", f"club_events?id=eq.{event_id}", {**write, **stamp}, prefer="return=minimal")
    empty = sum(1 for w in writes.values() if "interests" in w and not w["interests"])
    words = sum(1 for w in writes.values() if "what" in w)
    draws = {d: sum(1 for w in writes.values() if w.get("draw") == d) for d in (3, 2, 1)}
    print(f"[morning] tagged {len(writes)} events ({empty} with no interest; draw 3/2/1: "
          f"{draws[3]}/{draws[2]}/{draws[1]}), {words} with what they are in words, "
          f"{len(events) - len(writes)} left for tomorrow" + (" (dry run: nothing written)" if dry_run else ""))


def to_describe(today):
    """Approved upcoming Events found in the last two days whose About is empty or under a
    sentence, soonest first. Older ones were researched already (the 2026-10-24 backfill, or an
    earlier morning), so a thin one stays thin rather than being searched again every day."""
    since = (today - timedelta(days=2)).isoformat()
    rows = Supabase().call("GET", "club_events?select=id,title,event_date,start_time,location,description,source_name,"
                                  "source_url,clubs(name)&status=eq.approved&kind=eq.event"
                           f"&event_date=gte.{today}&created_at=gte.{since}&order=event_date&limit=1000")
    thin = [r for r in rows if len((r.get("description") or "").strip()) < THIN]
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
    writes, checks = plan_descriptions(read_items(out / "describe.jsonl"), events)
    if not dry_run:
        db = Supabase()
        for event_id, about in writes.items():
            db.call("PATCH", f"club_events?id=eq.{event_id}", {"description": about}, prefer="return=minimal")
    print(f"[morning] described {len(writes)} of {len(events)} thin events" + (" (dry run: nothing written)" if dry_run else ""))
    for c in checks:
        print(f"[check] {c}")


def todays_events(today):
    """Today's Events as the Town feed takes them (approved, posted by a neighbour or found by a
    source, not called off), with what the model weighs: interests, draw, Going and hearts. The
    feed's function itself reads private helpers the service key can't reach."""
    db = Supabase()
    rows = db.call("GET", "club_events?select=id,title,start_time,all_day,location,source_name,description,"
                          "interests,interests_tagged_at,category,draw,clubs(name)"
                          f"&status=eq.approved&kind=eq.event&event_date=eq.{today}&cancelled_at=is.null"
                          "&or=(submitted_by.not.is.null,source_name.not.is.null)&order=start_time") or []
    if not rows:
        return []
    ids = ",".join(r["id"] for r in rows)
    count = lambda table: [x["event_id"] for x in db.call("GET", f"{table}?select=event_id&event_id=in.({ids})") or []]
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
        db.call("DELETE", f"daily_standouts?town=eq.{TOWN}&day=eq.{today}", prefer="return=minimal")
        db.call("POST", "daily_standouts", rows, prefer="return=minimal")
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
    result = {"outcomes": [("published", ""), ("held", "unsure"), ("news", ""), ("merged", "into x")]}
    items = [{"title": "Plant Bingo"}, {"title": "Maybe a sale"}, {"title": "Closed Monday"}, {"title": "Fare for All"}]
    lines = summary_lines(prep, items, result, {"events": 2})
    checks.append((summary_lines({**prep, "first_seen": 2}, items, result, None)[1].endswith(", 2 new kept as a starting copy"),
                   "the summary counts new pages kept as a starting copy"))
    checks.append((lines[2] == "- Events: 1 new, 1 already listed, 1 held for Jesse" and "- Held: Maybe a sale" in lines
                   and "- Source failed: x https://x: HTTP 403" in lines
                   and "- Reader failed: Stearns County (civicplus-hcms): TimeoutError" in lines, "the summary names what failed"))
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
    checks.append((fingerprints_wait_for_write(), "a page's new fingerprint moves only after its events are "
                   "written: a write that fails leaves it, so prepare finds the same pages again"))
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def fingerprints_wait_for_write():
    """prepare's fetch and write's save against a fake database and fake sites, offline."""
    import io, tempfile, run as runner
    global Supabase

    class FakeDb(runner.Supabase):
        rows = {"milk|https://m/events": {"last_hash": "old", "last_checked_at": "2026-10-24"}}

        def __init__(self):
            pass

        def upsert_registry(self, rows):
            pass

        def state(self):
            return ({k: r.get("last_hash") for k, r in self.rows.items()},
                    {k for k, r in self.rows.items() if r.get("last_checked_at")})

        def record(self, entry_id, url, fields):
            self.rows.setdefault(f"{entry_id}|{url}", {}).update(fields)

    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "sources": [{"url": u, "method": "fetch"}]} for i, u in [("milk", "https://m/events"), ("new", "https://n/")]]
    names = ("apply", "listed_in_db", "interest_ids")
    saved = (runner.read_page, runner.validate, runner.find_root, Supabase, *(getattr(write_judged, n) for n in names))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            runner.read_page = lambda url, kind: (200, f"Plant Bingo Oct 24 at {url}", "fetch")
            runner.validate, runner.find_root, Supabase = (lambda e: []), (lambda *a: Path(tmp)), FakeDb
            write_judged.listed_in_db, write_judged.interest_ids = (lambda: []), (lambda: [])
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
                raise RuntimeError("apply_judged failed")
            first = prepare_fetch()
            try:
                write_with(boom)
            except RuntimeError:
                pass
            unmoved = FakeDb.rows["milk|https://m/events"]["last_hash"] == "old"
            starting_copy = FakeDb.rows["new|https://n/"].get("last_hash") is not None
            again = prepare_fetch()
            write_with(lambda result: {"events": 0})
            return first == again == ["milk"] and unmoved and starting_copy and prepare_fetch() == []
    finally:
        (runner.read_page, runner.validate, runner.find_root, Supabase,
         write_judged.apply, write_judged.listed_in_db, write_judged.interest_ids) = saved


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
