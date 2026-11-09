"""Spots the registry doesn't give, where Overture and OpenStreetMap agree (BP app inside-cards 20).

    python3 sources/scripts/find_spots.py "Pierz High School MAC GYM" …   # what each line finds (reads both maps)
    python3 sources/scripts/find_spots.py --selftest

Jesse, 2026-11-06 (inside-cards 06): no Apple spots, since Apple's terms forbid storing them or drawing them
on our Mapbox map. A place line the registry doesn't know gets a spot by itself when Overture and
OpenStreetMap agree, and the morning report lists it. When only one of them knows the place, the Event keeps
opening Apple Maps (Jesse, 2026-11-07).

Both maps are whole-state files, read once a morning by the Finish step (`spots.fill`), because Nominatim,
Overpass and Photon all disallow scripts in their robots rules (checked 2026-11-07):
  - Overture's places in Minnesota's box, through its own library from its open S3 bucket (CDLA-Permissive-2.0:
    storable). About 25 s for 425,000 places.
  - OpenStreetMap's Minnesota file from Geofabrik, whose download server has no robots rules (290 MB). Its
    named places, buildings and grounds take about 65 s and 1.2 GB.
Only Overture's point is stored. OpenStreetMap only confirms it, since a database made from OpenStreetMap
must be shared under its own licence.

A line agrees when:
  1. Its place is the part before the first comma. A last part naming a town keeps the answer in that town:
     Overture's town for it, or within 6 km of OpenStreetMap's ("Majestic Oaks Golf Course, Ham Lake"; "Heritage
     Park, Sartell" isn't St. Cloud's).
  2. The place is cut back to a word like School, Arena or Center, longest first, so "Pierz High School MAC
     GYM" asks for "Pierz High School". Every word left must be in both answers' names, in order, except the, of, and,
     at, area, public, senior, school, course and club ("Cloquet Senior High School", "Majestic Oaks Golf
     Club"). A cut ending at School needs its High, Middle or Elementary, so "Maple Lake Public Schools" can't
     answer for a whole town.
  3. Overture's point lies within 300 m of OpenStreetMap's place, or of its outline's box for grounds.
  4. Every agreeing answer lies within 1.5 km of the others: a chain ("Coborn's") or a common name
     ("Marshall High School") agrees in several towns and gets no spot, and so does a name over 50 places hold.
An Online line ("Online", "Zoom webinar") or a bare town names no one place (`nowhere`): the Event page shows
no Map button there. A town's name that is also a place's own ("Lake George", St. Cloud's park) isn't bare.
"""
import argparse
import json
import math
import re
import struct
import subprocess
import sys
import time
import urllib.request
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import STREET_WORDS, TOWN_KEYS, place_key  # noqa: E402
from run import UA  # noqa: E402

NOWHERE = "nowhere"  # a line that names no one place, as opposed to one no map knows yet
BOX = (-97.24, 43.50, -89.49, 49.38)  # Minnesota: west, south, east, north
OSM_FILE = "https://download.geofabrik.de/north-america/us/minnesota-latest.osm.pbf"
NEAR, ONE_PLACE, TOWN_KM, COMMON = 300, 1500, 6, 50  # metres, metres, km, places: rules 3, 4, 1 and 4

ONLINE = {"online", "virtual", "zoom", "webinar", "livestream"}
ONLINE_TOO = {"event", "only", "via", "on", "meeting", "class", "and", "or", "the"}  # "Online via Zoom", not "Zoom Room"
# Rule 2's words. HEADS end a place's name; FILLER needn't be in an answer's name; a cut needs at least one
# word that isn't GENERIC.
HEADS = {"school", "schools", "arena", "center", "centre", "university", "college", "academy", "complex", "hall",
         "fieldhouse", "rink", "forum", "stadium", "church", "park", "zoo"}
LEVELS = {"high", "middle", "elementary", "primary", "intermediate", "secondary", "junior"}
FILLER = {"the", "of", "and", "at", "area", "public", "senior", "school", "schools", "course", "club"}
GENERIC = HEADS | LEVELS | FILLER | {
    "main", "gym", "gyms", "gymnasium", "court", "courts", "field", "house", "community", "aux", "auxiliary",
    "pool", "ice", "room", "building", "activity", "activities", "varsity", "st", "hs", "ms", "athletics",
    "civic", "recreation", "golf", "memorial", "sports"}
# What OpenStreetMap calls a place, not a road or a river; and its towns.
OSM_KEYS = ("amenity", "leisure", "building", "tourism", "shop", "craft", "office", "historic", "sport",
            "healthcare", "club", "landuse", "man_made", "military")
OSM_TOWNS = {"city", "town", "village"}  # not hamlets or localities: OpenStreetMap names camps and resorts so


def words(text):
    """A name as words to compare: lower case, no apostrophes, & as and, saint and street words one way."""
    t = (text or "").lower().replace("’", "'").replace("'", "").replace("&", " and ")
    return [{"brother": "br"}.get(w, STREET_WORDS.get(w, w)) for w in re.findall(r"[a-z0-9]+", t)]


def metres(a, b):
    x = math.radians(b[1] - a[1]) * math.cos(math.radians((a[0] + b[0]) / 2))
    return 6371000 * math.hypot(x, math.radians(b[0] - a[0]))


def to_box(p, box):
    """Metres from point p to box [south, west, north, east] (0 inside it)."""
    return metres(p, (min(max(p[0], box[0]), box[2]), min(max(p[1], box[1]), box[3])))


def in_order(want, ws):
    """Every word of `want` in `ws`, in the same order: "High Speed Internet Osseo" isn't Osseo High School."""
    it = iter(ws)
    return all(w in it for w in want)


def cuts(ws):
    """Rule 2: the words each answer's name must hold, for each cut of the place, longest first."""
    ends = {len(ws)} | {i + 1 for i, w in enumerate(ws) if w in HEADS and i >= 1}
    for n in sorted(ends, reverse=True):
        need = [w for w in ws[:n] if w not in FILLER]
        whole = n == len(ws)
        if (whole or ws[n - 1] not in ("school", "schools") or any(w in LEVELS for w in need)) \
                and any(w not in GENERIC and len(w) >= 3 for w in need):
            yield need


class Names:
    """Rows [name, …] looked up by every word of their names."""

    def __init__(self, rows):
        self.rows, self.by_word = rows, defaultdict(set)
        for i, r in enumerate(rows):
            for w in set(words(r[0])):
                self.by_word[w].add(i)

    def having(self, ws):
        """The rows whose names hold every word of ws, in that order."""
        found = None
        for s in sorted((self.by_word.get(w, set()) for w in ws), key=len):
            found = set(s) if found is None else found & s
            if not found:
                break
        return [self.rows[i] for i in sorted(found or ()) if in_order(ws, words(self.rows[i][0]))]


class Maps:
    """Both maps, in the compact form `read` saves: Overture [name, lat, lng, town], OpenStreetMap places
    [name, south, west, north, east] and towns [name, lat, lng]."""

    def __init__(self, overture, osm, towns):
        self.overture, self.osm = Names(overture), Names(osm)
        self.towns = defaultdict(list)
        for name, lat, lng in towns:
            self.towns["".join(words(name))].append((lat, lng))
        self.named = {"".join(words(r[0])) for r in overture + osm}  # every place's own name

    def nowhere(self, part):
        """An Online part or a bare town: the registry's few, else a Minnesota town no place is named."""
        key = "".join(words(part))
        return is_nowhere(part) or key in self.towns and key not in self.named

    def find(self, line):
        """([lat, lng], why) for a place line where both maps agree, NOWHERE, or (None, why not)."""
        parts = [p.strip() for p in (line or "").split(",") if p.strip()]
        if not parts:
            return None, "no place line"
        if all(self.nowhere(p) for p in parts):  # "St. Cloud, MN" too
            return NOWHERE, "names no one place"
        if words(parts[0])[:1] == ["downtown"]:
            return None, "a downtown is a spot chosen by hand (sources/spots/)"
        town_key = "".join(words(parts[-1])) if len(parts) > 1 else None
        town = self.towns.get(town_key)
        in_town = lambda v: not town or "".join(words(v[3])) == town_key \
            or min(metres((v[1], v[2]), t) for t in town) <= TOWN_KM * 1000
        for need in cuts(words(parts[0])):
            overture, osm = self.overture.having(need), self.osm.having(need)
            if len(overture) > COMMON or len(osm) > COMMON:
                return None, f"{' '.join(need)!r} is in too many places' names"
            hits = [(v, o) for v in overture if in_town(v) for o in osm if to_box((v[1], v[2]), o[1:5]) <= NEAR]
            if not hits:
                continue
            points = [(v[1], v[2]) for v, _ in hits]
            if max(metres(a, b) for a in points for b in points) > ONE_PLACE:
                towns = sorted({v[3] or "?" for v, _ in hits})
                return None, f"{' '.join(need)!r} agrees in several places ({', '.join(towns[:4])})"
            line = set(words(parts[0]))  # the name adding fewest words: the school, not its stadium or tennis courts
            v, o = min(hits, key=lambda h: (len(set(words(h[0][0])) - line), len(words(h[0][0]))))
            return [v[1], v[2]], f"Overture's {v[0]!r} ({v[3]}), OpenStreetMap's {o[0]!r}"
        return None, "the maps don't agree"


def is_nowhere(line):
    """An Online line or one of the registry's bare towns ("St. Cloud, MN" too): works without the maps."""
    ws, parts = words(line), [p for p in (line or "").split(",") if words(p)]
    online = bool(set(ws) & ONLINE) and set(ws) <= ONLINE | ONLINE_TOO
    return bool(ws) and (online or all(place_key(p) in TOWN_KEYS for p in parts))


# --- reading the maps -------------------------------------------------------------------------------------

def read_overture():
    """Overture's places in Minnesota's box: [name, lat, lng, town]."""
    from overturemaps import core
    out = []
    for batch in core.record_batch_reader("place", bbox=BOX):
        for r in batch.select(["names", "geometry", "addresses"]).to_pylist():
            name, g = (r["names"] or {}).get("primary"), r["geometry"]
            if not name or not g or len(g) < 21:
                continue
            x, y = struct.unpack("<dd" if g[0] == 1 else ">dd", g[5:21])  # a WKB point
            out.append([name, round(y, 5), round(x, 5), ((r["addresses"] or [{}])[0] or {}).get("locality")])
    return out


def read_osm(pbf):
    """OpenStreetMap's named places as [name, south, west, north, east], and its towns as [name, lat, lng]."""
    import osmium

    class Reader(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.places, self.towns = [], []

        def node(self, n):
            name = n.tags.get("name")
            if name and n.tags.get("place") in OSM_TOWNS:
                self.towns.append([name, round(n.location.lat, 5), round(n.location.lon, 5)])
            elif name and any(k in n.tags for k in OSM_KEYS):
                lat, lng = round(n.location.lat, 5), round(n.location.lon, 5)
                self.places.append([name, lat, lng, lat, lng])

        def area(self, a):  # a building or grounds: a closed way or a multipolygon
            name = a.tags.get("name")
            if not name or "highway" in a.tags or not any(k in a.tags for k in OSM_KEYS):
                return
            points = [(p.lat, p.lon) for ring in a.outer_rings() for p in ring]
            if points:
                lats, lngs = [p[0] for p in points], [p[1] for p in points]
                self.places.append([name, *(round(x, 5) for x in (min(lats), min(lngs), max(lats), max(lngs)))])

    reader = Reader()
    reader.apply_file(str(pbf), locations=True, idx="flex_mem")
    return reader.places, reader.towns


def save_maps(folder):
    """Both maps into `folder`/maps.json, whole or not at all. The 290 MB file is deleted once read."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    pbf = folder / "minnesota.osm.pbf"
    req = urllib.request.Request(OSM_FILE, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r, open(pbf, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    osm, towns = read_osm(pbf)
    pbf.unlink()
    spare = folder / "maps.json.new"
    spare.write_text(json.dumps({"overture": read_overture(), "osm": osm, "towns": towns}))
    spare.replace(folder / "maps.json")


def last_line(text):
    """What a stopped process said last, the exception's own line: the report shows a message's first 200 characters,
    and the end of a traceback's last 300 had its cause cut off (the Nov 8 and 9 mornings)."""
    lines = [l.strip() for l in (text or "").splitlines() if l.strip()]
    return lines[-1][:160] if lines else "no message"


def read(folder, fresh_hours=20, minutes=7):
    """Maps from `folder`/maps.json, saved first when it's missing or older than `fresh_hours`. The saving runs
    as a process of its own, stopped after `minutes`: a cloud that runs out of memory or time ends it with an
    error here, never the morning's Finish (which would then run again into the same wall)."""
    saved = Path(folder) / "maps.json"
    if not saved.exists() or (time.time() - saved.stat().st_mtime) / 3600 > fresh_hours:
        r = subprocess.run([sys.executable, __file__, "--save-maps", str(folder)], capture_output=True, text=True,
                           timeout=minutes * 60)
        if r.returncode:
            raise RuntimeError(f"reading the maps stopped ({r.returncode}): {last_line(r.stderr or r.stdout)}")
    d = json.loads(saved.read_text())
    return Maps(d["overture"], d["osm"], d["towns"])


# --- self-test ---------------------------------------------------------------------------------------------

def selftest():
    overture = [["Pierz Healy High School", 45.9800, -94.1000, "Pierz"],
                ["Pierz High School Tennis Courts", 45.9805, -94.1010, "Pierz"],
                ["Majestic Oaks Golf Club", 45.2222, -93.2522, "Ham Lake"],
                ["Majestic Oaks Kennel", 45.5153, -93.6563, "Zimmerman"],
                ["Falls High School", 48.6000, -93.4000, "International Falls"],
                ["Fergus Falls High School", 46.2883, -96.0676, "Fergus Falls"],
                ["Bemidji Community Food Shelf", 47.4700, -94.8800, "Bemidji"],
                ["Coborn's", 45.5681, -94.2972, "St Joseph"], ["Coborn's", 45.3000, -93.5600, "Big Lake"],
                ["Maple Lake Post Office", 45.2290, -94.0010, "Maple Lake"],
                ["Brother Willie's Pub", 45.5810, -94.3920, "Collegeville"],
                ["Northern Hollow Winery", 45.6571, -93.9454, "Foley"],
                ["High Speed Internet Osseo", 45.1210, -93.4000, "Osseo"], ["Osseo Senior High School", 45.1205, -93.4022, "Osseo"],
                ["Chanhassen High Stadium", 44.8472, -93.5764, "Chanhassen"], ["Chanhassen High School", 44.8475, -93.5780, "Chanhassen"]]
    osm = [["Pierz Healy High School", 45.9790, -94.1020, 45.9815, -94.0990],
           ["Majestic Oaks Golf Club", 45.2115, -93.2591, 45.2298, -93.2397],  # the course's outline
           ["Falls High School", 48.5995, -93.4005, 48.6005, -93.3995],  # Fergus Falls' isn't in OpenStreetMap
           ["Bemidji Community Food Shelf", 47.4701, -94.8801, 47.4701, -94.8801],
           ["Coborn's", 45.5682, -94.2973, 45.5682, -94.2973], ["Coborn's", 45.3001, -93.5601, 45.3001, -93.5601],
           ["Maple Lake Post Office", 45.2291, -94.0011, 45.2291, -94.0011],
           ["Brother Willie's Pub", 45.5811, -94.3921, 45.5811, -94.3921],
           ["Northern Hollow Winery", 45.7938, -93.0852, 45.7938, -93.0852],  # the other branch, 75 km off
           ["Osseo Senior High School", 45.1195, -93.4035, 45.1215, -93.3995],
           ["Chanhassen High", 44.8460, -93.5790, 44.8490, -93.5750]]
    overture += [["Heritage Park", 45.5380, -94.1900, "St Cloud"], ["Lake George", 45.5544, -94.1628, "St Cloud"]]
    osm += [["Heritage Park", 45.5375, -94.1905, 45.5385, -94.1895], ["Lake George", 45.5540, -94.1630, 45.5548, -94.1625]]
    towns = [["Ham Lake", 45.2502, -93.2050], ["Pierz", 45.9814, -94.1025], ["St. Cloud", 45.5608, -94.1622],
             ["Foley", 45.6647, -93.9097], ["Sartell", 45.6216, -94.2069], ["Lake George", 47.2000, -94.9900]]
    maps = Maps(overture, osm, towns)
    cases = [
        ("Pierz High School MAC GYM", [45.98, -94.1], "a gym is its school, and the plainest name wins"),
        ("Majestic Oaks Golf Course, Ham Lake", [45.2222, -93.2522], "Overture's pin inside the course's outline"),
        ("Majestic Oaks Golf Course, Pierz", None, "not within 12 km of the town the line names"),
        ("Fergus Falls High School Gold Gym", None, "one map only: no spot, not International Falls"),
        ("Bemidji Community Arena", None, "every word counts: a food shelf isn't an arena"),
        ("Coborn's", None, "a chain agrees in several towns"),
        ("Maple Lake Public Schools High School Gym", None, "a cut at Schools needs its High"),
        ("Br. Willies Pub", [45.581, -94.392], "Br. is Brother"),
        ("Osseo High School Main Gym", [45.1205, -93.4022], "the school, not a shop with its words out of order"),
        ("Chanhassen High School Gym 3", [44.8475, -93.5780], "the school, not its stadium"),
        ("Northern Hallow Winery, Foley", None, "a misspelt name agrees nowhere"),
        ("Online", NOWHERE, "online"), ("St. Cloud", NOWHERE, "a bare town"), ("Ham Lake", NOWHERE, "any town"),
        ("Lake George", [45.5544, -94.1628], "a town's name that is also a place's own is that place"),
        ("St. Cloud, Lake George Park", None, "a town first isn't a bare town"),
        ("Heritage Park, Sartell", None, "not St. Cloud's, 9 km off"),
        ("Zoom Room, St. Cloud", None, "a room called Zoom isn't online"),
        ("Downtown St. Cloud", None, "a downtown is chosen by hand"), ("", None, "no line"), (None, None, "no line"),
    ]
    failed = 0
    for line, want, why in cases:
        got, said = maps.find(line)
        if got != want:
            failed += 1
            print(f"FAIL {why}: {line!r} -> {got} ({said}), want {want}")
    for line, want in (("Zoom webinar", True), ("Online via Zoom", True), ("St. Joseph", True), ("St. Cloud, MN", True),
                       ("Online Store Pickup Lot", False), ("Virtual Reality Center", False),
                       ("St. Cloud, Lake George Park", False), ("", False)):
        if is_nowhere(line) != want:
            failed += 1
            print(f"FAIL is_nowhere({line!r}) is {not want}")
    boom = "urllib.error.URLError: <urlopen error [Errno -3] Temporary failure in name resolution>"
    for text, want in (('Traceback (most recent call last):\n  File "x.py", line 1, in do_open\n    raise URLError(err)\n' + boom + "\n", boom),
                       ("", "no message"), (None, "no message")):
        if last_line(text) != want:
            failed += 1
            print(f"FAIL last_line({text!r}) is {last_line(text)!r}")
    print(f"{len(cases) + 11 - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("lines", nargs="*")
    ap.add_argument("--maps", default=str(Path(__file__).resolve().parents[1] / ".runs" / "spots"),
                    help="where the maps are kept between runs (a day)")
    ap.add_argument("--save-maps", metavar="FOLDER", help="read both maps into FOLDER/maps.json (what read() runs)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.save_maps:
        return save_maps(args.save_maps)
    maps = read(args.maps)
    for line in args.lines:
        print(line, "->", *maps.find(line))


if __name__ == "__main__":
    main()
