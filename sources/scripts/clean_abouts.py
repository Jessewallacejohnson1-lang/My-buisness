#!/usr/bin/env python3
"""
clean_abouts.py: the one-off cleaning of every upcoming Event's About, with its undo (BP app
docs/plans/inside-cards/issues/14-about-says-what-to-expect.md; Jesse, 2026-11-06: "i only want what its about
what to expect take out price time date place fron discription those all get there own section"). The rule is
sources/models/clean_about.md; the morning's About writers follow the same rule from here on (describe.md).

  --dry-run [--out DIR] [--model M]
      Read every approved upcoming non-game Event with an About from the live database (read-only, through
      Composio's SQL tool: no key on this Mac), ask the model for each one's About without its price, time, date
      and place (batches of 10 through `claude -p` on this Mac: Jesse's plan, no API key), and write
      DIR/14-dry-run.md (each Event's before and after, the counts, and the ticket's word search before and after)
      and DIR/14-before.json (every row as the dry run read it). The answers wait
      in DIR/14-answers.jsonl for --write, and a run again asks only for the Events not answered yet. Nothing is
      written to the database.
  --write [--out DIR]
      After Jesse's yes, and after the price migration (20261108194138_price_field.sql) is live (the reads select
      its columns): save DIR/14-undo.json (each row to be written as it is right then, its price included), then
      PATCH the answers onto the live rows (description, price, and end_at when the Event had none). Refuses when
      14-undo.json is there: a second write would save the cleaned words as the undo. Needs SUPABASE_URL and a key
      in the environment (db.py): `python3 ~/.claude/scripts/svc_env.py python3 sources/scripts/clean_abouts.py --write`.
  --undo [--out DIR]
      PATCH DIR/14-undo.json back, the same way.
  --selftest

DIR defaults to .runs/clean-abouts/ at the repo root.
"""
import argparse, json, re, sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
import write_judged
from check_flags import ask
from composio import execute

REF = "lxdgwhvqjqmqliobwjpi"  # Block Party's project (docs/rules/identifiers.md)
ROOT = Path(__file__).resolve().parents[2]
RULE = ROOT / "sources" / "models" / "clean_about.md"
BATCH = 10
HELPERS = 3
PRICE_MAX = 60    # as morning.PRICE_MAX
ABOUT_MAX = 1000  # as write_judged.clip
LOCAL = ZoneInfo("America/Chicago")
ROWS = """select id, title, event_date, start_time, end_at, location, description, price, described_at, about_written_at,
  source_name, category
from public.club_events
where status = 'approved' and kind = 'event' and cancelled_at is null
  and event_date >= (now() at time zone 'America/Chicago')::date
  and nullif(btrim(description), '') is not null
  and sport is null and coalesce(cardinality(team_ids), 0) = 0
order by event_date, start_time, title"""
# The ticket's word search, an estimate: "free" can be a false match, and a place named differently is missed.
SEARCH = {
    "price": re.compile(r"\$\s?\d|\bfree\b|\badmission\b|\btickets?\b|\bcosts?\b|\bdonation\b", re.I),
    "time": re.compile(r"\b\d{1,2}(:\d{2})?\s?(a\.?m\.?|p\.?m\.?)(?![a-z])|\bnoon\b|\bmidnight\b", re.I),
    "date": re.compile(r"\b(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day\b|"
                       r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.? \d{1,2}\b", re.I),
}
CLOCK = re.compile(r"^\s*(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s*m\.?\s*$", re.I)


def tidy(text):
    return " ".join((text or "").split())


def hits(about, location=None):
    """The ticket's word search on one About: which of price, time, date and place it names."""
    found = {k: m.group(0) for k, rx in SEARCH.items() if (m := rx.search(about))}
    first = (location or "").split(",")[0].strip()
    if len(first) > 3 and first.lower() in about.lower():
        found["place"] = first
    return found


def clock(words):
    """A time the app writes ("7 PM", "7:30 pm") as (hour, minute), or None."""
    m = CLOCK.match(words or "")
    if not m:
        return None
    return int(m[1]) % 12 + (12 if m[3].lower() == "p" else 0), int(m[2] or 0)


def end_at(row, end):
    """The end time the words gave, as the row's end_at: that day in Chicago time, the next day when it is at or
    before the start ("1 AM" after a 9 PM start). None when the row has an end or the words gave none we can read."""
    at = clock(end)
    if row.get("end_at") or at is None:
        return None
    day = date.fromisoformat(row["event_date"])
    when = datetime(day.year, day.month, day.day, *at, tzinfo=LOCAL)
    start = clock(row.get("start_time"))
    if start and at <= start:
        when += timedelta(days=1)
    return when.isoformat()


def own_hits(row, about):
    """The ticket's hits in `about` that name the Event's own fields: its weekday or date, its start or end, its place.
    A date that isn't its own (a series' last day), a time that isn't (a second service), a prize's dollars stay."""
    found, own = hits(about, row.get("location")), {}
    day = date.fromisoformat(row["event_date"])
    if "date" in found:
        words = found["date"].lower().rstrip(".")
        forms = {day.strftime("%A").lower()} | {f"{m} {day.day}" for m in (day.strftime("%b").lower(), day.strftime("%B").lower())}
        if words in forms or words.replace(".", "") in forms:
            own["date"] = found["date"]
    if "time" in found:
        ends = row.get("end_at") and datetime.fromisoformat(row["end_at"].replace("Z", "+00:00")).astimezone(LOCAL)
        at = clock(found["time"])
        if at and at in {clock(row.get("start_time")), ends and (ends.hour, ends.minute)}:
            own["time"] = found["time"]
    if "place" in found:
        own["place"] = found["place"]
    return own


def lines_of(rows, notes=None):
    """The batch lines the model reads (clean_about.md), one Event each."""
    def end_words(row):
        if not row.get("end_at"):
            return ""
        at = datetime.fromisoformat(row["end_at"].replace("Z", "+00:00")).astimezone(LOCAL)
        return at.strftime("%-I:%M %p").replace(":00 ", " ")
    return [json.dumps({"id": r["id"], "title": r["title"], "date": r["event_date"], "start": r.get("start_time") or "",
                        "end": end_words(r), "place": r.get("location") or "", "about": tidy(r["description"]),
                        **({"note": notes[r["id"]]} if notes and r["id"] in notes else {})},
                       ensure_ascii=False) for r in rows]


def answers_in(text, given):
    """The model's lines as answers, only for Events it was given."""
    out = []
    for ln in text.splitlines():
        ln = ln.strip().strip(",")
        if ln.startswith("{"):
            try:
                a = json.loads(ln)
            except ValueError:
                continue
            if isinstance(a, dict) and a.get("id") in given:
                out.append(a)
    return out


def plan(rows, answers):
    """Each answered Event's change: the About after (tidied, clipped), its price, the end_at it gains, and whether
    anything differs from the row. An Event the model didn't answer is left as it is."""
    said = {}
    for a in answers:  # the last About for an Event wins (a second pass), with the price and end an earlier pass found
        prev = said.get(a["id"], {})
        said[a["id"]] = {**a, "price": a.get("price") or prev.get("price") or "", "end": a.get("end") or prev.get("end") or ""}
    out = []
    for r in rows:
        a = said.get(r["id"])
        if not a:
            continue
        before = tidy(r["description"])
        after = write_judged.clip(tidy(a.get("about")) if isinstance(a.get("about"), str) else before, ABOUT_MAX)
        price = write_judged.clip(tidy(a.get("price")) if isinstance(a.get("price"), str) else "", PRICE_MAX)
        ends = end_at(r, a.get("end") if isinstance(a.get("end"), str) else "")
        out.append({"id": r["id"], "title": r["title"], "event_date": r["event_date"], "location": r.get("location") or "",
                    "described_at": r.get("described_at"),
                    "before": before, "after": after, "price": price, "end": tidy(a.get("end")) if ends else "",
                    "end_at": ends, "changed": after != before or bool(price) or bool(ends)})
    return out


def patch_body(change):
    """The columns to save. A cleaned About is marked written (about_written_at), so a re-read of its listing never
    writes the old words back over it (apply_judged, this ticket's migration), and researched (described_at, when it
    wasn't), so the morning doesn't lay it out again."""
    body = {"description": change["after"] or None}
    if change["after"] != change["before"]:
        now = datetime.now(LOCAL).isoformat()
        body["about_written_at"] = now
        if not change.get("described_at"):
            body["described_at"] = now
    if change["price"]:
        body["price"] = change["price"]
    if change["end_at"]:
        body["end_at"] = change["end_at"]
    return body


UNDONE = ("description", "price", "end_at", "described_at", "about_written_at")


def kept(rows, ids):
    """The undo: each of `ids`' rows as the database has it now, every column a write may change."""
    return {r["id"]: {k: r.get(k) for k in UNDONE} for r in rows if r["id"] in ids}


def report(rows, changes, today):
    """The dry run's page for Jesse: the counts, the word search before and after, the remaining hits, every Event."""
    by = {c["id"]: c for c in changes}
    cell = lambda t: (t or "").replace("|", "\\|").replace("\n", " ") or "—"
    before_hits = [hits(tidy(r["description"]), r.get("location")) for r in rows]
    after_hits = [hits(by[r["id"]]["after"], r.get("location")) if r["id"] in by else h for r, h in zip(rows, before_hits)]
    count = lambda found, k: sum(1 for h in found if k in h)
    changed = [c for c in changes if c["changed"]]
    out = [f"# 14: the About cleaning, dry run of {today}", "",
           f"{len(rows)} approved upcoming non-game Events with an About, read live. {len(changes)} answered by the model, "
           f"{len(changed)} would change: {sum(1 for c in changed if c['after'] != c['before'])} Abouts rewritten "
           f"({sum(1 for c in changed if not c['after'])} left empty, the page then shows its lines alone), "
           f"{sum(1 for c in changed if c['price'])} prices found, {sum(1 for c in changed if c['end_at'])} end times moved onto "
           f"the Event. Nothing written: `--write` after Jesse's yes, `--undo` from the 14-undo.json the write saves.", "",
           "The ticket's word search, before and after (an estimate: \"free\" can be a false match, a place named differently is missed):", "",
           "| Names a… | Before | After |", "|---|---|---|"]
    out += [f"| {k} | {count(before_hits, k)} | {count(after_hits, k)} |" for k in ("price", "time", "date", "place")]
    out += [f"| any | {sum(1 for h in before_hits if h)} | {sum(1 for h in after_hits if h)} |", "", "## Hits left after", ""]
    left = [(r, h) for r, h in zip(rows, after_hits) if h]
    out += [f"- {r['title']} ({r['event_date']}): " + ", ".join(f"{k} \"{v}\"" for k, v in h.items()) for r, h in left] or ["- none"]
    out += ["", "## Every Event", "", "| Event | Before | After | Price | End |", "|---|---|---|---|---|"]
    for r in rows:
        c = by.get(r["id"])
        after = c["after"] if c else "(not answered)"
        out.append(f"| {cell(r['title'])}<br>{r['event_date']} | {cell(tidy(r['description']))} | "
                   f"{'(unchanged)' if c and not c['changed'] else cell(after)} | {cell(c['price'] if c else '')} | "
                   f"{cell(c['end'] if c else '')} |")
    return "\n".join(out) + "\n"


def read_rows():
    return execute("SUPABASE_BETA_RUN_SQL_QUERY", {"ref": REF, "query": ROWS, "read_only": True}, 120)["result"]


def not_game(rows):
    return [r for r in rows if not write_judged.is_game({**r, "sport": None})]


def dry_run(out, model):
    out.mkdir(parents=True, exist_ok=True)
    rows = not_game(read_rows())
    before, answers_file = out / "14-before.json", out / "14-answers.jsonl"
    if not before.exists():  # the rows as they were before the first run, never overwritten
        before.write_text(json.dumps([{"id": i, **r} for i, r in kept(rows, {r["id"] for r in rows}).items()],
                                     indent=1, ensure_ascii=False))
    given = {r["id"] for r in rows}
    answers = answers_in(answers_file.read_text(), given) if answers_file.exists() else []
    todo = [r for r in rows if r["id"] not in {a["id"] for a in answers}]
    print(f"[clean] {len(rows)} Events with an About, {len(answers)} answered before, {len(todo)} to ask in batches of {BATCH}")
    rule, batches, notes = RULE.read_text(), [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)], {}

    def one(batch):
        text, usage = ask(model, rule, "\n".join(lines_of(batch, notes)) + "\n")
        got = answers_in(text, {r["id"] for r in batch})
        with answers_file.open("a") as f:
            f.write("".join(json.dumps(a, ensure_ascii=False) + "\n" for a in got))
        print(f"[clean] batch of {len(batch)}: {len(got)} answered ({usage.get('output_tokens', '?')} tokens out)")
        return got
    with ThreadPoolExecutor(HELPERS) as pool:
        for got in pool.map(one, batches):
            answers += got
    changes = plan(rows, answers)
    # A second pass for the Abouts that still name the Event's own day, time or place, each told what it still says.
    notes = {c["id"]: "The About still names the Event's own " + " and ".join(f'{k} "{v}"' for k, v in o.items()) + ": take it out."
             for c in changes if (o := own_hits({**next(r for r in rows if r["id"] == c["id"]), "description": c["after"]}, c["after"]))}
    again = [{**r, "description": next(c["after"] for c in changes if c["id"] == r["id"])} for r in rows if r["id"] in notes]
    if again and not (out / "14-second-pass").exists():
        print(f"[clean] second pass: {len(again)} Abouts still name the Event's own fields")
        with ThreadPoolExecutor(HELPERS) as pool:
            for got in pool.map(one, [again[i:i + BATCH] for i in range(0, len(again), BATCH)]):
                answers += got
        (out / "14-second-pass").write_text("\n".join(sorted(notes)) + "\n")
        changes = plan(rows, answers)
    (out / "14-dry-run.md").write_text(report(rows, changes, date.today().isoformat()))
    print(f"[clean] {len(rows)} Events, {len(changes)} answered, {sum(c['changed'] for c in changes)} would change, "
          f"{sum(1 for c in changes if c['price'])} prices found: {out / '14-dry-run.md'}")


def write(out):
    from db import Db
    db = Db()
    rows = not_game(read_rows())
    answers = answers_in((out / "14-answers.jsonl").read_text(), {r["id"] for r in rows})
    changes = [c for c in plan(rows, answers) if c["changed"]]
    undo_file = out / "14-undo.json"
    if undo_file.exists():
        sys.exit(f"{undo_file} is already here: a write ran before. Undo it first, or move it away on purpose.")
    undo_file.write_text(json.dumps(kept(rows, {c["id"] for c in changes}), indent=1, ensure_ascii=False))
    for c in changes:
        db.rest("PATCH", f"club_events?id=eq.{c['id']}", patch_body(c), prefer="return=minimal")
    print(f"[clean] wrote {len(changes)} of {len(rows)} Events")


def undo(out):
    from db import Db
    db = Db()
    saved = json.loads((out / "14-undo.json").read_text())
    for event_id, old in saved.items():
        db.rest("PATCH", f"club_events?id=eq.{event_id}", old, prefer="return=minimal")
    print(f"[clean] put back {len(saved)} Events")


def selftest():
    rows = [{"id": "a", "title": "Music Bingo", "event_date": "2026-11-20", "start_time": "7 PM", "end_at": None,
             "location": "Bad Habit Brewing, St. Joseph",
             "description": "Music bingo at Bad Habit Brewing, Friday Nov 20 from 7 to 9 PM. Free to play; all you need is a phone."},
            {"id": "b", "title": "Trail cleanup", "event_date": "2026-11-21", "start_time": "9 AM",
             "end_at": "2026-11-21T17:00:00+00:00", "location": "Trailhead", "description": "Gloves and bags provided. $5."},
            {"id": "c", "title": "Late show", "event_date": "2026-11-21", "start_time": "9 PM", "end_at": None,
             "location": None, "description": "Runs until 1 AM."},
            {"id": "g", "title": "Sartell Hockey vs Rocori", "event_date": "2026-11-22", "start_time": "7 PM",
             "end_at": None, "location": "Arena", "description": "x", "category": "watch_sports"}]
    text = ('{"id": "a", "about": "Music bingo in the taproom. All you need is a phone.", "price": " Free ", "end": "9 PM"}\n'
            '{"id": "b", "about": "Gloves and bags provided.", "price": "$5", "end": "5 PM"},\n'
            '{"id": "c", "about": "", "price": "", "end": "1 AM"}\n{"id": "zz", "about": "not given"}\n')
    answers = answers_in(text, {"a", "b", "c"})
    changes = plan(rows[:3], answers)
    a, b, c = changes
    before = [hits(tidy(r["description"]), r["location"]) for r in rows[:3]]
    rep = report(rows[:3], changes, "2026-11-08")
    checks = [
        ([x["id"] for x in answers] == ["a", "b", "c"], "the model's JSON lines are read, a trailing comma allowed, for given Events only"),
        (a["after"] == "Music bingo in the taproom. All you need is a phone." and a["price"] == "Free"
         and a["end_at"] == "2026-11-20T21:00:00-06:00" and a["changed"], "a cleaned About, its price tidied, and the end the Event lacked that day"),
        (b["after"] == "Gloves and bags provided." and b["price"] == "$5" and b["end_at"] is None and not b["end"],
         "an Event with an end keeps it: the words' end isn't written over it"),
        (c["after"] == "" and c["end_at"] == "2026-11-22T01:00:00-06:00" and c["changed"],
         "everything gone leaves the About empty; an end at or before the start is the next day"),
        ({k: v for k, v in patch_body(a).items() if k not in ("described_at", "about_written_at")}
         == {"description": a["after"], "price": "Free", "end_at": "2026-11-20T21:00:00-06:00"}
         and "described_at" in patch_body(a) and "described_at" in patch_body(c) and patch_body(c)["description"] is None
         and "described_at" not in patch_body(plan([{**rows[1], "described_at": "2026-11-01T12:00:00+00:00"}], answers)[0]),
         "the PATCH writes the About (null when empty), the price, the end, and described_at once, so it isn't researched again"),
        ("about_written_at" in patch_body(a) and "about_written_at" in patch_body(c)
         and "about_written_at" in patch_body(plan([{**rows[1], "described_at": "2026-11-01T12:00:00+00:00"}], answers)[0])
         and "about_written_at" not in patch_body({**a, "after": a["before"]}),
         "a rewritten About is marked written, researched before or not, so a re-read never puts the old words back"),
        (plan(rows[:1], [{"id": "a", "about": tidy(rows[0]["description"]), "price": "", "end": ""}])[0]["changed"] is False,
         "an About given back as it was is no change"),
        (sorted(before[0]) == ["date", "place", "price", "time"] and before[1] == {"price": "$5"} and list(before[2]) == ["time"],
         f"the ticket's word search names price, time, date and place: {before}"),
        (hits(a["after"], rows[0]["location"]) == {}, "and finds nothing in the cleaned About"),
        (not_game(rows) == rows[:3], "a game is left out"),
        (own_hits({**rows[0], "end_at": None}, "Music bingo Friday Nov 20 at Bad Habit Brewing from 7 PM; doors at 6.")
         == {"date": "Friday", "time": "7 PM", "place": "Bad Habit Brewing"}
         and own_hits(rows[0], "Bingo in the taproom through Dec 18, Tuesdays too; $500 prize.") == {},
         "a second pass is asked only for an About still naming the Event's own day, date, start or end, or place"),
        (plan(rows[:1], [{"id": "a", "about": "First.", "price": "Free", "end": "9 PM"}, {"id": "a", "about": "Second.", "price": ""}])[0]
         == {**a, "after": "Second."},
         "the last About for an Event wins (a second pass), and the price and end found before stay with it"),
        ("| price | 2 | 0 |" in rep and "| any | 3 | 0 |" in rep and "3 would change" in rep and "2 prices found" in rep
         and "2 end times moved" in rep and "Music bingo in the taproom" in rep and "(1 left empty" in rep,
         "the page counts the hits before and after, the changes, the prices and the ends"),
        ("price" in ROWS.split("from")[0] and "about_written_at" in ROWS.split("from")[0]
         and kept([{**rows[1], "price": "$10", "described_at": None, "about_written_at": None}], {"b"})
         == {"b": {"description": "Gloves and bags provided. $5.", "price": "$10", "end_at": "2026-11-21T17:00:00+00:00",
                   "described_at": None, "about_written_at": None}}
         and kept(rows, {"a"}).keys() == {"a"},
         "the undo keeps each written row's price as the database has it, not null over a price set since"),
        (lines_of(rows[1:2])[0] == '{"id": "b", "title": "Trail cleanup", "date": "2026-11-21", "start": "9 AM", "end": "11 AM", '
                                   '"place": "Trailhead", "about": "Gloves and bags provided. $5."}',
         f"a batch line says the Event's end in Chicago time: {lines_of(rows[1:2])[0]}"),
    ]
    for ok, what in checks:
        print(("ok   " if ok else "FAIL ") + what)
    failed = sum(1 for ok, _ in checks if not ok)
    print(f"{len(checks) - failed} passed, {failed} failed")
    return failed


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--undo", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--out", default=str(ROOT / ".runs" / "clean-abouts"))
    ap.add_argument("--model", default="sonnet", help="the model the morning's About writers run on (default sonnet)")
    args = ap.parse_args(argv)
    out = Path(args.out)
    if args.selftest:
        return 1 if selftest() else 0
    if args.dry_run:
        dry_run(out, args.model)
    elif args.write:
        write(out)
    elif args.undo:
        undo(out)
    else:
        ap.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
