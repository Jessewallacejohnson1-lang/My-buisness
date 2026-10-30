"""Where each upcoming Event really is, for the map's bubbles (BP app references/map-reset, 2026-10-30).

    python3 sources/scripts/spots.py               # dry run: what it would set, and what has no spot
    python3 sources/scripts/spots.py --write       # sets club_events.lat, lng (service key in the environment)
    python3 sources/scripts/spots.py --selftest

The map puts each of today's Events at `club_events.lat, lng`. The spots are hand-checked coordinates in
the source registry: each entry's `at: [lat, lng]` (its main door) and `venue_at:`, a map from a venue's
name, as event location lines write it, to its own [lat, lng] (Sexton Arena is not SJU's main door). An
Event goes to:
  1. the venue its location line names (the line whole, else the longest venue name inside it), else
  2. its Place's `at:`, when the line is empty or names that Place (its name, other names or address).
Nothing else: never the host's own grounds as a guess, since most unknown places are away games
(write_judged.py's ponytail on spots). An Event with no spot is listed, so its venue can be added.

The morning job's finish runs this for every upcoming Event still without a spot, so new ones get theirs
the morning they arrive; the first run filled the ones already listed.
"""
import argparse
import sys
from datetime import date, datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402

LOCAL = ZoneInfo("America/Chicago")


def spots_index(entries):
    """(venue key -> [lat, lng], entry id -> [lat, lng]) from the registry's `venue_at` and `at`."""
    venues, ats = {}, {}
    for e in entries:
        extra = e.get("_extra") or e
        if extra.get("at"):
            ats[e["id"]] = list(extra["at"])
        for name, at in (extra.get("venue_at") or {}).items():
            key = registry.place_key(name)
            if key and key not in registry.TOWN_KEYS:
                venues[key] = list(at)
    return venues, ats


def spot_for(location, entry_id, venues, ats, names):
    """[lat, lng] for an Event at `location` posted for Place `entry_id`, or None (rules in the docstring)."""
    key = registry.place_key(location)
    if key in venues:
        return venues[key]
    inside = [k for k in venues if len(k) >= 8 and k in key]
    if inside:
        return venues[max(inside, key=len)]
    if not key:
        return ats.get(entry_id)
    ids, found = registry.place_for(location, None, names)
    if found and entry_id in (ids or []):
        return ats.get(entry_id)
    return None


def fill(db, today, write, entries=None):
    """Set the spot of every Event from `today` on that has none; return the report's lines."""
    entries = entries if entries is not None else registry.load(registry.find_root(Path(__file__).parent))[0]
    venues, ats = spots_index(entries)
    names = registry.names_index(entries)
    rows = db.rest("GET", "club_events?select=id,title,event_date,location,place_entry_id"
                          f"&event_date=gte.{today}&lat=is.null&status=eq.approved&order=event_date") or []
    placed, missing = 0, []
    for r in rows:
        at = spot_for(r["location"], r["place_entry_id"], venues, ats, names)
        if not at:
            missing.append(r)
            continue
        placed += 1
        if write:
            db.rest("PATCH", f"club_events?id=eq.{quote(r['id'])}", {"lat": at[0], "lng": at[1]},
                    prefer="return=minimal")
    verb = "set" if write else "would set"
    lines = [f"- Map spots: {verb} {placed}, {len(missing)} with no spot"]
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
    ]
    venues, ats = spots_index(entries)
    names = registry.names_index(entries)
    cases = [
        ("Sexton Arena, Collegeville", "sju", [45.5798, -94.3962], "a named venue wins over its Place's door"),
        ("The Great Hall", "sju", [45.5809, -94.3920], "a venue with 'the' in front"),
        ("SJU, Collegeville", "sju", [45.5810, -94.3926], "the Place's own name: its door"),
        ("", "bar-grill-sals", [45.56443, -94.32055], "no place line: the Place itself"),
        (None, "bar-grill-sals", [45.56443, -94.32055], "no place line at all"),
        ("Municipal Athletic Center, St. Cloud", "activities-athletic-csb", [45.5731, -94.2276],
         "an away game goes where it's played"),
        ("Rush City High School", "activities-athletic-csb", None, "an unknown place is never the host's grounds"),
        ("Online", "sju", None, "online has no spot"),
        ("Collegeville", "sju", None, "a bare town is no place"),
    ]
    failed = 0
    for location, entry, want, why in cases:
        got = spot_for(location, entry, venues, ats, names)
        if got != want:
            failed += 1
            print(f"FAIL {why}: {location!r} -> {got}, want {want}")

    class FakeDb:
        def __init__(self): self.patched = []
        def rest(self, method, path, body=None, prefer=None):
            if method == "GET":
                return [{"id": "e1", "title": "Hockey", "event_date": "2026-10-30", "place_entry_id": "activities-athletic-csb",
                         "location": "Municipal Athletic Center, St. Cloud"},
                        {"id": "e2", "title": "Volleyball", "event_date": "2026-10-30", "place_entry_id": "activities-athletic-csb",
                         "location": "Rush City High School"}]
            self.patched.append((path, body))
    db = FakeDb()
    lines = fill(db, date(2026, 10, 30), write=True, entries=entries)
    if db.patched != [("club_events?id=eq.e1", {"lat": 45.5731, "lng": -94.2276})] or "set 1, 1 with no spot" not in lines[0] \
            or "Volleyball" not in lines[1]:
        failed += 1
        print(f"FAIL fill writes only real spots and lists the rest: {db.patched} {lines}")
    print(f"{len(cases) + 1 - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="set the spots (service role key in the environment)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    from db import Db
    print("\n".join(fill(Db(), datetime.now(LOCAL).date(), args.write)))


if __name__ == "__main__":
    main()
