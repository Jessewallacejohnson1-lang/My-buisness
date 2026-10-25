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
row, and lists them. It needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY; without them it only
lists. A place Google gives no hours keeps the ones it has.

A Google result is the place only when its phone, its street (house number and first street
word) or its website's domain matches the registry's (the 2026-10-22 pass's rule). A link
counts when the place's own website or its Google listing gives it, and is the one whose
handle names the place when several do.

  python3 sources/scripts/accounts.py setup     make or update the task and schedule
  python3 sources/scripts/accounts.py report    the latest month's run, matched (.runs/accounts/)
  python3 sources/scripts/accounts.py --selftest
"""

import argparse, json, os, re, sys, urllib.parse, urllib.request
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from social import TOWN, api, by_name, items

TASK, ACTOR, CAP = "bp-monthly-places", "compass~crawler-google-places", 3.00
CRON = "0 5 1 * *"
NOT_THE_PLACE = {"squarespace", "wix", "weebly", "godaddy", "shopify", "wordpress", "vagaro", "vagaropro",
                 "bookedonvagaro", "mindbody", "mindbodyonline", "square", "linktree", "yelp", "google",
                 "facebook", "instagram", "meta", "hashtag", "acehardware", "kwiktrip", "statefarm",
                 "edwardjones", "installedbuildingproducts"}
STOP = {"the", "and", "llc", "inc", "saint", "joseph", "company", "minnesota", "central", "center", "services"}


def digits(phone):
    d = re.sub(r"\D", "", phone or "")
    return d[-10:] if len(d) >= 10 else ""


def street(addr):
    m = re.match(r"\s*(\d+)\s+(?:[NSEW]\.?\s+)?([A-Za-z0-9]+)", addr or "")
    return (m.group(1), m.group(2).lower()) if m else None


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
    return f"{entry['_name']}, {entry['address']}, St. Joseph, MN"


def places(root):
    """The places worth a search: open ones with an address, so a result can be checked."""
    return [e for e in load(root)[0] if e["status"] in ("active", "proposed") and e.get("address")]


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
        if hours_of(it):
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
    """The project's REST API with the service key; None when the keys aren't here."""
    url, key = os.environ.get("SUPABASE_URL", "").rstrip("/"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        return None
    h = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    req = urllib.request.Request(url + path, json.dumps(body).encode() if body is not None else None, h, method=method)
    with urllib.request.urlopen(req, timeout=60) as r:
        text = r.read()
    return json.loads(text) if text.strip() else []


def new_hours(found, live):
    """The places whose Google hours differ from the page's (`live`: entry id to `places.hours`)."""
    return [{**f, "was": live.get(f["entry_id"])} for f in found
            if f["entry_id"] in live and f["hours"] != live[f["entry_id"]]]


def write_hours(found):
    """Puts each changed week on its place; returns the changes and whether they were written."""
    rows = db("GET", "/rest/v1/places?select=entry_id,hours&entry_id=not.is.null")
    if rows is None:
        return found, False
    changes = new_hours(found, {r["entry_id"]: r["hours"] for r in rows})
    for c in changes:
        db("PATCH", f"/rest/v1/places?entry_id=eq.{urllib.parse.quote(c['entry_id'])}", {"hours": c["hours"]})
    return changes, True


def setup():
    root = find_root()
    body = {"input": {"searchStringsArray": [search_of(e) for e in places(root)], "maxCrawledPlacesPerSearch": 1,
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


def report():
    root = find_root()
    task = by_name("/actor-tasks").get(TASK)
    runs = api("GET", f"/actor-tasks/{task['id']}/runs?desc=true&limit=5")["data"]["items"] if task else []
    run = next((r for r in runs if r["status"] in ("SUCCEEDED", "TIMED-OUT", "ABORTED")), None)
    if not run:
        return print("[accounts] no finished monthly run yet")
    pages = json.loads((root / "sources" / "social" / f"{TOWN}.json").read_text())
    out = match(places(root), items(run["defaultDatasetId"]), pages)
    out["run"] = {k: run.get(k) for k in ("id", "status", "finishedAt", "usageTotalUsd")}
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
    changes, written = write_hours(out["hours"])
    print(f"[accounts] hours: {len(changes)} " + ("places updated on their pages" if written else
          "places with Google hours (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY not set: nothing written)"))
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
    print("accounts.py selftest: 13 passed, 0 failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["setup", "report"])
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.step:
        ap.error("setup or report")
    setup() if args.step == "setup" else report()


if __name__ == "__main__":
    main()
