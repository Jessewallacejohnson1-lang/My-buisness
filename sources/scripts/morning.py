#!/usr/bin/env python3
"""
morning.py: the parts of the morning job that need no model (BP app
docs/plans/watch-every-place, ticket 05). The routine's steps are sources/models/morning.md.

  prepare   fetch every watched page the polite way (run.py --write keeps yesterday's
            fingerprints in the database), read the feeds and data sources (read_events.py),
            and lay out only the changed pages in batches of 12 for the cheap model, with
            the events already listed for the judge
  write     merge the feed items with the judge's items, write them (public.apply_judged
            over the service role key) and print the morning's summary

Everything lands in .runs/morning/. Both steps need SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY in the environment; `write --dry-run` writes nothing.

  python3 sources/scripts/morning.py prepare [--today YYYY-MM-DD]
  python3 sources/scripts/morning.py write [--dry-run]
  python3 sources/scripts/morning.py --selftest
"""

import argparse, json, re, shutil, subprocess, sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
from check_flags import batches, message
import write_judged

SCRIPTS = Path(__file__).resolve().parent
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
    entries = [e for e in load(root)[0] if e.get("status") == "active"]

    fetched = run([str(SCRIPTS / "run.py"), "--write", "--tier", "watched"], out, "fetch")
    report_path = re.search(r"^report: (.+)$", fetched.stdout, re.M)
    if fetched.returncode or not report_path:
        sys.exit(f"[morning] fetching failed:\n{(fetched.stdout + fetched.stderr)[-1500:]}")
    report = json.loads(Path(report_path.group(1)).read_text())
    run_dir = Path(report["run_dir"])

    feeds = run([str(SCRIPTS / "read_events.py"), "--items", str(out / "feeds.jsonl"), "--today", str(today)], out, "feeds")
    readers = [ln for ln in feeds.stdout.splitlines() if ln.startswith("[read] ok") or ln.startswith("[read] FAILED")]
    if feeds.returncode:
        readers.append(f"[read] FAILED read_events.py itself: {feeds.stderr.strip()[-300:]}")
        (out / "feeds.jsonl").write_text("")

    pages = pages_to_read(report["changed"], entries)
    for p in pages:
        p["text"] = snapshot_text(run_dir / "snapshots" / p["snapshot"])
    for i, b in enumerate(batches(pages), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(message(b, today))
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
    lines = [f"Morning watch, {prep['today']}",
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


def write(out, dry_run, today):
    prep = json.loads((out / "prepare.json").read_text())
    feeds, judged = read_items(out / "feeds.jsonl"), read_items(out / "judged.jsonl")
    items = feeds + judged
    existing = write_judged.listed_in_db()
    result = write_judged.plan(items, existing, today, write_judged.interest_ids())
    write_judged.report(items, result)
    written = None if dry_run else write_judged.apply(result)
    print("\n".join(summary_lines(prep, items, result, written)))


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
    from run import fingerprint
    checks.append((fingerprint("Trivia Oct 24 7:00 PM\nPage generated at 10/16/2026, 3:45:35 AM")
                   == fingerprint("Trivia Oct 24 7:00 PM\nPage generated at 10/17/2026, 3:48:48 AM")
                   and fingerprint("Wed, 14 Oct 2026 11:47:19 -0600\nFish fry") == fingerprint("Thu, 15 Oct 2026 06:01:02 -0600\nFish fry")
                   and fingerprint("Trivia Oct 24 7:00 PM") != fingerprint("Trivia Oct 24 8:00 PM"),
                   "a page's own clock doesn't change its fingerprint; an event's time does"))
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["prepare", "write"])
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--dry-run", action="store_true", help="write: print what would be written, write nothing")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.step:
        ap.error("prepare or write")
    today = date.fromisoformat(args.today) if args.today else datetime.now(LOCAL).date()
    out = find_root() / ".runs" / "morning"
    prepare(today, out) if args.step == "prepare" else write(out, args.dry_run, today)


if __name__ == "__main__":
    main()
