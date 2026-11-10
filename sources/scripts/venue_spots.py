#!/usr/bin/env python3
"""
venue_spots.py: a place line no registry, hand file or map gives a spot for gets one each morning, when two
searches agree on its street address (BP app inside-cards 20; Jesse, 2026-11-09: "allow with an agent check").

The 81 lines of sources/spots/found-by-address.yaml were found this way by hand: the venue's address copied from a page
that names it, found a second time by a separate search, then turned into a point by the US Census geocoder (free,
public domain, answers from the cloud in half a second). This is the same, every morning, for the lines that are new.

`prepare` takes the place lines of upcoming Events that have no spot and nothing giving one, at most MAX, the soonest
Event first, and lays them on one batch for two helpers (sources/models/venue-spot.md). A line another Event of ours
already got a spot for is copied, with no search. A line looked at in the last RETRY_DAYS (found or not) is left alone,
so a venue no page names is tried once a fortnight, never daily (club_events.spot_looked_at).

`keep`, a step of `morning.py finish`, puts a spot on each line where the helpers' two answers agree and the geocoder
agrees with them: the same street, or two points within 300 m; the street's number and town as the geocoder matched
them; inside Minnesota; each answer's quote holding the street number it gave; and one of the two from the venue's
own, its school's or its owner's page, not a listing site. Every spot put live is a report line saying where it came
from and how to take it down; every line left is one saying why.

  python3 sources/scripts/venue_spots.py prepare
  python3 sources/scripts/venue_spots.py keep --dry-run
  python3 sources/scripts/venue_spots.py --selftest
"""

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import find_spots  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
import spots  # noqa: E402
from db import DbError  # noqa: E402

MAX = 8            # place lines looked up a morning: two helpers, about three searches each
RETRY_DAYS = 14    # a line looked at and not found waits this long
CENSUS = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?"
KINDS = ("venue", "school", "weak", "none")  # whose page the address is on: the venue's, its school's, a listing site's
READINGS = ("venues.jsonl", "venues-2.jsonl")  # the two helpers' answers

SUFFIX = {"st": "street", "ave": "avenue", "rd": "road", "dr": "drive", "blvd": "boulevard", "ln": "lane", "ct": "court",
          "hwy": "highway", "pkwy": "parkway", "cty": "county", "co": "county", "n": "north", "s": "south", "e": "east",
          "w": "west"}
NOISE = {"north", "south", "east", "west", "street", "avenue", "road", "drive", "boulevard", "lane", "court", "the",
         "highway", "county", "parkway", "suite", "box"}


# --- Addresses --------------------------------------------------------------------------------------------------

def parts(address):
    """(street number, street words, town) of "street, town, MN ZIP" as a page prints it, or the geocoder's
    "STREET, TOWN, MN, ZIP". The town is the part before the state."""
    bits = [b.strip() for b in re.sub(r"[^A-Za-z0-9 ,'.-]", "", address or "").lower().split(",")]
    street = [SUFFIX.get(w, w) for w in re.sub(r"[.']", "", bits[0]).split()] if bits and bits[0] else []
    num = street[0] if street and street[0].isdigit() else None
    state = next((i for i, b in enumerate(bits) if i and re.match(r"(mn|minnesota)\b", b)), None)
    town = bits[state - 1] if state and state >= 2 else None
    town = re.sub(r"^st\b\.?", "saint", re.sub(r"\.", "", town or "")).strip()
    return num, {w for w in street[1:] if w not in NOISE}, town or None


def same_street(a, b):
    """The same number, town and street, however each page spells Avenue, N. or St."""
    x, y = parts(a), parts(b)
    return bool(x[0] and x[0] == y[0] and x[2] and x[2] == y[2] and (x[1] & y[1] or not (x[1] and y[1])))


def quoted(answer):
    """The answer's quote holds the street's number, and one of its words when it has any: it was copied from text."""
    num, words, _ = parts(answer.get("address"))
    q = str(answer.get("quote") or "").lower()
    return bool(num) and re.search(rf"\b{num}\b", q) is not None and (not words or any(w in q for w in words))


def geocode(address, opener=urllib.request.urlopen):
    """{"matched", "lat", "lng"} from the US Census geocoder, None when it knows no such address; a RuntimeError
    when it didn't answer (a morning later is soon enough)."""
    u = CENSUS + urllib.parse.urlencode({"address": address, "benchmark": "Public_AR_Current", "format": "json"})
    for attempt in range(3):
        try:
            with opener(urllib.request.Request(u, headers={"User-Agent": run.UA}), timeout=30) as r:
                m = json.load(r)["result"]["addressMatches"]
            time.sleep(0.3)
            return {"matched": m[0]["matchedAddress"], "lat": round(m[0]["coordinates"]["y"], 5),
                    "lng": round(m[0]["coordinates"]["x"], 5)} if m else None
        except Exception as e:
            err = e
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"the Census geocoder didn't answer ({' '.join(str(err).split())[:100]})")


def judge(a, b, geo=geocode):
    """("keep", {...}), ("no", why) or ("later", why) for one venue's two answers."""
    if not a or not b:  # a helper that gave no line for it (it stopped, or the cloud refused it): tomorrow
        return "later", "a helper gave no answer"
    if not (a.get("address") and b.get("address")):
        return "no", "the helpers found no address" if not (a.get("address") or b.get("address")) else "only one of the two searches found an address"
    if "none" in (a.get("kind"), b.get("kind")) or any(x.get("kind") not in KINDS for x in (a, b)):
        return "no", "an answer was marked as having no usable page"
    if not any(x["kind"] in ("venue", "school") for x in (a, b)):
        return "no", "both addresses are from listing sites, not the venue's, its school's or its owner's page"
    for x in (a, b):
        if not (parts(x["address"])[0] and parts(x["address"])[2]):
            return "no", f"{x['address']!r} has no street number and town"
        if not quoted(x):
            return "no", f"the quote for {x['address']!r} doesn't hold its street number"
    try:
        main = next(x for x in (a, b) if x["kind"] in ("venue", "school"))
        got = geo(main["address"])
        if not got:
            return "no", f"the Census doesn't know {main['address']!r}"
        num, _, town = parts(main["address"])
        gnum, _, gtown = parts(got["matched"])
        if (gnum, gtown) != (num, town):
            return "no", f"the Census matched {got['matched']!r}, not the same number and town"
        w, s, e, n = find_spots.BOX
        if not (s <= got["lat"] <= n and w <= got["lng"] <= e):
            return "no", "the point is outside Minnesota"
        if not same_street(a["address"], b["address"]):
            other = geo(next(x for x in (a, b) if x is not main)["address"])
            if not other or find_spots.metres((got["lat"], got["lng"]), (other["lat"], other["lng"])) > find_spots.NEAR:
                return "no", f"the searches found different places: {a['address']!r} and {b['address']!r}"
    except RuntimeError as e:
        return "later", str(e)
    return "keep", {"lat": got["lat"], "lng": got["lng"], "address": got["matched"].title().replace(", Mn,", ", MN,"),
                    "page": main.get("page") or ""}


# --- Which lines ------------------------------------------------------------------------------------------------

def pages(db, path):
    """Every row of a read, PostgREST answering at most 1,000 at a time."""
    rows = []
    while True:
        got = db.rest("GET", f"{path}&limit=1000&offset={len(rows)}") or []
        rows += got
        if len(got) < 1000:
            return rows


def todo(db, today, given, most=MAX):
    """(lines to look up, lines to copy, how many wait for another morning). `given(row)`: the registry or a hand file
    gives this Event a spot, so the morning's map step places it."""
    rows = pages(db, "club_events?select=id,title,event_date,location,place_entry_id,lat,lng,no_place,spot_looked_at"
                     f"&event_date=gte.{today}&status=eq.approved&order=event_date,id")
    known = {}  # a line's spot where one of ours put it: the line, and only if every such Event agrees
    for r in pages(db, "club_events?select=location,lat,lng&spot_looked_at=not.is.null&lat=not.is.null"):
        known.setdefault(r["location"], set()).add((round(r["lat"], 5), round(r["lng"], 5)))
    lines = {}
    for r in rows:
        if r["location"] and r.get("lat") is None and not r.get("no_place"):
            lines.setdefault(r["location"], []).append(r)
    cutoff = (today - timedelta(days=RETRY_DAYS)).isoformat()
    lookups, copies = [], []
    for line, rs in lines.items():
        if any(given(r) for r in rs):
            continue
        if len(known.get(line, ())) == 1:
            copies.append({"line": line, "at": list(next(iter(known[line]))), "events": len(rs)})
        elif not any((r.get("spot_looked_at") or "")[:10] >= cutoff for r in rs):
            lookups.append({"line": line, "events": len(rs), "first": rs[0]["event_date"], "host": rs[0]["place_entry_id"],
                            "title": rs[0]["title"]})
    lookups.sort(key=lambda v: (v["first"], -v["events"], v["line"]))
    return lookups[:most], copies, max(len(lookups) - most, 0)


def prepare(folder, db, today, given=None):
    """Lays out the batch for the helpers and found.json: the lines to look up, and the copies keep makes."""
    for name in READINGS:  # an earlier prepare's answers: their keys were other venues'
        (folder.parent / name).unlink(missing_ok=True)
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    if given is None:
        root = registry.find_root(Path(__file__).parent)
        entries = registry.load(root)[0]
        hand, (venues, ats), names = spots.hand_spots(root), spots.spots_index(entries), registry.names_index(entries)
        given = lambda r: spots.spot_for(r["location"], r["place_entry_id"], venues, ats, names, hand) is not None
    try:
        lookups, copies, later = todo(db, today, given)
    except DbError as e:  # club_events.spot_looked_at isn't applied yet: the morning goes on without this step
        print(f"[venues] skipped: {' '.join(str(e).split())[:150]}")
        return []
    for i, v in enumerate(lookups, 1):
        v["key"] = f"v{i}"
    (folder / "found.json.new").write_text(json.dumps({"today": str(today), "lines": lookups, "copies": copies, "later": later},
                                                  indent=1, ensure_ascii=False))
    (folder / "found.json.new").replace(folder / "found.json")  # whole or not at all
    if lookups:
        (folder / "batch.txt").write_text("\n".join(json.dumps({"venue": v["key"], "line": v["line"], "posted_by": v["host"],
                                                                 "for_example": v["title"], "events": v["events"],
                                                                 "first": v["first"]}, ensure_ascii=False)
                                                    for v in lookups) + "\n")
    print(f"[venues] {len(lookups)} place lines to look up, {len(copies)} to copy, {later} for another morning"
          + (f" ({folder / 'batch.txt'})" if lookups else ""))
    return lookups


# --- Keep -------------------------------------------------------------------------------------------------------

def answers_in(text):
    """The helper's JSON lines, by venue key; a line that isn't one is skipped."""
    out = {}
    for ln in text.splitlines():
        try:
            a = json.loads(ln.strip().strip(","))
        except ValueError:
            continue
        if isinstance(a, dict) and isinstance(a.get("venue"), str):
            out[a["venue"]] = a
    return out


def take_down(line):
    """The migration line that takes a spot down and keeps it down for good: spot_looked_at in the future is read as
    'looked at lately', so the morning never looks again."""
    q = "'" + line.replace("'", "''") + "'"
    return (f"update public.club_events set lat = null, lng = null, spot_looked_at = now() + interval '5 years' "
            f"where location = {q} and spot_looked_at is not null;")


def mark(db, today, line, now, at=None):
    """The upcoming Events at this line: looked at now, and given the spot when there is one."""
    body = {"spot_looked_at": now, **({"lat": at[0], "lng": at[1]} if at else {})}
    db.rest("PATCH", f"club_events?location=eq.{urllib.parse.quote(line, safe='')}&status=eq.approved"
                     f"&event_date=gte.{today}&lat=is.null", body, prefer="return=minimal")


def keep(run_, dry_run=False, geo=geocode):
    """Each line the two searches agree on gets its spot; every line looked up today is one report line. Kept as the
    step's lines, so a finish run again neither writes nor reports twice. Anything that breaks is one line: a lost
    morning report costs more than a spot a day late."""
    try:
        return kept_lines(run_, dry_run, geo)
    except Exception as e:
        return [f"[morning] venue spots failed: {' '.join(str(e).split())[:200]}"]


def kept_lines(run_, dry_run, geo):
    folder = run_.folder / "venues"
    if not (folder / "found.json").exists():
        return []
    done = run_.part(f"venues/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    found = json.loads((folder / "found.json").read_text())
    readings = [answers_in(f.read_text() if f.exists() else "") for f in (run_.folder / n for n in READINGS)]
    now = datetime.now(timezone.utc).isoformat()
    put, left = [], []
    try:
        for c in found["copies"]:
            if not dry_run:
                mark(run_.db, run_.today, c["line"], now, c["at"])
            put.append(f"- Spot copied: {c['line']} ({c['events']}): the spot another Event at this line got by address"
                       + (" (dry run: nothing written)" if dry_run else ""))
        for v in found["lines"]:
            verdict, got = judge(readings[0].get(v["key"]), readings[1].get(v["key"]), geo)
            if verdict == "later":  # not marked: tried again tomorrow
                left.append(f"- No spot by address yet: {v['line']}: {got}; tried again tomorrow")
            elif verdict == "no":
                if not dry_run:
                    mark(run_.db, run_.today, v["line"], now)
                left.append(f"- No spot by address: {v['line']} ({v['events']}): {got}; looked at again in {RETRY_DAYS} days")
            else:
                if not dry_run:
                    mark(run_.db, run_.today, v["line"], now, [got["lat"], got["lng"]])
                put.append(f"- Spot by address: {v['line']} ({v['events']}): {got['address']}, from {got['page']}; two searches "
                           f"found it. Wrong? Take it down with a migration: {take_down(v['line'])}"
                           + (" (dry run: nothing written)" if dry_run else ""))
    except DbError as e:
        left.append(f"[morning] venue spots failed: {' '.join(str(e).split())[:200]}")
    if found.get("later"):
        left.append(f"- No spot by address yet: {found['later']} more place lines, looked up on another morning")
    lines = ([f"- New spots by address: {len(put)} place lines"] + put if put else []) + left
    done.save(lines)
    return lines


# --- Self-test --------------------------------------------------------------------------------------------------

def selftest():
    from morning_run import FakeDb, Run
    import tempfile
    checks = []
    ok = lambda good, why: checks.append((bool(good), why))

    ok(same_street("340 N Friberg Avenue, Fergus Falls, MN 56537", "340 Friberg Ave, Fergus Falls, MN 56537"), "spellings of one street")
    ok(same_street("5600 85th Ave N, Brooklyn Park, MN", "5600 85TH AVE N, BROOKLYN PARK, MN, 55443"), "the geocoder's capitals and commas")
    ok(not same_street("1310 Rossman Ave, Detroit Lakes, MN", "1300 Rossman Ave, Detroit Lakes, MN"), "another number is another address")
    ok(not same_street("118 9th Street, Mora, MN", "118 9th Street, Pine City, MN"), "another town is another address")
    ok(same_street("100 Main St, St. Cloud, MN 56301", "100 Main Street, Saint Cloud, MN"), "St. and Saint")

    census = {"340 Friberg Ave, Fergus Falls, MN 56537": ("340 FRIBERG AVE, FERGUS FALLS, MN, 56537", 46.28601, -96.0692),
              "1300 Rossman Ave, Detroit Lakes, MN 56501": ("1300 ROSSMAN AVE, DETROIT LAKES, MN, 56501", 46.80930, -95.85320),
              "1310 Rossman Ave, Detroit Lakes, MN 56501": ("1310 ROSSMAN AVE, DETROIT LAKES, MN, 56501", 46.80922, -95.85317),
              "9 Far Rd, Detroit Lakes, MN 56501": ("9 FAR RD, DETROIT LAKES, MN, 56501", 46.9, -95.5),
              "5 Oak St, Moorhead, MN 56560": ("6 OAK ST, MOORHEAD, MN, 56560", 46.87, -96.76),
              "7 Dock Rd, Fargo, ND 58102": ("7 DOCK RD, FARGO, ND, 58102", 46.87, -96.78)}

    def geo(address):
        if address == "down":
            raise RuntimeError("the Census geocoder didn't answer (timed out)")
        m = census.get(address)
        return {"matched": m[0], "lat": m[1], "lng": m[2]} if m else None

    def ans(address, kind="venue", quote=None, **k):
        return {"venue": "v1", "address": address, "kind": kind, "page": "https://p", "quote": quote or f"Rink: {address}", **k}

    good = "340 Friberg Ave, Fergus Falls, MN 56537"
    v, got = judge(ans(good), ans("340 N Friberg Avenue, Fergus Falls, MN 56537", "weak"), geo)
    ok(v == "keep" and got["lat"] == 46.28601 and got["address"].startswith("340 Friberg Ave, Fergus Falls, MN,"), "two agreeing addresses keep")
    ok(judge(ans("1300 Rossman Ave, Detroit Lakes, MN 56501"), ans("1310 Rossman Ave, Detroit Lakes, MN 56501", "school"), geo)[0] == "keep",
       "two numbers on one campus (under 300 m) keep")
    ok(judge(ans("1300 Rossman Ave, Detroit Lakes, MN 56501"), ans("9 Far Rd, Detroit Lakes, MN 56501"), geo)[0] == "no",
       "two places far apart don't")
    ok(judge(ans(good, "weak"), ans(good, "weak"), geo)[0] == "no", "two listing sites alone don't")
    ok(judge(ans(good), ans(""), geo)[0] == "no" and judge(ans(""), ans(""), geo)[0] == "no", "one search finding an address, or none, doesn't")
    ok(judge(None, ans(good), geo)[0] == "later" and judge(None, None, geo)[0] == "later", "a helper with no line for it is tried tomorrow, not marked")
    ok(judge(ans(good), ans(good, "none"), geo)[0] == "no", "an answer marked none doesn't")
    ok(judge(ans(good, quote="Fergus Falls Ice Arena, ice and more"), ans(good), geo)[0] == "no", "a quote without the street number doesn't")
    ok(judge(ans("5 Oak St, Moorhead, MN 56560"), ans("5 Oak St, Moorhead, MN 56560"), geo)[0] == "no", "the geocoder matching another number doesn't")
    ok(judge(ans("7 Dock Rd, Fargo, ND 58102"), ans("7 Dock Rd, Fargo, ND 58102"), geo)[0] == "no", "an address with no Minnesota town doesn't")
    ok(judge(ans("2 Nowhere Ln, Alexandria, MN"), ans("2 Nowhere Ln, Alexandria, MN"), geo)[0] == "no", "an address the Census doesn't know doesn't")
    ok(judge(ans("down, x, MN"), ans("down, x, MN"), geo)[0] == "no", "an address with no street number doesn't")
    ok(judge(ans(good), ans(good), lambda a: geo("down"))[0] == "later", "a geocoder that didn't answer is tried tomorrow, not marked")

    today = date(2026, 11, 9)
    rows = [{"id": "e1", "title": "Hockey vs A", "event_date": "2026-11-12", "location": "New Arena", "place_entry_id": "h1"},
            {"id": "e2", "title": "Hockey vs B", "event_date": "2026-11-14", "location": "New Arena", "place_entry_id": "h1"},
            {"id": "e3", "title": "Game C", "event_date": "2026-11-10", "location": "Known Gym", "place_entry_id": "h2"},
            {"id": "e4", "title": "Game D", "event_date": "2026-11-11", "location": "Registry Hall", "place_entry_id": "h2"},
            {"id": "e5", "title": "Game E", "event_date": "2026-11-11", "location": "Tried Lately Rink", "place_entry_id": "h3",
             "spot_looked_at": "2026-11-05T12:00:00+00:00"},
            {"id": "e6", "title": "Game F", "event_date": "2026-11-13", "location": "Tried Long Ago Rink", "place_entry_id": "h3",
             "spot_looked_at": "2026-10-01T12:00:00+00:00"},
            {"id": "e7", "title": "Game G", "event_date": "2026-11-15", "location": "Placed Rink", "place_entry_id": "h3", "lat": 45.5, "lng": -94.1},
            {"id": "e8", "title": "Online", "event_date": "2026-11-15", "location": "Zoom", "place_entry_id": "h3", "no_place": True}]
    known = [{"location": "Known Gym", "lat": 45.1, "lng": -94.2}, {"location": "Two Spots Gym", "lat": 45.1, "lng": -94.2},
             {"location": "Two Spots Gym", "lat": 45.9, "lng": -94.9}]

    class Db(FakeDb):
        def __init__(self):
            self.calls = []

        def rest(self, method, path, body=None, prefer=None):
            self.calls.append((method, path, body))
            if method == "GET":
                if "spot_looked_at=not.is.null" in path:
                    return known if "offset=0" in path else []
                return rows if "offset=0" in path else []

    db = Db()
    lookups, copies, later = todo(db, today, lambda r: r["location"] == "Registry Hall", most=8)
    ok([v["line"] for v in lookups] == ["New Arena", "Tried Long Ago Rink"] and lookups[0]["events"] == 2 and lookups[0]["first"] == "2026-11-12",
       f"lines to look up: new and long-ago ones, soonest first; not placed, no-place, given or tried lately: {lookups}")
    ok(copies == [{"line": "Known Gym", "at": [45.1, -94.2], "events": 1}] and later == 0, f"a line one of ours placed is copied: {copies}")
    ok(len(todo(db, today, lambda r: False, most=1)[0]) == 1 and todo(db, today, lambda r: False, most=1)[2] == 2, "at most MAX, the rest wait")

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning"
        r = Run(folder, today, Db())
        ok(keep(r) == [], "no venues step, no lines")
        lookups = prepare(folder / "venues", r.db, today, given=lambda x: x["location"] == "Registry Hall")
        ok([v["key"] for v in lookups] == ["v1", "v2"] and (folder / "venues" / "batch.txt").exists(), "prepare lays out the batch")
        a1 = [ans(good, venue="v1"), ans("9 Far Rd, Detroit Lakes, MN 56501", venue="v2")]
        a2 = [ans("340 Friberg Avenue, Fergus Falls, MN 56537", "school", venue="v1"), ans("1300 Rossman Ave, Detroit Lakes, MN 56501", venue="v2")]
        (folder / "venues.jsonl").write_text("\n".join(json.dumps(a) for a in a1) + "\nnot json\n")
        (folder / "venues-2.jsonl").write_text("\n".join(json.dumps(a) for a in a2) + "\n")
        r.db.calls.clear()
        lines = keep(r, geo=geo)
        patches = [(p, b) for m, p, b in r.db.calls if m == "PATCH"]
        ok(len(patches) == 3 and "Known%20Gym" in patches[0][0] and patches[0][1]["lat"] == 45.1, f"the copy is written: {patches[:1]}")
        ok("location=eq.New%20Arena" in patches[1][0] and patches[1][1]["lat"] == 46.28601 and "spot_looked_at" in patches[1][1],
           f"a line both searches agree on gets its spot and its mark: {patches[1:2]}")
        ok("location=eq.Tried%20Long%20Ago%20Rink" in patches[2][0] and "lat" not in patches[2][1] and "spot_looked_at" in patches[2][1],
           f"a line they don't is marked looked at, with no spot: {patches[2:]}")
        ok(lines[0] == "- New spots by address: 2 place lines" and any("Take it down" in l and "New Arena" in l for l in lines)
           and any(l.startswith("- No spot by address: Tried Long Ago Rink") for l in lines), f"the report: {lines}")
        r.db.calls.clear()
        ok(keep(r, geo=geo) == lines and not [c for c in r.db.calls if c[0] == "PATCH"], "a finish run again neither writes nor reports twice")

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning"
        r = Run(folder, today, Db())
        prepare(folder / "venues", r.db, today, given=lambda x: False)
        (folder / "venues.jsonl").write_text(json.dumps(ans(good, venue="v1")) + "\n")
        (folder / "venues-2.jsonl").write_text(json.dumps(ans(good, venue="v1")) + "\n")
        r.db.calls.clear()
        lines = keep(r, dry_run=True, geo=geo)
        ok(not [c for c in r.db.calls if c[0] == "PATCH"] and any("dry run" in l for l in lines), "a dry run writes nothing")
        r2 = Run(Path(tmp) / "m2", today, Db())
        prepare(Path(tmp) / "m2" / "venues", r2.db, today, given=lambda x: False)
        for n in READINGS:
            (Path(tmp) / "m2" / n).write_text("\n".join(json.dumps(ans(good, venue=f"v{i}")) for i in (1, 2, 3)) + "\n")
        r2.db.calls.clear()
        lines = keep(r2, geo=lambda a: geo("down"))
        ok(not [c for c in r2.db.calls if c[0] == "PATCH" and "Known" not in c[1]] and any("tried again tomorrow" in l for l in lines),
           "a geocoder that didn't answer marks no looked-up line (a copy needs none)")

    class Broken(Db):
        def rest(self, method, path, body=None, prefer=None):
            if method == "GET":
                raise DbError("GET", path, 400, '{"message":"column club_events.spot_looked_at does not exist"}')
    with tempfile.TemporaryDirectory() as tmp:
        ok(prepare(Path(tmp) / "venues", Broken(), today, given=lambda x: False) == [], "a database without the column skips the step")

    ok(take_down("Rink's Gym").endswith("where location = 'Rink''s Gym' and spot_looked_at is not null;"), "the take-down line quotes the place line")

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
    from read_events import LOCAL
    r = Run(registry.find_root() / ".runs" / "morning", datetime.now(LOCAL).date(), run.Supabase())
    if a.step == "prepare":
        prepare(r.folder / "venues", r.db, r.today)
    elif a.step == "keep":
        print("\n".join(keep(r, a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
