#!/usr/bin/env python3
"""
apple_maps.py: Apple Maps says which app places closed for good, and they come off the app.

    python3 sources/scripts/apple_maps.py check [--write]     # morning.py finish runs it, writing
    python3 sources/scripts/apple_maps.py match places.json   # a Mac: Apple ids as migration lines
    python3 sources/scripts/apple_maps.py --selftest

Jesse, 2026-11-01: "use Apple Maps, Apple Maps is correct". Bello Cucina said goodbye on its own
Facebook on Oct 24; a week later Apple Maps had it Permanently Closed and Google still listed its
hours. Each app place keeps its Apple Maps place id (`places.apple_place_id`). Its public page,
https://maps.apple.com/place?place-id=<id> (robots.txt allows exactly that), carries
`"isPermanentlyClosed":true` once Apple knows. Then `check --write` sets `places.closed_at`, which
takes the place off Search and the map (the app reads only places whose `closed_at` is empty), and
cancels its upcoming Events. A place that moved out of town reads the same way.

More than MAX_AT_ONCE closings in one morning hides none and lists them: a page change on Apple's
side, not a wave of closings. Undo a hide in a migration that empties `closed_at` and
`apple_place_id` together, so the next morning doesn't hide it again.

`match` runs apple_match.swift (MapKit, so a Mac) on places exported as
[{id, entry_id, name, address, lat, lon}] and prints `update` lines for a migration: a new app place
gets its Apple id when it is added, else the morning report counts it as unmatched.
"""
import argparse, json, subprocess, sys
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import quote

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

PAGE = "https://maps.apple.com/place?place-id={}"
CLOSED = '"isPermanentlyClosed":true'
PLACE_PAGE = '"entity":'       # every place page has it; a page without it was not read right
MAX_AT_ONCE = 3                # ponytail: a fixed cap, not a share of the town; raise it with the town count


def read(apple_id, get):
    """'closed', 'open', or why the page could not be read."""
    try:
        status, body = get(PAGE.format(quote(apple_id)))
    except Exception as e:
        return f"unreadable: {' '.join(str(e).split())[:100]}"
    if status != 200 or PLACE_PAGE not in body:
        return f"unreadable: HTTP {status}, {len(body)} characters"
    return "closed" if CLOSED in body else "open"


def check(db, write, today, get=None):
    """Read every open app place's Apple Maps page; hide the ones Apple calls closed. The report's lines."""
    if get is None:
        from run import fetch as get
    rows = db.rest("GET", "places?select=id,entry_id,name,apple_place_id&closed_at=is.null&order=name") or []
    checked = [r for r in rows if r.get("apple_place_id")]
    found = {r["id"]: read(r["apple_place_id"], get) for r in checked}
    closed = [r for r in checked if found[r["id"]] == "closed"]
    bad = [f"{r['name']} ({found[r['id']]})" for r in checked if found[r["id"]].startswith("unreadable")]
    lines = [f"- Apple Maps: {len(checked) - len(bad)} places checked, {len(closed)} closed for good, "
             f"{len(rows) - len(checked)} with no Apple Maps place"]
    lines += [f"  - unreadable: {', '.join(bad[:10])}" + (f" and {len(bad) - 10} more" if len(bad) > 10 else "")] * bool(bad)
    if len(closed) > MAX_AT_ONCE:
        return lines + [f"  - {len(closed)} read as closed at once, so none hidden; check by hand: "
                        + ", ".join(r["name"] for r in closed)]
    still_open = {r["entry_id"] for r in rows if r not in closed}
    now = datetime.now(timezone.utc).isoformat()
    for r in closed:
        cancelled = []
        if write:
            db.rest("PATCH", f"places?id=eq.{quote(r['id'])}", {"closed_at": now}, prefer="return=minimal")
            if r["entry_id"] and r["entry_id"] not in still_open:  # Coborn's grocery and pharmacy share one entry
                cancelled = db.rest("PATCH", f"club_events?place_entry_id=eq.{quote(r['entry_id'])}"
                                             f"&event_date=gte.{today}&cancelled_at=is.null",
                                    {"cancelled_at": now}, prefer="return=representation") or []
        events = f", {len(cancelled)} upcoming Events cancelled" if cancelled else ""
        lines.append(f"  - {'Hidden' if write else 'Would hide'}: {r['name']} (Apple Maps: permanently closed{events}). "
                     "Undo: empty its closed_at and apple_place_id")
    return lines


def match(places_file):
    """apple_match.swift's answers as migration lines, the unmatched as comments."""
    out = subprocess.run(["swift", str(HERE / "apple_match.swift"), str(places_file)],
                         capture_output=True, text=True, check=True).stdout
    return sql_lines([json.loads(line) for line in out.splitlines() if line.strip()])


def sql_lines(found):
    lines = []
    for f in found:
        if f.get("apple_place_id"):
            lines.append(f"update public.places set apple_place_id = '{f['apple_place_id']}' where id = '{f['id']}';"
                         f"  -- {f['name']} = {f['apple_name']} ({f['metres']} m)")
        else:
            lines.append(f"-- no Apple Maps place: {f['name']} ({f['id']})")
    return lines


# --- self-test -----------------------------------------------------------------------------------------

class FakeDb:
    def __init__(self, rows, events=()):
        self.rows, self.events, self.patched = rows, list(events), []

    def rest(self, method, path, body=None, prefer=None):
        if method == "GET":
            return self.rows
        self.patched.append((path.split("?")[0], path, body))
        return self.events if path.startswith("club_events") else None


def selftest():
    page = lambda closed: (200, '{"entity":{"type":"BUSINESS"' + (',"isPermanentlyClosed":true' if closed else '') + '}}')
    pages = {"A": page(True), "B": page(False), "C": (200, "<html>Sorry</html>")}
    get = lambda url: pages[url.rsplit("=", 1)[1]]
    rows = [{"id": "1", "entry_id": "bello", "name": "Bello Cucina", "apple_place_id": "A"},
            {"id": "2", "entry_id": "sals", "name": "Sal's", "apple_place_id": "B"},
            {"id": "3", "entry_id": "odd", "name": "Odd page", "apple_place_id": "C"},
            {"id": "4", "entry_id": "home", "name": "Home business", "apple_place_id": None}]
    cases, failed = [], 0

    db = FakeDb(rows, events=[{"id": "e1"}])
    lines = check(db, True, date(2026, 11, 2), get)
    cases.append(([p[0] for p in db.patched] == ["places", "club_events"] and db.patched[0][1] == "places?id=eq.1"
                  and "event_date=gte.2026-11-02" in db.patched[1][1] and "place_entry_id=eq.bello" in db.patched[1][1],
                  "a closed place is hidden and its upcoming Events cancelled, nothing else written"))
    cases.append(("2 places checked, 1 closed for good, 1 with no Apple Maps place" in lines[0]
                  and "Odd page" in lines[1] and "Hidden: Bello Cucina" in lines[2] and "1 upcoming Events cancelled" in lines[2],
                  "the report counts, names the unreadable page and the hidden place"))

    db = FakeDb(rows)
    lines = check(db, False, date(2026, 11, 2), get)
    cases.append((db.patched == [] and "Would hide: Bello Cucina" in lines[-1], "without --write nothing is written"))

    twin = rows[:1] + [{"id": "5", "entry_id": "bello", "name": "Bello Pharmacy", "apple_place_id": "B"}]
    db = FakeDb(twin)
    check(db, True, date(2026, 11, 2), get)
    cases.append(([p[0] for p in db.patched] == ["places"], "Events stay while another open place shares the entry"))

    many = [{"id": str(i), "entry_id": f"p{i}", "name": f"Place {i}", "apple_place_id": "A"} for i in range(MAX_AT_ONCE + 1)]
    db = FakeDb(many)
    lines = check(db, True, date(2026, 11, 2), get)
    cases.append((db.patched == [] and "none hidden" in lines[-1], "too many closings at once hides none"))

    cases.append((read("A", lambda url: (_ for _ in ()).throw(OSError("timed out"))).startswith("unreadable"),
                  "a failed fetch is unreadable, never closed"))

    sql = sql_lines([{"id": "u1", "entry_id": "sals", "name": "Sal's", "apple_place_id": "IF1", "apple_name": "Sal's Bar", "metres": 7},
                     {"id": "u2", "entry_id": "home", "name": "Home", "missing": "none"}])
    cases.append((sql[0].startswith("update public.places set apple_place_id = 'IF1' where id = 'u1';")
                  and sql[1].startswith("-- no Apple Maps place: Home"), "match writes one update per place, keyed by its own id"))

    for ok, what in cases:
        if not ok:
            failed += 1
            print(f"FAIL {what}")
    print(f"{len(cases) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", choices=["check", "match"])
    ap.add_argument("places", nargs="?", help="match: the places to look up, as JSON")
    ap.add_argument("--write", action="store_true", help="check: hide the closed places (a key in the environment)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.command == "match":
        return print("\n".join(match(args.places)))
    from read_events import LOCAL
    from run import Supabase
    print("\n".join(check(Supabase(), args.write, datetime.now(LOCAL).date())))


if __name__ == "__main__":
    main()
