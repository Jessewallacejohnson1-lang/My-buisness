#!/usr/bin/env python3
"""The census rules that would quietly delete a business if they broke (ADR-018, ADR-019).

Run: python3 sources/scripts/test_census.py   (no network)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from discover import in_town, merge, zip_of


def rec(name, source="overture", **kw):
    return dict(name=name, source=source, **kw)


def names(roster):
    return sorted(p["name"] for p in roster)


# ZIP comes from after the state, never from a street number (ADR-019).
assert zip_of("8805 Ridgewood Ct, St Joseph, MN 56374") == "56374"
assert zip_of("30701 Pearl Drive # 3") is None
assert in_town(rec("A", address="1 Main St, Avon, MN 56310"), ["56374"]) is False
assert in_town(rec("A", source="maps", address=""), ["56374"]) is False   # service-area listing
assert in_town(rec("A", source="osm"), ["56374"]) is True                 # town-scoped source

# A shared phone alone does not merge: city hall's line also rings police and parks.
r = merge([rec("City of St. Joseph", phone="320-363-7201"),
           rec("Saint Joseph Police Department", phone="(320) 363-7201")])
assert len(r) == 2, names(r)

# A shared phone plus a distinctive word does.
r = merge([rec("Coborn's", phone="320-363-7111"),
           rec("Coborns Grocery", source="maps", phone="3203637111")])
assert len(r) == 1 and r[0]["name"] == "Coborn's", names(r)   # non-Google name wins (ADR-016)

# An old directory's phone never merges: numbers get reassigned.
r = merge([rec("Synergistic Healing", source="lakesnwoods.com", phone="320-363-4223"),
           rec("Synergistic Healing Arts", phone="320-363-4223")], stale={"lakesnwoods.com"})
assert len(r) == 2, names(r)

# Same street spot with overlapping names merges, even from the old directory.
r = merge([rec("CMS Autobody", address="109 Cedar St E"),
           rec("CMS Auto Body", source="lakesnwoods.com", address="109 Cedar Street NW")],
          stale={"lakesnwoods.com"})
assert len(r) == 1, names(r)

# A known-distinct pair stays apart even when a third sighting sits next to both.
r = merge([rec("Kwik Trip #147", address="200 2nd Ave NW"),
           rec("Kwik Trip #575", address="15 20th Ave SE"),
           rec("Kwik Trip", source="osm", address="15 20th Ave SE"),
           rec("Kwik Trip ", source="registry", address="200 2nd Ave NW")],
          known_distinct=[("Kwik Trip #147", "Kwik Trip #575")])
everything = [" ".join([p["name"], *p.get("aka", [])]) for p in r]
assert len(r) == 2 and not any("147" in e and "575" in e for e in everything), everything

print("census rules OK")
