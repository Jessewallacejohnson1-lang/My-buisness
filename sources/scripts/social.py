#!/usr/bin/env python3
"""
social.py: the social watch's script half (registry ADR-020, amended 2026-10-22). Places'
public Facebook and Instagram posts, read through Apify and never logged in, laid out exactly
as morning.py lays out changed pages, so the routine's next steps are the morning job's own:
the cheap model flags (flag.md), the routine's model judges (judge.md), and `morning.py save`
writes Events and News (morning.md's Read and judge, and Save). The routine's steps are
sources/models/social.md.

Apify reads the pages on its own clock (Jesse, 2026-10-23: "apify has direct sourcing"), so a
check never waits on the Claude plan: saved tasks hold each list's pages, and schedules start them.
The busy list (`bp-busy-<kind>`) is read at 9:30am and 7pm Chicago (Jesse, 2026-11-10: was noon and
9pm; 2026-11-09: was 6pm and 9pm). Every other page is read once a week, a seventh of them each day at
3pm (`bp-weekly-<day>-<kind>`, with their Facebook Events tabs, a search of Facebook's events for the
town and Facebook's own events page for the town: page_lists). A page's day is its `day` in the list,
set so each day reads a mix of kinds (Jesse, 2026-11-11: "divide the type of events up so a reading
can get a variety"; until then every page was read on Thursdays, one big drop a week). Each read
reaches back to an hour before its task's last good read (since), so a run that the monthly cap or
Facebook stopped is read up by the next. The routines come half an hour or more later
and read whatever Apify saved since the last check they finished, so one the plan's usage limit
skipped (the 9pm one on 2026-10-22) is read by the next.

  setup           makes or updates the tasks and schedules from sources/social/<town>.json, and
                  deletes the busy and weekly ones the list no longer has; run it after the list
                  changes (prepare also refreshes the tasks' pages and how far back they read)
  prepare busy    the busy list's Apify runs that finished since the last busy check
  prepare weekly  the weekly runs that finished since the last weekly check. Either works in parts
                  of about 6 minutes, as morning.py prepare does: run it again while it prints
                  "run again"
  done            after `morning.py save`: marks those runs read, so the next check starts after
                  them. A check that stopped early never marks, and the next reads its runs too.
                  It repeats the pictures line, so the answer carries what pictures cost.
  spend           one line for the morning report, "Apify: $X of $Y this month", with a
                  heads-up past 3/4 of the cap and at the cap (Jesse, 2026-11-04: no slowdown,
                  just say). The cap is whatever Apify reports. The 8 AM check emails this line
                  the morning it first passes either one (private.apify_level, BP app loopholes 13).

A post whose caption is short or gives no time of day also gets its pictures read (Jesse,
2026-10-26): Obbink's trivia night on Oct 29 was on its picture alone, under a one-line caption
("come out to the cocktail lounge…"), and the judge dropped it as a teaser. prepare downloads
up to PICTURES of the post's pictures from the address Apify saved, shrunk, into
.runs/morning/pictures/, and the post's page names them for the cheap model to open. Apify
already returns the addresses, so this costs nothing on Apify; it costs the Claude plan the
tokens of looking at them, which prepare prints as one `[social] pictures` line.

A page Apify says is "not available", or returns nothing at all for, on three reads in a row is set
aside (BP app smooth-mornings 04); "no new posts" is a good read, and a run that missed more than
half its pages (Facebook blocking Apify, a run stopped at its cap) counts against none. The next sync
takes it off its paid list and its day's weekly read tries it, a busy page every week and a weekly page
in the first week of each month; a good read puts it back. A weekly page that posts nothing new
QUIET_AFTER reads in a row is set aside the same way and read in the first week of each month, until
it posts again (Jesse, 2026-11-11). Each page is named once when set aside and once when back.

The mark lives in Apify's own storage (the named key-value store `bp-social-watch`, records
`read-busy` and `read-weekly`), so it survives each routine's throwaway copy; so do the set-aside
pages (record `missed`), saved by `done` with the mark.

Everything lands in .runs/morning/, the morning job's folder (each routine runs in its own copy
of the repository). In the cloud, Apify's REST API is called with no key: the environment's
network secret for api.apify.com adds it on the way out, so the token never enters the session.
APIFY_TOKEN in the environment is used when set; on a Mac with neither, the calls go through
Composio. Only Apify's schedules start paid runs; each task has its own spending cap.

  python3 sources/scripts/social.py setup [--town T]
  python3 sources/scripts/social.py prepare busy|weekly [--today YYYY-MM-DD] [--town T]
  python3 sources/scripts/social.py done [--town T]
  python3 sources/scripts/social.py spend
  python3 sources/scripts/social.py --selftest
"""

import argparse, hashlib, io, json, math, os, re, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
from run import late, failing, ASIDE_AFTER
from morning_run import Run
from batch import layout
from towns import TOWNS, DEFAULT, lookup
import composio

TOWN = DEFAULT  # the town whose page list is read: --town sets it
API = "https://api.apify.com/v2"
POSTS = 20  # most posts read per page per check; a busy page posts a few a day at most
ACTORS = {  # (actor, spending cap in USD per run) for each kind of read; a weekly cap is one day's share
    # Apify bills each page read, a post or none: Facebook half a cent, Instagram a fifth (Nov 2026).
    ("busy", "facebook"): ("apify~facebook-posts-scraper", 0.60),
    ("busy", "instagram"): ("apify~instagram-post-scraper", 0.30),
    ("weekly", "facebook"): ("apify~facebook-posts-scraper", 1.50),  # the whole list was $2.41 on Thursday, Nov 5
    ("weekly", "instagram"): ("apify~instagram-post-scraper", 0.60),  # the whole list was $0.75 on Nov 5
    ("weekly", "events"): ("apify~facebook-events-scraper", 1.50),
    ("weekly", "search"): ("apify~facebook-events-scraper", 1.60),  # three pages (two searches and the town's events page), up to SEARCH_EVENTS each at a cent
}
SEARCH_EVENTS = 50  # most events each search page reads (maxEvents is per start URL); Apify bills each one, a cent apiece
NEAR_KM = 10  # a found event farther than this from the town, by its map position, is someone else's
# A family's own day found by the search never reaches a model (a child's first birthday, 2026-11-03)
PRIVATE_DAY = re.compile(r"\bbirthday|\bbaby shower|\bbridal shower|\bwedding|\bgraduation party|\bcelebration of life|\bfuneral", re.I)
DAYS = ("sun", "mon", "tue", "wed", "thu", "fri", "sat")  # cron's order: 0 is Sunday
WEEKLY_AT = 15  # o'clock, Chicago: each day's share of the weekly list
# Apify's clock, Chicago time: (schedule, cron, run). A busy schedule starts the busy tasks, a day's
# weekly one that day's tasks.
SCHEDULES = ([("bp-busy-930am", "30 9 * * *", "busy"), ("bp-busy-7pm", "0 19 * * *", "busy")]
             + [(f"bp-weekly-{d}", f"0 {WEEKLY_AT} * * {i}", "weekly") for i, d in enumerate(DAYS)])
OVERLAP = timedelta(hours=1)  # a read reaches this far before its task's last good read, so a post that lands while a run starts is never lost
QUIET_AFTER = 4  # weekly reads in a row with no new post before a weekly page is read once a month (Jesse, 2026-11-11)
HEADS_UP = 0.75  # of the cap; private.apify_level says the same for the 8 AM email
STORE = "bp-social-watch"
LOOKBACK = {"busy": timedelta(days=8), "weekly": timedelta(days=15)}  # never reads runs older than this
DONE = ("SUCCEEDED", "FAILED", "ABORTED", "TIMED-OUT")
WAIT = 480  # seconds, over every part, that a check waits for an Apify run still going

# Pictures (Jesse, 2026-10-26: the words on a post's picture, when its caption doesn't say enough)
PICTURES = 3        # most read per post: a carousel's flyer is often its second or third slide
SHORT_WORDS = 30    # a caption under this many words has its pictures read, a time of day or not
WORDS_MAX = 10000   # a post's own words kept for its News page, as board_items.post_words allows (town-feed 65)
CLOCK = re.compile(r"\b\d{1,2}(:\d{2})?\s*(a\.?m\b|p\.?m\b)|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b", re.I)
LONG_SIDE = 1568    # px; a flyer's small print stays readable (Instagram posts are 1080 wide anyway)
UA = "BlockPartyBot/1.0 (+https://blockpartystjoe.com)"
# What looking at a picture costs, in list-price dollars per million picture tokens (the routines
# run on Jesse's Claude plan, so it is plan usage, not a bill). A picture costs about one token per
# 750 pixels. The cheap model (Haiku 5.5, $0.10 in) writes it to its cache at twice that, then
# carries it through the batch's ~40 later turns at a tenth: about $0.60. The judge (Sonnet 5.5,
# $2 in) opens only pictures an item rests on: $4 to cache, ~20 later turns at $0.20, about $8.
CHEAP_PER_M, JUDGE_PER_M = 0.60, 8.0


def task_name(run, kind, day=None):
    return f"bp-{run}-{day}-{kind}" if day else f"bp-{run}-{kind}"


def day_of(page):
    """The day of the week a page's weekly read falls on: its `day` in the list (set 2026-11-11 so each day
    reads a mix of kinds), else one its address picks, so it never moves."""
    return page.get("day") or DAYS[int(hashlib.md5(canon(page["url"]).encode()).hexdigest(), 16) % len(DAYS)]


def all_pages(root):
    return json.loads((root / "sources" / "social" / f"{TOWN}.json").read_text())


def pages_for(run, root):
    """The pages a run reads: busy or not, and never one Facebook hides from logged-out readers, nor one with
    `skip` (why): a page that only advertises stays on the list, so the monthly accounts check doesn't offer it
    again and its place keeps the link, but is never read (Jesse, 2026-11-11)."""
    return [p for p in all_pages(root) if p["busy"] == (run == "busy") and not p.get("hidden") and not p.get("skip")]


def events_tab(url):
    return url.rstrip("/") + "/upcoming_hosted_events"


def search_pages():
    """The town's Facebook events searches as pages of their own: the words searches (the town file's
    facebook_events_search, one query or a list; 2026-11-08: Collegeville too) and Facebook's own events page for the town (facebook_events_explore,
    `events/explore/<town>/<Facebook city id>`, the location-based list; 2026-11-08: 20 events for 20 cents,
    one of them in the words search, 8 in town and new). Their events are hosted by places the list may not
    know (2026-11-03: a band at La Playette, a parish craft fair), so each is named for its host."""
    town, pages = TOWNS[TOWN], []
    queries = town.get("facebook_events_search") or []
    for q in ([queries] if isinstance(queries, str) else queries):
        pages.append({"entry_id": "", "name": f"Facebook events search: {q}", "kind": "search", "busy": False,
                      "url": "https://www.facebook.com/events/search/?q=" + quote(q)})
    if town.get("facebook_events_explore"):
        pages.append({"entry_id": "", "name": "Facebook events page for the town", "kind": "search", "busy": False,
                      "url": town["facebook_events_explore"]})
    return pages


def far_away(loc):
    """A found event whose map position is over NEAR_KM from the town and whose place names neither the
    town nor its ZIP code. Facebook pins some places wrong (the Church of Saint Joseph at 31.95° N), so
    the words win."""
    town = TOWNS[TOWN]
    words = " ".join(str(loc.get(k) or "") for k in ("name", "contextualName", "streetAddress")).lower()
    name = town["display"].lower()
    if any(w in words for w in [name, name.replace("st. ", "saint "), *town.get("zips", [])]):
        return False
    try:
        lat, lng, (s, w, n, e) = float(loc["latitude"]), float(loc["longitude"]), town["bbox"]
    except (KeyError, TypeError, ValueError):
        return False
    mid = math.radians((s + n) / 2)
    return math.hypot((lat - (s + n) / 2) * 111, (lng - (w + e) / 2) * 111 * math.cos(mid)) > NEAR_KM


def actor_input(kind, urls, window):
    """A task's input: the pages, and how far back to read (a UTC time, "2026-11-11T14:30:00", or "16 hours")."""
    if kind == "facebook":
        return {"startUrls": [{"url": u} for u in urls], "resultsLimit": POSTS, "onlyPostsNewerThan": window}
    if kind == "instagram":
        return {"username": urls, "resultsLimit": POSTS, "onlyPostsNewerThan": window}
    if kind == "search":
        return {"startUrls": [{"url": u} for u in urls], "maxEvents": SEARCH_EVENTS}
    return {"startUrls": [{"url": events_tab(u)} for u in urls], "maxEvents": 10}


# ---- Apify: the REST API (the network secret, or APIFY_TOKEN), else Composio on a Mac ----

def direct():
    return bool(os.environ.get("APIFY_TOKEN")) or not shutil.which("composio")


def _http(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {os.environ['APIFY_TOKEN']}"}
                                                                           if os.environ.get("APIFY_TOKEN") else {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def _composio(slug, args):
    d = composio.execute(slug, args, timeout=120)
    return d.get("data", d) if isinstance(d, dict) else d


def items(dataset):
    if direct():
        out, offset = [], 0
        while True:
            page = _http("GET", f"/datasets/{dataset}/items?clean=true&offset={offset}&limit=1000")
            out += page
            if len(page) < 1000:
                return out
            offset += len(page)
    out, offset = [], 0
    while True:
        d = _composio("APIFY_GET_DATASET_ITEMS", {"datasetId": dataset, "limit": 200, "offset": offset})
        page = d if isinstance(d, list) else d.get("items") or []
        out += page
        if len(page) < 200:
            return out
        offset += len(page)


def limits():
    if direct():
        return _http("GET", "/users/me/limits")["data"]
    return _composio("APIFY_USERS_ME_LIMITS_GET", {})


def api(method, path, body=None):
    """Any Apify call: the REST API in the cloud, Composio's proxy on a Mac. None for a missing record."""
    if direct():
        try:
            return _http(method, path, body)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise
    d = composio.proxy(API + path, "apify", method, body)
    if isinstance(d, dict) and d.get("error"):
        if "not-found" in str(d["error"].get("type", "")):
            return None
        raise RuntimeError(f"Apify: {d['error']}")
    return d


def _store_id():
    return api("POST", f"/key-value-stores?name={STORE}")["data"]["id"]  # makes it the first time, finds it after


def last_read(run):
    rec = api("GET", f"/key-value-stores/{_store_id()}/records/read-{run}")
    return datetime.fromisoformat(rec["finished_at"]) if rec and rec.get("finished_at") else None


def mark_read(run, finished_at):
    api("PUT", f"/key-value-stores/{_store_id()}/records/read-{run}", {"finished_at": finished_at})


def read_missed():
    """The pages Apify came back not available or with nothing for, {page: {misses, why, aside}}, kept in
    the store beside the marks; `aside` is the day a page was set aside."""
    rec = api("GET", f"/key-value-stores/{_store_id()}/records/missed")
    return rec if isinstance(rec, dict) else {}


def save_missed(missed):
    api("PUT", f"/key-value-stores/{_store_id()}/records/missed", missed)


def by_name(path):
    return {x["name"]: x for x in api("GET", f"{path}?limit=1000")["data"]["items"]}


def canon(url):
    return url.rstrip("/").lower()


def next_read(now, day):
    """When `day`'s next weekly read (WEEKLY_AT o'clock) after `now` starts."""
    t = now.astimezone(LOCAL).replace(hour=WEEKLY_AT, minute=0, second=0, microsecond=0)
    t += timedelta(days=(DAYS.index(day) - 1 - t.weekday()) % 7)  # Python counts Monday 0, cron Sunday 0
    return t if t > now else t + timedelta(days=7)


def monthly_try(now, day):
    """Whether `day`'s next weekly read after `now` falls in a month's first week. By the clock, not the
    date: a 7:30 PM check that starts past midnight is still before it."""
    return next_read(now, day).day <= 7


def page_lists(root, missed=None, now=None):
    """{(run, kind): pages} for every list: each list's own pages; the weekly Events tabs of the busy
    list's Facebook pages and the hidden ones (their posts are hidden, their events are not: Stone Road
    at La Playette, 2026-11-03), and every Facebook page's in the first week of each month (Apify bills
    a cent for each tab read, empty or not); and the town's events search. A page set aside (`missed`)
    leaves its list for its day's weekly read: a busy page every week, a weekly page in the first week of
    each month. sync_tasks gives each weekly page its day's task."""
    category = {e["id"]: e.get("category") for e in load(root)[0]}
    aside = {u for u, m in (missed or {}).items() if m.get("aside")}
    month = lambda p: bool(now) and monthly_try(now, day_of(p))
    out = {}
    for run in ("busy", "weekly"):
        for p in pages_for(run, root):
            p["category"] = category.get(p["entry_id"])
            if canon(p["url"]) not in aside:
                out.setdefault((run, p["kind"]), []).append(p)
            elif run == "busy" or month(p):
                out.setdefault(("weekly", p["kind"]), []).append(p)
    out[("weekly", "events")] = [dict(p, category=category.get(p["entry_id"])) for p in all_pages(root)
                                 if p["kind"] == "facebook" and not p.get("skip") and (p["busy"] or p.get("hidden") or month(p))]
    if search_pages():
        out[("weekly", "search")] = search_pages()
    return {k: v for k, v in out.items() if k in ACTORS}


def last_good(task):
    """When a task's last run that succeeded started, or None."""
    got = api("GET", f"/actor-tasks/{task['id']}/runs?desc=true&limit=1&status=SUCCEEDED")["data"]["items"]
    return datetime.fromisoformat(got[0]["startedAt"].replace("Z", "+00:00")) if got else None


def days_began():
    """When the weekly list's days began (setup's store record `days-began`): a day's task that has never
    read reaches back to it, so the first read of each day picks up where the Thursday read left off."""
    rec = api("GET", f"/key-value-stores/{_store_id()}/records/days-began")
    return datetime.fromisoformat(rec["at"]) if rec and rec.get("at") else None


def since(task, began, now):
    """How far back a posts task reads, as a UTC time: OVERLAP before its last good read, so a run that the
    monthly cap, a usage limit or Facebook stopped is read up by the next (POSTS a page at most). A task
    that has never read reaches back to `began`, else a week."""
    at = (task and last_good(task)) or began or now - timedelta(days=7)
    return (at - OVERLAP).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")


def sync_tasks(root, missed=None, now=None):
    """Each task's pages as the lists now have them (page_lists), each weekly page in its day's task
    (`bp-weekly-<day>-<kind>`), and how far back each posts task reads (since); makes a task that is
    missing. Returns {task name: id} of the tasks with pages."""
    now = now or datetime.now(timezone.utc)
    tasks, ids, began = by_name("/actor-tasks"), {}, days_began()
    for (run, kind), pages in page_lists(root, missed, now).items():
        actor, cap = ACTORS[(run, kind)]
        shares = {None: pages} if run == "busy" else {}
        for p in ([] if run == "busy" else pages):
            shares.setdefault(day_of(p), []).append(p)
        for day, share in shares.items():
            name = task_name(run, kind, day)
            window = since(tasks.get(name), began, now) if kind in ("facebook", "instagram") else None
            body = {"input": actor_input(kind, [p["url"] for p in share], window),
                    "options": {"timeoutSecs": 600, "maxTotalChargeUsd": cap}}
            if name in tasks:
                api("PUT", f"/actor-tasks/{tasks[name]['id']}", body)
                ids[name] = tasks[name]["id"]
            else:
                ids[name] = api("POST", "/actor-tasks", {"actId": actor, "name": name, **body})["data"]["id"]
    # ponytail: a day's task left with no pages keeps its last ones until setup deletes it
    return ids


def setup():
    """The tasks and schedules as the list has them. The first setup with the weekly days starts them where
    the last weekly check left off (days_began); a busy or weekly task or schedule the list no longer has is
    deleted, never one whose runs no check has read yet."""
    root, now = find_root(), datetime.now(timezone.utc)
    if not days_began():
        began = last_read("weekly") or now
        api("PUT", f"/key-value-stores/{_store_id()}/records/days-began", {"at": began.isoformat()})
        print(f"[social] the weekly days begin where the last weekly check left off: {began.astimezone(LOCAL):%a %b %-d %-I:%M %p}")
    ids = sync_tasks(root, read_missed(), now)
    have, made = by_name("/schedules"), set()
    for name, cron, run in SCHEDULES:
        prefix = "bp-busy-" if run == "busy" else name + "-"
        actions = [{"type": "RUN_ACTOR_TASK", "actorTaskId": tid} for n, tid in ids.items() if n.startswith(prefix)]
        if not actions:
            continue
        body = {"name": name, "cronExpression": cron, "timezone": "America/Chicago", "isEnabled": True,
                "isExclusive": True, "actions": actions}
        if name in have:
            api("PUT", f"/schedules/{have[name]['id']}", body)
        else:
            api("POST", "/schedules", body)
        made.add(name)
        print(f"[social] schedule {name}: {cron} Chicago, {len(actions)} tasks")
    for name, s in have.items():  # a schedule the days replaced (the Thursday read's `bp-weekly`) first, then its tasks
        if re.match(r"bp-(busy|weekly)", name) and name not in made:
            api("DELETE", f"/schedules/{s['id']}")
            print(f"[social] schedule {name}: deleted")
    for name, t in by_name("/actor-tasks").items():
        if re.match(r"bp-(busy|weekly)-", name) and name not in ids:
            ran, mark = (t.get("stats") or {}).get("lastRunStartedAt"), last_read(name.split("-")[1])
            if ran and (not mark or datetime.fromisoformat(ran.replace("Z", "+00:00")) > mark):
                print(f"[social] task {name}: kept, its last run is not read yet; run setup again after the next check")
                continue
            api("DELETE", f"/actor-tasks/{t['id']}")
            print(f"[social] task {name}: deleted")
    for run in ("busy", "weekly"):
        if not last_read(run):  # the first setup: start from now, never from runs made before it
            mark_read(run, now.isoformat())


def runs_since(run, mark, now, give_up, stop=None):
    """{kind: [finished runs]} of a run's tasks since the mark, waiting until `give_up` (time.time())
    for one that started within the last 90 minutes and is still going, or until the part's `stop`.
    Runs older than LOOKBACK are never read."""
    tasks = {n: x for n, x in by_name("/actor-tasks").items() if n.startswith(f"bp-{run}-")}
    floor = max(mark, now - LOOKBACK[run]) if mark else now - LOOKBACK[run]
    while True:
        out, waiting = {}, []
        for name, task in tasks.items():
            for r in api("GET", f"/actor-tasks/{task['id']}/runs?desc=true&limit=30")["data"]["items"]:
                started = datetime.fromisoformat(r["startedAt"].replace("Z", "+00:00"))
                if r["status"] in DONE and r.get("finishedAt"):
                    if datetime.fromisoformat(r["finishedAt"].replace("Z", "+00:00")) > floor:
                        out.setdefault(name.rsplit("-", 1)[1], []).append(r)  # bp-busy-facebook, bp-weekly-mon-facebook
                elif now - started < timedelta(minutes=90):
                    waiting.append(name)
        if not waiting or time.time() > give_up or late(stop):
            return out, waiting
        time.sleep(15)


# ---- posts become pages, the way the cheap model reads them ----

def when_text(stamp):
    try:
        t = datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).astimezone(LOCAL)
    except ValueError:
        return str(stamp)
    return f"{t:%A, %B} {t.day} at {t:%-I:%M %p}"


def needs_pictures(text):
    """A caption too short to say much, or with no time of day in it: its pictures get read."""
    text = text or ""
    return len(text.split()) < SHORT_WORDS or not CLOCK.search(text)


def picture_urls(kind, row):
    """A post's pictures, at most PICTURES, as Apify saved them: Facebook's `media` (a video's
    is its still), Instagram's `displayUrl` then a carousel's `images` and `childPosts`. With
    Meta's own description of each where it has one ("May be an image of text that says …")."""
    if kind == "facebook":
        got = [((m.get("photo_image") or {}).get("uri") or m.get("thumbnail"), m.get("ocrText"))
               for m in row.get("media") or [] if isinstance(m, dict)]
    else:
        got = ([(row.get("displayUrl"), row.get("alt"))] + [(u, None) for u in row.get("images") or []]
               + [(c.get("displayUrl"), c.get("alt")) for c in row.get("childPosts") or [] if isinstance(c, dict)])
    out, seen = [], set()
    for url, about in got:
        key = urlsplit(url).path if isinstance(url, str) else None
        if key and url.startswith("http") and key not in seen:  # one picture under two signed addresses
            seen.add(key)
            out.append({"url": url, "about": (about or "").strip()})
    return out[:PICTURES]


def picture_tokens(w, h):
    return math.ceil(w * h / 750)


def fetch_picture(url, dest):
    """One picture to dest as a JPEG, its long side at most LONG_SIDE; its (w, h)."""
    from PIL import Image, ImageOps  # here alone, so spend, done and setup run without Pillow
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read(15_000_000)
    im = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    im.thumbnail((LONG_SIDE, LONG_SIDE))
    im.save(dest, "JPEG", quality=88)
    return im.size


def add_pictures(pages, folder, fetch=fetch_picture, stop=None, counts=None):
    """Every page with pictures gets them downloaded and named at its end, for the cheap model
    to open. A picture that won't download is a line in the summary, and its page keeps Meta's
    description. Returns the counts for the cost line, added to an earlier part's `counts`; a page
    not reached by the part's `stop` keeps its `pictures` for the next part."""
    folder.mkdir(parents=True, exist_ok=True)
    c = counts or {"read": 0, "posts": 0, "tokens": 0, "failed": []}
    for p in pages:
        if not p.get("pictures") or late(stop):
            continue
        lines = []
        for i, pic in enumerate(p.pop("pictures"), 1):
            dest = folder / f"{p['file']}-{i}.jpg"
            try:
                w, h = fetch(pic["url"], dest)
                c["read"], c["tokens"] = c["read"] + 1, c["tokens"] + picture_tokens(w, h)
                lines.append(f"Picture {i}: {dest}")
            except Exception as e:
                c["failed"].append(f"{p['name']} {p['file']} picture {i}: {e}")
            if pic["about"]:
                lines.append(f"Meta's own description of picture {i}: {pic['about']}")
        if any(ln.startswith("Picture ") for ln in lines):
            c["posts"] += 1
            lines.insert(0, "The post's caption doesn't say much, so its pictures come with it. Open each "
                            "picture below with the Read tool and read every word on it: those words are "
                            "part of this post.")
        if lines:
            p["text"] += "\n\n" + "\n".join(lines)
    return c


def pictures_line(pics):
    """One line for the answer: what reading pictures added to this check's cost."""
    if not pics or not pics.get("read"):
        return "[social] pictures: none read" + (f" ({len(pics['failed'])} would not download)" if pics and pics.get("failed") else "")
    m = pics["tokens"] / 1e6
    return (f"[social] pictures: {pics['read']} read on {pics['posts']} posts with a short caption or no time "
            f"({pics['tokens']:,} picture tokens): about ${m * CHEAP_PER_M:.3f} for the cheap model, and up to "
            f"${m * JUDGE_PER_M:.3f} more if the judge opens every one, on the Claude plan; nothing on Apify"
            + (f"; {len(pics['failed'])} would not download" if pics["failed"] else ""))


def src_of(row):
    """The page an Apify row came from, as its list's address would be written (canon)."""
    src = canon(row.get("inputUrl") or row.get("facebookUrl") or row.get("input") or "")  # "input": an events row's error
    return src or (f"https://www.instagram.com/{row['ownerUsername'].lower()}" if row.get("ownerUsername") else "")


def page_of(src, by_url):
    return by_url.get(src) or next((p for u, p in by_url.items() if u and u in src), None)


def run_pages(run_id):
    """The pages an Apify run was given, from its own input (a schedule's run carries the task's
    pages as they were when it started)."""
    got = api("GET", f"/actor-runs/{run_id}/key-value-store/records/INPUT") or {}
    urls = [u.get("url") if isinstance(u, dict) else u for u in got.get("startUrls") or []] + list(got.get("username") or [])
    return [canon(u) for u in urls if isinstance(u, str)]


def tally(reads, missed, today, weekly=()):
    """Each page the posts runs read, oldest run first: read when a row of it is a post or says it
    posted nothing new (`no_items`: most busy pages, most reads); missed when Apify says it is not
    available, or gives no row for it at all (Sal's, every read in October). run.failing decides: ASIDE_AFTER
    misses in a row set a page aside; a good read brings it back. A run that missed more than half its pages (Facebook
    blocking Apify, a run stopped at its cap) counts against none. A page of the `weekly` list (canon addresses)
    that read fine with nothing new QUIET_AFTER reads in a row is set aside as quiet: read in the first week of
    each month, and back with its first new post (Jesse, 2026-11-11). `reads`: (finished, pages, rows, what) per
    run. Returns the new state, the pages set aside and back, and a line per run not counted."""
    state, aside, back, uncounted = {u: dict(m) for u, m in missed.items()}, [], [], []
    for _, pages, rows, what in sorted(reads, key=lambda x: x[0]):
        found, posted, why, given = set(), set(), {}, {p: p for p in pages}
        for r in rows:
            u = page_of(src_of(r), given)
            if u and r.get("error") and r["error"] != "no_items":
                why[u] = r["error"]
            elif u:
                found.add(u)
                if not r.get("error"):
                    posted.add(u)
        counted = (len(pages) - len(found & set(pages))) * 2 <= len(pages)
        if not counted:
            uncounted.append(f"{what}: {len(pages) - len(found & set(pages))} of {len(pages)} pages not read, not counted")
        for u in pages:
            m = state.get(u, {})
            if u in weekly and u in found and u not in posted:  # read fine, nothing new
                quiet = m.get("quiet", 0) + 1
                if m.get("aside") and m.get("quiet"):  # quiet already: stays aside until it posts
                    state[u] = dict(m, quiet=quiet)
                    continue
                if m.get("aside"):  # set aside for misses, and read again
                    back.append(u)
                if quiet >= QUIET_AFTER:
                    state[u] = {"quiet": quiet, "why": "no new posts", "aside": str(today)}
                    aside.append(u)
                else:
                    state[u] = {"quiet": quiet}
                continue
            misses, happened = failing(m.get("misses", 0), m.get("aside"), u in found, counted)
            if happened in ("clear", "back"):
                back += [u] if happened == "back" else []
                state.pop(u, None)
            elif happened in ("missed", "set"):
                m = {"misses": misses, "why": why.get(u, "nothing back")}
                if happened == "set":
                    m["aside"] = str(today)
                    aside.append(u)
                state[u] = m
    return state, aside, back, uncounted


def aside_lines(state, aside, back, lists):
    """The answer's words: each page the check it is set aside and the check it is back."""
    named = {canon(p["url"]): p for pages in lists.values() for p in pages}
    name = lambda u: f"{named[u]['name']}'s {named[u]['kind'].title()} {u}" if u in named else u
    weekday = lambda u: dict(zip(DAYS, ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                                        "Saturday")))[day_of(named[u])] if u in named else "its day"
    retry = lambda u: (f"every {weekday(u)}" if named.get(u, {}).get("busy")
                       else f"on the first {weekday(u)} of each month")
    said = lambda u: (f"no new posts {state[u]['quiet']} weekly reads in a row; off its weekly list, read {retry(u)}"
                      if state[u].get("quiet") else
                      f"{state[u]['why'].replace('_', ' ')} {ASIDE_AFTER} reads in a row; off its paid list, tried {retry(u)}")
    return ([f"Set aside: {name(u)}: {said(u)}" for u in aside]
            + [f"Back: {name(u)}: read again, back on its list" for u in back])


def ig_page(user, by_url):
    """The watched page of an Instagram account, by its exact handle (page_of's "inside" match would take
    instagram.com/joetown for joetownsmash)."""
    user = str(user or "").strip().lstrip("@").lower()
    return user and (by_url.get(canon(f"https://www.instagram.com/{user}")) or by_url.get(canon(f"https://instagram.com/{user}")))


def collabs(row, host, by_url):
    """The registry places an Instagram collab post was made with besides its host (BP app town-feed 58): its
    co-authors and its owner, each a watched page, never the host's own place; 2 at most (club_events'
    collab_entry_ids). A plain @mention or a tagged account is no collab: they credit photographers and fans."""
    users = [c.get("username") for c in row.get("coauthorProducers") or [] if isinstance(c, dict)] + [row.get("ownerUsername")]
    out = []
    for u in users:
        p = ig_page(u, by_url)
        if p and p.get("entry_id") and p["entry_id"] != host.get("entry_id") and p["entry_id"] not in out:
            out.append(p["entry_id"])
    return out[:2]


def post_pages(kind, rows, by_url):
    """Apify's rows as pages: one post each, with who posted it, where and when. An empty row
    (a page with nothing new, hidden, gone) is no page; a hidden one is reported. A post whose
    caption needs its pictures carries their addresses under `pictures`, for add_pictures; one
    with no caption but a picture is a page too, since its words may all be on the picture. A post that is
    the place's own (an Instagram one owned by a watched page, else any) keeps its caption under `words`,
    for its News page (BP app town-feed 65): someone else's post on the page (MIAC's on CSB's) keeps none."""
    pages, hidden = [], []
    for r in rows:
        src = src_of(r)
        page = page_of(src, by_url)
        if kind == "instagram":  # a collab post shows on each author's page: its owner hosts it, read from either
            page = ig_page(r.get("ownerUsername"), by_url) or page
        who = page["name"] if page else f"A {TOWNS[TOWN]['display']} place"
        if r.get("error"):
            # "no_results" is a page's events tab listing none: each of Oct 29's 20 read fine as posts.
            if r["error"] not in ("no_items", "no_results"):
                hidden.append(f"{page['name'] if page else src}: {r['error']}")
            continue
        if kind in ("events", "search"):
            text = r.get("description") or ""
            loc = r.get("location") if isinstance(r.get("location"), dict) else {}
            where = loc.get("name") if loc else r.get("location")
            if kind == "search":
                hosts = [o["name"] for o in r.get("organizators") or [] if isinstance(o, dict) and o.get("name")]
                if (r.get("isPast") or r.get("isCanceled") or far_away(loc) or not hosts
                        or PRIVATE_DAY.search(r.get("name") or "")):
                    continue
                who = hosts[0]
            lead = (f"Found by searching Facebook's events for {TOWNS[TOWN]['display']}. Hosted by {', '.join(hosts)}."
                    if kind == "search" else f"{who} lists this event on its Facebook page.")
            body = (f"{lead}\n"
                    f"Event: {r.get('name') or r.get('title') or ''}\nWhen: {r.get('dateTimeSentence') or r.get('utcStartDate') or r.get('startDate') or ''}\n"
                    f"Where: {where or ''}\n\n{text}")
            pid, url, pics = r.get("id") or r.get("eventId") or r.get("url"), r.get("url"), []
        else:
            text = (r.get("text") if kind == "facebook" else r.get("caption")) or ""
            pics = picture_urls(kind, r) if needs_pictures(text) else []
            if not text.strip() and not pics:
                continue
            stamp = r.get("time") or r.get("timestamp")
            body = (f"{who} posted this on {kind.title()} "
                    f"on {when_text(stamp)}:\n\n{text.strip() or '(no caption)'}")
            pid, url = r.get("postId") or r.get("id") or r.get("shortCode"), r.get("url")
            own = kind == "facebook" or not r.get("ownerUsername") or ig_page(r.get("ownerUsername"), by_url)
            words = text.strip()[:WORDS_MAX] if own else ""
        if not page or not pid:
            continue
        made_with = collabs(r, page, by_url) if kind == "instagram" else []
        pages.append({"file": f"{kind}-{pid}", "url": url or page["url"], "entry_id": page["entry_id"],
                      "name": who if kind == "search" else page["name"], "category": page.get("category"), "trust": "official", "text": body,
                      **({"pictures": pics} if pics else {}), **({"collabs": made_with} if made_with else {}),
                      **({"words": words} if kind in ("facebook", "instagram") and words else {})})
    return pages, hidden


def prepare(run, now):
    """In timed parts, as morning.py's: the wait for an Apify run still going and the pictures'
    downloads stop after the part's minutes and say "run again", and social-part.json carries the check to
    the next part."""
    root, out, today, check, stop = find_root(), run.folder, run.today, run.check, run.stop
    state, part = run.begin("social-part.json", {"failed": [], "give_up": time.time() + WAIT})
    if state == "busy":
        return print("[social] another prepare is still running in this copy: let it finish, and start no second one")
    if state == "prepared":
        print("[social] prepared already: nothing read again")  # run again after it was done; never start over
        return say_prepared(run.summary(), out)
    saved = part.saved
    if state == "new":
        try:
            saved["missed"] = read_missed()
        except Exception as e:  # every page read this time, and none counted
            saved["missed"], _ = None, saved["failed"].append(f"set-aside pages unreadable: {e}")
        try:
            sync_tasks(root, saved["missed"], now)  # the next run reads the list as it is now
        except Exception as e:
            saved["failed"].append(f"task pages not refreshed: {e}")
        day = DAYS[(now.astimezone(LOCAL).weekday() + 1) % 7]  # a weekly check reads its day's share
        saved["listed"] = sum(1 for (r, _), v in page_lists(root, saved["missed"], now).items() if r == check
                              for p in v if check == "busy" or day_of(p) == day)
        try:
            mark = last_read(check)
        except Exception as e:  # the store unreadable: the last LOOKBACK of runs, and say so
            mark, _ = None, saved["failed"].append(f"last read unreadable ({e}); reading every run of the last {LOOKBACK[check].days} days")
        saved["mark"] = mark and mark.isoformat()
    now = datetime.fromisoformat(saved.setdefault("now", now.isoformat()))  # every part by the first part's clock
    lists, failed = page_lists(root), saved["failed"]
    mark = saved["mark"] and datetime.fromisoformat(saved["mark"])
    if "posts" not in saved:
        found, waiting = runs_since(check, mark, now, saved["give_up"], stop)
        if waiting and time.time() <= saved["give_up"]:  # the part's time is spent first
            part.save()
            return print(f"[social] run again: {', '.join(waiting)} still running on Apify")
        failed += [f"{n} still running after 8 minutes; its posts wait for the next check" for n in waiting]

        posts, cost, until, reads = [], 0.0, mark, []
        for kind, runs in found.items():
            # Every page of its kind, either list: a run may carry a page set aside or back since.
            by_url = {canon(p["url"]): p for (_, k), ps in lists.items() if k == kind for p in ps}
            if kind == "events":  # every Facebook page: a first-week run carries them all
                every = {canon(p["url"]): p for p in all_pages(root) if p["kind"] == "facebook"}
                by_url = {events_tab(u): p for u, p in every.items()} | every
            for r in runs:
                cost += float(r.get("usageTotalUsd") or 0)
                finished = datetime.fromisoformat(r["finishedAt"].replace("Z", "+00:00"))
                until = max(until, finished) if until else finished
                rows = items(r["defaultDatasetId"])
                got, hidden = post_pages(kind, rows, by_url)
                posts += got
                if kind in ("events", "search"):  # a posts page Apify can't read is named once, set aside (tally)
                    failed += [f"{kind}: {h}" for h in hidden]
                elif r["status"] == "SUCCEEDED" and saved.get("missed") is not None:
                    reads.append((r["finishedAt"], run_pages(r["id"]), rows,
                                  f"{kind} run at {finished.astimezone(LOCAL):%a %-I:%M %p}"))
                if r["status"] != "SUCCEEDED":
                    failed.append(f"{kind} run {r['id']} at {finished.astimezone(LOCAL):%a %-I:%M %p}: {r['status']}")
        seen, unique = set(), []
        for p in posts:  # overlapping windows read a post twice; one page each
            if p["file"] not in seen:
                seen.add(p["file"]), unique.append(p)
        if saved.get("missed") is not None:  # saved by `done` with the mark, so a check that stops early counts nothing
            weekly = {canon(p["url"]) for (r, _), ps in lists.items() if r == "weekly" for p in ps if not p.get("busy")}
            missed, aside, back, uncounted = tally(reads, saved["missed"], today, weekly)
            saved.update(missed=missed, aside=aside_lines(missed, aside, back, lists))
            failed += uncounted
        saved.update(posts=unique, cost=cost, until=until and until.isoformat(), runs=sum(len(v) for v in found.values()))
    posts = saved["posts"]
    pics = add_pictures(posts, out / "pictures", fetch_picture, stop, saved.get("pics"))
    if any(p.get("pictures") for p in posts):
        saved["pics"] = pics
        part.save()
        return print(f"[social] run again: {sum(bool(p.get('pictures')) for p in posts)} posts' pictures still to read")
    failed = failed + [f"picture not downloaded: {f}" for f in pics["failed"]]
    cost, runs = saved["cost"], saved["runs"]
    until = saved["until"] and datetime.fromisoformat(saved["until"])
    for i, text in enumerate(layout(posts, today, TOWNS[TOWN]["display"]), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(text)
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in posts], indent=1))
    (out / "feeds.jsonl").write_text("")
    try:
        import write_judged
        interests = write_judged.interest_ids()
    except Exception as e:  # no database keys (a dry run on a Mac): the judge then uses null
        interests, _ = [], failed.append(f"interest ids unread: {e}")
    checked = saved.get("listed", 0)  # set-aside pages left out
    summary = {"today": str(today), "run": check, "since": mark.isoformat() if mark else None,
               "fetched": checked, "changed": len(posts), "first_seen": 0, "to_read": len(posts),
               "batches": len(list((out / "batches").iterdir())), "failed": failed, "readers": [],
               "interests": interests, "apify_usd": round(cost, 3), "apify_runs": runs,
               "read_until": until.isoformat() if until and runs else None, "pictures": pics,
               "aside": saved.get("aside", []), "missed": saved.get("missed")}
    run.prepared(summary)
    say_prepared(summary, out)


def say_prepared(s, out):
    mark = s["since"] and datetime.fromisoformat(s["since"])
    since = f"since {mark.astimezone(LOCAL):%a %b %-d %-I:%M %p}" if mark else "of the last days"
    print(f"[social] {s['run']}: {s['apify_runs']} Apify runs {since}, {s['fetched']} pages, {s['changed']} new posts in "
          f"{s['batches']} batches ({out / 'batches'}), Apify ${s['apify_usd']:.2f}")
    print(pictures_line(s["pictures"]))
    for a in s["aside"]:
        print(f"[social] {a}")
    for f in s["failed"]:
        print(f"[social] FAILED {f}")


def finish(run):
    """After the write: mark this check's runs read, so the next check starts after them, and the next
    prepare a new check."""
    prep = run.summary()
    run.finished()
    print(pictures_line(prep.get("pictures")))
    if not prep.get("read_until"):
        return print(f"[social] {prep['run']}: no Apify runs to mark")
    try:
        mark_read(prep["run"], prep["read_until"])
        if prep.get("missed") is not None:  # with the mark, so no run is counted twice
            # ponytail: last save wins; a busy and a weekly check overlapping (hours apart by schedule) could
            # undo the other's comeback. Save only the pages this check changed if they ever overlap.
            save_missed(prep["missed"])
    except Exception as e:  # the next check then reads these runs again; the writer merges repeats
        return print(f"[social] FAILED marking {prep['run']} read ({e}): check the Apify network secret")
    print(f"[social] {prep['run']}: {prep['apify_runs']} runs marked read, up to "
          f"{datetime.fromisoformat(prep['read_until']).astimezone(LOCAL):%a %b %-d %-I:%M %p}")


def missed_checks(now=None):
    """Social checks that should have finished by this morning and didn't, for the morning report (BP app loopholes 09;
    Jesse, 2026-11-05: the Oct 22 refusal went unnoticed). A check's mark is the last Apify run it read, and the next
    check reads what a refused one left, so only the day's last check of each list counts: the busy mark should be past
    last night's 7 PM run, the weekly mark past yesterday's 3 PM run."""
    now = (now or datetime.now(LOCAL)).astimezone(LOCAL)
    yesterday = (now - timedelta(days=1)).replace(minute=0, second=0, microsecond=0)
    due = [("busy", "last evening's check", yesterday.replace(hour=19)),
           ("weekly", "yesterday afternoon's check", yesterday.replace(hour=WEEKLY_AT))]
    out = []
    for run, name, by in due:
        mark = last_read(run)
        if not mark or mark < by:
            read = f"read up to {mark.astimezone(LOCAL):%a %b %-d %-I:%M %p}" if mark else "never read"
            out.append(f"{name} didn't finish ({read})")
    return out


def spend_line(used, cap):
    line = f"Apify: ${used:.2f} of ${cap:.0f} this month"
    if used >= cap - 0.01:
        return line + ". The cap is reached: Apify has stopped every check until the cycle resets."
    if used >= cap * HEADS_UP:
        return line + ". Heads-up: past 3/4 of the cap."
    return line


def spend():
    try:
        d = limits()
    except urllib.error.HTTPError as e:  # 401: the environment's Apify network secret is missing or wrong
        return f"Apify: spend unknown, Apify refused the request (HTTP {e.code}): check the routine's network secret"
    end = d.get("monthlyUsageCycle", {}).get("endAt", "")[:10]
    return (spend_line(float(d["current"]["monthlyUsageUsd"]), float(d["limits"]["maxMonthlyUsageUsd"]))
            + (f" (resets after {end})" if end else ""))


def selftest():
    ok = 0
    def check(cond, what):
        nonlocal ok
        if not cond:
            sys.exit(f"selftest failed: {what}")
        ok += 1
    t = lambda d, h, m: datetime(2026, 10, d, h, m, tzinfo=LOCAL)
    real_last_read = globals()["last_read"]
    def missed(busy, weekly, now):
        globals()["last_read"] = {"busy": busy, "weekly": weekly}.get
        try:
            return missed_checks(now)
        finally:
            globals()["last_read"] = real_last_read
    thu, fri = t(29, 6, 0), t(30, 6, 0)  # Oct 29, 2026 is a Thursday
    check(missed(t(28, 21, 1), t(28, 15, 1), thu) == [], "both lists' last runs read by morning: nothing to say")
    check(missed(t(28, 12, 1), t(28, 15, 1), thu) == ["last evening's check didn't finish (read up to Wed Oct 28 12:01 PM)"],
          "only the morning run read: last evening's last check didn't finish")
    check(missed(t(29, 21, 1), t(28, 15, 1), fri) == ["yesterday afternoon's check didn't finish (read up to Wed Oct 28 3:01 PM)"],
          "the weekly list is read every afternoon now: Thursday's day unread is said on Friday")
    check(missed(None, t(29, 15, 1), fri) == ["last evening's check didn't finish (never read)"], "no mark at all")
    check(actor_input("facebook", ["u"], "2026-11-11T14:30:00")["onlyPostsNewerThan"] == "2026-11-11T14:30:00",
          "a task reads back to a time")
    check([s for s in SCHEDULES if s[2] == "busy"] == [("bp-busy-930am", "30 9 * * *", "busy"), ("bp-busy-7pm", "0 19 * * *", "busy")]
          and [(n, c) for n, c, r in SCHEDULES if r == "weekly"] == [(f"bp-weekly-{d}", f"0 15 * * {i}") for i, d in enumerate(DAYS)]
          and DAYS[0] == "sun", "the busy list at 9:30am and 7pm; the weekly list a day at a time at 3pm, cron's Sunday first")
    check(task_name("weekly", "events", "mon") == "bp-weekly-mon-events" and task_name("busy", "facebook") == "bp-busy-facebook",
          "a task's name")
    wed = datetime(2026, 11, 4, 21, 30, tzinfo=LOCAL)  # a Wednesday evening
    check(next_read(wed, "thu") == datetime(2026, 11, 5, 15, tzinfo=LOCAL) and next_read(wed, "wed") == datetime(2026, 11, 11, 15, tzinfo=LOCAL)
          and next_read(wed, "sun") == datetime(2026, 11, 8, 15, tzinfo=LOCAL)
          and next_read(datetime(2026, 11, 5, 15, tzinfo=LOCAL), "thu") == datetime(2026, 11, 12, 15, tzinfo=LOCAL),
          "a day's next read: later this week, or next week once its 3pm has come")
    check(monthly_try(wed, "thu") and monthly_try(wed, "sat") and not monthly_try(wed, "wed") and not monthly_try(wed, "mon"),
          "a day's monthly try: its next read falls on the month's first seven days")
    page = {"url": "https://www.facebook.com/krewe"}
    check(day_of(dict(page, day="tue")) == "tue" and day_of(page) in DAYS and day_of(page) == day_of({"url": "https://www.facebook.com/Krewe/"}),
          "a page's day is its own, else one its address picks, the same every time")
    real_good = globals()["last_good"]
    try:
        globals()["last_good"] = lambda task: task.get("good")
        began, now = datetime(2026, 11, 5, 21, 3, tzinfo=timezone.utc), datetime(2026, 11, 11, 16, tzinfo=timezone.utc)
        reads = [since({"good": datetime(2026, 11, 10, 15, 0, tzinfo=timezone.utc)}, began, now), since({"good": None}, began, now),
                 since(None, began, now), since(None, None, now)]
    finally:
        globals()["last_good"] = real_good
    check(reads == ["2026-11-10T14:00:00", "2026-11-05T20:03:00", "2026-11-05T20:03:00", "2026-11-04T15:00:00"],
          f"a read reaches an hour before its task's last good read; one that never read, back to when the days began, else a week: {reads}")
    by_url = {"https://www.facebook.com/krewe": {"name": "Krewe", "entry_id": "krewe", "url": "https://www.facebook.com/krewe"}}
    rows = [{"inputUrl": "https://www.facebook.com/krewe/", "postId": "1", "url": "https://fb/p/1", "text": "Trivia tonight at 7!",
             "time": "2026-10-22T23:05:00.000Z"},
            {"inputUrl": "https://www.facebook.com/krewe", "error": "no_items"},
            {"inputUrl": "https://www.facebook.com/gone", "error": "not_available"},
            {"inputUrl": "https://www.facebook.com/krewe", "postId": "2", "text": ""}]
    got, hidden = post_pages("facebook", rows, by_url)
    check(len(got) == 1 and got[0]["file"] == "facebook-1" and got[0]["trust"] == "official", "one post becomes one page")
    check("Thursday, October 22 at 6:05 PM" in got[0]["text"] and "Krewe posted this on Facebook" in got[0]["text"], "the page says who posted it and when, in Chicago time")
    check(hidden == ["https://www.facebook.com/gone: not_available"], "a hidden page is reported, an empty one is not")
    tab = lambda e: {"error": e, "input": "https://www.facebook.com/krewe/upcoming_hosted_events"}
    _, hidden = post_pages("events", [tab("no_results"), tab("blocked")], {events_tab(u): p for u, p in by_url.items()})
    check(hidden == ["Krewe: blocked"], "an events tab listing none says nothing; another error names its page")
    sp, ex = search_pages()[0], search_pages()[-1]
    found = lambda eid, loc, **kw: {"inputUrl": sp["url"], "id": eid, "url": f"https://fb/e/{eid}", "name": "Stone Road Live",
                                    "location": loc, "dateTimeSentence": "Saturday, November 7, 2026 at 8:30 PM CST",
                                    "organizators": [{"name": "Stone Road"}], **kw}
    rows = [found("la", {"name": "The La Playette", "latitude": 45.565, "longitude": -94.32}),
            found("church", {"name": "Church of Saint Joseph of Saint Joseph", "contextualName": "Saint Joseph, MN, United States",
                             "latitude": 31.95, "longitude": -94.3}),
            found("avon", {"name": "Avon Community Church", "contextualName": "Avon, MN", "latitude": 45.609, "longitude": -94.451}),
            found("old", {}, isPast=True), found("nobody", {}, organizators=[]), found("kid", {}, name="Serenity's First Birthday"),
            found("obbink", {"name": "Obbink Distilling"}, inputUrl=ex["url"])]
    got, _ = post_pages("search", rows, {canon(sp["url"]): sp, canon(ex["url"]): ex})
    check([p["file"] for p in got] == ["search-la", "search-church", "search-obbink"] and got[0]["name"] == "Stone Road"
          and "Hosted by Stone Road." in got[0]["text"] and "8:30 PM" in got[0]["text"]
          and got[2]["text"].startswith("Found by searching Facebook's events"),
          "a found event is named for its host, from the words search or the town's events page; one past, hostless, "
          "a family's own day, or pinned far from town with no town word is left out")
    ig = [{"inputUrl": "https://www.instagram.com/krewe", "id": "9", "caption": "Live music Saturday", "timestamp": "2026-10-22T20:00:00Z"}]
    got, _ = post_pages("instagram", ig, {"https://www.instagram.com/krewe": {"name": "Krewe", "entry_id": "krewe", "url": "u"}})
    check(len(got) == 1 and "on Instagram on Thursday, October 22 at 3:00 PM" in got[0]["text"], "an Instagram post reads the same way")
    nt = {"name": "The North Table", "entry_id": "north-table", "url": "https://www.instagram.com/thenorthtables"}
    mh = {"name": "Milk & Honey Ciders", "entry_id": "milk-and-honey-ciders", "url": "https://www.instagram.com/milkandhoneyciders"}
    jt = {"name": "Joetown", "entry_id": "joetown", "url": "https://www.instagram.com/joetown"}
    watched = {canon(p["url"]): p for p in (nt, mh, jt)}
    collab = {"id": "c1", "caption": "Cider brunch Sunday 10am", "ownerUsername": "thenorthtables",
              "coauthorProducers": [{"username": "milkandhoneyciders"}, {"username": "joetownsmash"}],
              "mentions": ["joetown"], "taggedUsers": [{"username": "joetown"}]}
    got = [post_pages("instagram", [dict(collab, inputUrl=p["url"])], watched)[0][0] for p in (nt, mh)]
    check(all(g["entry_id"] == "north-table" and g["collabs"] == ["milk-and-honey-ciders"] for g in got),
          "a collab post read from either author's page is its owner's, made with the other; a co-author we don't watch, "
          "a mention and a tag are no collab, and joetown is not joetownsmash")
    got = post_pages("instagram", [dict(collab, inputUrl=mh["url"], ownerUsername="somefan")], watched)[0][0]
    check(got["entry_id"] == "milk-and-honey-ciders" and "collabs" not in got,
          "an owner we don't watch leaves the post with the page it was read from, made with nobody else")
    check("words" not in got, "someone else's post on a watched page keeps no words of the place's own (town-feed 65)")
    got = post_pages("instagram", [dict(collab, inputUrl=mh["url"])], watched)[0][0]
    check(got["words"] == "Cider brunch Sunday 10am", "a watched page's own post keeps its caption as its words")
    got = post_pages("facebook", [{"inputUrl": "https://www.facebook.com/krewe", "postId": "7", "url": "https://fb/p/7",
                                   "text": "  PASTRIES\n-Morning bun\n" + "x" * WORDS_MAX}], by_url)[0][0]
    check(got["words"].startswith("PASTRIES\n-Morning bun") and len(got["words"]) == WORDS_MAX,
          "a Facebook post's words keep their lines, trimmed, cut at the column's limit")
    teaser = "Come out to the cocktail lounge tonight for plump, juicing brains 🧠"  # Obbink, 2026-10-25
    check(needs_pictures(teaser) and needs_pictures(""), "a short caption or none reads its pictures")
    check(needs_pictures("Our fall menu is here " * 8) and not needs_pictures("Trivia night is back " * 8 + "at 7 pm"),
          "a long caption reads its pictures only when it gives no time of day")
    check(all(not needs_pictures("Doors open early " * 10 + t) for t in ("7:30", "7pm", "7 p.m.", "noon")), "the times it knows")
    ob = {"name": "Obbink Distillery", "entry_id": "distillery-obbink", "url": "https://www.instagram.com/obbinkdistilling"}
    rows = [{"inputUrl": ob["url"], "id": "5", "caption": teaser, "timestamp": "2026-10-25T21:00:00Z", "type": "Sidecar",
             "displayUrl": "https://cdn/a.jpg?sig=1", "alt": "May be an image of text that says 'TRIVIA'",
             "images": ["https://cdn/a.jpg?sig=2", "https://cdn/b.jpg", "https://cdn/c.jpg", "https://cdn/d.jpg"]},
            {"inputUrl": ob["url"], "id": "6", "caption": "", "displayUrl": "https://cdn/e.jpg"},
            {"inputUrl": ob["url"], "id": "7", "caption": ""}]
    got, _ = post_pages("instagram", rows, {ob["url"]: ob})
    check([p["file"] for p in got] == ["instagram-5", "instagram-6"], "a captionless post with a picture is a page; one without is not")
    check([x["url"] for x in got[0]["pictures"]] == ["https://cdn/a.jpg?sig=1", "https://cdn/b.jpg", "https://cdn/c.jpg"]
          and got[0]["pictures"][0]["about"].startswith("May be"), "a carousel's first three pictures, each once, with Meta's words")
    fb = [{"inputUrl": "https://www.facebook.com/krewe", "postId": "8", "text": "Fun night!",
           "media": [{"thumbnail": "https://fb/t.jpg", "photo_image": {"uri": "https://fb/full.jpg"}, "ocrText": "May be an image of text"}]}]
    check(post_pages("facebook", fb, by_url)[0][0]["pictures"] == [{"url": "https://fb/full.jpg", "about": "May be an image of text"}],
          "a Facebook post's full-size picture")
    with tempfile.TemporaryDirectory() as tmp:
        from PIL import Image
        tmp = Path(tmp)
        Image.new("RGB", (2400, 3000), "white").save(tmp / "flyer.png")
        w, h = fetch_picture((tmp / "flyer.png").as_uri(), tmp / "out.jpg")
        check((w, h) == (1254, 1568) and Image.open(tmp / "out.jpg").format == "JPEG", "a picture is shrunk to a 1568 px JPEG")
        def fake(url, dest):
            if "c.jpg" in url:
                raise OSError("HTTP Error 403")
            dest.write_bytes(b"x")
            return 1080, 1350
        pics = add_pictures(got, tmp / "pictures", fake)
        check(f"Picture 1: {tmp / 'pictures' / 'instagram-5-1.jpg'}" in got[0]["text"] and "read every word" in got[0]["text"]
              and "Meta's own description of picture 1: May be" in got[0]["text"] and "Picture 3:" not in got[0]["text"]
              and "pictures" not in got[0], "the page names each picture for the cheap model, Meta's words beside it")
        check(pics["read"] == 3 and pics["posts"] == 2 and pics["tokens"] == 3 * 1944 and len(pics["failed"]) == 1,
              "three read on two posts, one that would not download reported")
    line = pictures_line(pics)
    check("3 read on 2 posts" in line and "5,832 picture tokens" in line and "$0.003 for the cheap model" in line
          and "$0.047 more if the judge" in line and "1 would not download" in line, f"the cost line: {line}")
    check(pictures_line({"read": 0, "failed": []}) == "[social] pictures: none read", "a check with no pictures says so")
    check(spend_line(8.4, 19) == "Apify: $8.40 of $19 this month", "the plain spend line")
    check("Heads-up" not in spend_line(29.99, 40), "just under 3/4 of a $40 cap: no heads-up")
    check(spend_line(30, 40) == "Apify: $30.00 of $40 this month. Heads-up: past 3/4 of the cap.", "at 3/4: the heads-up")
    check("Heads-up" in spend_line(39.5, 40), "above 3/4: the heads-up")
    check("cap is reached" in spend_line(40, 40) and "Heads-up" not in spend_line(40, 40), "at the cap: the cap line alone")
    blocked = ("import sys; sys.modules['PIL'] = None; import social; social.limits = lambda: "
               "{'current': {'monthlyUsageUsd': 8.4}, 'limits': {'maxMonthlyUsageUsd': 25}}; print(social.spend())")
    r = subprocess.run([sys.executable, "-c", blocked], cwd=Path(__file__).resolve().parent, capture_output=True, text=True)
    check(r.stdout == "Apify: $8.40 of $25 this month\n", f"spend runs with Pillow blocked: {r.stdout}{r.stderr[-300:]}")
    for cond, what in in_parts():
        check(cond, what)
    for cond, what in set_aside_reads():
        check(cond, what)
    for cond, what in done_alone():
        check(cond, what)
    for cond, what in quiet_pages():
        check(cond, what)
    for cond, what in setup_alone():
        check(cond, what)
    print(f"social.py selftest: {ok} passed, 0 failed")


def done_alone():
    """done through a Run, with Apify's store faked: it marks the runs read and saves the set-aside pages, and the check
    is over. Run again it writes the same marks, so nothing moves."""
    import contextlib
    g, wrote = globals(), []
    saved = g["mark_read"], g["save_missed"]
    g["mark_read"], g["save_missed"] = (lambda run, at: wrote.append(("read", run, at))), (lambda m: wrote.append(("missed", m)))
    until, missed = "2026-10-28T23:33:00+00:00", {"https://www.facebook.com/x": {"misses": 1, "why": "nothing back"}}

    def done(**prep):
        """One `done`, with what its prepare found: what it printed."""
        run = Run(folder, date(2026, 10, 28), check="busy")
        run.prepared({"today": "2026-10-28", "run": "busy", "apify_runs": 2, "pictures": None, **prep})
        said = io.StringIO()
        with contextlib.redirect_stdout(said):
            finish(run)
        return said.getvalue(), run.summary().get("done")
    try:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            told, over = done(read_until=until, missed=missed)
            first = list(wrote)
            done(read_until=until, missed=missed)
            twice = list(wrote)
            wrote.clear()
            none = done(read_until=None, missed=missed)
            none_wrote = list(wrote)

            def refused(run, at):
                raise OSError("HTTP Error 401")
            g["mark_read"] = refused
            failed = done(read_until=until, missed=missed)
            failed_wrote = list(wrote)
    finally:
        g["mark_read"], g["save_missed"] = saved
    return [
        (first == [("read", "busy", until), ("missed", missed)] and over is True and "2 runs marked read" in told,
         f"done alone marks the runs read and saves the set-aside pages, and the check is over: {first}"),
        (twice == first * 2, "done run again writes the same marks"),
        (none_wrote == [] and none[1] is True and "no Apify runs to mark" in none[0], "a check with no runs marks nothing"),
        (failed_wrote == [] and "[social] FAILED marking busy read (HTTP Error 401)" in failed[0] and failed[1] is True,
         "a store that refuses is one line, and the set-aside pages wait with the mark, so no run is counted twice"),
    ]


def set_aside_reads():
    """Six checks against a fake Apify, offline, each prepare and done as the routine runs them: Sal's,
    on the busy list, comes back not available three busy reads in a row, then its day's weekly read
    (Thursday) finds a post. Krewe and Bo (busy) post nothing new on the busy reads; Hall (weekly, on
    Thursdays) posts; JT is weekly on Mondays. Apify's schedules are played by hand:
    each run reads its task's pages as they were when it started (smooth-mornings 04)."""
    import contextlib, write_judged
    g = globals()
    sals, krewe, bo, hall, jt = (f"https://www.facebook.com/{n}" for n in ("salsbar", "krewe", "bodiddleys", "hallcomponents", "jt"))
    pages = [{"entry_id": "la", "name": "La Playette", "kind": "facebook", "url": "https://www.facebook.com/la", "busy": False,
              "hidden": True, "day": "thu"},
             {"entry_id": "sals", "name": "Sal's Bar and Grill", "kind": "facebook", "url": sals, "busy": True, "day": "thu"},
             {"entry_id": "krewe", "name": "Krewe", "kind": "facebook", "url": krewe, "busy": True, "day": "thu"},
             {"entry_id": "bo", "name": "Bo", "kind": "facebook", "url": bo, "busy": True, "day": "thu"},
             {"entry_id": "hall", "name": "Hall", "kind": "facebook", "url": hall, "busy": False, "day": "thu"},
             {"entry_id": "jt", "name": "JT", "kind": "facebook", "url": jt, "busy": False, "day": "mon"},
             {"entry_id": "ad", "name": "Ad", "kind": "facebook", "url": "https://www.facebook.com/ad", "busy": False,
              "day": "thu", "skip": "only ads"}]
    tasks, runs, store, data = {}, {}, {"read-busy": {"finished_at": "2026-10-26T00:00:00+00:00"},
                                        "read-weekly": {"finished_at": "2026-10-26T00:00:00+00:00"}}, {}

    def apify(method, path, body=None):
        bits = path.split("?")[0].split("/")
        if path.startswith("/actor-tasks?"):
            return {"data": {"items": [{"name": n, "id": n} for n in tasks]}}
        if path.endswith("/runs?desc=true&limit=30"):
            return {"data": {"items": runs.get(bits[2], [])[::-1]}}
        if path.endswith("&status=SUCCEEDED"):  # last_good
            return {"data": {"items": [r for r in runs.get(bits[2], []) if r["status"] == "SUCCEEDED"][-1:]}}
        if bits[1] == "actor-tasks":
            tasks[body.get("name") or bits[2]] = json.loads(json.dumps(body["input"]))
            return {"data": {"id": body.get("name") or bits[2]}}
        if path.startswith("/key-value-stores?"):
            return {"data": {"id": "s"}}
        if bits[1] == "key-value-stores":
            return store.update({bits[-1]: body}) if method == "PUT" else store.get(bits[-1])
        return data[bits[2]][0]  # a run's INPUT

    def ran(task, at, posting=(), quiet=()):
        """Apify's schedule starts `task` with its pages as they are: a page posts if `posting`, says it
        posted nothing new if `quiet`, else Apify says it is not available."""
        rid = f"r{len(data)}"
        given = [u["url"] for u in tasks[task]["startUrls"]]
        rows = [{"inputUrl": u, "postId": f"{rid}-{u[-4:]}", "url": f"{u}/posts/{rid}", "text": "Trivia tonight at 7 pm",
                 "time": at} if u in posting else {"inputUrl": u, "error": "no_items" if u in quiet else "not_available"}
                for u in given]
        data[rid] = (tasks[task], rows)
        runs.setdefault(task, []).append({"id": rid, "status": "SUCCEEDED", "startedAt": at, "finishedAt": at,
                                          "defaultDatasetId": rid, "usageTotalUsd": 0.01})

    def check(name, when):
        now = datetime.fromisoformat(when)
        said, run = io.StringIO(), Run(folder, now.astimezone(LOCAL).date(), check=name, minutes=None)
        with contextlib.redirect_stdout(said):
            prepare(run, now)
            finish(run)
        return said.getvalue().splitlines()
    fakes = {"api": apify, "items": lambda rid: data[rid][1], "load": lambda root: ([], [])}
    saved = {k: g[k] for k in (*fakes, "find_root")}, write_judged.interest_ids
    said, inputs = [], {}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            folder, root = Path(tmp) / "morning", Path(tmp)
            (root / "sources" / "social").mkdir(parents=True)
            (root / "sources" / "social" / f"{TOWN}.json").write_text(json.dumps(pages))
            g.update(fakes, find_root=lambda *a: root)
            write_judged.interest_ids = lambda: ["dining"]
            sync_tasks(root, {}, datetime(2026, 10, 26, tzinfo=LOCAL))
            for i, (day, hour) in enumerate([(26, 23), (27, 2), (27, 23), (28, 2)]):  # 6 and 9 PM Chicago, Mon and Tue
                ran("bp-busy-facebook", f"2026-10-{day}T{hour:02d}:05:00+00:00", quiet=[krewe, bo])
                said.append(check("busy", f"2026-10-{day}T{hour:02d}:30:00+00:00"))
                inputs[i] = {t: [u["url"] for u in x.get("startUrls", [])] for t, x in tasks.items()}
            ran("bp-weekly-thu-facebook", "2026-10-29T20:05:00+00:00", [hall, sals])  # Thursday 3 PM
            said.append(check("weekly", "2026-10-29T20:45:00+00:00"))
            ran("bp-busy-facebook", "2026-10-29T23:05:00+00:00", [krewe], [bo])
            said.append(check("busy", "2026-10-29T23:30:00+00:00"))
            inputs["after"] = {t: [u["url"] for u in x.get("startUrls", [])] for t, x in tasks.items()}
            on_lists = sorted(t for t, given in inputs["after"].items() if sals in given)
            wk = lambda *when: [p for p in page_lists(root, {canon(hall): {"aside": "2026-10-22"}},
                                                      datetime(2026, 11, *when, tzinfo=LOCAL)).get(("weekly", "facebook"), [])
                                if p["entry_id"] == "hall"]
            monthly = [len(wk(4, 21, 30)), len(wk(5, 0, 5)), len(wk(5, 15, 45))]
            ev = lambda *when: sorted(p["entry_id"] for p in page_lists(root, {}, datetime(2026, 11, *when, tzinfo=LOCAL))[("weekly", "events")])
            events_lists = [ev(4, 21, 30), ev(10, 21, 30)]
    finally:
        g.update(saved[0])
        write_judged.interest_ids = saved[1]
    named = [i for i, lines in enumerate(said) if any("salsbar" in ln or "Sal's" in ln for ln in lines)]
    sal_lines = [[ln for ln in lines if "salsbar" in ln or "Sal's" in ln] for lines in said]
    counts = [next(ln.split(", ")[1] for ln in lines if ln.startswith("[social] busy:")) for lines in said[:4]]
    weekly_count = next(ln.split(", ")[1] for ln in said[4] if ln.startswith("[social] weekly:"))
    twenty_four = [f"https://www.facebook.com/p{i}" for i in range(24)]
    blocked = tally([(f"2026-10-2{i}", twenty_four, [], f"facebook run {i}") for i in range(3)], {}, date(2026, 10, 28))
    return [
        (sals not in inputs[3]["bp-busy-facebook"] and sals in inputs[3]["bp-weekly-thu-facebook"]
         and sals in inputs[2]["bp-busy-facebook"] and on_lists == ["bp-busy-facebook"]
         and all(krewe in inputs[i]["bp-busy-facebook"] for i in inputs) and counts == ["3 pages"] * 3 + ["2 pages"],
         "a social page not available three reads in a row leaves its paid list at the next sync, for its "
         "day's weekly read, and goes back on its list when that read finds it; one with no new posts stays; "
         "the pages count leaves set-aside pages out"),
        (inputs["after"]["bp-weekly-thu-facebook"] == [hall] and inputs["after"]["bp-weekly-mon-facebook"] == [jt]
         and weekly_count == "7 pages" and inputs["after"]["bp-weekly-mon-events"] == [events_tab(jt)]
         and not any("facebook.com/ad" in u for given in inputs["after"].values() for u in given),
         "each weekly page is in its own day's task; Thursday's check counts Thursday's pages (Hall's and Sal's posts, "
         "five Events tabs); JT's Events tab is on Monday's task in the week its Monday is the month's first; a page "
         "that only advertises is in none"),
        (named == [2, 4] and sal_lines[2] == [f"[social] Set aside: Sal's Bar and Grill's Facebook {sals}: not available 3 "
                                         "reads in a row; off its paid list, tried every Thursday"]
         and sal_lines[4] == [f"[social] Back: Sal's Bar and Grill's Facebook {sals}: read again, back on its list"],
         "a social page is named the check it is set aside and the check it is back, and no other"),
        (events_lists == [["bo", "hall", "krewe", "la", "sals"], ["bo", "krewe", "la", "sals"]]
         and sorted(u for t, given in inputs["after"].items() if t.endswith("-search") for u in given)
         == sorted(p["url"] for p in search_pages()),
         "the weekly Events tabs read the busy and hidden Facebook pages, and every one when its day falls in a "
         "month's first week (Hall's Thursday, not JT's Monday); the town's events searches have tasks of their own"),
        (monthly == [1, 1, 0], "a weekly page set aside is tried with its day's read in a month's first week, "
                               "by the clock: a 7:30 PM check that starts past midnight still puts it on"),
        (tally([("t", [sals, krewe, bo], [{"inputUrl": krewe, "error": "no_items"}, {"inputUrl": bo, "error": "no_items"}],
                 "x")] * 3, {}, date(2026, 10, 28))[0] == {sals: {"misses": 3, "why": "nothing back", "aside": "2026-10-28"}},
         "a page Apify gives no row for three reads in a row is set aside too"),
        (blocked[0] == {} and blocked[3] == [f"facebook run {i}: 24 of 24 pages not read, not counted" for i in range(3)],
         "a run that reads few of its pages (Facebook blocking Apify, a cap) counts against none, in one line"),
    ]


def quiet_pages():
    """tally's quiet rule offline: a weekly page with no new post four reads in a row is read once a month until
    it posts; a busy page never is; a page set aside for misses that reads again comes back, counting from one."""
    qa, busy = "https://www.facebook.com/quiet", "https://www.facebook.com/busy"
    none = lambda u: {"inputUrl": u, "error": "no_items"}
    reads = [(f"2026-11-0{i}", [qa, busy], [none(qa), none(busy)], f"run {i}") for i in range(1, 6)]
    day = date(2026, 11, 4)
    three, four, five = (tally(reads[:n], {}, day, {qa}) for n in (3, 4, 5))
    posted = tally([("2026-11-09", [qa], [{"inputUrl": qa, "postId": "1", "text": "Open late tonight"}], "r")], four[0], day, {qa})
    missed = {qa: {"misses": 3, "why": "not_available", "aside": "2026-11-01"}}
    again = tally([("2026-11-09", [qa], [none(qa)], "r")], missed, day, {qa})
    lists = {("weekly", "facebook"): [{"url": qa, "name": "Quiet", "kind": "facebook", "busy": False, "day": "tue"}],
             ("busy", "facebook"): [{"url": busy, "name": "Busy", "kind": "facebook", "busy": True, "day": "fri"}]}
    lines = aside_lines({**four[0], busy: {"misses": 3, "why": "not_available", "aside": "2026-11-04"}}, [qa, busy], [], lists)
    return [
        (three[0] == {qa: {"quiet": 3}} and four[0] == {qa: {"quiet": 4, "why": "no new posts", "aside": "2026-11-04"}}
         and four[1] == [qa] and five[0][qa]["quiet"] == 5 and five[1] == [qa] and busy not in five[0],
         "a weekly page with nothing new four reads in a row is set aside once, and stays; a busy page never is"),
        (posted[0] == {} and posted[2] == [qa], "a quiet page's first new post brings it back"),
        (again[0] == {qa: {"quiet": 1}} and again[2] == [qa], "a page set aside for misses that reads again is back, quiet from one"),
        (lines == [f"Set aside: Quiet's Facebook {qa}: no new posts 4 weekly reads in a row; off its weekly list, read on the "
                   "first Tuesday of each month",
                   f"Set aside: Busy's Facebook {busy}: not available 3 reads in a row; off its paid list, tried every Friday"],
         f"the words for a quiet page and for a busy one: {lines}"),
    ]


def setup_alone():
    """setup against a fake Apify, offline, the day the weekly list's days begin: a task per day and kind, a schedule
    per day starting only that day's tasks, every read reaching back to the last weekly check; the Thursday read's
    schedule and its read task deleted, a task whose run no check has read kept, and nothing that isn't the watch's
    touched."""
    import contextlib
    g = globals()
    pages = [{"entry_id": "krewe", "name": "Krewe", "kind": "facebook", "url": "https://www.facebook.com/krewe", "busy": True, "day": "fri"},
             {"entry_id": "hall", "name": "Hall", "kind": "facebook", "url": "https://www.facebook.com/hall", "busy": False, "day": "tue"},
             {"entry_id": "hall", "name": "Hall", "kind": "instagram", "url": "https://www.instagram.com/hall", "busy": False, "day": "tue"},
             {"entry_id": "jt", "name": "JT", "kind": "facebook", "url": "https://www.facebook.com/jt", "busy": False, "day": "sat"}]
    task = lambda n, ran=None: {"name": n, "id": n, "stats": {"lastRunStartedAt": ran}}
    tasks = {n: task(n, r) for n, r in [("bp-busy-facebook", "2026-11-11T15:30:00Z"), ("bp-weekly-facebook", "2026-11-05T21:00:00Z"),
                                        ("bp-weekly-search", "2026-11-06T15:00:00Z"), ("bp-dig-facebook", None), ("bp-monthly-places", None)]}
    inputs, schedules, deleted = {}, {n: {"name": n, "id": n} for n in ("bp-busy-930am", "bp-busy-7pm", "bp-weekly", "bp-monthly-places")}, []
    store = {"read-busy": {"finished_at": "2026-11-11T15:40:00+00:00"}, "read-weekly": {"finished_at": "2026-11-05T21:03:00+00:00"}}

    def apify(method, path, body=None):
        bits = path.split("?")[0].split("/")
        if method == "DELETE":
            deleted.append(path)
            return (tasks if bits[1] == "actor-tasks" else schedules).pop(bits[2])
        if path.startswith("/actor-tasks?"):
            return {"data": {"items": list(tasks.values())}}
        if path.startswith("/schedules?"):
            return {"data": {"items": list(schedules.values())}}
        if path.endswith("&status=SUCCEEDED"):
            ran = tasks[bits[2]]["stats"]["lastRunStartedAt"]
            return {"data": {"items": [{"startedAt": ran}] if ran else []}}
        if bits[1] == "actor-tasks":
            name = body.get("name") or bits[2]
            tasks.setdefault(name, task(name))
            inputs[name] = body["input"]
            return {"data": {"id": name}}
        if bits[1] == "schedules":
            schedules[body["name"]] = dict(body, id=body["name"])
            return {"data": {"id": body["name"]}}
        if path.startswith("/key-value-stores?"):
            return {"data": {"id": "s"}}
        return store.update({bits[-1]: body}) if method == "PUT" else store.get(bits[-1])
    saved = {k: g[k] for k in ("api", "find_root", "load", "read_missed", "search_pages")}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sources" / "social").mkdir(parents=True)
            (root / "sources" / "social" / f"{TOWN}.json").write_text(json.dumps(pages))
            g.update(api=apify, find_root=lambda *a: root, load=lambda root: ([], []), read_missed=dict, search_pages=list)
            with contextlib.redirect_stdout(io.StringIO()):
                setup()
    finally:
        g.update(saved)
    weekly = {n: [a["actorTaskId"] for a in s["actions"]] for n, s in schedules.items() if n.startswith("bp-weekly-")}
    return [
        (weekly == {"bp-weekly-tue": ["bp-weekly-tue-facebook", "bp-weekly-tue-instagram"], "bp-weekly-sat": ["bp-weekly-sat-facebook"],
                    "bp-weekly-fri": ["bp-weekly-fri-events"]}
         and [a["actorTaskId"] for a in schedules["bp-busy-930am"]["actions"]] == ["bp-busy-facebook"]
         and schedules["bp-weekly-tue"]["cronExpression"] == "0 15 * * 2"
         and not any("input" in a for s in schedules.values() for a in s.get("actions", [])),
         f"a schedule per day starts only that day's tasks (Krewe's Events tab on its Friday), and none overrides how far back: {weekly}"),
        (inputs["bp-weekly-tue-facebook"]["onlyPostsNewerThan"] == "2026-11-05T20:03:00"
         and inputs["bp-weekly-sat-facebook"]["onlyPostsNewerThan"] == "2026-11-05T20:03:00"
         and inputs["bp-busy-facebook"]["onlyPostsNewerThan"] == "2026-11-11T14:30:00"
         and store["days-began"] == {"at": "2026-11-05T21:03:00+00:00"},
         "each day's first read reaches back to the last weekly check; the busy list to its own last read"),
        (sorted(deleted) == ["/actor-tasks/bp-weekly-facebook", "/schedules/bp-weekly"]
         and {"bp-weekly-search", "bp-dig-facebook", "bp-monthly-places"} <= set(tasks) and "bp-monthly-places" in schedules,
         f"the Thursday read's schedule and read task are deleted; one with a run no check has read is kept; the dig's "
         f"and the accounts' are never touched: {deleted}"),
    ]


def in_parts():
    """prepare in 2-minute parts against a fake Apify whose run is still going for 200 seconds and
    pictures that take 30 seconds each, offline on a fake clock; then one long check, and one whose
    run never ends."""
    import contextlib, run as runner, write_judged
    g, clock, got = globals(), type("Clock", (), {})(), []
    day, at = date(2026, 10, 28), datetime(2026, 10, 28, 23, 30, tzinfo=timezone.utc)
    clock.monotonic = clock.time = lambda: clock.t
    clock.sleep = lambda s: setattr(clock, "t", clock.t + s)
    page = {"url": "https://www.facebook.com/krewe", "name": "Krewe", "entry_id": "krewe", "category": None}
    rows = [{"inputUrl": page["url"], "postId": str(i), "url": f"https://fb/p/{i}", "text": "Fun night!",
             "time": "2026-10-28T22:00:00.000Z", "media": [{"photo_image": {"uri": f"https://fb/{i}.jpg"}}]} for i in range(3)]

    def apify(method, path, body=None):
        if path.startswith("/actor-tasks?"):
            return {"data": {"items": [{"name": "bp-busy-facebook", "id": "t1"}]}}
        done = clock.t >= 1000 + ends
        return {"data": {"items": [{"id": "r1", "status": "SUCCEEDED" if done else "RUNNING", "startedAt": "2026-10-28T23:25:00Z",
                                    "finishedAt": "2026-10-28T23:33:00Z" if done else None, "defaultDatasetId": "d1",
                                    "usageTotalUsd": 0.17}]}}

    def picture(url, dest):
        got.append(url)
        clock.t += 30
        dest.write_bytes(b"x")
        return 1080, 1350

    def check(minutes):
        """One check's prepare, part after part: each part's words, and the batches it laid out."""
        clock.t, said = 1000.0, []
        if (folder / "prepare.json").exists():  # the last check's `done`: this prepare starts a new check
            Run(folder, day).finished()
        while len(said) < 6 and (not said or "run again" in said[-1]):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                prepare(Run(folder, day, check="busy", minutes=minutes), at)
            said.append(out.getvalue())
        return said, {f.name: f.read_text() for f in (folder / "batches").iterdir()} if (folder / "batches").exists() else {}
    fakes = {"api": apify, "items": lambda d: rows, "sync_tasks": lambda root, *a: None, "fetch_picture": picture,
             "read_missed": dict,
             "last_read": lambda run: datetime(2026, 10, 28, 2, 40, tzinfo=timezone.utc), "time": clock,
             "page_lists": lambda root, *a: {("busy", "facebook"): [page]}}
    saved = {k: g[k] for k in (*fakes, "find_root")}, runner.time, write_judged.interest_ids
    try:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "morning"
            g.update(fakes, find_root=lambda *a: Path(tmp))
            runner.time, write_judged.interest_ids = clock, lambda: ["dining"]
            ends = 200
            one, one_batches = check(None)
            got.clear()
            parts, batches = check(2)
            pictures = list(got)
            ends = float("inf")
            never, _ = check(2)
            again, flags = io.StringIO(), folder / "flags.jsonl"
            flags.write_text("{}\n")  # the helpers' flags, already in
            with contextlib.redirect_stdout(again):  # run again once done, before `done`: nothing read again
                prepare(Run(folder, day, check="busy", minutes=2), at)
            again = (again.getvalue(), flags.exists())
    finally:
        g.update(saved[0])
        runner.time, write_judged.interest_ids = saved[1:]
    (n, parts), (m, never) = (len(parts), parts + [""] * 3), (len(never), never + [""] * 4)  # a failing check reads as one
    return [
        (parts[0] == "[social] run again: bp-busy-facebook still running on Apify\n" and n == 3,
         "a run still going when the part's time is spent: run again, not a wait past it"),
        (parts[1] == "[social] run again: 1 posts' pictures still to read\n"
         and sorted(pictures) == [f"https://fb/{i}.jpg" for i in range(3)],
         "pictures over parts: each read once, the rest left for the next part"),
        (batches == one_batches and len(batches) == 1 and parts[2].split("\n")[0] == one[0].split("\n")[0],
         "the parts lay out what one long check does"),
        (m == 4 and "[social] FAILED bp-busy-facebook still running after 8 minutes" in never[3],
         "a run that never ends is waited for 8 minutes over every part, then left for the next check"),
        (again[0].startswith("[social] prepared already") and again[0].endswith(never[3]) and again[1],
         "prepare run again once done says its summary again and starts nothing over"),
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["setup", "prepare", "done", "spend"])
    ap.add_argument("run", nargs="?", choices=["busy", "weekly"])
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--town", default=DEFAULT, help="the town whose page list (sources/social/<town>.json) is read")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    global TOWN
    lookup(args.town)
    TOWN = args.town
    if args.step == "spend":
        return print(spend())
    if args.step == "setup":
        return setup()
    now = datetime.now(timezone.utc)
    today = date.fromisoformat(args.today) if args.today else now.astimezone(LOCAL).date()
    run = Run(find_root() / ".runs" / "morning", today, check=args.run)
    if args.step == "done":
        return finish(run)
    if args.step != "prepare" or not args.run:
        ap.error("setup, prepare busy|weekly, done, or spend")
    prepare(run, now)


if __name__ == "__main__":
    main()
