#!/usr/bin/env python3
"""The census rules that would quietly delete a business if they broke (ADR-018, ADR-019).

Run: python3 sources/scripts/test_census.py   (no network)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from discover import collect_chamber, in_town, merge, near_duplicates, placed_elsewhere, zip_of
from maps import answered


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

# A no-ZIP sighting (a chamber member) of a place every source with a ZIP puts in another
# town belongs to that town; one also seen in town stays.
recs = [rec("Wacosa", source="stjosephchamber.com"),
        rec("Wacosa", address="2700 1st St N, St Cloud, MN 56303"),
        rec("Coborn's", source="stjosephchamber.com"),
        rec("Coborn's", address="1 Main St, St Cloud, MN 56301"),
        rec("Coborn's", address="1500 Elm St E, St Joseph, MN 56374")]
away = placed_elsewhere(recs, ["56374"])
kept = [r for r in recs if in_town(r, ["56374"], away)]
assert [r["source"] for r in kept] == ["stjosephchamber.com", "overture"] and \
    {r["name"] for r in kept} == {"Coborn's"}, kept

# One address, overlapping names, different phones: two places (2026-10-17).
r = merge([rec("Consumer Directions", address="1140 Elm St E Ste A", phone="3202578333"),
           rec("A New Direction", address="1140 Elm St E", phone="+13202576058")])
assert len(r) == 2, names(r)

# A merge keeps the name it started with; it used to take whatever it absorbed last.
r = merge([rec("Omega Force Appliance Repair", address="545 8th Ave NE", phone="17633906267"),
           rec("Kostreba Appliance Services Center", address="545 8th Ave NE",
               phone="+17633906267")])
assert len(r) == 1 and r[0]["name"] == "Omega Force Appliance Repair" and \
    r[0]["aka"] == ["Kostreba Appliance Services Center"], r
assert merge([rec(" Bloom Styling & Events")])[0]["name"] == "Bloom Styling & Events"

# The town's own name is no distinctive word: two Avon places on one phone stay two.
r = merge([rec("City of Avon", phone="320-356-7922"),
           rec("Avon Police Department", phone="320-356-7922")], town_words=["avon"])
assert len(r) == 2, names(r)

# Places sharing a phone, or a street and a word, are asked about. A phone shared by
# more than three places is a switchboard and asks nothing.
roster = merge([rec("Patents Minnesota", phone="3203637296"),
                rec("Quill & Disc", phone="3203637296"),
                rec("AMI", address="30865 Kohler Rd"), rec("Ami Auction", address="30865 Kohler Rd"),
                *(rec(n, phone="320-363-7201") for n in
                  ("City Hall", "Police", "Fire Station", "Klinefelter Park"))])
asked = set(near_duplicates(roster))
assert asked == {("same phone", "Patents Minnesota", "Quill & Disc"),
                 ("same street", "AMI", "Ami Auction")}, asked

# A failed map search is no answer, so the next run asks again.
assert not answered('{"successful": false, "error": "getaddrinfo ENOTFOUND backend.composio.dev"}')
assert not answered("Error: network unreachable")
assert answered('{"successful": true, "data": {"results": {}}}')

# The chamber reader knows one site; another town's chamber gets the plain reader.
try:
    collect_chamber("https://avonchamber.com/members/", Path("/nonexistent"))
    raise AssertionError("read another town's chamber as St. Joseph's")
except RuntimeError as ex:
    assert "stjosephchamber.com" in str(ex), ex

print("census rules OK")
