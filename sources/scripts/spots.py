"""Where each upcoming Event really is, for the map's bubbles (BP app references/map-reset, 2026-10-30).

    python3 sources/scripts/spots.py               # dry run: what it would set, and what has no spot
    python3 sources/scripts/spots.py --maps        # the same with Overture and OpenStreetMap read (2 minutes)
    python3 sources/scripts/spots.py --write       # sets club_events.lat, lng, no_place (service key in the environment)
    python3 sources/scripts/spots.py --selftest

The map puts each of today's Events at `club_events.lat, lng`. An Event goes to:
  1. the spot `sources/spots/*.yaml` gives its location line, matched whole with its town: a hand-chosen
     spot for a line that names no registry place (a downtown, an away venue), or none when the line names
     no one place (several schools); else
  2. the venue its location line names, from the registry's hand-checked `venue_at:`, a map from a venue's
     name, as event location lines write it, to its own [lat, lng] (Sexton Arena is not SJU's main door):
     the line whole, else the longest venue name inside it, from its own Place's venues or, for a name long
     enough to be one building only (16 letters and up, "South Junior High School"), anyone's: a short name
     like "City Hall" or "Great Hall" inside a line from another town's host must not land here; else
  3. the `at:` (main door) of the registry Place the line names (registry.place_for: name, other names,
     venues or address), or of its own Place when the line is empty; else
  4. where Overture and OpenStreetMap agree on the line (find_spots.py; BP app inside-cards 20, Jesse
     2026-11-06), when the morning read them.
Never the host's own grounds as a guess, since most unknown places are away games (write_judged.py's
ponytail on spots). An Online line, a bare town or a hand `none` sets `no_place` instead, so the Event page
shows no Map button (inside-cards 06). An Event with no spot is listed, so its venue can be added.

The morning job's finish runs this over every upcoming Event, writing only the spots that changed, so a
new Event gets its spot the morning it arrives and a moved one follows it; the first run filled the ones
already listed. Events posted in the app (posting is paused) wait for the next morning. A morning that
couldn't read the two maps leaves the spots they gave as they were, rather than emptying them.
"""
import argparse
import sys
from datetime import date, datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402
from find_spots import NOWHERE, is_nowhere  # noqa: E402

LOCAL = ZoneInfo("America/Chicago")


def spots_index(entries):
    """(venue key -> (its entry, [lat, lng]), entry id -> [lat, lng]) from the registry's `venue_at` and `at`."""
    venues, ats = {}, {}
    for e in entries:
        extra = e.get("_extra") or e
        if extra.get("at"):
            ats[e["id"]] = list(extra["at"])
        for name, at in (extra.get("venue_at") or {}).items():
            key = registry.place_key(name)
            if key and key not in registry.TOWN_KEYS:
                venues[key] = (e["id"], list(at))
    return venues, ats


def line_key(line):
    """A place line with its town, as the hand file matches it: "VA Medical Center, St. Cloud" isn't Minneapolis's."""
    return registry.place_key((line or "").replace(",", " "))


def hand_spots(root):
    """sources/spots/*.yaml: each place line, matched whole, -> [lat, lng], or NOWHERE for null. A value that is
    neither raises ValueError naming it (the self-test reads the real files, so CI stops a bad edit)."""
    found = {}
    for path in sorted((Path(root) / "sources" / "spots").glob("*.yaml")):
        for line, at in (yaml.safe_load(path.read_text()) or {}).items():
            if at is not None and not (isinstance(at, list) and len(at) == 2
                                       and all(isinstance(x, (int, float)) for x in at)
                                       and 43 < at[0] < 50 and -98 < at[1] < -89):
                raise ValueError(f"{path.name}: {line!r} needs [lat, lng] in Minnesota or null, not {at!r}")
            found[line_key(line)] = list(at) if at else NOWHERE
    return found


# A venue name this long names one building wherever it's written; shorter ones match only their own Place's lines.
ANYONE_S = 16


def spot_for(location, entry_id, venues, ats, names, hand=None):
    """[lat, lng] for an Event at `location` posted for Place `entry_id`, NOWHERE, or None when the registry
    doesn't know (rules 1 to 3 in the docstring)."""
    if line_key(location) in (hand or {}):
        return hand[line_key(location)]
    if is_nowhere(location):
        return NOWHERE
    key = registry.place_key(location)
    if key in venues:
        return venues[key][1]
    inside = [k for k, (owner, _) in venues.items()
              if len(k) >= 8 and k in key and (owner == entry_id or len(k) >= ANYONE_S)]
    if inside:
        return venues[max(inside, key=len)][1]
    if not key:
        return ats.get(entry_id)
    ids, found = registry.place_for(location, None, names)
    return next((ats[i] for i in ids or [] if i in ats), None) if found else None


def fill(db, today, write, entries=None, maps=None, hand=None):
    """Give every Event from `today` on the spot the rules give it now, writing only the ones that
    differ (a new Event, a moved one, a corrected spot; one no longer known is emptied), and return
    the report's lines. `maps`: find_spots.Maps, or None when the morning couldn't read them, and then a
    spot the registry doesn't give stays as it was."""
    root = registry.find_root(Path(__file__).parent)
    entries = entries if entries is not None else registry.load(root)[0]
    hand = hand if hand is not None else hand_spots(root)
    venues, ats = spots_index(entries)
    names = registry.names_index(entries)
    # Every spot the registry and hand file give: with no maps, a row at one of these lost it (its line changed),
    # and a row elsewhere was placed by the maps, so it stays.
    given = {tuple(at) for at in [*ats.values(), *(v[1] for v in venues.values()), *hand.values()] if at != NOWHERE}
    found = {}  # place line -> the maps' answer: a line repeats on a team's whole season
    rows, page = [], 1000  # PostgREST answers at most 1,000 rows a read
    while True:
        got = db.rest("GET", "club_events?select=id,title,event_date,location,place_entry_id,lat,lng,no_place"
                             f"&event_date=gte.{today}&status=eq.approved&order=event_date,id"
                             f"&limit={page}&offset={len(rows)}") or []
        rows += got
        if len(got) < page:
            break
    changed, missing, nowhere, new = 0, [], 0, {}
    for r in rows:
        at = spot_for(r["location"], r["place_entry_id"], venues, ats, names, hand)
        why = "the registry"
        if at is None and maps is not None:
            if r["location"] not in found:
                found[r["location"]] = maps.find(r["location"])
            at, why = found[r["location"]]
        if at is None and maps is None and (r.get("no_place") or r.get("lat") is not None
                                            and (r["lat"], r["lng"]) not in given):
            continue  # the maps placed it (or found it a town) on an earlier morning: kept until they're read again
        nowhere += at == NOWHERE
        if not at:
            missing.append(r)
        spot = at if at and at != NOWHERE else [None, None]
        want = {"lat": spot[0], "lng": spot[1], "no_place": at == NOWHERE}
        if want == {k: r.get(k) for k in want}:
            continue
        changed += 1
        if spot[0] is not None and r.get("lat") is None:
            new.setdefault((r["location"] or "(no place line)", why), []).append(r)
        if write:
            db.rest("PATCH", f"club_events?id=eq.{quote(r['id'])}", want, prefer="return=minimal")
    verb = "set" if write else "would set"
    lines = [f"- Map spots: {verb} {changed}, {len(rows) - len(missing) - nowhere} placed, {nowhere} at no one place, "
             f"{len(missing)} with no spot"]
    # The new ones, so a wrong one is seen the morning it arrives (Jesse, 2026-11-06)
    if new:
        lines.append(f"- New spots: {sum(map(len, new.values()))} Events at {len(new)} places")
        lines += [f"  - {line} ({len(rs)}): {why}" for (line, why), rs in list(new.items())[:15]]
        lines += [f"  - and {len(new) - 15} more places"] * (len(new) > 15)
    lines += ["- With no spot:"] * bool(missing)
    lines += [f"  - {r['event_date']} {r['title']} · {r['location'] or '(no place line)'} ({r['place_entry_id']})"
              for r in missing[:25]]
    lines += [f"  - and {len(missing) - 25} more"] * (len(missing) > 25)
    return lines


# --- self-test -----------------------------------------------------------------------------------------

def selftest():
    entries = [
        {"id": "sju", "_name": "Saint John's University", "aka": ["SJU"], "address": "2850 Abbey Plaza",
         "_extra": {"at": [45.5810, -94.3926], "venue_at": {"Sexton Arena": [45.5798, -94.3962],
                                                            "Great Hall": [45.5809, -94.3920]}}},
        {"id": "bar-grill-sals", "_name": "Sal's Bar & Grill", "_extra": {"at": [45.56443, -94.32055]}},
        {"id": "activities-athletic-csb", "_name": "CSB Athletics", "_extra": {"at": [45.5600, -94.3200]}},
        {"id": "municipal-athletic-complex", "_name": "Municipal Athletic Complex",
         "_extra": {"venue_at": {"Municipal Athletic Center": [45.5731, -94.2276]}}},
        {"id": "st-cloud-area-school-district-742", "_name": "St. Cloud Area School District 742",
         "_extra": {"venue_at": {"South Junior High School": [45.54686, -94.16724]}}},
    ]
    venues, ats = spots_index(entries)
    names = registry.names_index(entries)
    hand = {line_key("Downtown St. Cloud"): [45.5604, -94.1590], line_key("Catholic Community Schools"): NOWHERE}
    cases = [
        ("Sexton Arena, Collegeville", "sju", [45.5798, -94.3962], "a named venue wins over its Place's door"),
        ("The Great Hall", "sju", [45.5809, -94.3920], "a venue with 'the' in front"),
        ("SJU, Collegeville", "sju", [45.5810, -94.3926], "the Place's own name: its door"),
        ("", "bar-grill-sals", [45.56443, -94.32055], "no place line: the Place itself"),
        (None, "bar-grill-sals", [45.56443, -94.32055], "no place line at all"),
        ("Municipal Athletic Center, St. Cloud", "activities-athletic-csb", [45.5731, -94.2276],
         "an away game goes where it's played"),
        ("Rush City High School", "activities-athletic-csb", None, "an unknown place is never the host's grounds"),
        ("Online", "sju", NOWHERE, "online is no one place"),
        ("Collegeville", "sju", NOWHERE, "a bare town is no one place"),
        ("Great Hall, SJU", "csbsju-events", [45.5809, -94.3920], "anyone's line that is the venue's name whole"),
        ("Sartell Great Hall", "sartell-high-school", None, "a short venue name inside another host's line is not it"),
        ("South Junior High School Gym, East", "kennedy-community-school", [45.54686, -94.16724],
         "a long venue name inside anyone's line"),
        ("SJU", "csbsju-events", [45.5810, -94.3926], "a line naming a Place goes to that Place, whoever posted it"),
        ("Downtown St. Cloud", "328-american-legion-post", [45.5604, -94.1590], "a hand spot, matched whole"),
        ("Downtown St. Cloud Library", "328-american-legion-post", None, "a hand spot isn't matched inside a line"),
        ("Catholic Community Schools", "st-joseph-catholic-school", NOWHERE, "a hand none: several schools"),
    ]
    failed = 0
    for location, entry, want, why in cases:
        got = spot_for(location, entry, venues, ats, names, hand)
        if got != want:
            failed += 1
            print(f"FAIL {why}: {location!r} -> {got}, want {want}")

    class FakeDb:
        def __init__(self, rows): self.rows, self.patched = rows, []
        def rest(self, method, path, body=None, prefer=None):
            if method == "GET":
                return self.rows
            self.patched.append((path.split("eq.")[1], body))

    class FakeMaps:
        def find(self, line):
            return ([45.98, -94.1], "Overture's 'Pierz Healy High School'") if line.startswith("Pierz") else (None, "no")

    row = lambda i, title, place, entry, lat=None, lng=None, no_place=False: {
        "id": i, "title": title, "event_date": "2026-10-30", "location": place, "place_entry_id": entry,
        "lat": lat, "lng": lng, "no_place": no_place}
    rows = [row("e1", "Hockey", "Municipal Athletic Center, St. Cloud", "activities-athletic-csb"),
            row("e2", "Volleyball", "Rush City High School", "activities-athletic-csb"),
            row("e3", "Raffle", None, "bar-grill-sals", 45.56443, -94.32055),
            row("e4", "Moved game", "Great Hall", "sju", 45.5798, -94.3962),
            row("e5", "Gymnastics", "Pierz High School MAC GYM", "activities-athletic-csb"),
            row("e6", "Webinar", "Online", "sju"),
            row("e7", "Old find", "Pierz High School", "activities-athletic-csb", 45.98, -94.1)]
    checks = []
    db = FakeDb(rows)
    lines = fill(db, date(2026, 10, 30), True, entries, FakeMaps(), hand)
    checks.append((db.patched == [("e1", {"lat": 45.5731, "lng": -94.2276, "no_place": False}),
                                  ("e4", {"lat": 45.5809, "lng": -94.3920, "no_place": False}),
                                  ("e5", {"lat": 45.98, "lng": -94.1, "no_place": False}),
                                  ("e6", {"lat": None, "lng": None, "no_place": True})],
                   f"fill writes only what changed: a new spot, a moved one, the maps' one, no one place: {db.patched}"))
    checks.append((lines[:4] == ["- Map spots: set 4, 5 placed, 1 at no one place, 1 with no spot",
                                 "- New spots: 2 Events at 2 places",
                                 "  - Municipal Athletic Center, St. Cloud (1): the registry",
                                 "  - Pierz High School MAC GYM (1): Overture's 'Pierz Healy High School'"]
                   and "Volleyball" in lines[-1], f"the report lists the new spots and the ones with none: {lines}"))
    db = FakeDb(rows + [row("e8", "Moved off", "Rush City High School", "sju", 45.5810, -94.3926),
                        row("e9", "Town only the maps know", "Ham Lake", "sju", no_place=True)])
    fill(db, date(2026, 10, 30), True, entries, None, hand)
    checks.append(([i for i, _ in db.patched] == ["e1", "e4", "e6", "e8"],
                   f"maps not read: their old spot (e7) and town (e9) stay, none is found (e5), and a registry "
                   f"spot whose line changed is emptied (e8): {db.patched}"))
    try:
        real = hand_spots(registry.find_root(Path(__file__).parent))
        checks.append((bool(real) and all(v == NOWHERE or len(v) == 2 for v in real.values()),
                       "sources/spots/ reads: every line a spot or null"))
    except ValueError as e:
        checks.append((False, str(e)))
    for ok, why in checks:
        if not ok:
            failed += 1
            print(f"FAIL {why}")
    print(f"{len(cases) + len(checks) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="set the spots (service role key in the environment)")
    ap.add_argument("--maps", action="store_true", help="read Overture and OpenStreetMap too (kept a day in sources/.runs/spots)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    from db import Db
    import find_spots
    maps = find_spots.read(Path(__file__).resolve().parents[1] / ".runs" / "spots") if args.maps else None
    print("\n".join(fill(Db(), datetime.now(LOCAL).date(), args.write, maps=maps)))


if __name__ == "__main__":
    main()
