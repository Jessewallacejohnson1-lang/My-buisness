#!/usr/bin/env python3
"""
gone_places.py: once a month, check half the open places Apple Maps can't see, and hide the ones two checks call gone
(BP app watch-every-place 33).

The morning's Apple Maps check (apple_maps.py) never reads a place with no `apple_place_id`; American Burger Bar
(closed 2018) and 20 more gone places hid there until ticket 32's sweep. Two separate checks, as ticket 32 ran them:
(1) one Google Maps search per place (maps.py, SerpAPI, cached), (2) an agent's web research that never sees Google's
answer. Only both saying gone hides a place (Jesse, 2026-11-09), and never one with Events in the last 90 days or
ahead, Jesse's word in its registry Notes, or an `inside:` host; a double is listed for Jesse, never hidden.

Half the places each month (Jesse, 2026-11-20), so every place is seen every two months and SerpAPI's 250 a month,
shared with town-discovery, keeps room: a run over MAX_SEARCHES stops before searching.

    python3 sources/scripts/gone_places.py pick   <dir> [--month 2026-12]  # free: this month's half -> <dir>/pick.json
    python3 sources/scripts/gone_places.py google <dir>                    # SerpAPI: <dir>/google.json, <dir>/brief.txt
      ... hand brief.txt to a research agent; save its JSON list as <dir>/agent.json ...
    python3 sources/scripts/gone_places.py decide <dir> [--retire]         # the lists, a sample, <dir>/hide.sql
    python3 sources/scripts/gone_places.py --selftest

`pick` and `decide` read the live database with the key in the environment (db.py); nothing here writes to it.
hide.sql goes in a migration, applied on Jesse's yes for the first batch (a random sample shown first), then under
the two-check rule. The morning report lists the hides (apple_maps.unseen_hides).
"""
import argparse, hashlib, json, random, re, socket, sys
from urllib.parse import urlparse
from datetime import date, timedelta
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))


SKIP = {"the", "and", "inc", "llc", "joseph", "saint", "st", "of", "co", "company"}


def words(s):
    return {w for w in re.findall(r"[a-z0-9]+", (s or "").lower()) if len(w) > 2 and w not in SKIP}


def city(address):
    """'2010 County Road 75, St. Joseph, MN 56374' -> 'st joseph'; '' when the address names none."""
    parts = [p.strip() for p in (address or "").split(",")]
    m = next((parts[i - 1] for i, p in enumerate(parts) if i and re.match(r"(MN|Minnesota)\b", p)), "")
    return re.sub(r"\bsaint\b", "st", re.sub(r"[^a-z ]", "", m.lower())).strip()


def google_says(place, hits):
    """One Google Maps answer, read the way ticket 32 read it: 'open', 'closed', 'not found' or 'other town'."""
    w = words
    if not words(place["name"]):  # a short name (BP, MN 511): its every word counts
        w = lambda s: set(re.findall(r"[a-z0-9]+", (s or "").lower()))
    ours = w(place["name"])
    if not ours:
        return "unclear"
    share = lambda h: len(ours & w(h.get("title"))) / max(1, len(ours))
    best = max(hits, key=share, default=None)
    if not best or share(best) < 0.5:
        return "not found"
    if "permanently closed" in json.dumps(best).lower():
        return "closed"
    home, there = city(place.get("address")) or "st joseph", city(best.get("address"))
    return "other town" if there and there != home else "open"


def pick(rows, month):
    """This month's half (Jesse, 2026-11-20: "check half the places each month"): a place's id picks
    odd or even months for good, so every place is seen every two months and a new place joins a side."""
    odd = int(month[-2:]) % 2
    return [r for r in rows if hashlib.sha1(r["id"].encode()).digest()[0] % 2 == odd]


GONE = {"closed", "not found", "other town"}


def decide(places, google, agent, entries, busy):
    """Each checked place Google calls gone, sorted: 'hide' (both checks say gone), 'kept' (a rule keeps it),
    'doubles' and 'one check' (listed for Jesse). Each item is (place, why)."""
    out = {"hide": [], "kept": [], "doubles": [], "one check": []}
    for p in places:
        g = google.get(p["id"])
        if g not in GONE:
            continue
        a = agent.get(p["id"]) or {"agent": "unclear"}
        e = entries.get(p.get("entry_id")) or {}
        if a["agent"] == "double":
            out["doubles"].append((p, f"Google: {g}; agent: a double of {a.get('of') or '?'}"))
        elif a["agent"] != "gone":
            out["one check"].append((p, f"Google: {g}; agent: {a['agent']}"))
        elif p.get("entry_id") in busy:
            out["kept"].append((p, "both say gone, but it has Events in the last 90 days or ahead"))
        elif "jesse" in (e.get("notes") or "").lower():
            out["kept"].append((p, "both say gone, but its registry Notes carry Jesse's word"))
        elif e.get("inside"):
            out["kept"].append((p, f"both say gone, but it runs inside {e['inside']}"))
        else:
            out["hide"].append((p, f"Google: {g}; agent: gone"))
    return out


# Notes run to the next blank line or heading: they wrap over lines.
ENTRY = re.compile(r"^## [^\n]*\n```yaml\n(.*?)\n```\n(?:(Notes:.*?)(?=\n\n|\n## |\n?\Z)\n?)?", re.M | re.S)


def entry_notes(text):
    """{entry id: {inside, notes}} from a town file; registry.py never parses Notes, and these rules read them."""
    out = {}
    for m in ENTRY.finditer(text):
        data = yaml.safe_load(m.group(1)) or {}
        out[str(data.get("id"))] = {"inside": data.get("inside"), "notes": (m.group(2) or "")[len("Notes: "):]}
    return out


def retire(text, entry_id, why, day):
    """The town file with one entry retired and why in its Notes (README: never delete an entry)."""
    for m in ENTRY.finditer(text):
        if not re.search(rf"^id: {re.escape(entry_id)}$", m.group(1), re.M):
            continue
        block = re.sub(r"^status: .*$", "status: retired", m.group(1), count=1, flags=re.M)
        if "status: retired" not in block:
            block = block.replace(f"id: {entry_id}", f"id: {entry_id}\nstatus: retired", 1)
        note = (f"Retired {day} by the monthly check of places Apple Maps can't see: {why}; "
                "hidden in the app (`places.closed_at`) (BP app watch-every-place 33).")
        notes = f"{m.group(2)} {note}" if m.group(2) else f"Notes: {note}"
        start = m.start() + m.group(0).index("```yaml")
        return text[:start] + f"```yaml\n{block}\n```\n{notes}\n" + text[m.end():]
    raise KeyError(f"no registry entry {entry_id}")


BRIEF = """Research whether each place below, in or near {town}, is still open. Use web search and the place's own
website and social pages: local news (WJON, St. Cloud Times), a goodbye post, its newest post's date, what business is
at its address now, state licences, the Secretary of State. Do not use or look up Google Maps or Apple Maps: another
check reads those, and your answer must stand on its own.

- A post, an event or an ad from the last 90 days means it is open.
- A business that is part of another place at the same address (a chair in a salon, a kitchen in a food hall) is
  open, not a double. A double is a second record for one and the same business: name which.
- A record that was never a place (a sales page, a home-based seller with no storefront, one agent's home address)
  counts as gone.

Answer with only a JSON list, one object per place:
[{{"id": "<id>", "agent": "gone" | "open" | "double" | "unclear", "of": "<the other record, for a double>",
  "when": "<closing date if known>", "evidence": "<two sentences>", "sources": ["<url>", ...]}}]

Places:
{places}"""


def brief(places, town="St. Joseph, Minnesota"):
    """What a research agent gets: the places, without Google's answer (ticket 32: two separate checks)."""
    lines = []
    for p in places:
        sites = [l["url"] for l in (p.get("links") or []) if l.get("url")]
        lines.append(f"- id {p['id']}: {p['name']}, {p.get('address') or 'no address on file'}"
                     + (f"; pages on file: {', '.join(sites)}" if sites else ""))
    return BRIEF.format(town=town, places="\n".join(lines))


def hide_sql(hides):
    """A migration that hides the places both checks call gone, as ticket 32's did."""
    out = ["-- Places Apple Maps can't see that Google Maps and an agent's separate research both call gone (BP app",
           "-- watch-every-place 33, the monthly check). Registry entries retired. None has Events in the last 90 days or ahead.",
           "-- Undo one: set its closed_at back to null (no apple_place_id, so the morning won't hide it again).", ""]
    for p, why in hides:
        out += [f"-- {p['name']}: {why}",
                f"update public.places set closed_at = now() where id = '{p['id']}' and closed_at is null;"]
    return "\n".join(out) + "\n"


def street(address):
    return re.sub(r"[^a-z0-9]", "", (address or "").split(",")[0].lower())


def resolves(host):
    try:
        socket.gethostbyname(host)
        return True
    except OSError:
        return False


def hints(p, rows, entries, resolves=resolves):
    """Ticket 32's free hints, listed beside the checks and never a verdict: the website's domain gone, and another
    place of the same kind at the address that Apple Maps knows (not for an `inside:` entry, which shares its host's)."""
    out = []
    sites = [l["url"] for l in (p.get("links") or []) if l.get("kind") == "website" and l.get("url")]
    if sites and not resolves(urlparse(sites[0]).hostname or ""):
        out.append("website domain gone")
    if not (entries.get(p.get("entry_id")) or {}).get("inside") and street(p.get("address")):
        same = [r["name"] for r in rows if r.get("apple_place_id") and r["id"] != p["id"]
                and street(r.get("address")) == street(p.get("address")) and r.get("primary_type") == p.get("primary_type")]
        out += [f"same address as {n} (on Apple Maps)" for n in same]
    return out


MAX_SEARCHES = 75   # of SerpAPI's 250 a month; 118 places / 2 = about 59 today


def every_row(db, path):
    """Every row of a read, PostgREST answering at most 1,000 at a time."""
    rows = []
    while True:
        got = db.rest("GET", f"{path}&order=id&limit=1000&offset={len(rows)}") or []
        rows += got
        if len(got) < 1000:
            return rows


def busy_entries(db, today):
    """Entry ids with an Event or a News in the last 90 days or ahead (Heim-kins, ticket 32: a Facebook event kept it)."""
    since = today - timedelta(days=90)
    ev = every_row(db, f"club_events?select=place_entry_id&place_entry_id=not.is.null&event_date=gte.{since}")
    news = every_row(db, f"board_items?select=place_entry_id&place_entry_id=not.is.null&created_at=gte.{since}")
    return {r["place_entry_id"] for r in ev + news}


def shared_entries(rows):
    """Entry ids two or more open places carry (Coborn's grocery and pharmacy)."""
    seen = [r.get("entry_id") for r in rows if r.get("entry_id")]
    return {e for e in seen if seen.count(e) > 1}


def retirable(hides, entries, shared):
    """The hidden places' registry entries to retire: never one another open place still shares."""
    return [p["entry_id"] for p, _ in hides if p.get("entry_id") in entries and p["entry_id"] not in shared]


def run_pick(db, folder, month, today):
    import registry
    every = db.rest("GET", "places?select=id,entry_id,name,address,lat,lon,links,primary_type,apple_place_id"
                           "&closed_at=is.null&order=name") or []
    rows = [r for r in every if not r.get("apple_place_id")]
    half = pick(rows, month)
    entries = entry_notes((registry.find_root(HERE) / "sources" / "st-joseph-mn.md").read_text())
    for p in half:
        p["hints"] = hints(p, every, entries)
    if len(half) > MAX_SEARCHES:
        sys.exit(f"{len(half)} places is over {MAX_SEARCHES} searches; raise MAX_SEARCHES only with SerpAPI room to spare")
    Path(folder).mkdir(parents=True, exist_ok=True)
    busy = sorted(busy_entries(db, today))
    (Path(folder) / "pick.json").write_text(json.dumps({"month": month, "places": half, "busy": busy,
                                                        "shared": sorted(shared_entries(every))}, indent=1))
    print(f"{month}: {len(half)} of {len(rows)} places with no Apple Maps place to check, {len(half)} Google searches "
          f"(of SerpAPI's 250 a month); {sum(p.get('entry_id') in busy for p in half)} have Events or News in 90 days")
    for p in half:
        notes = p["hints"] + ["Events or News in 90 days"] * (p.get("entry_id") in busy)
        print(f"  - {p['name']}" + (f" ({'; '.join(notes)})" if notes else ""))


def run_google(folder):
    import maps
    picked = json.loads((Path(folder) / "pick.json").read_text())["places"]
    said = {}
    for p in picked:
        q = f"{p['name']} {p.get('address') or 'St. Joseph MN'}"
        ll = f"@{p['lat']},{p['lon']},15z" if p.get("lat") else None
        said[p["id"]] = google_says(p, maps.hits(maps.search(q, Path(folder) / "gmaps", ll=ll)))
    (Path(folder) / "google.json").write_text(json.dumps(said, indent=1))
    gone = [p for p in picked if said[p["id"]] in GONE]
    (Path(folder) / "brief.txt").write_text(brief(gone))
    print(f"{len(picked)} searched, {len(gone)} Google calls gone; brief.txt has them for a research agent")


def run_decide(folder, retire_them, sample):
    import registry
    f = Path(folder)
    picked = json.loads((f / "pick.json").read_text())
    google = json.loads((f / "google.json").read_text())
    agent = {a["id"]: a for a in json.loads((f / "agent.json").read_text())}
    town_file = registry.find_root(HERE) / "sources" / "st-joseph-mn.md"
    text = town_file.read_text()
    out = decide(picked["places"], google, agent, entry_notes(text), set(picked["busy"]))
    for k, items in out.items():
        print(f"{k} ({len(items)}):")
        for p, why in items:
            print(f"  - {p['name']}: {why}")
    if out["hide"] and sample:
        print(f"random sample for Jesse ({min(sample, len(out['hide']))}):")
        for p, why in random.sample(out["hide"], min(sample, len(out["hide"]))):
            print(f"  - {p['name']} ({p.get('address')}): {agent[p['id']].get('evidence')} {agent[p['id']].get('sources')}")
    (f / "hide.sql").write_text(hide_sql(out["hide"]))
    if retire_them:
        whys = {p.get("entry_id"): why for p, why in out["hide"]}
        for e in retirable(out["hide"], entry_notes(text), set(picked.get("shared", ()))):
            text = retire(text, e, whys[e], str(date.today()))
        town_file.write_text(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", choices=["pick", "google", "decide"])
    ap.add_argument("folder", nargs="?")
    ap.add_argument("--month", default=date.today().strftime("%Y-%m"))
    ap.add_argument("--retire", action="store_true", help="decide: retire the hidden places' registry entries")
    ap.add_argument("--sample", type=int, default=5, help="decide: how many hides to show Jesse at random")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.command or not a.folder:
        ap.error("a command and a folder")
    if a.command == "pick":
        from db import Db
        return run_pick(Db(), a.folder, a.month, date.today())
    if a.command == "google":
        return run_google(a.folder)
    return run_decide(a.folder, a.retire, a.sample)


# --- self-test -----------------------------------------------------------------------------------------

def selftest():
    cases = []
    abb = {"name": "American Burger Bar", "address": "2010 County Road 75, St. Joseph, MN 56374"}
    cases.append((google_says(abb, [{"title": "American Burger Bar", "address": "2010 Co Rd 75, St Joseph, MN",
                                     "open_state": "Permanently closed"}]) == "closed",
                  "Google's 'Permanently closed' reads closed"))
    cases.append((google_says(abb, [{"title": "Neighbors Route 75", "address": "2010 Co Rd 75, St Joseph, MN"}]) == "not found",
                  "another business at the address is not found"))
    tan = {"name": "Malibu Tan", "address": "708 Elm St E, Saint Joseph, MN 56374"}
    cases.append((google_says(tan, [{"title": "Malibu Tan", "address": "3333 W Division St, St Cloud, MN 56301"}]) == "other town",
                  "only in another town"))
    cases.append((google_says(tan, [{"title": "Malibu Tan", "address": "708 Elm St E, St Joseph, MN 56374"}]) == "open"
                  and google_says(tan, []) == "not found", "same town is open; no hits is not found"))
    rows = [{"id": f"id-{i}", "name": f"P{i}", "apple_place_id": None} for i in range(40)]
    dec, jan = pick(rows, "2026-12"), pick(rows, "2027-01")
    cases.append((sorted(r["id"] for r in dec + jan) == sorted(r["id"] for r in rows) and 10 < len(dec) < 30
                  and pick(rows, "2027-02") == dec, "two months in a row check every place once, about half each"))
    P = lambda n, e: {"id": n, "entry_id": e, "name": n.title(), "address": "1 Main St, St. Joseph, MN"}
    places = [P("gone", "gone"), P("busy", "busy"), P("word", "word"), P("inner", "inner"), P("twin", "twin"),
              P("maybe", "maybe"), P("fine", "fine")]
    google = {"gone": "closed", "busy": "not found", "word": "other town", "inner": "closed", "twin": "closed",
              "maybe": "not found", "fine": "open"}
    agent = {"gone": {"agent": "gone"}, "busy": {"agent": "gone"}, "word": {"agent": "gone"}, "inner": {"agent": "gone"},
             "twin": {"agent": "double", "of": "Host Bar"}, "maybe": {"agent": "unclear"}}
    entries = {"word": {"notes": "A place (Jesse, 2026-11-18: \"it is a place\")."}, "inner": {"inside": "host"}}
    out = decide(places, google, agent, entries, busy={"busy"})
    names = lambda k: [r["id"] for r, _ in out[k]]
    cases.append((names("hide") == ["gone"], "only a place both checks call gone, with nothing to keep it, is hidden"))
    cases.append((names("kept") == ["busy", "word", "inner"] and "Events" in out["kept"][0][1] and "Jesse" in out["kept"][1][1]
                  and "inside" in out["kept"][2][1], "Events in 90 days, Jesse's word and an `inside` entry keep a place"))
    cases.append((names("doubles") == ["twin"] and names("one check") == ["maybe"] and "fine" not in str(out),
                  "a double and a one-check place are listed for Jesse; Google-open places drop out"))
    town = ("---\nschema: 1\ntown: st-joseph-mn\n---\n\n## Joetown Burgers\n```yaml\nid: joetown-smashburger\nstatus: proposed\n"
            "inside: food-house-tap\n```\nNotes: A place (Jesse, 2026-11-18).\n\n## Oasis\n```yaml\nid: oasis\nstatus: active\n"
            "tier: listed\n```\n\n## Next\n```yaml\nid: next\nstatus: active\n```\n")
    got = entry_notes(town)
    cases.append((got["joetown-smashburger"] == {"inside": "food-house-tap", "notes": "A place (Jesse, 2026-11-18)."}
                  and got["oasis"] == {"inside": None, "notes": ""}, "the registry's inside and Notes per entry"))
    after = retire(town, "oasis", "Google: closed; agent: gone", "2026-12-01")
    cases.append(("id: oasis\nstatus: retired\ntier: listed" in after
                  and "Notes: Retired 2026-12-01 by the monthly check of places Apple Maps can't see" in after
                  and "id: next\nstatus: active" in after and after.count("status: retired") == 1,
                  "retire sets status and adds a Notes line, touching nothing else"))
    after = retire(town, "joetown-smashburger", "why", "2026-12-01")
    cases.append(("Notes: A place (Jesse, 2026-11-18). Retired 2026-12-01" in after, "an existing Notes line gets the reason added"))
    oasis = {"id": "u-1", "entry_id": "oasis", "name": "The Oasis Bar and Pit", "address": "1 Main St, St. Joseph, MN",
             "links": [{"kind": "website", "url": "https://oasis.example"}], "google_saw": "Google: permanently closed"}
    b = brief([oasis])
    cases.append(("The Oasis Bar and Pit" in b and "1 Main St" in b and "oasis.example" in b and "u-1" in b
                  and oasis["google_saw"] not in b and "permanently" not in b.lower() and "90 days" in b,
                  "the research brief names the place but never Google's answer"))
    sql = hide_sql([(oasis, "Google: closed; agent: gone")])
    cases.append(("update public.places set closed_at = now() where id = 'u-1' and closed_at is null;" in sql
                  and "-- The Oasis Bar and Pit: Google: closed; agent: gone" in sql and "Undo" in sql,
                  "the hide migration has one guarded update per place, with why"))
    birdie = {"id": "b", "entry_id": "birdies", "name": "Birdie's", "address": "13 2nd Ave NW, St. Joseph, MN 56374",
              "primary_type": "restaurant", "links": [{"kind": "website", "url": "https://birdies.example/menu"}]}
    house = {"id": "h", "entry_id": "food-house-tap", "name": "The House", "address": "13 2nd Ave NW, St Joseph, MN 56374",
             "primary_type": "restaurant", "apple_place_id": "I1"}
    gym = {**house, "id": "g", "name": "Gym", "primary_type": "gym"}
    resolves = lambda host: host != "birdies.example"
    cases.append((hints(birdie, [house, gym, birdie], {}, resolves) == ["website domain gone", "same address as The House (on Apple Maps)"],
                  "a dead domain and an Apple-matched place of the same kind at the address are hints"))
    cases.append((hints({**birdie, "entry_id": "joetown"}, [house], {"joetown": {"inside": "food-house-tap"}}, lambda h: True) == [],
                  "an `inside` entry at its host's address is no hint"))
    # Review fixes, 2026-11-20.
    wrapped = ("## Joetown\n```yaml\nid: joetown\nstatus: active\n```\nNotes: Burgers inside the Food House,\n"
               "kept as a place (Jesse, 2026-11-18).\n\n## Next\n```yaml\nid: next\nstatus: active\n```\n")
    cases.append(("jesse" in entry_notes(wrapped)["joetown"]["notes"].lower(), "Notes read to the paragraph's end"))
    after = retire(wrapped, "joetown", "why", "2026-12-01")
    cases.append(("(Jesse, 2026-11-18). Retired 2026-12-01" in after and after.count("kept as a place") == 1
                  and "\n\n## Next" in after, "a wrapped Notes paragraph gets the reason at its end"))
    cases.append((google_says({"name": "BP", "address": "1 Main St, St. Joseph, MN"},
                              [{"title": "BP", "address": "1 Main St, St Joseph, MN"}]) == "open"
                  and google_says({"name": "BP"}, [{"title": "Casey's", "address": "2 Elm St, St Joseph, MN"}]) == "not found",
                  "a short name (BP) is matched by its whole words"))

    class Pages:
        def rest(self, method, path):
            off = int(re.search(r"offset=(\d+)", path).group(1))
            if path.startswith("board_items"):
                return []
            return [{"place_entry_id": "quiet"}] * 1000 if off == 0 else [{"place_entry_id": "busy"}] if off == 1000 else []
    cases.append(("busy" in busy_entries(Pages(), date(2026, 12, 1)), "busy places are read past PostgREST's 1,000 rows"))
    hides = [({"id": "g", "entry_id": "coborns"}, "w"), ({"id": "o", "entry_id": "oasis"}, "w"), ({"id": "n"}, "w")]
    cases.append((retirable(hides, {"coborns": {}, "oasis": {}}, {"coborns"}) == ["oasis"],
                  "an entry another open place shares (Coborn's grocery and pharmacy) is not retired"))
    cases.append((shared_entries([{"entry_id": "coborns"}, {"entry_id": "coborns"}, {"entry_id": "oasis"}, {}]) == {"coborns"},
                  "an entry two open places carry is shared"))
    failed = [what for ok, what in cases if not ok]
    for what in failed:
        print(f"FAIL {what}")
    print(f"gone_places.py selftest: {len(cases) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
