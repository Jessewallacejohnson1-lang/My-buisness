#!/usr/bin/env python3
"""
resolve_google_place_ids.py — find Google's own place id for each `places` row that only
has a local one (`stjoe-*`), once, so the app can ask Google for a place's photos by id
(the cheap IDs-only tier) instead of searching for it on every visit.

For each such row: Text Search "<name> St Joseph MN", then the first of the top five hits
that clears Locked Rule A against the row's name and coordinate (ported 1:1 from
`RuleA` in BlockParty/Backend/GooglePlacesService.swift: names must align; 90 m when they
merely align, 400 m on an exact name, 2 km on an exact name of a park, trail or campus).
A row nothing clears is left without one. Place ids may be persisted (Google's ToS);
nothing else from Google is.

    python3 scripts/resolve_google_place_ids.py            # resolve; writes build/google-place-ids.json + .sql
    python3 scripts/resolve_google_place_ids.py --selftest # Rule A port, no network

The .sql holds one UPDATE per resolved row, for `places.google_place_id`. Keys are parsed
from the gitignored Swift config files.
"""
from __future__ import annotations

import json
import math
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"
BUNDLE_ID = "Jesse.BlockParty"  # the Places key is restricted to the app's bundle id


def parse_swift_constant(path: Path, pattern: str) -> str:
    m = re.search(pattern, path.read_text())
    if not m:
        sys.exit(f"could not parse key from {path}")
    return m.group(1)


# ---------- Locked Rule A, ported ----------

FUZZY_M, EXACT_M, LARGE_M = 90, 400, 2_000
LARGE_TYPES = {"park", "city_park", "nature_preserve", "hiking_area", "route", "university"}
MIN_TOKEN = 5


def normalize(s: str) -> str:
    return "".join(c if (c.isalnum() or c == " ") else " " for c in s.lower())


def tokens(s: str) -> set[str]:
    return {t for t in s.split() if len(t) >= MIN_TOKEN}


def names_align(a: str, b: str) -> bool:
    return a in b or b in a or bool(tokens(a) & tokens(b))


def metres(lat1, lon1, lat2, lon2) -> float:
    r = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def clears(resolved_name, rlat, rlon, types, primary, curated_name, clat, clon) -> bool:
    resolved, curated = normalize(resolved_name), normalize(curated_name)
    if not resolved.strip() or not curated.strip():
        return False
    d = metres(rlat, rlon, clat, clon)
    if resolved == curated:
        large = primary in LARGE_TYPES or any(t in LARGE_TYPES for t in types)
        return d <= (LARGE_M if large else EXACT_M)
    return names_align(resolved, curated) and d <= FUZZY_M


def selftest():
    assert clears("Bad Habit Brewing Company", 45.5640, -94.3180, [], None, "Bad Habit Brewing Company", 45.5641, -94.3181)
    assert not clears("Bad Habit Brewing Company", 45.5640, -94.3180, [], None, "Bad Habit Brewing Company", 45.60, -94.3180)
    assert clears("Krewe Restaurant", 45.5640, -94.3180, [], None, "Krewe", 45.5643, -94.3182)       # contains, 40 m
    assert not clears("Krewe Restaurant", 45.5640, -94.3180, [], None, "Krewe", 45.5660, -94.3180)   # contains, 220 m
    assert not clears("Memorial Park", 45.56, -94.32, ["park"], "park", "Monument Park", 45.56, -94.32)
    assert clears("Centennial Park", 45.56, -94.32, ["park"], "park", "Centennial Park", 45.57, -94.32)  # 1.1 km, park
    assert not clears("", 45.56, -94.32, [], None, "Anything", 45.56, -94.32)
    print("selftest ok")


# ---------- the run ----------

def main():
    google_key = parse_swift_constant(ROOT / "BlockParty" / "Config" / "GooglePlacesConfig.swift", r'"([A-Za-z0-9_\-]{30,})"')
    supabase_url = parse_swift_constant(ROOT / "BlockParty" / "Backend" / "SupabaseConfig.swift", r'"(https://[a-z0-9]+\.supabase\.co)"')
    anon = parse_swift_constant(ROOT / "BlockParty" / "Backend" / "SupabaseConfig.swift", r'"(eyJ[A-Za-z0-9_\-\.]+)"')

    req = urllib.request.Request(f"{supabase_url}/rest/v1/places?select=id,place_id,name,lat,lon&order=name",
                                 headers={"apikey": anon, "Authorization": f"Bearer {anon}"})
    rows = [r for r in json.load(urllib.request.urlopen(req, timeout=20)) if not (r["place_id"] or "").startswith("ChIJ")]

    found, missed = [], []
    for row in rows:
        body = json.dumps({"textQuery": f"{row['name']} St Joseph MN", "regionCode": "us",
                           "locationBias": {"circle": {"center": {"latitude": row["lat"], "longitude": row["lon"]}, "radius": 15000}}}).encode()
        search = urllib.request.Request("https://places.googleapis.com/v1/places:searchText", data=body, headers={
            "Content-Type": "application/json", "X-Goog-Api-Key": google_key, "X-Ios-Bundle-Identifier": BUNDLE_ID,
            "X-Goog-FieldMask": "places.id,places.location,places.displayName,places.primaryType,places.types"})
        hits = json.load(urllib.request.urlopen(search, timeout=20)).get("places", [])[:5]
        hit = next((h for h in hits if clears(h.get("displayName", {}).get("text", ""), h["location"]["latitude"], h["location"]["longitude"],
                                               h.get("types", []), h.get("primaryType"), row["name"], row["lat"], row["lon"])), None)
        if hit:
            found.append({"id": row["id"], "place_id": row["place_id"], "name": row["name"], "google_place_id": hit["id"],
                          "google_name": hit["displayName"]["text"],
                          "metres": round(metres(hit["location"]["latitude"], hit["location"]["longitude"], row["lat"], row["lon"]))})
        else:
            missed.append({"id": row["id"], "name": row["name"], "top": [h.get("displayName", {}).get("text") for h in hits[:3]]})
        print(("ok   " if hit else "miss ") + row["name"] + (f"  ->  {hit['displayName']['text']}" if hit else ""), flush=True)

    OUT.mkdir(exist_ok=True)
    (OUT / "google-place-ids.json").write_text(json.dumps({"found": found, "missed": missed}, indent=1))
    # Both values come from Google and our own table, and are checked to be plain ids
    # before they go into SQL.
    for f in found:
        assert re.fullmatch(r"[A-Za-z0-9_-]+", f["google_place_id"]) and re.fullmatch(r"[0-9a-f-]{36}", f["id"]), f
    sql = "".join(f"update public.places set google_place_id = '{f['google_place_id']}' where id = '{f['id']}';\n" for f in found)
    (OUT / "google-place-ids.sql").write_text(sql)
    print(f"{len(found)} resolved, {len(missed)} not -> {OUT / 'google-place-ids.json'}")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
