#!/usr/bin/env python3
"""
discover.py — build the town roster, and report what the registry is missing.

ADR-010 makes completeness the goal and says coverage is measured against an external
count of what exists, never against what we already hold. This is that external count.

It reads four kinds of source and merges them into one roster:

  * OpenStreetMap, via the Overpass API — the only machine-readable full-coverage list.
  * Local directory pages (joetown.org/explore, the chamber member directory) — curated,
    and better than OSM at knowing which places are actually trading.
  * Pages that disallow robots — reported as agent tasks, never fetched (ADR-001).
  * The registry itself, to subtract what we already have.

It writes `proposed` entries ONLY, and never touches an existing entry. Per ADR-008 an
agent may not set `active`; per ADR-010 Jesse promotes `listed` entries in batches.

Dedupe is deliberately timid. Names that normalise to exactly the same string are merged.
Anything merely SIMILAR is reported as a possible duplicate for a human to settle and is
NOT merged — a wrongly merged pair silently deletes a business from the town, which is
the one failure mode this whole script exists to prevent.

Attribution: OpenStreetMap data is ODbL. Any surface built on this roster owes
"© OpenStreetMap contributors". The `source` field on every record carries provenance so
OSM-derived rows stay identifiable.
"""

import argparse, html, json, re, sys, time, unicodedata
import urllib.error
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path
from urllib.parse import urlparse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from run import fetch, UA

# Overpass is a free, donated, frequently-overloaded service. 504s are routine and mean
# "busy", not "broken", so try the mirrors in turn before giving up.
# kumi first because it is the one that reliably answers this query; overpass-api.de
# 504s under load most afternoons. overpass.osm.ch is DELIBERATELY ABSENT: on
# 2026-09-23 it returned HTTP 200 with zero elements in 0.6s for a bbox the other
# mirrors answer with 200+. A mirror that returns a confident empty answer is worse
# than one that errors, because an empty roster reads as "nothing is missing".
OVERPASS_MIRRORS = [
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]
# Everything that could be useful to a neighbour, not just businesses (ADR-010).
OSM_KEYS = ["shop", "amenity", "office", "craft", "tourism", "healthcare",
            "leisure", "club", "historic"]
NEAR_DUPLICATE = 0.87        # SequenceMatcher ratio; above this we ASK, never merge

# ADR-013: places and events are separate things. Directory pages list both in one grid,
# so names that read like an occurrence are ROUTED to an events draft, never dropped — a
# place misfiled as an event is still a missing place (ADR-010), and only a human can
# settle "Woodfired Wednesdays".
EVENTISH = re.compile(
    r"\b(fest|festival|crawl|rocks|rocktoberfest|series|celebration|parade|"
    r"mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays|"
    r"days|nights|market day|reunion|fundraiser|benefit|tournament|expo|fair)\b",
    re.I)


def looks_like_event(name):
    return bool(EVENTISH.search(name))

TOWNS = {
    "st-joseph-mn": {
        # South, west, north, east. Covers the city plus the immediate fringe, because
        # Milk & Honey is out on County Road 51 and still very much St. Joe.
        "bbox": (45.540, -94.360, 45.590, -94.280),
        # Floor for the silent-empty guard. Measured 202-204 elements on 2026-09-23,
        # so half that is comfortably below real data and well above a broken mirror.
        "osm_min_elements": 100,
        # Pairs confirmed DISTINCT by a human, so the duplicate report stops asking.
        # Recurring false positives train people to skim the report, which is how a real
        # duplicate gets waved through.
        # Confirmed SAME place under different names. First entry of each group is the
        # name that survives; the rest fold into it. This is the roster-side twin of an
        # entry's `aka:` — `aka` settles a roster name against the registry, this settles
        # two roster names against each other, before either becomes an entry.
        "aliases": [
            ["The Wandering Cow", "Wandering Cow Ice Cream"],
            ["Sal's Bar and Grill", "Sal's Bar", "Sals Bar and Grill"],
            ["Flour & Flower Bakery", "Flour & Flower", "Flower + Flour Bakery"],
        ],
        "known_distinct": [
            # Jesse, 2026-09-23: "sju for mens, cbs is womens" — two colleges, two
            # athletics programmes, and they must never be merged.
            ("csb athletic activities", "sju athletic activities"),
        ],
        "directories": [
            {"id": "joetown", "url": "https://www.joetown.org/explore"},
            # Readable after all (ADR-014). It was written off as blocking us because
            # RobotFileParser read robots.txt with urllib's default user-agent, got a
            # throttling 403, and turned that into disallow-all. Its robots.txt actually
            # permits everyone and asks for Crawl-delay: 10, which the fetcher now obeys.
            {"id": "chamber", "url": "https://stjosephchamber.com/member-directory/",
             "collector": "chamber"},
        ],
        # Known robots refusals. Listed so they show up as work rather than vanishing.
        # The fix for a robots block is search_snippet, never a workaround (ADR-001).
        # stjosephmn.gov/9/Business is NOT here: it is fetchable (ADR-012) and was
        # checked — it holds bid opportunities, permits and zoning, no business list.
        # A fetchable page with nothing on it is not a roster source.
        # Nothing is agent-only for this town any more. stjosephmn.gov is fetchable
        # (ADR-012) and its /9/Business page holds permits and zoning, not a business
        # list; the chamber is fetchable too (ADR-014).
        "agent_only": [],
    }
}

# Link-farm and infrastructure hosts that appear on every page and are never a business.
NOISE_HOSTS = ("squarespace", "sqspcdn", "typekit", "googleapis", "gstatic",
               "fonts.", "facebook.com/sharer", "twitter.com/intent", "youtube.com",
               "instagram.com/p/", "cdn.", "w3.org", "schema.org")


def norm(name):
    """Fold a business name to a comparison key. Aggressive on purpose."""
    s = unicodedata.normalize("NFKD", html.unescape(str(name)))
    s = s.encode("ascii", "ignore").decode().lower().replace("&", " and ")
    # "Saint Joseph Meat Market" and "St. Joseph Meat Market" are one butcher. This is
    # the town's name, so it appears in a lot of business names and is worth folding.
    s = re.sub(r"\bsaint\b", "st", s)
    # Apostrophes are DELETED, not spaced. A curly one is dropped by the ascii fold
    # above while a straight one would survive to become a space, so "Sal's" and
    # "Sal’s" normalised to different keys and the same bar appeared twice.
    s = s.replace("\u2019", "").replace("'", "")
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    # "and" goes with the articles: "Flour & Flower" becomes "flour and flower" while
    # "Flower + Flour" becomes "flower flour", and that single connector token was
    # enough to propose the same bakery twice. Connectors are not identity.
    s = re.sub(r"\b(the|a|an|and)\b", " ", s)
    s = re.sub(r"\b(llc|inc|co|company|corp|ltd|the)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def match_key(name):
    """Merge key: the normalised words, SORTED.

    Word order is not identity. joetown.org lists "Flower + Flour Bakery" and the
    registry calls the same shop "Flour & Flower Bakery"; on a plain normalised string
    those are different places and the bakery gets proposed a second time. Comparing
    the token SET catches the swap. Token-set identity is still a strong claim — every
    word has to be present — so this stays on the safe side of merging.
    """
    return " ".join(sorted(norm(name).split()))


def osm_category(tags):
    for k in OSM_KEYS:
        if k in tags:
            return f"{k}={tags[k]}"
    return None


def collect_osm(bbox, min_elements, cache=None, max_age_days=7, refresh=False):
    s, w, n, e = bbox
    # ONE key-regex pass, not one query per key. Nine separate nwr statements timed
    # every mirror out; this returns the same features in a single traversal.
    query = (f'[out:json][timeout:60];'
             f'nwr[~"^({"|".join(OSM_KEYS)})$"~"."]({s},{w},{n},{e});'
             f'out tags center;')
    # Overpass is donated infrastructure and this query takes over a minute. Cache it:
    # the roster is a monthly job, and a town's shops do not turn over in an afternoon.
    if cache and not refresh and cache.exists():
        age = (datetime.now(timezone.utc).timestamp() - cache.stat().st_mtime) / 86400
        if age < max_age_days:
            data = json.loads(cache.read_text())
            print(f"[discover] osm: using cache, {age:.1f}d old (--refresh to re-fetch)")
            return _osm_records(data, min_elements, "cache")

    last = None
    for endpoint in OVERPASS_MIRRORS:
        req = urllib.request.Request(
            endpoint, data=urllib.parse.urlencode({"data": query}).encode(),
            headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = json.load(r)
            break
        except Exception as ex:
            last = f"{urlparse(endpoint).netloc}: {ex}"
    else:
        raise RuntimeError(f"all Overpass mirrors failed (last: {last})")

    recs = _osm_records(data, min_elements, urlparse(endpoint).netloc)
    if cache:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(data))
    return recs


def _osm_records(data, min_elements, where):
    if len(data.get("elements", [])) < min_elements:
        # A confident empty answer is the dangerous failure: it makes MISSING smaller
        # and the registry look more complete than it is, which is the one thing
        # ADR-010 measures. Treat "implausibly few" as an outage, not as truth.
        raise RuntimeError(
            f"only {len(data.get('elements', []))} elements from "
            f"{where} (expected >= {min_elements}) — treating as an "
            f"outage rather than an empty town")
    out = []
    for el in data.get("elements", []):
        tags = el.get("tags", {})
        name = tags.get("name")
        if not name:
            continue                       # unnamed features are geometry, not places
        out.append({
            "name": name,
            "category": osm_category(tags),
            "website": tags.get("website") or tags.get("contact:website"),
            "lat": el.get("lat") or (el.get("center") or {}).get("lat"),
            "lon": el.get("lon") or (el.get("center") or {}).get("lon"),
            "source": "osm",
        })
    return out


CHAMBER_CATEGORY = re.compile(r'href="(https://stjosephchamber\.com/member/category/[^"]+/)"')
CHAMBER_MEMBER = re.compile(
    r'href="(https://stjosephchamber\.com/member/(?!category/)[^"/]+/)"[^>]*>(.*?)</a>', re.S)


def fetch_patiently(url, tries=2, base_wait=30):
    """fetch() with backoff on 403.

    Two tries, not four. When this host decides to throttle it applies a cooldown far
    longer than any backoff we would sit through, so extra retries add load to a small
    chamber's server and change nothing. Give up early and let the next run pick it up.

    stjosephchamber.com answers 200 when approached at its stated pace and 403 when it
    decides you are going too fast — the same URL, minutes apart. A 403 here is a
    "slow down", not a "go away": its robots.txt has no Disallow at all. So back off
    and try again rather than recording the source as blocked, which is the mistake
    that hid this directory for two days.
    """
    last = None
    for attempt in range(tries):
        try:
            return fetch(url)
        except urllib.error.HTTPError as ex:
            if ex.code != 403:
                raise
            last = ex
            if attempt < tries - 1:
                wait = base_wait * (attempt + 1)
                print(f"[discover] 403 from {urlparse(url).netloc}, waiting {wait}s "
                      f"(attempt {attempt + 2}/{tries})")
                time.sleep(wait)
    raise last


def collect_chamber(url, cache=None, max_age_days=30, refresh=False,
                    budget_seconds=600):
    """Two levels: the directory lists categories, each category lists its members.

    The directory page itself carries only category names and counts — the member list
    is rendered client-side, so fetching the one page yields nothing. The category pages
    DO carry their members in the HTML, so this walks them. 22 categories at the
    Crawl-delay: 10 the site asks for is about four minutes; it is a monthly job.
    """
    # 22 category pages at Crawl-delay 10, plus backoff when the host pushes back, is
    # minutes not seconds. Cache it for a month: chamber membership moves slowly and this
    # is a monthly job. --refresh forces the walk.
    if cache and not refresh and cache.exists():
        age = (datetime.now(timezone.utc).timestamp() - cache.stat().st_mtime) / 86400
        if age < max_age_days:
            print(f"[discover] chamber: using cache, {age:.1f}d old (--refresh to re-walk)")
            return json.loads(cache.read_text())

    deadline = time.monotonic() + budget_seconds
    # Our IP is BLOCKED by this host — earned on 2026-09-23 by ignoring its
    # Crawl-delay while iterating parser code against the live site, and still in
    # force a day later. Direct fetching is therefore not the route any more:
    # `harvest_chamber.py --harvest` pulls the pages through Firecrawl and writes the
    # cache this function reads. Fail with that instruction rather than hammering a
    # host that has already said no.
    raise RuntimeError(
        "chamber cache missing or stale, and this IP is blocked by stjosephchamber.com. "
        "Run: python3 sources/scripts/harvest_chamber.py --root . --harvest --parse")

    _status, index = fetch_patiently(url)  # unreachable; kept for when the block lifts
    cats = sorted(set(CHAMBER_CATEGORY.findall(index)))
    print(f"[discover] chamber: walking {len(cats)} categories at the site's stated pace",
          flush=True)
    out, seen = [], set()
    for cat in cats:
        slug = cat.rstrip("/").rsplit("/", 1)[-1]
        if time.monotonic() > deadline:
            # Partial beats nothing, and beats grinding. A run that sat in backoff for
            # 14 minutes without finishing one category is the site telling us to come
            # back later, not a problem to push through.
            print(f"[discover] chamber: {budget_seconds}s budget spent, stopping with "
                  f"{len(out)} members — rerun later for the rest", flush=True)
            break
        try:
            _st, page = fetch_patiently(cat)
        except Exception as ex:
            print(f"[discover] chamber category {slug}: {ex}")
            continue
        for href, anchor in CHAMBER_MEMBER.findall(page):
            name = re.sub(r"\s+", " ", TAGS.sub(" ", html.unescape(anchor))).strip()
            if len(re.sub(r"[^A-Za-z0-9]", "", name)) < 3 or len(name) > 60:
                continue
            k = norm(name)
            if not k or k in seen:
                continue
            seen.add(k)
            out.append({"name": name, "category": slug, "website": None,
                        "lat": None, "lon": None, "source": "stjosephchamber.com"})
        print(f"[discover]   {slug}: {len(out)} members so far", flush=True)
    # Only cache a COMPLETE walk. Caching a partial one for a month would freeze the
    # roster at whatever the throttle happened to allow that afternoon.
    if cache and out and time.monotonic() <= deadline:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(out))
    return out


LINK = re.compile(r'<a\b[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>', re.S | re.I)
TAGS = re.compile(r"<[^>]+>")


def collect_directory(url):
    """Anchor text on a directory page is almost always the business name."""
    # fetch() returns (status, decoded_text) — NOT bytes. Unpacking it as one value and
    # calling str() on the tuple parsed the tuple's repr, which is why anchor text came
    # back carrying the two-character sequence backslash-n and produced entries named
    # "\n \n \n". The junk filter below stays as hygiene, but this was the cause.
    _status, html_text = fetch(url)
    host = urlparse(url).netloc
    out, seen = [], set()
    for href, anchor in LINK.findall(html_text):
        if any(h in href for h in NOISE_HOSTS) or host in href:
            continue
        name = html.unescape(TAGS.sub(" ", anchor))
        # joetown.org embeds JSON in places, so some anchor text arrives with the
        # two-character sequence backslash-n rather than a real newline. Those must go
        # BEFORE the "has real letters" test below, or the n's count as letters and
        # entries named "\n \n \n \n" sail through it — which is exactly what happened.
        name = re.sub(r"\\+[nrt]", " ", name)
        name = re.sub(r"\s+", " ", name).strip()
        # Anchor text that is only whitespace, or the literal characters "\n", survives
        # tag-stripping and became three entries named "\n \n \n". Require real letters.
        if len(re.sub(r"[^A-Za-z0-9]", "", name)) < 3 or len(name) > 60:
            continue
        if name.lower() in ("read more", "learn more", "website", "click here", "home"):
            continue
        key = norm(name)
        if not key or key in seen:
            continue
        seen.add(key)
        out.append({"name": name, "category": None, "website": href,
                    "lat": None, "lon": None, "source": urlparse(url).netloc})
    return out


def build_alias_map(groups):
    """alias key -> canonical (key, display name). Empty when a town declares none."""
    out = {}
    for group in groups or ():
        canon = group[0]
        for name in group:
            out[match_key(name)] = (match_key(canon), canon)
    return out


def merge(records, aliases=None):
    """Exact normalised-name matches collapse. Nothing else does."""
    aliases = aliases or {}
    by_key = {}
    for r in records:
        k = match_key(r["name"])
        if k in aliases:
            k, canon_name = aliases[k]
            r = dict(r, name=canon_name)   # one place, one name
        if not k:
            continue
        if k in by_key:
            cur = by_key[k]
            cur["sources"] = sorted(set(cur["sources"] + [r["source"]]))
            for f in ("category", "website", "lat", "lon"):
                if cur.get(f) is None:
                    cur[f] = r.get(f)
        else:
            r = dict(r)
            r["sources"] = [r.pop("source")]
            r["key"] = k
            r["display_key"] = norm(r["name"])
            by_key[k] = r
    return list(by_key.values())


def near_duplicates(roster, known_distinct=()):
    """Report pairs a human should look at. Never merged automatically."""
    out, keys = [], [r["key"] for r in roster]
    toks = [set(k.split()) for k in keys]
    settled = {frozenset((match_key(a), match_key(b))) for a, b in known_distinct}
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = keys[i], keys[j]
            # A strict subset is the shape of "Sal's Bar" against "Sal's Bar and Grill",
            # or "The Wandering Cow" against "Wandering Cow Ice Cream" — usually one
            # place written two ways, but NOT always ("Memorial Park" is not "Park"),
            # so it is reported and never merged. Needs 2+ shared words to be worth
            # raising at all.
            if frozenset((a, b)) in settled:
                continue
            if toks[i] and toks[j] and toks[i] != toks[j] and \
               (toks[i] < toks[j] or toks[j] < toks[i]) and min(len(toks[i]), len(toks[j])) >= 2:
                out.append((1.0, roster[i]["name"], roster[j]["name"]))
                continue
            if frozenset((a, b)) in settled:
                continue
            if abs(len(a) - len(b)) > 12:
                continue
            ratio = SequenceMatcher(None, a, b).ratio()
            if ratio >= NEAR_DUPLICATE:
                out.append((round(ratio, 3), roster[i]["name"], roster[j]["name"]))
    return sorted(out, reverse=True)


def entry_md(rec):
    slug = re.sub(r"[^a-z0-9]+", "-", rec["key"]).strip("-")[:40]
    url = rec.get("website") or "TODO"
    method = "fetch" if url != "TODO" else "submission"
    lines = [f"## {rec['name']}", "```yaml", f"id: {slug}", "status: proposed",
             "tier: listed"]
    if rec.get("category"):
        lines.append(f"category: {rec['category']}")
    lines += ["added_by: agent:discover", "sources:",
              f"  - url: {url}", "    kind: website", f"    method: {method}",
              "    trust: official", "```"]
    prov = ", ".join(rec["sources"])
    geo = (f" Mapped at {rec['lat']:.5f}, {rec['lon']:.5f}."
           if rec.get("lat") and rec.get("lon") else "")
    todo = ("" if url != "TODO" else
            " No URL was found, so this is `submission`: it waits on the owner rather "
            "than guessing an address (ADR-007).")
    lines.append(f"Notes: Proposed by discovery on {datetime.now(timezone.utc):%Y-%m-%d} "
                 f"from {prov}.{geo}{todo} Unreviewed — tier `listed`, so it publishes "
                 f"nothing until promoted.")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--root", default=".")
    ap.add_argument("--refresh", action="store_true",
                    help="ignore the cached Overpass result and re-fetch")
    args = ap.parse_args()

    town = TOWNS.get(args.town)
    if not town:
        sys.exit(f"no discovery config for town {args.town!r}")

    root = find_root(args.root)
    entries, _ = load(root)
    have = {match_key(e["_name"]) for e in entries}
    have |= {match_key(e.get("id", "").replace("-", " ")) for e in entries}
    # `aka:` is how a human settles "same place, different name" permanently. No rule can
    # know that Kennedy Elementary and Kennedy Community School are one school, so the
    # entry says so and discovery stops re-proposing it every month (ADR-007: additive).
    for e in entries:
        for alias in (e.get("aka") or []):
            have.add(match_key(alias))

    records, notes = [], []
    try:
        osm = collect_osm(town["bbox"], town.get("osm_min_elements", 1),
                          cache=Path(root) / ".runs" / "cache" / f"osm-{args.town}.json",
                          refresh=args.refresh)
        records += osm
        notes.append(f"osm: {len(osm)} named")
    except Exception as ex:
        notes.append(f"osm: FAILED ({ex})")

    for d in town["directories"]:
        try:
            got = (collect_chamber(d["url"],
                                   cache=Path(root) / ".runs" / "cache" / "chamber.json",
                                   refresh=args.refresh)
                   if d.get("collector") == "chamber"
                   else collect_directory(d["url"]))
            records += got
            notes.append(f"{d['id']}: {len(got)}")
        except Exception as ex:
            notes.append(f"{d['id']}: FAILED ({ex})")

    alias_map = build_alias_map(town.get("aliases"))
    roster = merge(records, alias_map)
    missing = [r for r in roster if r["key"] not in have]
    events = [r for r in missing if looks_like_event(r["name"])]
    places = [r for r in missing if not looks_like_event(r["name"])]
    dupes = near_duplicates(roster, town.get("known_distinct", ()))

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out_dir = Path(root) / ".runs" / f"discover-{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "roster.json").write_text(json.dumps(roster, indent=1, ensure_ascii=False))
    (out_dir / "proposed.md").write_text(
        "\n\n".join(entry_md(r) for r in sorted(places, key=lambda r: r["name"])))
    (out_dir / "events.md").write_text(
        "# Looks like an EVENT, not a place (ADR-013)\n\n"
        "Routed here rather than dropped. The test is a heuristic and it is wrong in both\n"
        "directions — move anything that is really a place back into the town file.\n\n"
        + "\n".join(f"- {r['name']}  ({', '.join(r['sources'])})"
                    for r in sorted(events, key=lambda r: r["name"])))

    # A stable path beside the timestamped run, so the newest lists are findable without
    # knowing today's timestamp. The dated folders stay as the history.
    latest = Path(root) / ".runs" / "latest"
    try:
        if latest.is_symlink() or latest.exists():
            latest.unlink()
        latest.symlink_to(out_dir, target_is_directory=True)
    except OSError:
        pass

    print(f"[discover] {'  '.join(notes)}")
    print(f"roster {len(roster)} | registry {len(entries)} | MISSING {len(missing)}"
          f"  ({len(places)} places, {len(events)} look like events)")
    coverage = 100 * (len(roster) - len(missing)) / max(len(roster), 1)
    print(f"coverage {coverage:.0f}% of the roster is in the registry")
    for a in town.get("agent_only", []):
        print(f"  AGENT   {a['id']}: {a['url']} — {a['why']}")
    if dupes:
        print(f"  {len(dupes)} possible duplicate pair(s) — NOT merged, settle by hand:")
        for ratio, a, b in dupes[:15]:
            print(f"    {ratio}  {a!r} ~ {b!r}")
    print(f"draft places: {out_dir / 'proposed.md'}")
    if events:
        print(f"likely events: {out_dir / 'events.md'} — {len(events)}, review by hand")


if __name__ == "__main__":
    main()
