#!/usr/bin/env python3
"""
nothing_scheduled.py: every confirmed thing with nothing scheduled and no page the morning watch reads for it, walked
once in AGAIN for a page that gives its dates; what the walk finds waits for Jesse's tick before it is watched (BP app
docs/plans/nothing-scheduled, ticket 04; Jesse, 2026-11-13: "yes i want that to be an automated step for all things
that are confirmed but havent been scheduled").

Confirmed, and what is walked (BP app dig-deeper 26 counted them live on 2026-11-13):
- A local school's activity with no upcoming Event: its own school's games or its fielder's, and its co-op team's
  (activities_next, the school page's own pairing, never the school alone). Walked: clubs, arts, and sports in season
  or with no high school season. A sport out of season is skipped: its schedule arrives by itself.
- An open Place with no upcoming Event and no page we read (an active, watched page, or a social page not `skip`).
  Walked: the kinds that hold Events (to eat or drink, parks, arts and history, community, church and school, or a
  place with no kind known). Trades, storage and offices are skipped.
- An approved Group with no Event coming whose own page isn't on a site we read. Only its one-off Events are looked for:
  its regular meetings stay on its page (Jesse, 2026-11-13).

On Sundays the morning report says how many are due, beside the photo dig's weekly pass. A chat walks them
(sources/models/dates.md for its finders): MOST a week, the ones walked longest ago first.

  python3 sources/scripts/nothing_scheduled.py count                    the counts; nothing walked
  python3 sources/scripts/nothing_scheduled.py walk [--most N] [--only KEY ...]   the things due, in batches for the
                                                                        finders (.runs/morning/scheduled/find-N.txt)
  python3 sources/scripts/nothing_scheduled.py read URL                 one page through the polite fetcher, as text
  python3 sources/scripts/nothing_scheduled.py keep [--dry-run]         the finders' pages checked and listed for
                                                                        Jesse's tick (picks.json), each thing walked
                                                                        remembered (public.date_walks)
  python3 sources/scripts/nothing_scheduled.py --selftest

The list is find_calendars.py's picks: Jesse unticks on an approval page, and `find_calendars.py --promote <choices>
--picks .runs/morning/scheduled/picks.json` makes each page left ticked watched (ADR-022). A page whose thing has no
registry entry is listed as `new`: the chat writes its entry before promoting. Facebook and Instagram pages the finders
name are listed apart and never read here: reading them is the paid rung (BP app nothing-scheduled 06), through the
social watch's list (sources/social/<town>.json) after Jesse's yes.
"""
import argparse, json, re, sys
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, is_todo  # noqa: E402
from run import Supabase, fetch, to_text  # noqa: E402
from morning_run import Part  # noqa: E402
from towns import DEFAULT, lookup  # noqa: E402

AGAIN = timedelta(days=28)   # a thing walked isn't walked again sooner (ticket 04)
MOST = 40                    # things a week: about 266 to walk, so a full pass takes about seven weeks
PER_FIND = 5                 # things in one finder's batch
AHEAD = 90                   # a page counts when it gives a date this many days ahead (the readers' DAYS_AHEAD)
RUNGS = ("school", "broad", "own", "search")  # the Ladder, cheapest first (dig-deeper 26's hand walk)
READ_MOST = 12000            # characters of a page `read` prints for a finder

# A sport's season, by its name (dig-deeper 26's count), first match wins: boys' swim is winter, girls' fall.
SEASON_OF = (("winter", r"basketball|hockey|wrestl|gymnast|nordic|alpine|ski|dance|bowling|swim.*boys|boys.*swim"),
             ("spring", r"baseball|softball|track|golf|lacrosse|clay|trap|tennis.*boys|boys.*tennis|volleyball.*boys"
                        r"|boys.*volleyball|fishing"),
             ("fall", r"football|soccer|volleyball|cross country|swim|tennis"))
# Each season's days, month-day, from MSHSL's calendar: a sport is walked from its first practice to its last
# tournament (the agent's pick; 2026-11-13 is winter, as dig-deeper 26 counted it).
SEASONS = {"fall": ("08-01", "11-07"), "winter": ("11-08", "03-14"), "spring": ("03-15", "06-14")}
# A Place of these kinds holds Events; any other kind (a plumber, storage, an office) never does (Jesse, 2026-11-13).
HOLDS = re.compile(r"park|museum|monument|gallery|theat|library|church|worship|food_bank|community|education|school|"
                   r"restaurant|\bbar\b|brewery|winery|cider|cafe|coffee", re.I)
HOLDS_TYPES = {"Community group", "Church", "School / college", "Park / historic"}
SOCIAL = re.compile(r"(?:facebook|instagram)\.com/", re.I)
ICAL = re.compile(r"\.ics\b|[?&]ical=1|/ical\b|iCalendar", re.I)
FEED = re.compile(r"/feed/?$|/rss\b|\.rss$|\.xml$", re.I)


def out_dir():
    return find_root() / ".runs" / "morning"


def season(name):
    low = name.lower()
    return next((s for s, pattern in SEASON_OF if re.search(pattern, low)), None)


def in_season(name, today):
    s = season(name)
    if s is None:
        return True
    start, end = SEASONS[s]
    md = today.strftime("%m-%d")
    return start <= md <= end if start <= end else (md >= start or md <= end)


def host(url):
    return urlparse(url).netloc.lower().removeprefix("www.")


def page_key(url):
    p = urlparse(url)
    return host(url) + p.path.rstrip("/") + (f"?{p.query}" if p.query else "")


def real(s):
    return s.get("url") and not is_todo(s["url"])


def watched_pages(entry):
    """An entry's pages the morning watch reads: active and watched, fetched or read through an API."""
    if entry.get("status") != "active" or entry.get("tier") != "watched":
        return []
    return [s["url"] for s in entry.get("sources") or [] if real(s) and s.get("method") in ("fetch", "api")]


def school_entry(team, entries):
    """The school's registry entry: "Apollo High School" is apollo (read_events.bound_team), "College of Saint Benedict"
    is the entry of that name or other name."""
    import read_events
    names = {(team.get("school_name") or "").lower(), (team.get("name") or "").lower()} - {""}
    return next((e for e in entries if read_events.bound_team(e) == team["id"]), None) or next(
        (e for e in entries if names & {n.lower() for n in [e["_name"], *(e.get("aka") or [])]}), None)


def things(rows, entries, social, today):
    """Every confirmed thing, with whether it has nothing scheduled, a page we read, and whether the step walks it (and
    why not). `rows`: the database's (read_rows); `entries`: the registry's; `social`: the social watch's page list."""
    by_id = {e["id"]: e for e in entries}
    read_hosts = {host(u) for e in entries for u in watched_pages(e)}
    socials = defaultdict(list)
    for p in social:
        socials[p["entry_id"]] += [] if p.get("skip") else [p["url"]]
    covered = lambda eid: bool(eid and (watched_pages(by_id.get(eid, {})) or socials.get(eid)))  # noqa: E731
    out = []
    teams = {t["id"]: t for t in rows["teams"]}
    schools = {t["id"]: school_entry(t, entries) or {} for t in rows["teams"]}
    with_event = set(rows["with_event"])
    for a in rows["activities"]:
        team, school = teams.get(a["team_id"]), schools.get(a["team_id"])
        if not team:
            continue
        sport = a["kind"] == "sport"
        label = (season(a["name"]) or "no season") if sport else a["kind"]
        out.append({"key": f"activity:{a['id']}", "what": "activity", "name": a["name"], "label": label,
                    "nothing": a["id"] not in with_event, "page": False,
                    "walk": not sport or in_season(a["name"], today),
                    "school": team.get("school_name") or team["name"], "note": a.get("note"),
                    "entry": school.get("id"), "sites": sites(school), "read": watched_pages(school)})
    busy = set(rows["busy_places"])
    for p in rows["places"]:
        e = by_id.get(p["entry_id"], {})
        kinds = " ".join(dict.fromkeys(filter(None, (e.get("category"), p.get("primary_type"), e.get("place_type")))))
        holds = p.get("family") == "food" or e.get("place_type") in HOLDS_TYPES or bool(HOLDS.search(kinds)) or not kinds
        out.append({"key": f"place:{p['entry_id']}", "what": "place", "name": p["name"],
                    "label": "holds Events" if holds else "never holds an Event", "kind": kinds,
                    "nothing": p["entry_id"] not in busy, "page": covered(p["entry_id"]), "walk": holds,
                    "entry": p["entry_id"] if e else None, "sites": sites(e), "social": socials.get(p["entry_id"], []),
                    "read": watched_pages(e)})
    busy = set(rows["busy_groups"])
    for g in rows["groups"]:
        page = g.get("page_url") or ""
        host_place = by_id.get(g.get("place_entry_id") or "", {})
        out.append({"key": f"group:{g['id']}", "what": "group", "name": g["name"], "label": g.get("kind") or "group",
                    "nothing": g["id"] not in busy,
                    "page": bool(page and host(page) in read_hosts) or covered(g.get("own_entry_id")), "walk": True,
                    "host": host_place.get("_name"), "entry": g.get("own_entry_id"),
                    "sites": [page] if page else [], "read": watched_pages(host_place)})
    return out


def sites(entry):
    return [s["url"] for s in (entry or {}).get("sources") or [] if real(s) and not SOCIAL.search(s["url"])]


def walked_things(all_things):
    """The things the step walks: nothing scheduled, no page we read, and of a kind it walks."""
    return [t for t in all_things if t["nothing"] and not t["page"] and t["walk"]]


def count_lines(all_things):
    """dig-deeper 26's counts, one line a kind of thing."""
    lines = []
    acts = [t for t in all_things if t["what"] == "activity"]
    empty = [t for t in acts if t["nothing"]]
    walked = Counter(t["label"] for t in empty if t["walk"])
    skipped = Counter(t["label"] for t in empty if not t["walk"])
    say = lambda c: ", ".join(f"{k} {n}" for k, n in c.most_common())  # noqa: E731
    lines.append(f"[scheduled] school activities: {len(acts)}, {len(empty)} with nothing scheduled; walked "
                 f"{sum(walked.values())} ({say(walked)}), skipped {sum(skipped.values())} out of season ({say(skipped)})")
    places = [t for t in all_things if t["what"] == "place"]
    empty = [t for t in places if t["nothing"]]
    bare = [t for t in empty if not t["page"]]
    lines.append(f"[scheduled] Places: {len(places)} open, {len(empty)} with nothing scheduled, {len(bare)} of them "
                 f"with no page we read; walked {sum(t['walk'] for t in bare)}, skipped "
                 f"{sum(not t['walk'] for t in bare)} of a kind that never holds an Event")
    groups = [t for t in all_things if t["what"] == "group"]
    empty = [t for t in groups if t["nothing"]]
    bare = [t for t in empty if not t["page"]]
    lines.append(f"[scheduled] Groups: {len(groups)}, {len(empty)} with no Event coming, {len(bare)} of them with no "
                 f"page we read; walked {len(bare)}")
    return lines


def pages(db, path):
    """Every row of a read, PostgREST answering at most 1,000 at a time."""
    rows = []
    while True:
        got = db.rest("GET", f"{path}&limit=1000&offset={len(rows)}") or []
        rows += got
        if len(got) < 1000:
            return rows


def read_rows(db, today):
    teams = db.rest("GET", "teams?select=id,name,school_name&local=is.true") or []
    ids = [t["id"] for t in teams]
    up = (f"status=eq.approved&cancelled_at=is.null&event_date=gte.{today}")
    return {
        "teams": teams,
        "activities": pages(db, f"team_activities?select=id,team_id,name,kind,note&team_id=in.({','.join(ids)})&order=id"),
        "with_event": [r["id"] for r in db.rest("POST", "rpc/activities_next", {"p_teams": ids}) or []],
        "places": pages(db, "places?select=entry_id,name,family,primary_type&closed_at=is.null&entry_id=not.is.null&order=entry_id"),
        "busy_places": {r["place_entry_id"] for r in pages(db, f"club_events?select=place_entry_id&{up}&place_entry_id=not.is.null&order=id")},
        "groups": db.rest("GET", "clubs?select=id,name,kind,own_entry_id,place_entry_id,page_url&status=eq.approved") or [],
        "busy_groups": {r["club_id"] for r in pages(db, f"club_events?select=club_id&{up}&club_id=not.is.null&order=id")},
    }


def load_all(db, today, root=None, town=DEFAULT):
    import registry
    root = root or find_root()
    entries = [e for e in registry.load(root)[0] if e["_town"] == town]
    social_file = root / "sources" / "social" / f"{town}.json"
    social = json.loads(social_file.read_text()) if social_file.exists() else []
    return things(read_rows(db, today), entries, social, today), entries


def last_walks(db):
    return {r["thing"]: r["walked_at"] for r in pages(db, "date_walks?select=thing,walked_at&order=thing")}


def due(all_things, walks, now, most=MOST):
    """The things to walk now: not walked within AGAIN, the ones walked longest ago first; among those never walked,
    Groups, then Places, then school activities (the hand walk found dates for 2 of 5 Places and Groups, 3 of 15
    activities)."""
    since = (now - AGAIN).isoformat()
    rank = {"group": 0, "place": 1, "activity": 2}
    left = [t for t in walked_things(all_things) if not walks.get(t["key"]) or walks[t["key"]] < since]
    left.sort(key=lambda t: (walks.get(t["key"]) or "", rank[t["what"]], t.get("school") or "", t["name"]))
    return left[:most], len(left)


def due_line(db, today, now=None):
    """The morning report's line on Sundays, beside the photo dig's weekly pass: how many are due, and how to walk
    them. Any other day, nothing. A count that fails is the line, never a lost report."""
    from event_photos import WEEKLY_DAY  # here: event_photos imports morning, which imports this
    if today.weekday() != WEEKLY_DAY:
        return []
    now = now or datetime.now(timezone.utc)
    try:
        all_things, _ = load_all(db, today)
        todo, left = due(all_things, last_walks(db), now)
    except Exception as e:
        return [f"[scheduled] the Sunday count failed: {' '.join(str(e).split())[:300]}"]
    total = len(walked_things(all_things))
    if not todo:
        return [f"[scheduled] none of the {total} things with nothing scheduled is due for a walk"]
    return [f"[scheduled] {left} of {total} things with nothing scheduled are due for a walk: say \"nothing scheduled\" "
            f"in a chat to walk {len(todo)} (BP app nothing-scheduled 04)"]


def finder_line(t, town, today):
    """What a finder knows of one thing (sources/models/dates.md)."""
    where = {"activity": lambda: f"{t['label']} at {t['school']}", "place": lambda: f"a place in {town} ({t['kind']})",
             "group": lambda: f"a group in {town}" + (f", meets at {t['host']}" if t.get("host") else "")}[t["what"]]()
    line = {"thing": t["key"], "name": t["name"], "what": where, "town": town,
            "sites": [u for u in t["sites"] if u not in t["read"]], "read": t["read"],
            "between": [str(today), str(today + timedelta(days=AHEAD))]}
    if t.get("note"):
        line["note"] = t["note"]
    if t.get("social"):
        line["social"] = t["social"]
    return line


def walk(out, all_things, walks, now, most=MOST, only=None, town=DEFAULT):
    """The things due (or `only` those keys), in batches for the finders."""
    folder = out / "scheduled"
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    if only:
        todo, left = [t for t in all_things if t["key"] in set(only)], len(only)
    else:
        todo, left = due(all_things, walks, now, most)
    import read_events
    label, today = lookup(town)["label"], now.astimezone(read_events.LOCAL).date()
    (folder / "things.json").write_text(json.dumps(todo, indent=1, ensure_ascii=False))
    for i in range(0, len(todo), PER_FIND):
        (folder / f"find-{i // PER_FIND + 1}.txt").write_text(
            "".join(json.dumps(finder_line(t, label, today), ensure_ascii=False) + "\n" for t in todo[i:i + PER_FIND]))
    batches = (len(todo) + PER_FIND - 1) // PER_FIND
    print(f"[scheduled] {len(todo)} of {left} things due, in {batches} batches for the finders ({folder})" if todo
          else "[scheduled] no thing due")
    return todo


def kind_of(url):
    return "ical" if ICAL.search(url) else "rss" if FEED.search(urlparse(url).path) else "website"


def entry_for(url, thing, entries):
    """The registry entry a found page joins: the entry that already names this page, else the one whose site it is
    when that is a single entry, else the thing's own (its school, its place, its Group's own entry), else none."""
    key, site = page_key(url), host(url)
    named = [e for e in entries if any(real(s) and page_key(s["url"]) == key for s in e.get("sources") or [])]
    if named:
        return named[0]
    on_site = [e for e in entries if any(real(s) and host(s["url"]) == site for s in e.get("sources") or [])]
    own = next((e for e in entries if e["id"] == thing.get("entry")), None)
    if own in on_site or len(on_site) != 1:
        return own
    return on_site[0]


def keep(out, entries, db=None, dry_run=False, now=None, readable=None):
    """The finders' answers (scheduled/pages.jsonl) checked: a page we already read, one that won't read by a plain
    fetch, one with no date in the next AHEAD days, and a Facebook or Instagram page are taken out of the tick list, the
    social pages listed apart. The rest, by registry entry, go to scheduled/picks.json for Jesse's tick. Every thing a
    finder answered for is remembered as walked; one it didn't is walked next time."""
    from find_calendars import readable as polite_readable
    from morning import read_items
    from read_events import LOCAL
    readable = readable or polite_readable
    now = now or datetime.now(timezone.utc)
    folder = out / "scheduled"
    laid = {t["key"]: t for t in json.loads((folder / "things.json").read_text())} if (folder / "things.json").exists() else {}
    answers = {a["thing"]: a for a in read_items(folder / "pages.jsonl") if isinstance(a, dict) and a.get("thing") in laid}
    read_now = {page_key(u) for e in entries for u in watched_pages(e)}
    today = now.astimezone(LOCAL).date()
    found, social, dropped, rungs = [], [], [], Counter()
    for key, a in answers.items():
        t, page = laid[key], str(a.get("page") or "").strip()
        social += [{"thing": t["name"], "url": u} for u in a.get("social") or [] if isinstance(u, str) and SOCIAL.search(u)]
        rung = a.get("rung") if a.get("rung") in RUNGS and page.startswith("http") else None
        rungs[rung or "none"] += 1
        if not rung:
            continue
        when = str(a.get("date") or "")
        why = ("a Facebook or Instagram page" if SOCIAL.search(page) else "already read" if page_key(page) in read_now
               else None if re.fullmatch(r"\d{4}-\d{2}-\d{2}", when) and today <= date.fromisoformat(when)
               <= today + timedelta(days=AHEAD) else f"no date in the next {AHEAD} days")
        if why:
            dropped.append(f"{t['name']}: {page} ({why})")
            if SOCIAL.search(page):
                social.append({"thing": t["name"], "url": page})
            continue
        found.append({"thing": t, "url": page, "rung": rung, "date": when, "event": " ".join(str(a.get("event") or "").split())[:80]})
    checked = Part(folder / "readable.json", empty={})  # a keep run again reads no page twice
    for f in found:
        if f["url"] not in checked.saved:
            checked.saved[f["url"]] = readable(f["url"])
            checked.save()
    picks = {}
    for f in found:
        if not checked.saved[f["url"]]:
            dropped.append(f"{f['thing']['name']}: {f['url']} (won't read by a plain fetch)")
            continue
        e = entry_for(f["url"], f["thing"], entries)
        row = picks.setdefault(e["id"] if e else f["url"], {
            "id": e["id"] if e else None, "name": e["_name"] if e else f["thing"]["name"],
            "category": (e or {}).get("category"), "status": (e or {}).get("status"), "url": f["url"],
            "state": "ok" if e else "new", "pages": [], "things": []})
        if f["url"] not in [p["url"] for p in row["pages"]]:
            row["pages"].append({"url": f["url"], "why": f"{f['rung']}: {f['thing']['name']}, {f['event']} {f['date']}".strip(),
                                 "kind": kind_of(f["url"])})
        row["things"].append(f["thing"]["name"])
    rows = sorted(picks.values(), key=lambda r: r["name"])
    (folder / "picks.json").write_text(json.dumps(rows, indent=1, ensure_ascii=False))
    (folder / "social.json").write_text(json.dumps(social, indent=1, ensure_ascii=False))
    searches = sum(int(a.get("searches") or 0) for a in answers.values() if str(a.get("searches") or "0").isdigit())
    with_page = len(answers) - rungs["none"]
    lines = [f"[scheduled] walked {len(answers)} of {len(laid)}: a page with a date for {with_page} ("
             + ", ".join(f"{r} {rungs[r]}" for r in RUNGS) + f"), none {rungs['none']}; {searches} web searches",
             f"[scheduled] {sum(len(r['pages']) for r in rows)} pages listed for Jesse's tick ({folder / 'picks.json'}); "
             f"{len(social)} Facebook or Instagram pages listed, not read ({folder / 'social.json'})"]
    lines += [f"[scheduled] taken out: {d}" for d in dropped]
    marks = [{"thing": k, "walked_at": now.isoformat()} for k in answers]
    if dry_run or not marks:
        lines.append(f"[scheduled] {'would remember' if dry_run else 'remembered'} {len(marks)} things walked")
    else:
        (db or Supabase()).rest("POST", "date_walks?on_conflict=thing", marks, prefer="resolution=merge-duplicates,return=minimal")
        lines.append(f"[scheduled] remembered {len(marks)} things walked (public.date_walks)")
    print("\n".join(lines))
    return rows, social, lines


def read_page(url, get=fetch):
    """A page as a finder reads it: its text, or one line saying why it won't read (a finder reads no traceback)."""
    try:
        _, raw = get(url)
    except Exception as e:
        return f"won't read: {' '.join(str(e).split())[:200]}"
    return to_text(raw)[:READ_MOST]


# --- self-test ---------------------------------------------------------------------------------------------------

def selftest():
    import tempfile
    from morning_run import FakeDb
    checks = []

    def check(ok, why):
        checks.append((bool(ok), why))

    nov13, jul1 = date(2026, 11, 13), date(2026, 7, 1)
    check(season("Boys Swim & Dive") == "winter" and season("Girls Swim & Dive") == "fall"
          and season("Swimming & Diving - Boys") == "winter" and season("Baseball") == "spring"
          and season("Volleyball - Boys") == "spring" and season("Volleyball (girls)") == "fall"
          and season("Ultimate Frisbee (Club)") is None, "a sport's season by its name, boys' swim winter, girls' fall")
    check(in_season("Boys Hockey", nov13) and not in_season("Boys Hockey", jul1) and in_season("Boys Hockey", date(2027, 2, 1))
          and not in_season("Football", nov13) and in_season("Football", date(2026, 9, 1)) and not in_season("Baseball", nov13)
          and in_season("SJU Rugby", jul1), "in season: winter runs over the new year; a sport with no season always")

    entries = [
        {"id": "apollo-high-school", "_name": "Apollo High School", "_town": "st-joseph-mn", "status": "active", "tier": "watched",
         "sources": [{"url": "https://www.gobound.com/mn/schools/stcloudapollo/calendar/ical", "method": "fetch"}]},
        {"id": "csb", "_name": "College of Saint Benedict", "_town": "st-joseph-mn", "status": "active", "tier": "watched",
         "sources": [{"url": "https://www.csbsju.edu/calendar/", "method": "search_snippet"}]},
        {"id": "cafe", "_name": "Corner Cafe", "_town": "st-joseph-mn", "status": "active", "tier": "listed", "category": "restaurant",
         "sources": [{"url": "https://cafe.example/", "method": "fetch"}]},
        {"id": "plumber", "_name": "Plumber", "_town": "st-joseph-mn", "category": "home_service", "sources": [{"url": "TODO"}]},
        {"id": "bar", "_name": "Bar", "_town": "st-joseph-mn", "status": "active", "tier": "watched", "category": "bar",
         "sources": [{"url": "https://bar.example/events", "method": "fetch"}]},
        {"id": "pub", "_name": "Pub", "_town": "st-joseph-mn", "category": "bar", "sources": [{"url": "TODO"}]},
        {"id": "inn", "_name": "Inn", "_town": "st-joseph-mn", "category": "bar", "sources": [{"url": "TODO"}]},
        {"id": "church", "_name": "Church", "_town": "st-joseph-mn", "status": "active", "tier": "watched", "category": "church",
         "sources": [{"url": "https://church.example/calendar/", "method": "fetch"}]},
        {"id": "diocese", "_name": "Diocese", "_town": "st-joseph-mn", "status": "proposed", "tier": "watched",
         "sources": [{"url": "https://paper.example/events/?ical=1", "method": "fetch"}]},
        {"id": "nature", "_name": "Nature Club", "_town": "st-joseph-mn", "status": "active", "tier": "listed",
         "sources": [{"url": "https://clubs.example/nature", "method": "fetch"}]},
        {"id": "garden", "_name": "Garden Club", "_town": "st-joseph-mn", "status": "active", "tier": "listed",
         "sources": [{"url": "https://clubs.example/garden", "method": "fetch"}]},
    ]
    social = [{"entry_id": "pub", "url": "https://www.facebook.com/pub"},
              {"entry_id": "inn", "url": "https://www.facebook.com/inn", "skip": True}]
    acts = [("a1", "apollo", "Chess Club", "club"), ("a2", "apollo", "Band", "arts"), ("a3", "apollo", "Boys Hockey", "sport"),
            ("a4", "apollo", "Baseball", "sport"), ("a5", "apollo", "Football", "sport"), ("a6", "saint-benedict", "Rugby", "sport"),
            ("a7", "apollo", "Girls Swim & Dive", "sport"), ("a8", "apollo", "Boys Swim & Dive", "sport"), ("a9", "apollo", "Choir", "arts")]
    rows = {"teams": [{"id": "apollo", "name": "Apollo", "school_name": "Apollo High School"},
                      {"id": "saint-benedict", "name": "Saint Benedict", "school_name": "College of Saint Benedict"}],
            "activities": [{"id": i, "team_id": s, "name": n, "kind": k, "note": None} for i, s, n, k in acts],
            "with_event": ["a2", "a8"],
            "places": [{"entry_id": "cafe", "name": "Corner Cafe", "family": "food", "primary_type": "restaurant"},
                       {"entry_id": "plumber", "name": "Plumber", "family": "business", "primary_type": "home_service"},
                       {"entry_id": "bar", "name": "Bar", "family": "food", "primary_type": "bar"},
                       {"entry_id": "pub", "name": "Pub", "family": "food", "primary_type": "bar"},
                       {"entry_id": "inn", "name": "Inn", "family": "food", "primary_type": "bar"},
                       {"entry_id": "lot", "name": "Mystery Lot", "family": "business", "primary_type": None},
                       {"entry_id": "church", "name": "Church", "family": "business", "primary_type": "church"}],
            "busy_places": {"church"},
            "groups": [{"id": "g1", "name": "Quilters", "kind": "Quilting", "own_entry_id": None, "place_entry_id": "church",
                        "page_url": "https://www.church.example/groups/"},
                       {"id": "g2", "name": "Lions Club", "kind": "Service club", "own_entry_id": None, "place_entry_id": None,
                        "page_url": "https://lions.example/"},
                       {"id": "g3", "name": "Runners", "kind": "Running", "own_entry_id": None, "place_entry_id": "bar",
                        "page_url": "https://runners.example/"}],
            "busy_groups": {"g3"}}
    got = things(rows, entries, social, nov13)
    by = {t["key"]: t for t in got}
    check([t["key"] for t in walked_things(got)] == ["activity:a1", "activity:a3", "activity:a6", "activity:a9",
                                                      "place:cafe", "place:inn", "place:lot", "group:g2"],
          "walked: a club, a winter sport, a sport with no season, arts; a cafe, a pub whose page is skipped, a place of "
          "no known kind; a Group whose page isn't on a site we read")
    check(by["place:plumber"]["label"] == "never holds an Event" and not by["place:plumber"]["walk"]
          and by["place:bar"]["page"] and by["place:pub"]["page"] and not by["place:inn"]["page"],
          "a plumber is skipped; a watched page or a social page covers a Place, a skipped social page doesn't")
    check(by["group:g1"]["page"] and not by["group:g2"]["page"] and not by["group:g3"]["nothing"],
          "a Group whose page is on its host's watched site is covered; one with an Event coming isn't empty")
    check(by["activity:a6"]["entry"] == "csb" and by["activity:a3"]["entry"] == "apollo-high-school"
          and by["activity:a3"]["read"] == ["https://www.gobound.com/mn/schools/stcloudapollo/calendar/ical"],
          "an activity's school entry, by its team or its school's name, with the pages we already read")
    lines = count_lines(got)
    check(lines == ["[scheduled] school activities: 9, 7 with nothing scheduled; walked 4 (club 1, winter 1, no season 1, "
                    "arts 1), skipped 3 out of season (fall 2, spring 1)",
                    "[scheduled] Places: 7 open, 6 with nothing scheduled, 4 of them with no page we read; walked 3, "
                    "skipped 1 of a kind that never holds an Event",
                    "[scheduled] Groups: 3, 2 with no Event coming, 1 of them with no page we read; walked 1"],
          f"the counts, dig-deeper 26's lines: {lines}")
    summer = count_lines(things(rows, entries, social, jul1))[0]
    check("walked 3 (club 1, no season 1, arts 1), skipped 4 out of season (fall 2, winter 1, spring 1)" in summer,
          "in July the winter sport waits too")

    now = datetime(2026, 11, 15, 12, tzinfo=timezone.utc)
    walks = {"group:g2": "2026-10-04T12:00:00+00:00", "place:cafe": "2026-11-01T12:00:00+00:00",
             "activity:a1": "2026-09-20T12:00:00+00:00"}
    todo, left = due(got, walks, now, most=4)
    check([t["key"] for t in todo] == ["place:inn", "place:lot", "activity:a3", "activity:a9"] and left == 7,
          "due: never walked first, Groups then Places then activities; walked within four weeks waits")
    todo, _ = due(got, walks, now)
    check([t["key"] for t in todo][-2:] == ["activity:a1", "group:g2"], "then the one walked longest ago")

    db = FakeDb(answers={"teams": rows["teams"], "team_activities": rows["activities"],
                         "rpc/activities_next": [{"id": "a2"}, {"id": "a8"}], "places": rows["places"],
                         "club_events?select=place_entry_id": [{"place_entry_id": "church"}],
                         "club_events?select=club_id": [{"club_id": "g3"}], "clubs": rows["groups"],
                         "date_walks": [{"thing": k, "walked_at": v} for k, v in walks.items()]})
    read = read_rows(db, nov13)
    check(read["with_event"] == ["a2", "a8"] and read["busy_places"] == {"church"} and read["busy_groups"] == {"g3"}
          and last_walks(db) == walks and not db.writes(), "the rows read, nothing written")

    global load_all
    was = load_all
    load_all = lambda db, today: (got, entries)  # noqa: E731
    try:
        monday = due_line(db, date(2026, 11, 16), now)
        calls = len(db.calls)
        sunday = due_line(db, date(2026, 11, 15), now)
        load_all = lambda db, today: 1 / 0  # noqa: E731
        broken = due_line(db, date(2026, 11, 15), now)
    finally:
        load_all = was
    check(monday == [] and calls == len(db.calls) - 1 and sunday == [
        '[scheduled] 7 of 8 things with nothing scheduled are due for a walk: say "nothing scheduled" in a chat to walk 7 '
        '(BP app nothing-scheduled 04)'] and broken == ["[scheduled] the Sunday count failed: division by zero"],
          f"the morning report's line on Sundays only; a count that fails is the line: {monday}, {sunday}, {broken}")

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        (out / "scheduled").mkdir()
        (out / "scheduled" / "stale.txt").write_text("x")
        laid = walk(out, got, walks, now, most=6)
        files = sorted(p.name for p in (out / "scheduled").iterdir())
        first = [json.loads(ln) for ln in (out / "scheduled" / "find-1.txt").read_text().splitlines()]
        check(files == ["find-1.txt", "find-2.txt", "things.json"] and len(laid) == 6 and len(first) == 5
              and first[0] == {"thing": "place:inn", "name": "Inn", "what": "a place in St. Joseph MN (bar)",
                               "town": "St. Joseph MN", "sites": [], "read": [], "between": ["2026-11-15", "2027-02-13"]},
              "walk: the due things in batches of five, each with what a finder needs; last week's files gone")
        hockey = next(x for x in first if x["thing"] == "activity:a3")
        check(hockey["what"] == "winter at Apollo High School" and hockey["read"] and not hockey["sites"],
              "an activity names its school; a page already read isn't offered as its site")
        walk(out, got, walks, now, only=["group:g2", "place:cafe"])
        check(len(json.loads((out / "scheduled" / "things.json").read_text())) == 2, "--only lays out just those")

        answers = [
            {"thing": "group:g2", "rung": "broad", "page": "https://paper.example/events/?ical=1", "date": "2026-12-06",
             "event": "Pancake breakfast", "social": ["https://www.facebook.com/lions"], "searches": 3},
            {"thing": "place:cafe", "rung": "own", "page": "https://cafe.example/events", "date": "2026-11-20",
             "event": "Trivia night", "searches": 2},
            {"thing": "nobody", "rung": "own", "page": "https://x.example/"},
        ]
        (out / "scheduled" / "pages.jsonl").write_text("".join(json.dumps(a) + "\n" for a in answers) + "not json\n")
        db = FakeDb()
        rows_out, soc, _ = keep(out, entries, db, now=now, readable=lambda u: True)
        check([(r["id"], r["state"], [p["kind"] for p in r["pages"]]) for r in rows_out]
              == [("cafe", "ok", ["website"]), ("diocese", "ok", ["ical"])]
              and rows_out[1]["pages"][0]["why"] == "broad: Lions Club, Pancake breakfast 2026-12-06"
              and soc == [{"thing": "Lions Club", "url": "https://www.facebook.com/lions"}],
              "keep: each page by the entry it joins (the cafe's own, the paper that already names it), Facebook apart")
        marks = db.writes("date_walks")
        check(len(marks) == 1 and sorted(m["thing"] for m in marks[0][2]) == ["group:g2", "place:cafe"]
              and marks[0][2][0]["walked_at"] == now.isoformat(), "every thing a finder answered for is remembered")

        walk(out, got, walks, now, only=["group:g2", "place:cafe", "place:inn", "place:lot", "activity:a3", "activity:a1"])
        answers = [
            {"thing": "group:g2", "rung": "search", "page": "https://lions.example/calendar", "date": "2026-12-01", "event": "Fish fry"},
            {"thing": "place:cafe", "rung": "own", "page": "https://bar.example/events/", "date": "2026-11-20"},
            {"thing": "place:inn", "rung": "own", "page": "https://www.facebook.com/inn/events", "date": "2026-11-20"},
            {"thing": "place:lot", "rung": "search", "page": "https://lot.example/js", "date": "2026-11-21"},
            {"thing": "activity:a3", "rung": "school", "page": "https://apollo.example/hockey", "date": "2027-04-01"},
            {"thing": "activity:a1", "rung": "none", "page": "", "searches": "lots"},
        ]
        (out / "scheduled" / "pages.jsonl").write_text("".join(json.dumps(a) + "\n" for a in answers))
        db = FakeDb()
        rows_out, soc, said = keep(out, entries, db, dry_run=True, now=now, readable=lambda u: "/js" not in u)
        check([(r["id"], r["state"]) for r in rows_out] == [(None, "new")] and rows_out[0]["name"] == "Lions Club"
              and soc == [{"thing": "Inn", "url": "https://www.facebook.com/inn/events"}],
              "a page no entry owns is new; a social page is listed apart")
        check(said[0] == "[scheduled] walked 6 of 6: a page with a date for 5 (school 1, broad 0, own 2, search 2), none 1; 0 web searches"
              and any("bar.example/events/ (already read)" in s for s in said)
              and any("apollo.example/hockey (no date in the next 90 days)" in s for s in said)
              and any("lot.example/js (won't read by a plain fetch)" in s for s in said)
              and said[-1] == "[scheduled] would remember 6 things walked" and not db.writes(),
              f"a dry run says what it took out and why, and writes nothing: {said}")

    def refuse(url):
        raise RuntimeError("robots.txt disallows -> switch method to search_snippet")
    check(read_page("u", refuse) == "won't read: robots.txt disallows -> switch method to search_snippet"
          and read_page("u", lambda url: (200, "<p>Fish fry</p><script>x</script>")) == "Fish fry",
          "read: the page's text, or why it won't read in one line")
    check(kind_of("https://x.org/events/?ical=1") == "ical" and kind_of("https://x.org/feed/") == "rss"
          and kind_of("https://x.org/events") == "website", "a page's kind by its address")
    on_site = [{"id": "csbsju-events", "_name": "Campus", "sources": [{"url": "https://my.csbsju.edu/api/"}]},
               {"id": "music", "_name": "Music", "sources": [{"url": "https://www.csbsju.edu/music/events-new/"}]},
               {"id": "csb", "_name": "CSB", "sources": [{"url": "https://www.csbsju.edu/calendar/"}]}]
    check(entry_for("https://csbsju.edu/music/events-new", {"entry": "csb"}, on_site)["id"] == "music"
          and entry_for("https://www.csbsju.edu/music/other", {"entry": "csb"}, on_site)["id"] == "csb"
          and entry_for("https://elsewhere.org/", {"entry": None}, on_site) is None,
          "the entry naming the page, else the thing's own on that site")

    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", choices=("count", "walk", "read", "keep"))
    ap.add_argument("url", nargs="?")
    ap.add_argument("--most", type=int, default=MOST)
    ap.add_argument("--only", nargs="+", help="walk: these things' keys (activity:<id>, place:<entry>, group:<id>)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--town", default=DEFAULT)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
    if args.command == "read":
        return print(read_page(args.url))
    now = datetime.now(timezone.utc)
    import read_events
    today = now.astimezone(read_events.LOCAL).date()
    if args.command == "keep":
        import registry
        return keep(out_dir(), [e for e in registry.load(find_root())[0] if e["_town"] == args.town], dry_run=args.dry_run, now=now)
    db = Supabase()
    all_things, _ = load_all(db, today, town=args.town)
    if args.command == "count":
        return print("\n".join(count_lines(all_things)))
    if args.command == "walk":
        return walk(out_dir(), all_things, last_walks(db) if not args.only else {}, now, args.most, args.only, args.town)
    ap.print_help()


if __name__ == "__main__":
    main()
