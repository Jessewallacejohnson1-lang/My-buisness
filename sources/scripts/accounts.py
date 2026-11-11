#!/usr/bin/env python3
"""
accounts.py: once a month, every place's Facebook and Instagram pages, found again (Jesse,
2026-10-23: "apify can help find places too monthly for 2 bucks"). Apify's Google Maps crawler
looks up each registry place by its name and address on its own schedule (task and schedule
`bp-monthly-places`, the 1st at 5am Chicago, about 0.5¢ a place) and reads the place's own
website for its social links. `report` then matches each result to its place and lists what
the social watch's page list (sources/social/<town>.json) is missing: new pages, pages that
changed, and places Google now calls closed. Nothing is written for those: Jesse approves the
list, and a session adds the pages and runs `social.py setup`. Finding places nobody has listed
yet stays with town-discovery.

The same results carry each place's Google hours, and those go live on their own (Jesse,
2026-10-25: hours are a fact; BP app business-hours): `report` writes every place whose hours
changed or that has hours for the first time to `places.hours`, the business page's open-till
row, and lists them. It needs SUPABASE_URL and a key (db.py); without them it only
lists. A place Google gives no hours keeps the ones it has, and so does one whose registry entry says
`hours_from: website` (its own site is newer than Google's: Jesse, 2026-10-26), or whose week the social watch
read from its own post (`from` in `places.hours`, written by morning.py save; BP app business-hours 02).

A Google result is the place only when its phone, its street (house number and first street
word) or its website's domain matches the registry's (the 2026-10-22 pass's rule). A link
counts when the place's own website or its Google listing gives it, and is the one whose
handle names the place when several do.

  python3 sources/scripts/accounts.py setup     make or update the task and schedule
  python3 sources/scripts/accounts.py report [--town T]   the latest month's run, matched (.runs/accounts/)
  python3 sources/scripts/accounts.py tagged [--town T]   Instagram accounts our pages tagged 3+ times this month
                                                          (report prints them too)
  python3 sources/scripts/accounts.py --selftest
"""

import argparse, json, os, re, sys, urllib.parse, urllib.request
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import key_headers
from registry import find_root, load
from social import api, by_name, items
from towns import DEFAULT, lookup

TASK, ACTOR, CAP = "bp-monthly-places", "compass~crawler-google-places", 3.00
TAGGED_AT_LEAST, TAGGED_BY_AT_LEAST = 3, 2  # tags in a month, and by how many different pages, before an account is proposed
CRON = "0 5 1 * *"
NOT_THE_PLACE = {"squarespace", "wix", "weebly", "godaddy", "shopify", "wordpress", "vagaro", "vagaropro",
                 "bookedonvagaro", "mindbody", "mindbodyonline", "square", "linktree", "yelp", "google",
                 "facebook", "instagram", "meta", "hashtag", "acehardware", "kwiktrip", "statefarm",
                 "edwardjones", "installedbuildingproducts",
                 "fmcsa", "dot_fmcsa",  # Iman Carrier's site links the federal trucking agency (2026-11-11)
                 "minnesotadnr"}  # the statewide DNR, not the St. Wendel Tamarack Bog it runs (2026-11-11)
STOP = {"the", "and", "llc", "inc", "saint", "joseph", "company", "minnesota", "central", "center", "services"}


def digits(phone):
    d = re.sub(r"\D", "", phone or "")
    return d[-10:] if len(d) >= 10 else ""


# Google writes "Co Rd 75" where a place's own page says "County Road 75".
COUNTY = {"co": "county", "cr": "county", "cty": "county"}


def street(addr):
    m = re.match(r"\s*(\d+)\s+(?:[NSEW]\.?\s+)?([A-Za-z0-9]+)", addr or "")
    return (m.group(1), COUNTY.get(m.group(2).lower(), m.group(2).lower())) if m else None


def domain(url):
    m = re.match(r"(?:https?://)?(?:www\.)?([^/:?#]+)", (url or "").strip().lower())
    return m.group(1) if m and "." in m.group(1) else ""


def handle(url):
    m = re.search(r"\.com/(?:pages/)?([^/?#]+)", url or "")
    return m.group(1).lower().rstrip(".") if m else ""


def social(url):
    """('facebook'|'instagram', clean url) for a link to a page, or None for anything else."""
    raw = (url or "").strip()
    if raw and not raw.lower().startswith("http"):
        raw = "https://" + raw.lstrip("/")
    m = re.search(r"facebook\.com/profile\.php\?(?:.*&)?id=(\d+)", raw)
    u = f"https://www.facebook.com/profile.php?id={m.group(1)}" if m else raw.split("?")[0].rstrip("/").rstrip(".")
    low = u.lower()
    if low.endswith("profile.php") or handle(u) in NOT_THE_PLACE:
        return None
    if re.search(r"facebook\.com/(sharer|share|dialog|plugins|tr|events/|groups/|photo|watch|hashtag)", low):
        return None
    if "facebook.com/" in low:
        return ("facebook", re.sub(r"^https?://(m\.|www\.)?", "https://www.", u))
    if re.search(r"instagram\.com/(p|reel|explore|accounts)/", low):
        return None
    if "instagram.com/" in low:
        return ("instagram", re.sub(r"^https?://(www\.)?", "https://www.", u))
    return None


def website(entry):
    return next((s["url"] for s in entry["sources"] if s.get("kind") == "website" and s.get("url", "").startswith("http")), "")


def search_of(entry):
    """Google's search for a place: its name and address in its own town ("St. Joseph MN" reads "St. Joseph, MN")."""
    return f"{entry['_name']}, {entry['address']}, {', '.join(lookup(entry.get('_town', DEFAULT))['label'].rsplit(' ', 1))}"


def town_words(town):
    """The town's name as an address writes it: "St. Joseph", "St Joseph" or "Saint Joseph"."""
    name = lookup(town)["display"]
    rest = re.sub(r"^(?:St\.?|Saint)\s+", "", name)
    return (r"(St\.?|Saint) " if rest != name else "") + re.escape(rest)


def places(root, app=None):
    """The places worth a search: open ones with an address, so a result can be checked. The
    registry's address comes first (non-Google sources only, ADR-016); else the app's page for the
    place (`app`: entry id to `places.address`), so every place in the app is checked."""
    out = []
    for e in load(root)[0]:
        address = e.get("address") or re.sub(r",\s*" + town_words(e.get("_town", DEFAULT)) + r"\b.*$", "", (app or {}).get(e["id"], ""))
        if e["status"] in ("active", "proposed") and address:
            out.append({**e, "address": address})
    return out


def app_addresses():
    """The app's place pages' addresses by entry id; {} without the keys."""
    rows = db("GET", "/rest/v1/places?select=entry_id,address&entry_id=not.is.null&address=not.is.null")
    return {r["entry_id"]: r["address"] for r in rows or []}


def same_place(entry, item):
    why = []
    if digits(entry.get("phone")) and digits(entry.get("phone")) == digits(item.get("phone") or item.get("phoneUnformatted")):
        why.append("phone")
    if street(entry.get("address")) and street(entry.get("address")) == street(item.get("street") or item.get("address")):
        why.append("street")
    if domain(website(entry)) and domain(website(entry)) == domain(item.get("website")):
        why.append("website")
    return why


def links_of(item):
    found = {}
    for u in (item.get("facebooks") or []) + (item.get("instagrams") or []) + [item.get("website")]:
        s = social(u)
        if s:
            found.setdefault(s[0], set()).add(s[1])
    return {k: sorted(v) for k, v in found.items()}


def pick(name, urls, freq):
    """One link: the only one (unless other places share it and its handle doesn't name this
    place), or the one whose handle names the place best. None when unclear."""
    words = [w for w in re.findall(r"[a-z0-9]+", name.lower().replace("’", "").replace("'", "")) if len(w) >= 3 and w not in STOP]
    score = lambda u: sum(w in re.sub(r"[^a-z0-9]", "", handle(u)) for w in words)
    if len(urls) == 1:
        return urls[0] if freq[urls[0].lower()] == 1 or score(urls[0]) else None
    ranked = sorted(urls, key=score, reverse=True)
    if ranked and score(ranked[0]) and score(ranked[0]) > score(ranked[1]):
        return ranked[0]
    return None


DAYS = {"Sunday": "sun", "Monday": "mon", "Tuesday": "tue", "Wednesday": "wed", "Thursday": "thu",
        "Friday": "fri", "Saturday": "sat"}
DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]  # a week as a neighbour reads it
TIME = re.compile(r"(\d{1,2})(?::(\d{2}))?\s*([AP]M)?", re.I)


def clock(text, meridiem):
    """"9:30 PM" (or "9:30" with the range's other half's PM) as "21:30"; None when unreadable."""
    m = TIME.fullmatch(text.strip())
    if not m or not (m.group(3) or meridiem):
        return None
    h, mins, pm = int(m.group(1)), int(m.group(2) or 0), (m.group(3) or meridiem).upper() == "PM"
    if not 1 <= h <= 12 or mins > 59:
        return None
    return f"{h % 12 + (12 if pm else 0):02d}:{mins:02d}"


def day_ranges(text):
    """One day's Google words, "11 AM to 2 PM, 4 to 10 PM", as [["11:00","14:00"],["16:00","22:00"]];
    [] closed; None when any part is unreadable, so a misread day never stands in for a real one."""
    text = re.sub(r"[\u202f\u2009\xa0]", " ", text).strip()
    if text.lower() == "closed":
        return []
    if text.lower().startswith("open 24"):
        return [["00:00", "24:00"]]
    out = []
    for part in re.split(r"\s*,\s*", text):
        ends = re.split(r"\s*(?:to|–|-)\s*", part)
        if len(ends) != 2:
            return None
        end_m = TIME.fullmatch(ends[1].strip())
        end = clock(ends[1], None)
        start = clock(ends[0], end_m.group(3) if end_m else None)
        # "11 to 2 PM" is 11 AM: a start borrowed the end's PM and landed after it.
        if start and end and not TIME.fullmatch(ends[0].strip()).group(3) and start > end and end != "00:00":
            start = clock(ends[0], "AM")
        if not start or not end:
            return None
        out.append([start, end])
    return out


def hours_of(item):
    """Google's week, as `places.hours` keeps it ({"sun": [...], ..., "sat": [...]}); None when Google
    gives none or any day is unreadable."""
    days = {DAYS.get(d.get("day")): day_ranges(d.get("hours") or "") for d in item.get("openingHours") or []}
    keys = list(DAYS.values())
    if set(days) != set(keys) or any(v is None for v in days.values()):
        return None
    return {k: days[k] for k in keys}


def match(entries, results, pages):
    """What the page list is missing: {'new': [...], 'changed': [...], 'closed': [...], 'counts': {...}}."""
    by_search = {search_of(e): e for e in entries}
    have = {(p["entry_id"], p["kind"]): p["url"].rstrip("/").lower() for p in pages}
    matched, closed, hours, counts = [], [], [], Counter(results=len(results))
    for it in results:
        e = by_search.get(it.get("searchString"))
        if not e or not same_place(e, it):
            counts["no_match"] += 1
            continue
        counts["matched"] += 1
        if it.get("permanentlyClosed"):
            closed.append({"entry_id": e["id"], "name": e["_name"]})
        matched.append((e, links_of(it)))
        # `hours_from: website`: the place's own site is newer than Google (Jesse, 2026-10-26).
        if hours_of(it) and e.get("hours_from") != "website":
            hours.append({"entry_id": e["id"], "name": e["_name"], "hours": hours_of(it)})
    freq = Counter(u.lower() for _, found in matched for urls in found.values() for u in urls)
    new, changed = [], []
    for e, found in matched:
        for kind in ("facebook", "instagram"):
            url = pick(e["_name"], found.get(kind, []), freq)
            if not url:
                continue
            row = {"entry_id": e["id"], "name": e["_name"], "kind": kind, "url": url}
            old = have.get((e["id"], kind))
            if old is None:
                new.append(row)
            elif old != url.rstrip("/").lower():
                changed.append({**row, "was": old})
    counts.update(new=len(new), changed=len(changed), closed=len(closed))
    return {"new": new, "changed": changed, "closed": closed, "hours": hours, "counts": dict(counts)}


def db(method, path, body=None):
    """The project's REST API with the routine's key (db.py); None when the keys aren't here."""
    url, keys = os.environ.get("SUPABASE_URL", "").rstrip("/"), key_headers()
    if not url or not keys:
        return None
    h = {**keys, "Content-Type": "application/json"}
    req = urllib.request.Request(url + path, json.dumps(body).encode() if body is not None else None, h, method=method)
    with urllib.request.urlopen(req, timeout=60) as r:
        text = r.read()
    return json.loads(text) if text.strip() else []


def new_hours(found, live):
    """The places whose hours differ from the page's (`live`: entry id to `places.hours`), each laid over what
    the page has: a season stays (Google has none, and it was read from the place's own site), and a post that
    names a few days leaves the rest of the week. A week a place posted carries `from` (its post, when it was
    saved, and the days it changed: BP app business-hours 02); Google's never does, so only another post
    replaces it, as `hours_from: website` keeps Google off a week read by hand (Jesse, 2026-10-26)."""
    out = []
    for f in found:
        if f["entry_id"] not in live:
            continue
        was = live[f["entry_id"]] or {}
        if was.get("from") and not f["hours"].get("from"):
            continue
        hours, changed = {**was, **f["hours"]}, [d for d in DAY_KEYS if f["hours"].get(d, was.get(d)) != was.get(d)]
        if not changed:
            continue
        if "from" in f["hours"]:
            hours["from"] = {**f["hours"]["from"], "was": {d: was.get(d) for d in changed}}
        # A post's few days over a place with no whole week would show the rest closed, and Google would never
        # mend it: `short` names the days missing, and it is not written.
        short = [d for d in DAY_KEYS if d not in hours] if "from" in f["hours"] else []
        out.append({**f, "hours": hours, "was": live[f["entry_id"]], **({"short": short} if short else {})})
    return out


def write_hours(found, rest=None, write=True):
    """Puts each changed week on its place; returns the changes and whether they were written (`write` False:
    only found). `rest`: a Db's rest, as the social watch's save gives; else the keys in the environment."""
    rest = rest or (lambda method, path, body=None: db(method, "/rest/v1/" + path, body))
    rows = rest("GET", "places?select=entry_id,hours&entry_id=not.is.null")
    if rows is None:
        return found, False
    changes = new_hours(found, {r["entry_id"]: r["hours"] for r in rows})
    for c in [c for c in changes if not c.get("short")] if write else []:
        rest("PATCH", f"places?entry_id=eq.{urllib.parse.quote(c['entry_id'])}", {"hours": c["hours"]})
    return changes, write


def clock_words(a, b):
    """["16:00", "21:00"] as "4–9 PM", ["10:00", "21:00"] as "10 AM–9 PM"."""
    def say(t):
        h, m = map(int, t.split(":"))
        return f"{h % 12 or 12}{f':{m:02d}' if m else ''}", "AM" if h % 24 < 12 else "PM"
    (s, sm), (e, em) = say(a), say(b)
    return f"{s}–{e} {em}" if sm == em else f"{s} {sm}–{e} {em}"


def day_words(ranges):
    return ", ".join(clock_words(a, b) for a, b in ranges) if ranges else "closed"


def change_words(name, hours):
    """A week a post changed, in plain words: "Milk & Honey Ciders, from its post <url>: Tue 4–9 PM, now
    closed; Wed 4–9 PM, now closed"."""
    mark, days = hours["from"], []
    for d in (d for d in DAY_KEYS if d in mark["was"]):
        old = mark["was"][d]
        days.append(f"{d.title()} " + (f"{day_words(old)}, now " if old is not None else "now ") + day_words(hours.get(d)))
    return f"{name}, from its post {mark['post']}: " + "; ".join(days)


def setup():
    root = find_root()
    body = {"input": {"searchStringsArray": [search_of(e) for e in places(root, app_addresses())], "maxCrawledPlacesPerSearch": 1,
                      "language": "en", "scrapeContacts": True, "maxImages": 0, "maxReviews": 0},
            "options": {"timeoutSecs": 3600, "maxTotalChargeUsd": CAP}}
    tasks = by_name("/actor-tasks")
    tid = (api("PUT", f"/actor-tasks/{tasks[TASK]['id']}", body) if TASK in tasks
           else api("POST", "/actor-tasks", {"actId": ACTOR, "name": TASK, **body}))["data"]["id"]
    sched = {"name": TASK, "cronExpression": CRON, "timezone": "America/Chicago", "isEnabled": True,
             "isExclusive": True, "actions": [{"type": "RUN_ACTOR_TASK", "actorTaskId": tid}]}
    have = by_name("/schedules")
    api("PUT", f"/schedules/{have[TASK]['id']}", sched) if TASK in have else api("POST", "/schedules", sched)
    print(f"[accounts] {TASK}: {len(body['input']['searchStringsArray'])} places, the 1st of each month at 5am Chicago, cap ${CAP:.0f}")


def tag_counts(rows, known):
    """{account: (times, [pages that tagged it])} from Instagram rows the social watch read: accounts our
    pages tagged or mentioned TAGGED_AT_LEAST times or more, TAGGED_BY_AT_LEAST different pages among them (one
    page's own staff, athletes and clients tag high on their own: 25 names on 2026-11-08's first count, one of
    them a place), less the pages themselves and the list's own."""
    counts, by = Counter(), {}
    owners = {str(r.get("ownerUsername") or "").lower() for r in rows}
    for r in rows:
        owner = str(r.get("ownerUsername") or "").lower()
        names = set(r.get("mentions") or []) | {t.get("username") for t in r.get("taggedUsers") or [] if isinstance(t, dict)}
        for n in names:
            n = str(n or "").lower().lstrip("@")
            if n and n not in known and n not in owners:
                counts[n] += 1
                by.setdefault(n, set()).add(owner)
    return {n: (c, sorted(by[n])) for n, c in counts.most_common() if c >= TAGGED_AT_LEAST and len(by[n]) >= TAGGED_BY_AT_LEAST}


def tagged(town=DEFAULT, days=31):
    """Instagram accounts the town's pages tagged TAGGED_AT_LEAST times or more in the last month's posts the
    social watch already read (Apify keeps a run's rows 31 days, and reading them costs nothing), that the page
    list lacks. The 2026-11-03 search test found @joetownmn this way, tagged 19 times and never watched (Jesse,
    2026-11-08: yes). Returns (accounts, posts read)."""
    root = find_root()
    pages = json.loads((root / "sources" / "social" / f"{town}.json").read_text())
    known = {m.group(1).lower() for p in pages if p["kind"] == "instagram"
             for m in [re.search(r"instagram\.com/([^/?#]+)", p["url"])] if m}
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S")
    rows = []
    for name, task in by_name("/actor-tasks").items():
        if name.startswith(("bp-busy-", "bp-weekly-")) and name.endswith("-instagram"):  # bp-weekly-<day>-instagram
            for r in api("GET", f"/actor-tasks/{task['id']}/runs?desc=true&limit=100")["data"]["items"]:
                if r["status"] == "SUCCEEDED" and (r.get("startedAt") or "")[:19] >= since:
                    rows += items(r["defaultDatasetId"])
    return tag_counts(rows, known), len(rows)


def say_tagged(tags, n):
    print(f"[accounts] tagged: {len(tags)} Instagram accounts {TAGGED_BY_AT_LEAST}+ of our pages tagged {TAGGED_AT_LEAST}+ times "
          f"in {n} posts this month and the list lacks")
    for a, (c, b) in tags.items():
        print(f"  @ {a}: tagged {c} times by {', '.join(b)}")


def report(town=DEFAULT):
    """The latest run matched to `town`'s places and its social page list, and the accounts they tag."""
    root = find_root()
    task = by_name("/actor-tasks").get(TASK)
    runs = api("GET", f"/actor-tasks/{task['id']}/runs?desc=true&limit=5")["data"]["items"] if task else []
    run = next((r for r in runs if r["status"] in ("SUCCEEDED", "TIMED-OUT", "ABORTED")), None)
    if not run:
        return print("[accounts] no finished monthly run yet")
    pages = json.loads((root / "sources" / "social" / f"{town}.json").read_text())
    out = match([e for e in places(root, app_addresses()) if e["_town"] == town], items(run["defaultDatasetId"]), pages)
    out["run"] = {k: run.get(k) for k in ("id", "status", "finishedAt", "usageTotalUsd")}
    try:
        tags, n = tagged(town)
        out["tagged"] = [{"account": a, "times": c, "by": b} for a, (c, b) in tags.items()]
    except Exception as e:  # the proposal still lists Google's finds
        tags, n = {}, 0
        print(f"[accounts] tagged: not counted ({e})")
    dest = root / ".runs" / "accounts"
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "proposal.json").write_text(json.dumps(out, indent=1))
    c = out["counts"]
    print(f"[accounts] run {run['id']} ({run['status']}, ${float(run.get('usageTotalUsd') or 0):.2f}): "
          f"{c.get('matched', 0)} of {c['results']} results matched their place; "
          f"{c['new']} new pages, {c['changed']} changed, {c['closed']} places Google calls closed ({dest / 'proposal.json'})")
    for r in out["new"]:
        print(f"  + {r['name']}: {r['kind']} {r['url']}")
    for r in out["changed"]:
        print(f"  ~ {r['name']}: {r['kind']} {r['was']} -> {r['url']}")
    for r in out["closed"]:
        print(f"  x {r['name']}: Google says permanently closed")
    say_tagged(tags, n)
    changes, written = write_hours(out["hours"])
    print(f"[accounts] hours: {len(changes)} " + ("places updated on their pages" if written else
          "places with Google hours (SUPABASE_URL or a key not set: nothing written)"))
    if written:
        for c in changes:
            print(f"  h {c['name']}: " + ("hours added" if c["was"] is None else "hours changed"))


def selftest():
    e = {"id": "krewe", "_name": "Krewe", "address": "21 College Ave N", "phone": "320-555-0101", "status": "active",
         "sources": [{"kind": "website", "url": "https://krewe.com/menu"}]}
    s = search_of(e)
    hit = {"searchString": s, "street": "21 College Ave N", "facebooks": ["facebook.com/KreweStJoe/"],
           "instagrams": ["https://instagram.com/p/abc", "https://www.instagram.com/krewe"], "website": "https://krewe.com"}
    miss = {"searchString": s, "street": "9 Elm St", "phone": "320-555-9999", "facebooks": ["https://facebook.com/other"]}
    out = match([e], [hit, miss], [{"entry_id": "krewe", "kind": "instagram", "url": "https://www.instagram.com/krewe/"}])
    assert out["counts"]["matched"] == 1 and out["counts"]["no_match"] == 1, "only a result with the place's street, phone or site is it"
    assert out["new"] == [{"entry_id": "krewe", "name": "Krewe", "kind": "facebook", "url": "https://www.facebook.com/KreweStJoe"}], "a new page"
    assert not out["changed"], "a page the list already has is not news"
    assert social("https://www.facebook.com/sharer/sharer.php?u=x") is None and social("https://wix.com/x") is None, "share links and site builders"
    assert pick("Krewe", ["https://www.facebook.com/a", "https://www.facebook.com/krewe"], Counter()) == "https://www.facebook.com/krewe"
    closed = match([e], [{**hit, "permanentlyClosed": True}], [])
    assert closed["closed"] == [{"entry_id": "krewe", "name": "Krewe"}], "a place Google calls closed"
    assert day_ranges("11\u202fAM to 2\u202fPM, 4 to 10\u202fPM") == [["11:00", "14:00"], ["16:00", "22:00"]], "two ranges"
    assert day_ranges("11 to 2 PM") == [["11:00", "14:00"]] and day_ranges("4 PM to 1 AM") == [["16:00", "01:00"]]
    assert day_ranges("Closed") == [] and day_ranges("Open 24 hours") == [["00:00", "24:00"]]
    assert day_ranges("12 to 8 PM") == [["12:00", "20:00"]] and day_ranges("by appointment") is None
    week = [{"day": d, "hours": "9 AM to 5 PM"} for d in DAYS]
    assert hours_of({"openingHours": week})["mon"] == [["09:00", "17:00"]], "a whole week"
    assert hours_of({"openingHours": week[:6]}) is None, "a week missing a day is no week"
    found = [{"entry_id": "a", "name": "A", "hours": {"mon": []}}, {"entry_id": "b", "name": "B", "hours": {"mon": []}}]
    assert [c["entry_id"] for c in new_hours(found, {"a": {"mon": []}, "b": None})] == ["b"], "only changed hours"
    assert street("709 County Road 75 W") == street("709 Co Rd 75") == ("709", "county"), "Co Rd is County Road"
    market = {"entry_id": "m", "name": "M", "hours": {"fri": [["15:00", "18:00"]]}}
    assert not new_hours([market], {"m": {"fri": [["15:00", "18:00"]], "season": ["05-08", "10-16"]}}), "a season is not a change"
    assert new_hours([market], {"m": {"fri": [], "season": ["05-08", "10-16"]}})[0]["hours"]["season"] == ["05-08", "10-16"], "new hours keep the season"
    own = match([{**e, "hours_from": "website"}], [{**hit, "openingHours": week}], [])
    assert not own["hours"] and match([e], [{**hit, "openingHours": week}], [])["hours"], "a place's own site beats Google when marked"
    # A week a place posted (BP app business-hours 02): Milk & Honey's winter hours over the week it had.
    pm = lambda a, b: [[a, b]]
    had = {"mon": [], "tue": pm("16:00", "21:00"), "wed": pm("16:00", "21:00"), "thu": pm("16:00", "21:00"),
           "fri": pm("12:00", "21:00"), "sat": pm("10:00", "21:00"), "sun": pm("10:00", "18:00")}
    winter = {d: day_ranges(t) for d, t in {"mon": "Closed", "tue": "Closed", "wed": "Closed", "thu": "4 PM to 9 PM",
              "fri": "12 PM to 9 PM", "sat": "10 AM to 9 PM", "sun": "10 AM to 6 PM"}.items()}
    mark = {"post": "https://www.facebook.com/x/posts/1", "at": "2026-11-02T23:31:00+00:00"}
    post = {"entry_id": "mh", "name": "Milk & Honey Ciders", "hours": {**winter, "from": mark}}
    [c] = new_hours([post], {"mh": had})
    assert {d: c["hours"][d] for d in DAY_KEYS} == {**had, "tue": [], "wed": []}, "a post's week replaces the days it names"
    assert c["hours"]["from"] == {**mark, "was": {"tue": had["tue"], "wed": had["wed"]}}, "the week says from what post, and what it was"
    assert change_words(c["name"], c["hours"]) == ("Milk & Honey Ciders, from its post https://www.facebook.com/x/posts/1: "
                                                   "Tue 4–9 PM, now closed; Wed 4–9 PM, now closed"), change_words(c["name"], c["hours"])
    posted = c["hours"]
    assert not new_hours([{"entry_id": "mh", "name": "M", "hours": had}], {"mh": posted}), "Google leaves a week a place posted"
    assert new_hours([{**post, "hours": {"mon": pm("16:00", "21:00"), "from": mark}}], {"mh": posted})[0]["hours"]["tue"] == [], \
        "a newer post changes only the days it names"
    assert not new_hours([post], {"mh": posted}), "the same week posted again is no change"
    [half] = new_hours([{**post, "hours": {"thu": pm("16:00", "21:00"), "from": mark}}], {"mh": None})
    assert half["short"] == ["mon", "tue", "wed", "fri", "sat", "sun"], "a few days over no week are short"
    seasonal = new_hours([{**post, "hours": {"fri": [], "from": mark}}], {"mh": {**had, "season": ["05-08", "10-16"]}})[0]["hours"]
    assert seasonal["season"] == ["05-08", "10-16"] and seasonal["fri"] == [], "a posted week keeps the season"
    assert [day_words(r) for r in (pm("10:00", "21:00"), pm("12:00", "21:00"), [["10:30", "14:00"], ["17:00", "24:00"]], [])] \
        == ["10 AM–9 PM", "12–9 PM", "10:30 AM–2 PM, 5 PM–12 AM", "closed"], "hours in plain words"
    calls = []
    fake = lambda method, path, body=None: calls.append((method, path)) or ([{"entry_id": "mh", "hours": had}] if method == "GET" else None)
    assert write_hours([post], fake, write=False)[0] and calls == [("GET", "places?select=entry_id,hours&entry_id=not.is.null")], "a dry run writes nothing"
    assert write_hours([post], fake)[1] and calls[-1] == ("PATCH", "places?entry_id=eq.mh"), "a change is written to its place"
    calls.clear()
    short = {**post, "hours": {"thu": pm("16:00", "21:00"), "from": mark}}
    assert write_hours([short], lambda m, p, b=None: calls.append(m) or [{"entry_id": "mh", "hours": None}])[0][0]["short"] \
        and calls == ["GET"], "a short week is never written"
    rows = [{"ownerUsername": "salsbarandgrill", "mentions": [], "taggedUsers": [{"username": "joetownmn"}]},
            {"ownerUsername": "joetownsmash", "mentions": ["thehousefoodandtap"],
             "taggedUsers": [{"username": "joetownmn"}, {"username": "thehousefoodandtap"}]},
            {"ownerUsername": "joetownmn", "mentions": ["rubinskivisual"],
             "taggedUsers": [{"username": "salsbarandgrill"}, {"username": "thehousefoodandtap"}]},
            {"ownerUsername": "krewe", "mentions": ["@thehousefoodandtap"], "taggedUsers": None}] \
        + [{"ownerUsername": "csb_athletics", "mentions": [], "taggedUsers": [{"username": "a_player"}]}] * 3
    assert tag_counts(rows, {"joetownmn"}) == {"thehousefoodandtap": (3, ["joetownmn", "joetownsmash", "krewe"])}, \
        "an account tagged 3+ times by 2+ of our pages, not on the list and not one of them, is proposed with who tagged " \
        "it; one page's own player, tagged 3 times by it alone, is not"
    print("accounts.py selftest: 30 passed, 0 failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["setup", "report", "tagged"])
    ap.add_argument("--town", default=DEFAULT, help="report: the town whose places and page list to match "
                                                     "(setup searches every town's places, each in its own town)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.step:
        ap.error("setup, report or tagged")
    lookup(args.town)
    if args.step == "tagged":
        return say_tagged(*tagged(args.town))
    setup() if args.step == "setup" else report(args.town)


if __name__ == "__main__":
    main()
