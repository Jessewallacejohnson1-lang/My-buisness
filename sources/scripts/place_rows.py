#!/usr/bin/env python3
"""Every open registry place with an address becomes a page in the app (BP app place-pages 01).

    python3 sources/scripts/place_rows.py [--town T] [--existing db|FILE|none] [--maps] [--no-fetch]   # dry run
    python3 sources/scripts/place_rows.py --apply                     # writes, after Jesse's yes (service key in env)
    python3 sources/scripts/place_rows.py --selftest

Jesse, 2026-11-08 ("i agree"): every open registry place with an address gets its page, churches, schools, parks and
city offices included; the place type stays a filter. One row per place in `places`, keyed by its registry id
(`entry_id`), with:
  - name and address from the registry (the street as the registry writes it, then the town and ZIP the map gives);
  - its map spot: the registry's `at`, else Overture's point for the same address or the same name in the town
    (CDLA-Permissive, storable; OpenStreetMap and Apple's spots are never stored: sources/README.md, Jesse 2026-11-06).
    A place no map places gets no row yet and is listed;
  - category: `family` (food or business, the app's two) and `primary_type` from the registry's `category`; `types`
    carries the category and the place type (church, school, park, government, community_group, business);
  - links from the registry's sources and the social watch's page list (sources/social/<town>.json): the website's
    home (https before http), then Facebook, then Instagram, one of each;
  - About: the site's own description, word for word, cut at the last full sentence; blank when the site has none.
    The page is read once with run.py's polite fetch and kept in .runs/place-rows/<town>/pages/.

A dry run prints what it would add and what it would change on the rows that exist, each add with where its spot
came from; `--apply` writes. Running it again refreshes facts and never overwrites a field a person set: an
existing row keeps its name, About, logo, hours, Apple id, adults-only flag and spot; only an empty address or
About is filled, and a link kind it lacks is added. So a second run makes no changes.

The Overture read needs the `overturemaps` library (the morning job has it; on a Mac:
`uv run --python 3.12 --with overturemaps --with pyyaml python3 sources/scripts/place_rows.py --maps`); its
answer is kept in .runs/place-rows/<town>/overture.json and read by later runs.
"""
import argparse
import html as htmllib
import json
import os
import re
import struct
import sys
from pathlib import Path
from urllib.parse import quote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402  (the polite fetch)
from db import Db, DbError  # noqa: E402
from registry import STREET_WORDS, find_root, load, place_key  # noqa: E402
from towns import DEFAULT, load_towns, lookup  # noqa: E402

SOURCE = "registry"  # places.source for a row this script made
# What the app calls food (PlaceCategoryMap.swift's food types and its `_restaurant` rule), in the registry's words too.
FOOD = {"restaurant", "fine_dining_restaurant", "bar", "bar_and_grill", "pub", "wine_bar", "night_club", "cafe",
        "coffee_shop", "cafeteria", "tea_house", "bakery", "bagel_shop", "donut_shop", "dessert_shop", "sandwich_shop",
        "meal_takeaway", "meal_delivery", "fast_food_restaurant", "fast_food", "ice_cream_shop", "juice_shop", "brewery",
        "cidery", "winery", "distillery", "food_court", "deli", "diner", "pizza", "ice_cream"}
PLACE_TYPES = {"Business": "business", "Community group": "community_group", "Church": "church",
               "School / college": "school", "Government": "government", "Park / historic": "park"}
SUITE = {"ste", "suite", "unit", "apt", "#", "bldg", "building", "floor", "fl"}
SENTENCE_END = re.compile(r"[.!?]['\")\]]?(?=\s+[A-Z0-9\"'(]|$)")
# A period after one of these ends no sentence ("St. Cloud", "Dr. Platt", "Inc. is").
ABBREVIATIONS = {"st", "mt", "ft", "dr", "mr", "mrs", "ms", "ave", "rd", "blvd", "hwy", "inc", "co", "ltd", "llc", "jr",
                 "sr", "vs", "no", "etc", "e.g", "i.e", "u.s", "p.o"}
TAGLINE = 120  # characters: longer with no full stop is a paragraph cut short, not a tagline
CONNECTORS = {"and", "or", "the", "a", "an", "of", "in", "for", "to", "with", "at", "by", "from", "as", "is", "are", "our",
              "your", "we", "that", "on", "&"}
# Words of a page that stands in for a site: a parked domain or a host's placeholder, never the place's own About.
PLACEHOLDER = re.compile(r"porkbun|godaddy|squarespace|wix\.com|wordpress|this domain|coming soon|under construction|"
                         r"point of sale|^home\s*-\s|^learn more$|^welcome$|^welcome to the .*calendar|\S{30,}", re.I)
META = re.compile(r"<meta\b[^>]*>", re.I)
ATTR = re.compile(r"""([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')""")


# --- one entry, one row ------------------------------------------------------------------------------------------

def link_kind(url):
    host = (urlparse(url).netloc or "").lower()
    if "facebook.com" in host or "fb.com" in host:
        return "facebook"
    if "instagram.com" in host:
        return "instagram"
    return "website"


# A registry page that is one of a site's own inner pages (what the morning watch reads): the link is the site's
# home. A place's page on someone else's site (a Linktree, a Wix address, a clinic's page on its group's site, a
# state park's page) keeps its own URL: its host's home would be a stranger's.
WATCH_PAGE = re.compile(r"^(feeds?|rss|blog|news|events?|calendar|about|contact|resources|pages|company|community-events|"
                        r"closeouts|specials|team)[\w.-]*$", re.I)


def home(url):
    """The site's home for one of its own inner pages (a feed, a blog, an events or news page); a place's page on a
    shared site, as given, without any fragment."""
    p = urlparse(url)
    parts = [s for s in p.path.split("/") if s]
    feedish = "feed" in p.path.lower() or p.path.lower().endswith((".xml", ".rss")) or re.search(r"ical|feed|rss", p.query, re.I)
    if not parts or feedish or any(WATCH_PAGE.match(s) for s in parts):
        return f"{p.scheme}://{p.netloc}/"
    return p._replace(fragment="").geturl()


def links_of(entry, social=()):
    """The page's links: the website's home (https before http), then Facebook, then Instagram, one of each. A
    `TODO` or non-http source is no link. `social`: the social watch's pages for this entry ({kind, url})."""
    found = {}
    urls = [s.get("url") for s in entry.get("sources") or []] + [p.get("url") for p in social]
    for u in urls:
        u = str(u or "").strip()
        if not u.startswith(("http://", "https://")):
            continue
        kind = link_kind(u)
        link = home(u) if kind == "website" else u
        kept = found.get(kind)
        if kept is None or (kept.startswith("http://") and link.startswith("https://")):
            found[kind] = link
    return [{"kind": k, "url": found[k]} for k in ("website", "facebook", "instagram") if k in found]


def category_of(entry):
    """(family, primary_type, types) from the registry's `category` ("amenity=fast_food" is "fast_food") and
    `place_type`. The app's family is food or business; the place type stays a filter in `types`."""
    cat = str(entry.get("category") or "").split("=")[-1].strip().lower().replace("-", "_").replace(" ", "_") or None
    food = cat in FOOD or (cat or "").endswith("_restaurant")
    kind = PLACE_TYPES.get(entry.get("place_type"), "business")
    types = [t for t in (cat, kind) if t]
    return "food" if food else "business", cat, list(dict.fromkeys(types))


def about_of(page):
    """The site's description, word for word: <meta name="description">, else og:description; cut at the last
    full sentence, so a description the site cut short ends whole. One with no sentence at all is kept as it is,
    unless it trails off ("..."); none, blank."""
    descs = {}
    for tag in META.findall(page or ""):
        attrs = {k.lower(): htmllib.unescape(v if v is not None else w) for k, v, w in ATTR.findall(tag)}
        name = (attrs.get("name") or attrs.get("property") or "").lower()
        if name in ("description", "og:description") and attrs.get("content", "").strip():
            descs.setdefault(name, " ".join(attrs["content"].split()))
    text = descs.get("description") or descs.get("og:description") or ""
    return cut_sentence(text)


def sentence_ends(text):
    """Where sentences end in `text`: a full stop, ! or ? before a capital or the end, not one after an
    abbreviation ("St. Cloud") or an initial ("J. Smith")."""
    ends = []
    for m in SENTENCE_END.finditer(text):
        before = re.search(r"([A-Za-z.]+)$", text[:m.start()])
        word = (before.group(1) if before else "").lower().strip(".")
        if m.group(0)[0] == "." and (word in ABBREVIATIONS or len(word) == 1):
            continue
        ends.append(m.end())
    return ends


def cut_sentence(text):
    text = text.strip()
    if not text or PLACEHOLDER.search(text) or len(text.split()) < 3:
        return ""
    if text.endswith(("...", "…")):
        text = text[:-3].rstrip() if text.endswith("...") else text[:-1].rstrip()
        ends = sentence_ends(text)
        return text[:ends[-1]].strip() if ends else ""
    ends = sentence_ends(text)
    if not ends:  # no sentence at all: a tagline stays, a paragraph the site cut mid-sentence goes
        return "" if len(text) > TAGLINE or text.split()[-1].lower() in CONNECTORS else text
    return text[:ends[-1]].strip()


def street_key(address):
    """An address reduced to its street: the part before the first comma, suite and unit dropped, street words
    spelled one way ("710 County Road 75 E Suite 104" and "710 Co Rd 75 E" are one key)."""
    part = (address or "").split(",")[0].lower().replace("’", "'")
    words = re.findall(r"[a-z0-9#']+", part)
    out = []
    for w in words:
        if w in SUITE or (out and w.startswith("#")):
            break
        out.append(STREET_WORDS.get(w, w))
    return " ".join(out)


def row_of(entry, spot, links, about, town):
    """A new `places` row for a registry entry. `spot` is ([lat, lng], source); `town` is the sources/towns/ file."""
    family, primary, types = category_of(entry)
    (lat, lng), _ = spot
    street = str(entry["address"]).split(",")[0].strip()
    where = spot_town(spot, town)
    return {"entry_id": entry["id"], "name": entry["_name"], "address": f"{street}, {where}" if where else street,
            "lat": round(float(lat), 6), "lon": round(float(lng), 6), "family": family, "primary_type": primary,
            "types": types, "source": SOURCE, "about": about or None, "links": links}


def spot_town(spot, town):
    """"St. Joseph, MN 56374" from the map's locality and postcode, else the town's own name and state. The map's
    spelling of the town itself ("St Joseph", "Saint Joseph") gives way to the town file's."""
    _, source = spot
    place = source.get("place") if isinstance(source, dict) else None
    locality = (place or {}).get("locality") or town.get("display")
    if place_key(locality) in {place_key(town.get("display") or ""), place_key(town.get("label") or "")}:
        locality = town.get("display") or locality
    postcode = ((place or {}).get("postcode") or "")[:5]
    state = town.get("state", "MN")
    return f"{locality}, {state} {postcode}".strip() if locality else ""


def refresh(row, entry, links):
    """What changes on a row that exists: an empty address or About filled, a link kind it lacks added. Its name,
    About, logo, hours, Apple id, adults-only flag and spot are a person's, or another ticket's, and stay."""
    change = {}
    if not (row.get("address") or "").strip() and entry.get("address"):
        change["address"] = str(entry["address"]).split(",")[0].strip()
    have = {l.get("kind") for l in row.get("links") or []}
    added = [l for l in links if l["kind"] not in have]
    if added:
        change["links"] = list(row.get("links") or []) + added
    return change


# --- spots -------------------------------------------------------------------------------------------------------

def in_town(place, town):
    """An Overture place inside the town: its ZIP among the town's, or its locality the town's name."""
    zips = {str(z) for z in town.get("zips") or []}
    if (place.get("postcode") or "")[:5] in zips:
        return True
    return place_key(place.get("locality") or "") in {place_key(town.get("display") or ""), place_key(town.get("label") or "")}


def spot_of(entry, overture, town):
    """([lat, lng], {source, ...}) for an entry: the registry's `at`, else Overture's point for the same street in
    the town, else for the same name in the town (one place only); else (None, why not)."""
    at = entry.get("at")
    if isinstance(at, (list, tuple)) and len(at) == 2:
        return [float(at[0]), float(at[1])], {"source": "registry at"}
    if overture is None:
        return None, "maps not read (--maps)"
    key = street_key(entry.get("address"))
    hits = [p for p in overture if p.get("street") == key and in_town(p, town)] if key else []
    if hits:
        p = min(hits, key=lambda h: 0 if place_key(h["name"]) == place_key(entry["_name"]) else 1)
        return [p["lat"], p["lng"]], {"source": "Overture, by address", "place": p}
    names = {place_key(entry["_name"]), *(place_key(a) for a in entry.get("aka") or [])} - {""}
    hits = [p for p in overture if place_key(p["name"]) in names and in_town(p, town)]
    if len({(h["lat"], h["lng"]) for h in hits}) == 1:
        return [hits[0]["lat"], hits[0]["lng"]], {"source": "Overture, by name", "place": hits[0]}
    if hits:
        return None, f"Overture has {len(hits)} places of that name in town"
    return None, "no map has its street or its name in town"


def read_overture(bbox):
    """Overture's places in `bbox` (south, west, north, east): [{name, lat, lng, street, locality, postcode}]."""
    from overturemaps import core
    south, west, north, east = bbox
    out = []
    for batch in core.record_batch_reader("place", bbox=(west, south, east, north)):
        for r in batch.select(["names", "geometry", "addresses"]).to_pylist():
            name, g = (r["names"] or {}).get("primary"), r["geometry"]
            if not name or not g or len(g) < 21:
                continue
            x, y = struct.unpack("<dd" if g[0] == 1 else ">dd", g[5:21])  # a WKB point
            a = (r["addresses"] or [{}])[0] or {}
            out.append({"name": name, "lat": round(y, 6), "lng": round(x, 6), "street": street_key(a.get("freeform")),
                        "freeform": a.get("freeform"), "locality": a.get("locality"), "postcode": a.get("postcode")})
    return out


def overture_places(folder, town, read):
    """Overture's places for the town from `folder`/overture.json, read and saved when `read` or missing."""
    saved = Path(folder) / "overture.json"
    if read or not saved.exists():
        if not read:
            return None
        bbox = town.get("overture_bbox") or town.get("bbox")
        if not bbox:
            sys.exit("the town file has no overture_bbox or bbox to read Overture in")
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_text(json.dumps(read_overture(bbox)))
    return json.loads(saved.read_text())


# --- the plan ----------------------------------------------------------------------------------------------------

def open_places(entries, town_id):
    """The town's open places with an address: not retired, a place (not an event or a feed), an address given."""
    return [e for e in entries if e.get("_town") == town_id and e.get("status") != "retired"
            and e.get("entity", "place") == "place" and str(e.get("address") or "").strip()]


def social_pages(root, town_id):
    f = root / "sources" / "social" / f"{town_id}.json"
    pages = {}
    if f.exists():
        for p in json.loads(f.read_text()):
            pages.setdefault(p.get("entry_id"), []).append(p)
    return pages


def plan(entries, existing, town, town_id, social=None, overture=None, pages=None):
    """(adds, changes, unplaced): rows to add, {row id: fields} to change, and entries with no spot yet. `existing`:
    the `places` rows with an entry_id; `pages`: entry id -> its site's HTML (None for one not read)."""
    social, pages = social or {}, pages or {}
    by_entry = {}
    for r in existing:
        by_entry.setdefault(r.get("entry_id"), []).append(r)
    adds, changes, unplaced = [], {}, []
    for e in open_places(entries, town_id):
        links = links_of(e, social.get(e["id"], ()))
        if e["id"] in by_entry:
            for r in by_entry[e["id"]]:
                change = refresh(r, e, links)
                if change:
                    changes[r["id"]] = {"name": r.get("name"), "entry_id": e["id"], **change}
            continue
        spot = spot_of(e, overture, town)
        if spot[0] is None:
            unplaced.append((e, spot[1]))
            continue
        adds.append({**row_of(e, spot, links, about_of(pages.get(e["id"])), town), "_spot": spot[1]})
    return adds, changes, unplaced


def site_of(links):
    return next((l["url"] for l in links if l["kind"] == "website"), None)


def read_pages(adds_entries, folder, fetch=run.fetch):
    """Each entry's site home, once: kept as .runs/place-rows/<town>/pages/<id>.html (an empty file for a page that
    couldn't be read, so it isn't asked again this run). Returns entry id -> HTML or None."""
    pages, notes = {}, []
    folder = Path(folder) / "pages"
    folder.mkdir(parents=True, exist_ok=True)
    for e, url in adds_entries:
        f = folder / f"{e['id']}.html"
        if not f.exists():
            try:
                status, body = fetch(url)
                f.write_text(body if status == 200 else "")
                if status != 200:
                    notes.append(f"{e['id']}: HTTP {status}")
            except Exception as ex:
                f.write_text("")
                notes.append(f"{e['id']}: {' '.join(str(ex).split())[:120]}")
        text = f.read_text()
        pages[e["id"]] = text or None
    return pages, notes


def existing_rows(db):
    return db.rest("GET", "places?select=id,entry_id,name,address,lat,lon,family,primary_type,types,about,links,"
                          "logo_url,search_logo,hours,apple_place_id,closed_at,source&entry_id=not.is.null") or []


def apply(db, adds, changes):
    """Writes: the adds in one POST, each change its own PATCH. Returns the lines to say."""
    lines = []
    if adds:
        rows = [{k: v for k, v in a.items() if not k.startswith("_")} for a in adds]
        db.rest("POST", "places", rows, prefer="return=minimal")
        lines.append(f"added {len(rows)} places")
    for row_id, change in changes.items():
        fields = {k: v for k, v in change.items() if k not in ("name", "entry_id")}
        db.rest("PATCH", f"places?id=eq.{quote(row_id)}", fields, prefer="return=minimal")
    if changes:
        lines.append(f"changed {len(changes)} rows")
    return lines


def say(adds, changes, unplaced, notes, folder):
    out = [f"Would add {len(adds)} places, change {len(changes)} rows; {len(unplaced)} open places with an address "
           f"have no spot yet, so no row"]
    sources = {}
    for a in adds:
        sources[a["_spot"]["source"]] = sources.get(a["_spot"]["source"], 0) + 1
    out.append("  spots: " + ", ".join(f"{k} {v}" for k, v in sorted(sources.items())))
    out.append(f"  with About {sum(1 for a in adds if a['about'])}, with a website {sum(1 for a in adds if site_of(a['links']))}, "
               f"with Facebook {sum(1 for a in adds if any(l['kind'] == 'facebook' for l in a['links']))}, "
               f"with Instagram {sum(1 for a in adds if any(l['kind'] == 'instagram' for l in a['links']))}, "
               f"food {sum(1 for a in adds if a['family'] == 'food')}")
    for a in adds:
        out.append(f"  + {a['name']} ({a['entry_id']}): {a['address']}; {a['_spot']['source']}; "
                   + ", ".join(l["kind"] for l in a["links"]) + (f"; About: {a['about'][:80]}…" if a["about"] else "; no About"))
    for row_id, c in changes.items():
        out.append(f"  ~ {c['name']} ({c['entry_id']}): " + ", ".join(k for k in c if k not in ("name", "entry_id")))
    for e, why in unplaced:
        out.append(f"  ? {e['_name']} ({e['id']}): {e['address']}: {why}")
    out += [f"  page not read: {n}" for n in notes]
    out.append(f"  plan: {folder}/plan.json")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--town", default=DEFAULT)
    ap.add_argument("--existing", default="db", help="'db', 'none', or a JSON file of the places rows that exist")
    ap.add_argument("--maps", action="store_true", help="read Overture for the town (needs overturemaps)")
    ap.add_argument("--no-fetch", action="store_true", help="don't read any site: About stays blank")
    ap.add_argument("--apply", action="store_true", help="write (service role key in the environment)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    root = find_root(".")
    town = load_towns(root / "sources" / "towns").get(args.town) or lookup(args.town)  # another town's file, in its own root
    entries, errors = load(root)
    if errors:
        sys.exit("\n".join(errors))
    folder = root / ".runs" / "place-rows" / args.town
    folder.mkdir(parents=True, exist_ok=True)
    db = None
    if args.existing == "db" or args.apply:
        db = Db(missing="needs SUPABASE_URL and a key in env (db.py): the publishable key reads, the service key writes")
        existing = existing_rows(db)
    elif args.existing == "none":
        existing = []
    else:
        existing = json.loads(Path(args.existing).read_text())
    overture = overture_places(folder, town, args.maps)
    social = social_pages(root, args.town)
    have = {r.get("entry_id") for r in existing}
    new = [e for e in open_places(entries, args.town) if e["id"] not in have]
    pages, notes = {}, []
    if not args.no_fetch:
        sites = [(e, site_of(links_of(e, social.get(e["id"], ())))) for e in new]
        pages, notes = read_pages([(e, u) for e, u in sites if u], folder)
    adds, changes, unplaced = plan(entries, existing, town, args.town, social, overture, pages)
    (folder / "plan.json").write_text(json.dumps({"adds": adds, "changes": changes,
                                                  "unplaced": [(e["id"], why) for e, why in unplaced]}, indent=1, default=str))
    print("\n".join(say(adds, changes, unplaced, notes, folder)))
    if args.apply:
        if not db.keys.get("Authorization"):
            sys.exit("--apply needs the service role key (SUPABASE_SERVICE_ROLE_KEY), not the publishable key")
        print("\n".join(apply(db, adds, changes)))


# --- self-test ---------------------------------------------------------------------------------------------------

def selftest():
    import tempfile
    town = {"display": "Stubville", "zips": ["56999"], "bbox": [45.5, -94.4, 45.6, -94.2]}
    krewe = {"id": "krewe", "_name": "Krewe", "_town": "stub-mn", "status": "active", "address": "25 1st Ave NW, Suite 200",
             "category": "restaurant", "place_type": "Business", "aka": ["Krewe Restaurant"],
             "sources": [{"url": "http://krewemn.com/events", "kind": "website", "method": "fetch"},
                         {"url": "https://krewemn.com/", "kind": "website", "method": "fetch"},
                         {"url": "https://www.facebook.com/krewerestaurant/", "kind": "facebook", "method": "submission"}]}
    church = {"id": "church", "_name": "Church of Stubville", "_town": "stub-mn", "status": "proposed", "address": "100 Oak St",
              "category": "amenity=place_of_worship", "place_type": "Church", "at": [45.55, -94.3],
              "sources": [{"url": "TODO", "kind": "website", "method": "submission"}]}
    nowhere = {"id": "far", "_name": "Far Shop", "_town": "stub-mn", "status": "active", "address": "9 Nowhere Rd",
               "sources": [{"url": "TODO", "method": "submission"}]}
    retired = {**krewe, "id": "old", "_name": "Old", "status": "retired"}
    no_address = {**krewe, "id": "bare", "_name": "Bare", "address": ""}
    overture = [{"name": "Krewe Restaurant", "lat": 45.5651, "lng": -94.3187, "street": street_key("25 First Avenue NW"),
                 "freeform": "25 First Avenue NW", "locality": "Stubville", "postcode": "56999"},
                {"name": "Krewe Restaurant", "lat": 46.0, "lng": -95.0, "street": street_key("25 1st Ave NW"),
                 "freeform": "25 1st Ave NW", "locality": "Elsewhere", "postcode": "55555"}]
    social = {"krewe": [{"kind": "instagram", "url": "https://www.instagram.com/krewemn"}]}
    page = ('<html><head><meta property="og:description" content="Shared words"><meta content="Cajun &amp; Creole in '
            'Stubville. Open for dinner Tue to Sat. Reservations…" name="description"></head></html>')
    checks = []

    assert links_of(krewe, social["krewe"]) == [{"kind": "website", "url": "https://krewemn.com/"},
                                               {"kind": "facebook", "url": "https://www.facebook.com/krewerestaurant/"},
                                               {"kind": "instagram", "url": "https://www.instagram.com/krewemn"}], \
        "links: the site's home, https before http, then Facebook, then Instagram, the social list's included"
    assert links_of(church) == [], "a TODO source is no link"
    assert home("https://adarahomehealth.com/feed/") == "https://adarahomehealth.com/" \
        and home("https://x.com/blog-feed.xml") == home("https://x.com/events/?ical=1") == home("https://x.com/pages/news") == "https://x.com/" \
        and home("https://gcremn.com/24-north-lofts/") == "https://gcremn.com/24-north-lofts/" \
        and home("https://linktr.ee/annereneebridalco") == "https://linktr.ee/annereneebridalco" \
        and home("https://kwelz.clientsecure.me/#home") == "https://kwelz.clientsecure.me/" \
        and home("https://www.gutters.com/about-us/news-and-events.html") == "https://www.gutters.com/", \
        "a site's own feed, blog, events or about page gives its home; a place's page on a shared site stays"
    assert cut_sentence("Home - St. Cloud Area School District 742") == "" \
        and cut_sentence("Toast is a restaurant point of sale and management system that helps restaurants.") == "" \
        and cut_sentence("Craftsman.Green breathable wood flooringInstallationRefinishingInlayTodd Theisen is a craftsman.") == "", \
        "a page title, a platform's own words or run-together words are no About"
    assert category_of(krewe) == ("food", "restaurant", ["restaurant", "business"]) \
        and category_of(church) == ("business", "place_of_worship", ["place_of_worship", "church"]) \
        and category_of({"category": "amenity=fast_food"}) == ("food", "fast_food", ["fast_food", "business"]) \
        and category_of({}) == ("business", None, ["business"]), "family, type and the place type as a filter"
    assert about_of(page) == "Cajun & Creole in Stubville. Open for dinner Tue to Sat.", \
        "About: the description, entities read, cut at the last full sentence before its trailing-off"
    assert about_of('<meta name="description" content="Family owned since 1982">') == "Family owned since 1982" \
        and about_of("<html></html>") == "" and about_of(None) == "" \
        and about_of('<meta name="description" content="Welcome to our...">') == "", "a whole short line stays; none, blank"
    assert cut_sentence("Window cleaning in St. Cloud, MN. Call J. Smith at 320-555-0100 for a") == "Window cleaning in St. Cloud, MN." \
        and cut_sentence("Serving the greater St. Cloud area since 1961") == "Serving the greater St. Cloud area since 1961" \
        and cut_sentence("For over 28 years the trusted choice for window cleaning, gutter cleaning and power washing in St. Cloud and") == "" \
        and cut_sentence("Brought to you by Porkbun.") == "" and cut_sentence("Learn More") == "", \
        "St. and an initial end no sentence; a parked domain's words or two words are no About"
    assert street_key("710 County Road 75 E Suite 104") == street_key("710 Co Rd 75 E") == "710 co rd 75 e" \
        and street_key("25 1st Ave NW, Suite 200") == street_key("25 First Avenue NW") == "25 1st ave nw" \
        and street_key("15 E Minnesota St Ste 105A") == "15 e minnesota st", "one street, one key"

    spot, why = spot_of(krewe, overture, town)
    assert spot == [45.5651, -94.3187] and why["source"] == "Overture, by address", f"the same street in town: {why}"
    assert spot_of(church, overture, town) == ([45.55, -94.3], {"source": "registry at"}), "the registry's at first"
    assert spot_of(nowhere, overture, town)[0] is None and spot_of(nowhere, None, town) == (None, "maps not read (--maps)")
    by_name = spot_of({**krewe, "address": "1 Other St"}, overture, town)
    assert by_name[0] == [45.5651, -94.3187] and by_name[1]["source"] == "Overture, by name", "else the name, in town only"

    adds, changes, unplaced = plan([krewe, church, nowhere, retired, no_address], [], town, "stub-mn", social, overture,
                                   {"krewe": page})
    assert [a["entry_id"] for a in adds] == ["krewe", "church"] and [e["id"] for e, _ in unplaced] == ["far"], \
        f"open places with an address and a spot become rows; retired and bare ones don't: {adds}, {unplaced}"
    k = adds[0]
    assert spot_town(([0, 0], {"source": "Overture, by address", "place": {"locality": "Stub-ville", "postcode": "56999-1234"}}), town) \
        == "Stubville, MN 56999" and spot_town(([0, 0], {"source": "Overture, by address", "place": {"locality": "Elsewhere"}}), town) \
        == "Elsewhere, MN", "the town's own spelling of itself; another town's name stays"
    assert k["name"] == "Krewe" and k["address"] == "25 1st Ave NW, Stubville, MN 56999" and k["family"] == "food" \
        and k["source"] == SOURCE and k["about"].startswith("Cajun") and len(k["links"]) == 3 and k["lat"] == 45.5651, k
    assert adds[1]["address"] == "100 Oak St, Stubville, MN" and adds[1]["about"] is None and adds[1]["links"] == [], adds[1]

    # The rows exist, one with a hand-set About and a logo and a hand-trimmed name: a second run keeps them.
    rows = [{"id": "r1", "entry_id": "krewe", "name": "Krewe (hand)", "address": k["address"], "about": "By hand.",
             "logo_url": "x", "links": [{"kind": "website", "url": "https://krewemn.com/"}]},
            {"id": "r2", "entry_id": "church", "name": "Church", "address": "", "about": None, "links": []}]
    adds2, changes2, _ = plan([krewe, church, nowhere], rows, town, "stub-mn", social, overture, {"krewe": page})
    assert adds2 == [] and set(changes2) == {"r1", "r2"}, changes2
    assert set(changes2["r1"]) == {"name", "entry_id", "links"} \
        and [l["kind"] for l in changes2["r1"]["links"]] == ["website", "facebook", "instagram"], \
        f"a hand About, name and logo stay; missing link kinds are added: {changes2['r1']}"
    assert changes2["r2"] == {"name": "Church", "entry_id": "church", "address": "100 Oak St"}, "an empty address is filled"
    rows2 = [{**rows[0], "links": changes2["r1"]["links"]}, {**rows[1], "address": "100 Oak St"}]
    assert plan([krewe, church, nowhere], rows2, town, "stub-mn", social, overture, {"krewe": page})[:2] == ([], {}), \
        "the run after that changes nothing"

    # Another town's file, three places, goes through the same door: a stub repo in a temp folder.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "sources" / "towns").mkdir(parents=True)
        (root / "sources" / "towns" / "stub-mn.yaml").write_text("label: Stubville MN\ndisplay: Stubville\nphoto_slug: stub\nzips: ['56999']\n")
        (root / "sources" / "stub-mn.md").write_text("---\nschema: 1\ntown: stub-mn\n---\n" + "".join(
            f"## {n}\n```yaml\nid: {i}\nstatus: proposed\ntier: listed\naddress: \"{i} Main St\"\ncategory: {c}\nat: [45.5{k}, -94.3]\n"
            f"sources:\n  - url: TODO\n    method: submission\n```\n"
            for k, (n, i, c) in enumerate([("Stub Bakery", "stub-bakery", "bakery"), ("Stub Hall", "stub-hall", "gov"),
                                          ("Stub Park", "stub-park", "leisure=park")])))
        entries, errors = load(root)
        import yaml
        stub_town = yaml.safe_load((root / "sources" / "towns" / "stub-mn.yaml").read_text())
        a3, c3, u3 = plan(entries, [], stub_town, "stub-mn")
        assert not errors and len(a3) == 3 and not c3 and not u3 and a3[0]["address"] == "stub-bakery Main St, Stubville, MN" \
            and a3[0]["family"] == "food" and a3[2]["types"] == ["park", "business"], (errors, a3)
        got, notes = read_pages([(entries[0], "https://stub/")], root / ".runs" / "place-rows" / "stub-mn",
                                fetch=lambda url: (200, page))
        assert got == {"stub-bakery": page} and notes == [] \
            and (root / ".runs" / "place-rows" / "stub-mn" / "pages" / "stub-bakery.html").exists(), "a page is kept under the town"
        again, notes = read_pages([(entries[0], "https://stub/"), (entries[1], "https://down/")],
                                  root / ".runs" / "place-rows" / "stub-mn", fetch=lambda url: (_ for _ in ()).throw(RuntimeError("robots.txt disallows")))
        assert again == {"stub-bakery": page, "stub-hall": None} and notes == ["stub-hall: robots.txt disallows"], "kept pages aren't fetched again"

    class FakeDb:
        def __init__(self):
            self.calls = []

        def rest(self, method, path, body=None, prefer=None):
            self.calls.append((method, path, body))

    fake = FakeDb()
    said = apply(fake, adds, changes2)
    assert said == ["added 2 places", "changed 2 rows"] and fake.calls[0][0] == "POST" and fake.calls[0][1] == "places" \
        and all(not k.startswith("_") for k in fake.calls[0][2][0]) and fake.calls[1] == ("PATCH", "places?id=eq.r1", {"links": changes2["r1"]["links"]}) \
        and fake.calls[2] == ("PATCH", "places?id=eq.r2", {"address": "100 Oak St"}), fake.calls
    print("place_rows: selftest ok")


if __name__ == "__main__":
    main()
