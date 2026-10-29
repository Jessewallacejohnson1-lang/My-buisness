#!/usr/bin/env python3
"""
social.py: the social watch's script half (registry ADR-020, amended 2026-10-22). Places'
public Facebook and Instagram posts, read through Apify and never logged in, laid out exactly
as morning.py lays out changed pages, so the routine's next steps are the morning job's own:
the cheap model flags (flag.md), the routine's model judges (judge.md), and `morning.py save`
writes Events and News (morning.md's Read and judge, and Save). The routine's steps are
sources/models/social.md.

Apify reads the pages on its own clock (Jesse, 2026-10-23: "apify has direct sourcing"), so a
check never waits on the Claude plan: saved tasks `bp-<run>-<kind>` hold each list's pages, and
schedules start them, the busy list at 6pm and 9pm Chicago and every other page (plus the busy
list's Facebook Events tabs) on Thursdays at 3pm. The routines come half an hour or more later
and read whatever Apify saved since the last check they finished, so one the plan's usage limit
skipped (the 9pm one on 2026-10-22) is read by the next.

  setup           makes or updates the tasks and schedules from sources/social/<town>.json; run it
                  after the list changes (prepare also refreshes the tasks' pages)
  prepare busy    the busy list's Apify runs that finished since the last busy check
  prepare weekly  the weekly runs that finished since the last weekly check. Either works in parts
                  of about 6 minutes, as morning.py prepare does: run it again while it prints
                  "run again"
  done            after `morning.py save`: marks those runs read, so the next check starts after
                  them. A check that stopped early never marks, and the next reads its runs too.
                  It repeats the pictures line, so the answer carries what pictures cost.
  spend           one line for the morning report, "Apify: $X of $25 this month", with a
                  heads-up past $15 and at the cap (Jesse, 2026-10-22: no slowdown, just say).
                  The cap is whatever Apify reports: $25 since Jesse raised it from $19 on
                  2026-10-28.

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
takes it off its paid list and the Thursday read tries it, a busy page every week and a weekly page
in the first week of each month; a good read puts it back. It is named once when set aside and once
when back.

The mark lives in Apify's own storage (the named key-value store `bp-social-watch`, records
`read-busy` and `read-weekly`), so it survives each routine's throwaway copy; so do the set-aside
pages (record `missed`), saved by `done` with the mark.

Everything lands in .runs/morning/, the morning job's folder (each routine runs in its own copy
of the repository). In the cloud, Apify's REST API is called with no key: the environment's
network secret for api.apify.com adds it on the way out, so the token never enters the session.
APIFY_TOKEN in the environment is used when set; on a Mac with neither, the calls go through
Composio. Only Apify's schedules start paid runs; each task has its own spending cap.

  python3 sources/scripts/social.py setup
  python3 sources/scripts/social.py prepare busy|weekly [--today YYYY-MM-DD]
  python3 sources/scripts/social.py done
  python3 sources/scripts/social.py spend
  python3 sources/scripts/social.py --selftest
"""

import argparse, io, json, math, os, re, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
from run import deadline, late
from batch import layout
import composio

TOWN = "st-joseph-mn"
API = "https://api.apify.com/v2"
POSTS = 20  # most posts read per page per check; a busy page posts a few a day at most
ACTORS = {  # (actor, spending cap in USD per run) for each kind of read
    ("busy", "facebook"): ("apify~facebook-posts-scraper", 0.40),
    ("busy", "instagram"): ("apify~instagram-post-scraper", 0.20),
    ("weekly", "facebook"): ("apify~facebook-posts-scraper", 2.50),
    ("weekly", "instagram"): ("apify~instagram-post-scraper", 0.75),
    ("weekly", "events"): ("apify~facebook-events-scraper", 1.00),
}
# Apify's clock, Chicago time: (schedule, cron, run, how far back each read goes). A window
# reaches an hour past the last one, so a post that lands while a run starts is never lost.
SCHEDULES = [("bp-busy-6pm", "0 18 * * *", "busy", "22 hours"),
             ("bp-busy-9pm", "0 21 * * *", "busy", "4 hours"),
             ("bp-weekly", "0 15 * * 4", "weekly", "169 hours")]
EMPTY = {"no_items", "not_available", "not_found", "Restricted profile"}
HEADS_UP = 15.0
STORE = "bp-social-watch"
LOOKBACK = {"busy": timedelta(days=8), "weekly": timedelta(days=15)}  # never reads runs older than this
DONE = ("SUCCEEDED", "FAILED", "ABORTED", "TIMED-OUT")
WAIT = 480  # seconds, over every part, that a check waits for an Apify run still going
PART_MINUTES = 6  # as morning.py prepare's parts: the cloud stops a command at 10 minutes
MISSES = 3  # reads in a row a page comes back not available or with nothing before it is set aside (smooth-mornings 04)

# Pictures (Jesse, 2026-10-26: the words on a post's picture, when its caption doesn't say enough)
PICTURES = 3        # most read per post: a carousel's flyer is often its second or third slide
SHORT_WORDS = 30    # a caption under this many words has its pictures read, a time of day or not
CLOCK = re.compile(r"\b\d{1,2}(:\d{2})?\s*(a\.?m\b|p\.?m\b)|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b", re.I)
LONG_SIDE = 1568    # px; a flyer's small print stays readable (Instagram posts are 1080 wide anyway)
UA = "BlockPartyBot/1.0 (+https://blockpartystjoe.com)"
# What looking at a picture costs, in list-price dollars per million picture tokens (the routines
# run on Jesse's Claude plan, so it is plan usage, not a bill). A picture costs about one token per
# 750 pixels. The cheap model (Haiku 5.5, $0.10 in) writes it to its cache at twice that, then
# carries it through the batch's ~40 later turns at a tenth: about $0.60. The judge (Sonnet 5.5,
# $2 in) opens only pictures an item rests on: $4 to cache, ~20 later turns at $0.20, about $8.
CHEAP_PER_M, JUDGE_PER_M = 0.60, 8.0


def task_name(run, kind):
    return f"bp-{run}-{kind}"


def pages_for(run, root):
    """The pages a run reads: busy or not, and never one Facebook hides from logged-out readers."""
    pages = json.loads((root / "sources" / "social" / f"{TOWN}.json").read_text())
    return [p for p in pages if p["busy"] == (run == "busy") and not p.get("hidden")]


def events_tab(url):
    return url.rstrip("/") + "/upcoming_hosted_events"


def actor_input(kind, urls, window):
    """A task's input: the pages, and how far back to read ("22 hours"); a schedule overrides the window."""
    if kind == "facebook":
        return {"startUrls": [{"url": u} for u in urls], "resultsLimit": POSTS, "onlyPostsNewerThan": window}
    if kind == "instagram":
        return {"username": urls, "resultsLimit": POSTS, "onlyPostsNewerThan": window}
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


def monthly_try(now):
    """Whether the next Thursday 3 PM read after `now` (SCHEDULES' bp-weekly) falls in a month's first
    week. By the clock, not the date: a 9:30 PM check that starts past midnight is still before it."""
    t = now.astimezone(LOCAL).replace(hour=15, minute=0, second=0, microsecond=0)
    t += timedelta(days=(3 - t.weekday()) % 7)
    return (t if t > now else t + timedelta(days=7)).day <= 7


def page_lists(root, missed=None, now=None):
    """{(run, kind): pages} for every task: each list's own pages, and the busy list's Facebook
    pages again for the weekly Events tabs. A page set aside (`missed`) leaves its list for the
    Thursday read: a busy page every week, a weekly page in the first week of each month."""
    category = {e["id"]: e.get("category") for e in load(root)[0]}
    aside = {u for u, m in (missed or {}).items() if m.get("aside")}
    out = {}
    for run in ("busy", "weekly"):
        for p in pages_for(run, root):
            p["category"] = category.get(p["entry_id"])
            if canon(p["url"]) not in aside:
                out.setdefault((run, p["kind"]), []).append(p)
            elif run == "busy" or (now and monthly_try(now)):
                out.setdefault(("weekly", p["kind"]), []).append(p)
    out[("weekly", "events")] = [p for p in out.get(("busy", "facebook"), [])]
    # ponytail: a list left empty keeps its task's last pages; give the task no pages if one ever empties
    return {k: v for k, v in out.items() if k in ACTORS}


def sync_tasks(root, missed=None, now=None):
    """Each task's pages as the list now has them, set-aside pages moved (page_lists); makes a task
    that is missing."""
    tasks, ids = by_name("/actor-tasks"), {}
    for (run, kind), pages in page_lists(root, missed, now).items():
        actor, cap = ACTORS[(run, kind)]
        body = {"input": actor_input(kind, [p["url"] for p in pages], next(w for _, _, r, w in SCHEDULES if r == run)),
                "options": {"timeoutSecs": 600, "maxTotalChargeUsd": cap}}
        name = task_name(run, kind)
        if name in tasks:
            api("PUT", f"/actor-tasks/{tasks[name]['id']}", body)
            ids[name] = tasks[name]["id"]
        else:
            ids[name] = api("POST", "/actor-tasks", {"actId": actor, "name": name, **body})["data"]["id"]
    return ids


def setup():
    root = find_root()
    ids = sync_tasks(root, read_missed(), datetime.now(LOCAL))
    have = by_name("/schedules")
    for name, cron, run, window in SCHEDULES:
        actions = [{"type": "RUN_ACTOR_TASK", "actorTaskId": tid,
                    **({} if n.endswith("-events") else {"input": {"onlyPostsNewerThan": window}})}  # merged over the task's own input
                   for n, tid in ids.items() if n.startswith(f"bp-{run}-")]
        body = {"name": name, "cronExpression": cron, "timezone": "America/Chicago", "isEnabled": True,
                "isExclusive": True, "actions": actions}
        if name in have:
            api("PUT", f"/schedules/{have[name]['id']}", body)
        else:
            api("POST", "/schedules", body)
        print(f"[social] schedule {name}: {cron} Chicago, {len(actions)} tasks, reading {window} back")
    now = datetime.now(timezone.utc).isoformat()
    for run in ("busy", "weekly"):
        if not last_read(run):  # the first setup: start from now, never from runs made before it
            mark_read(run, now)


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
                        out.setdefault(name.split("-", 2)[2], []).append(r)
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
    src = canon(row.get("inputUrl") or row.get("facebookUrl") or "")
    return src or (f"https://www.instagram.com/{row['ownerUsername'].lower()}" if row.get("ownerUsername") else "")


def page_of(src, by_url):
    return by_url.get(src) or next((p for u, p in by_url.items() if u and u in src), None)


def run_pages(run_id):
    """The pages an Apify run was given, from its own input (a schedule's run carries the task's
    pages as they were when it started)."""
    got = api("GET", f"/actor-runs/{run_id}/key-value-store/records/INPUT") or {}
    urls = [u.get("url") if isinstance(u, dict) else u for u in got.get("startUrls") or []] + list(got.get("username") or [])
    return [canon(u) for u in urls if isinstance(u, str)]


def tally(reads, missed, today):
    """Each page the posts runs read, oldest run first: read when a row of it is a post or says it
    posted nothing new (`no_items`: most busy pages, most reads); missed when Apify says it is not
    available, or gives no row for it at all (Sal's, every read in October). MISSES misses in a row set
    a page aside; a good read brings it back. A run that missed more than half its pages (Facebook
    blocking Apify, a run stopped at its cap) counts against none. `reads`: (finished, pages, rows,
    what) per run. Returns the new state, the pages set aside and back, and a line per run not counted."""
    state, aside, back, uncounted = {u: dict(m) for u, m in missed.items()}, [], [], []
    for _, pages, rows, what in sorted(reads, key=lambda x: x[0]):
        found, why, given = set(), {}, {p: p for p in pages}
        for r in rows:
            u = page_of(src_of(r), given)
            if u and r.get("error") and r["error"] != "no_items":
                why[u] = r["error"]
            elif u:
                found.add(u)
        counted = (len(pages) - len(found & set(pages))) * 2 <= len(pages)
        if not counted:
            uncounted.append(f"{what}: {len(pages) - len(found & set(pages))} of {len(pages)} pages not read, not counted")
        for u in pages:
            m = state.get(u, {})
            if u in found:
                back += [u] if m.get("aside") else []
                state.pop(u, None)
            elif counted and not m.get("aside"):
                m = {"misses": m.get("misses", 0) + 1, "why": why.get(u, "nothing back")}
                if m["misses"] >= MISSES:
                    m["aside"] = str(today)
                    aside.append(u)
                state[u] = m
    return state, aside, back, uncounted


def aside_lines(state, aside, back, lists):
    """The answer's words: each page the check it is set aside and the check it is back."""
    named = {canon(p["url"]): p for pages in lists.values() for p in pages}
    name = lambda u: f"{named[u]['name']}'s {named[u]['kind'].title()} {u}" if u in named else u
    retry = lambda u: ("the Thursday read" if named.get(u, {}).get("busy")
                       else "the Thursday read in the first week of each month")
    return ([f"Set aside: {name(u)}: {state[u]['why'].replace('_', ' ')} {MISSES} reads in a row; off its paid list, "
             f"tried with {retry(u)}"
             for u in aside]
            + [f"Back: {name(u)}: read again, back on its list" for u in back])


def post_pages(kind, rows, by_url):
    """Apify's rows as pages: one post each, with who posted it, where and when. An empty row
    (a page with nothing new, hidden, gone) is no page; a hidden one is reported. A post whose
    caption needs its pictures carries their addresses under `pictures`, for add_pictures; one
    with no caption but a picture is a page too, since its words may all be on the picture."""
    pages, hidden = [], []
    for r in rows:
        src = src_of(r)
        if r.get("error") in EMPTY or r.get("error"):
            if r.get("error") != "no_items":
                hidden.append(f"{src}: {r.get('error')}")
            continue
        page = page_of(src, by_url)
        if kind == "events":
            text = r.get("description") or ""
            where = r.get("location", {}).get("name") if isinstance(r.get("location"), dict) else r.get("location")
            body = (f"{page['name'] if page else 'A St. Joseph place'} lists this event on its Facebook page.\n"
                    f"Event: {r.get('name') or r.get('title') or ''}\nWhen: {r.get('dateTimeSentence') or r.get('utcStartDate') or r.get('startDate') or ''}\n"
                    f"Where: {where or ''}\n\n{text}")
            pid, url, pics = r.get("id") or r.get("eventId") or r.get("url"), r.get("url"), []
        else:
            text = (r.get("text") if kind == "facebook" else r.get("caption")) or ""
            pics = picture_urls(kind, r) if needs_pictures(text) else []
            if not text.strip() and not pics:
                continue
            stamp = r.get("time") or r.get("timestamp")
            body = (f"{page['name'] if page else 'A St. Joseph place'} posted this on {kind.title()} "
                    f"on {when_text(stamp)}:\n\n{text.strip() or '(no caption)'}")
            pid, url = r.get("postId") or r.get("id") or r.get("shortCode"), r.get("url")
        if not page or not pid:
            continue
        pages.append({"file": f"{kind}-{pid}", "url": url or page["url"], "entry_id": page["entry_id"],
                      "name": page["name"], "category": page.get("category"), "trust": "official", "text": body,
                      **({"pictures": pics} if pics else {})})
    return pages, hidden


def prepare(run, today, out, now, minutes=PART_MINUTES):
    """In timed parts, as morning.py's: the wait for an Apify run still going and the pictures'
    downloads stop after `minutes` and say "run again", and social-part.json carries the check to
    the next part."""
    root = find_root()
    stop, part_f = deadline(minutes), out / "social-part.json"
    part = json.loads(part_f.read_text()) if part_f.exists() else {}
    if part.get("run") != run or part.get("today") != str(today) or (out / "prepare.json").exists():  # a new check
        if out.exists():
            shutil.rmtree(out)
        (out / "batches").mkdir(parents=True)
        part = {"run": run, "today": str(today), "failed": [], "give_up": time.time() + WAIT}
        try:
            part["missed"] = read_missed()
        except Exception as e:  # every page read this time, and none counted
            part["missed"], _ = None, part["failed"].append(f"set-aside pages unreadable: {e}")
        try:
            sync_tasks(root, part["missed"], now)  # the next run reads the list as it is now
        except Exception as e:
            part["failed"].append(f"task pages not refreshed: {e}")
        part["listed"] = sum(len(v) for (r, _), v in page_lists(root, part["missed"], now).items() if r == run)
        try:
            mark = last_read(run)
        except Exception as e:  # the store unreadable: the last LOOKBACK of runs, and say so
            mark, _ = None, part["failed"].append(f"last read unreadable ({e}); reading every run of the last {LOOKBACK[run].days} days")
        part["mark"] = mark and mark.isoformat()
    now = datetime.fromisoformat(part.setdefault("now", now.isoformat()))  # every part by the first part's clock
    lists, failed = page_lists(root), part["failed"]
    mark = part["mark"] and datetime.fromisoformat(part["mark"])
    if "posts" not in part:
        found, waiting = runs_since(run, mark, now, part["give_up"], stop)
        if waiting and time.time() <= part["give_up"]:  # the part's time is spent first
            part_f.write_text(json.dumps(part))
            return print(f"[social] run again: {', '.join(waiting)} still running on Apify")
        failed += [f"{n} still running after 8 minutes; its posts wait for the next check" for n in waiting]

        posts, cost, until, reads = [], 0.0, mark, []
        for kind, runs in found.items():
            # Every page of its kind, either list: a run may carry a page set aside or back since.
            by_url = {canon(p["url"]): p for (_, k), ps in lists.items() if k == kind for p in ps}
            if kind == "events":
                by_url = {events_tab(u): p for u, p in by_url.items()} | by_url
            for r in runs:
                cost += float(r.get("usageTotalUsd") or 0)
                finished = datetime.fromisoformat(r["finishedAt"].replace("Z", "+00:00"))
                until = max(until, finished) if until else finished
                rows = items(r["defaultDatasetId"])
                got, hidden = post_pages(kind, rows, by_url)
                posts += got
                if kind == "events":  # a posts page Apify can't read is named once, set aside (tally)
                    failed += [f"{kind}: {h}" for h in hidden]
                elif r["status"] == "SUCCEEDED" and part.get("missed") is not None:
                    reads.append((r["finishedAt"], run_pages(r["id"]), rows,
                                  f"{kind} run at {finished.astimezone(LOCAL):%a %-I:%M %p}"))
                if r["status"] != "SUCCEEDED":
                    failed.append(f"{kind} run {r['id']} at {finished.astimezone(LOCAL):%a %-I:%M %p}: {r['status']}")
        seen, unique = set(), []
        for p in posts:  # overlapping windows read a post twice; one page each
            if p["file"] not in seen:
                seen.add(p["file"]), unique.append(p)
        if part.get("missed") is not None:  # saved by `done` with the mark, so a check that stops early counts nothing
            state, aside, back, uncounted = tally(reads, part["missed"], today)
            part.update(missed=state, aside=aside_lines(state, aside, back, lists))
            failed += uncounted
        part.update(posts=unique, cost=cost, until=until and until.isoformat(), runs=sum(len(v) for v in found.values()))
    posts = part["posts"]
    pics = add_pictures(posts, out / "pictures", fetch_picture, stop, part.get("pics"))
    if any(p.get("pictures") for p in posts):
        part_f.write_text(json.dumps({**part, "pics": pics}))
        return print(f"[social] run again: {sum(bool(p.get('pictures')) for p in posts)} posts' pictures still to read")
    failed = failed + [f"picture not downloaded: {f}" for f in pics["failed"]]
    cost, runs = part["cost"], part["runs"]
    until = part["until"] and datetime.fromisoformat(part["until"])
    for i, text in enumerate(layout(posts, today), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(text)
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in posts], indent=1))
    (out / "feeds.jsonl").write_text("")
    try:
        import write_judged
        interests = write_judged.interest_ids()
    except Exception as e:  # no database keys (a dry run on a Mac): the judge then uses null
        interests, _ = [], failed.append(f"interest ids unread: {e}")
    checked = part.get("listed", 0)  # set-aside pages left out
    summary = {"today": str(today), "run": run, "since": mark.isoformat() if mark else None,
               "fetched": checked, "changed": len(posts), "first_seen": 0, "to_read": len(posts),
               "batches": len(list((out / "batches").iterdir())), "failed": failed, "readers": [],
               "interests": interests, "apify_usd": round(cost, 3), "apify_runs": runs,
               "read_until": until.isoformat() if until and runs else None, "pictures": pics,
               "aside": part.get("aside", []), "missed": part.get("missed")}
    (out / "prepare.json").write_text(json.dumps(summary, indent=1))
    since = f"since {mark.astimezone(LOCAL):%a %b %-d %-I:%M %p}" if mark else "of the last days"
    print(f"[social] {run}: {runs} Apify runs {since}, {checked} pages, {len(posts)} new posts in "
          f"{summary['batches']} batches ({out / 'batches'}), Apify ${cost:.2f}")
    print(pictures_line(pics))
    for a in summary["aside"]:
        print(f"[social] {a}")
    for f in failed:
        print(f"[social] FAILED {f}")


def finish(out):
    """After the write: mark this check's runs read, so the next check starts after them."""
    prep = json.loads((out / "prepare.json").read_text())
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


def spend_line(used, cap):
    line = f"Apify: ${used:.2f} of ${cap:.0f} this month"
    if used >= cap - 0.01:
        return line + ". The cap is reached: Apify has stopped every check until the cycle resets."
    if used >= HEADS_UP:
        return line + f". Heads-up: past ${HEADS_UP:.0f}."
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
    check(actor_input("facebook", ["u"], "4 hours")["onlyPostsNewerThan"] == "4 hours", "a task reads a window back from now")
    check([w for _, _, r, w in SCHEDULES if r == "busy"] == ["22 hours", "4 hours"], "6pm reads back past last night's 9pm, 9pm past 6pm")
    check(task_name("weekly", "events") == "bp-weekly-events", "a task's name")
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
    ig = [{"inputUrl": "https://www.instagram.com/krewe", "id": "9", "caption": "Live music Saturday", "timestamp": "2026-10-22T20:00:00Z"}]
    got, _ = post_pages("instagram", ig, {"https://www.instagram.com/krewe": {"name": "Krewe", "entry_id": "krewe", "url": "u"}})
    check(len(got) == 1 and "on Instagram on Thursday, October 22 at 3:00 PM" in got[0]["text"], "an Instagram post reads the same way")
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
    check("Heads-up" in spend_line(15.2, 19) and "cap is reached" in spend_line(19, 19), "the heads-up and the cap")
    blocked = ("import sys; sys.modules['PIL'] = None; import social; social.limits = lambda: "
               "{'current': {'monthlyUsageUsd': 8.4}, 'limits': {'maxMonthlyUsageUsd': 25}}; print(social.spend())")
    r = subprocess.run([sys.executable, "-c", blocked], cwd=Path(__file__).resolve().parent, capture_output=True, text=True)
    check(r.stdout == "Apify: $8.40 of $25 this month\n", f"spend runs with Pillow blocked: {r.stdout}{r.stderr[-300:]}")
    for cond, what in in_parts():
        check(cond, what)
    for cond, what in set_aside_reads():
        check(cond, what)
    print(f"social.py selftest: {ok} passed, 0 failed")


def set_aside_reads():
    """Six checks against a fake Apify, offline, each prepare and done as the routine runs them: Sal's,
    on the busy list, comes back not available three busy reads in a row, then Thursday's weekly read
    finds a post. Krewe and Bo (busy) post nothing new on the busy reads; Hall (weekly) posts. Apify's
    schedules are played by hand:
    each run reads its task's pages as they were when it started (smooth-mornings 04)."""
    import contextlib, write_judged
    g = globals()
    sals, krewe, bo, hall = (f"https://www.facebook.com/{n}" for n in ("salsbar", "krewe", "bodiddleys", "hallcomponents"))
    pages = [{"entry_id": "sals", "name": "Sal's Bar and Grill", "kind": "facebook", "url": sals, "busy": True},
             {"entry_id": "krewe", "name": "Krewe", "kind": "facebook", "url": krewe, "busy": True},
             {"entry_id": "bo", "name": "Bo", "kind": "facebook", "url": bo, "busy": True},
             {"entry_id": "hall", "name": "Hall", "kind": "facebook", "url": hall, "busy": False}]
    tasks, runs, store, data = {}, {}, {"read-busy": {"finished_at": "2026-10-26T00:00:00+00:00"},
                                        "read-weekly": {"finished_at": "2026-10-26T00:00:00+00:00"}}, {}

    def apify(method, path, body=None):
        bits = path.split("?")[0].split("/")
        if path.startswith("/actor-tasks?"):
            return {"data": {"items": [{"name": n, "id": n} for n in tasks]}}
        if path.endswith("/runs?desc=true&limit=30"):
            return {"data": {"items": runs.get(bits[2], [])[::-1]}}
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

    def check(run, when):
        now = datetime.fromisoformat(when)
        said = io.StringIO()
        with contextlib.redirect_stdout(said):
            prepare(run, now.astimezone(LOCAL).date(), folder, now, None)
            finish(folder)
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
            sync_tasks(root, {}, date(2026, 10, 26))
            for i, (day, hour) in enumerate([(26, 23), (27, 2), (27, 23), (28, 2)]):  # 6 and 9 PM Chicago, Mon and Tue
                ran("bp-busy-facebook", f"2026-10-{day}T{hour:02d}:05:00+00:00", quiet=[krewe, bo])
                said.append(check("busy", f"2026-10-{day}T{hour:02d}:30:00+00:00"))
                inputs[i] = {t: [u["url"] for u in x.get("startUrls", [])] for t, x in tasks.items()}
            ran("bp-weekly-facebook", "2026-10-29T20:05:00+00:00", [hall, sals])  # Thursday 3 PM
            said.append(check("weekly", "2026-10-29T20:45:00+00:00"))
            ran("bp-busy-facebook", "2026-10-29T23:05:00+00:00", [krewe], [bo])
            said.append(check("busy", "2026-10-29T23:30:00+00:00"))
            inputs["after"] = {t: [u["url"] for u in x.get("startUrls", [])] for t, x in tasks.items()}
            on_lists = sorted(t for t, given in inputs["after"].items() if sals in given)
            wk = lambda *when: page_lists(root, {canon(hall): {"aside": "2026-10-22"}},
                                          datetime(2026, 11, *when, tzinfo=LOCAL)).get(("weekly", "facebook"), [])
            monthly = [len(wk(4, 21, 30)), len(wk(5, 0, 5)), len(wk(5, 15, 45))]
    finally:
        g.update(saved[0])
        write_judged.interest_ids = saved[1]
    named = [i for i, lines in enumerate(said) if any("salsbar" in ln or "Sal's" in ln for ln in lines)]
    sal_lines = [[ln for ln in lines if "salsbar" in ln or "Sal's" in ln] for lines in said]
    counts = [next(ln.split(", ")[1] for ln in lines if ln.startswith("[social] busy:")) for lines in said[:4]]
    twenty_four = [f"https://www.facebook.com/p{i}" for i in range(24)]
    blocked = tally([(f"2026-10-2{i}", twenty_four, [], f"facebook run {i}") for i in range(3)], {}, date(2026, 10, 28))
    return [
        (sals not in inputs[3]["bp-busy-facebook"] and sals in inputs[3]["bp-weekly-facebook"]
         and sals in inputs[2]["bp-busy-facebook"] and on_lists == ["bp-busy-facebook"]
         and all(krewe in inputs[i]["bp-busy-facebook"] for i in inputs) and counts == ["3 pages"] * 3 + ["2 pages"],
         "a social page not available three reads in a row leaves its paid list at the next sync, for the "
         "Thursday read, and goes back on its list when that read finds it; one with no new posts stays; "
         "the pages count leaves set-aside pages out"),
        (named == [2, 4] and sal_lines[2] == [f"[social] Set aside: Sal's Bar and Grill's Facebook {sals}: not available 3 "
                                         "reads in a row; off its paid list, tried with the Thursday read"]
         and sal_lines[4] == [f"[social] Back: Sal's Bar and Grill's Facebook {sals}: read again, back on its list"],
         "a social page is named the check it is set aside and the check it is back, and no other"),
        (monthly == [1, 1, 0], "a weekly page set aside is tried with the Thursday read in a month's first week, "
                               "by the clock: a 9:30 PM check that starts past midnight still puts it on"),
        (tally([("t", [sals, krewe, bo], [{"inputUrl": krewe, "error": "no_items"}, {"inputUrl": bo, "error": "no_items"}],
                 "x")] * 3, {}, date(2026, 10, 28))[0] == {sals: {"misses": 3, "why": "nothing back", "aside": "2026-10-28"}},
         "a page Apify gives no row for three reads in a row is set aside too"),
        (blocked[0] == {} and blocked[3] == [f"facebook run {i}: 24 of 24 pages not read, not counted" for i in range(3)],
         "a run that reads few of its pages (Facebook blocking Apify, a cap) counts against none, in one line"),
    ]


def in_parts():
    """prepare in 2-minute parts against a fake Apify whose run is still going for 200 seconds and
    pictures that take 30 seconds each, offline on a fake clock; then one long check, and one whose
    run never ends."""
    import contextlib, run as runner, write_judged
    g, clock, got = globals(), type("Clock", (), {})(), []
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
        while len(said) < 6 and (not said or "run again" in said[-1]):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                prepare("busy", date(2026, 10, 28), folder, datetime(2026, 10, 28, 23, 30, tzinfo=timezone.utc), minutes)
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
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["setup", "prepare", "done", "spend"])
    ap.add_argument("run", nargs="?", choices=["busy", "weekly"])
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.step == "spend":
        return print(spend())
    if args.step == "setup":
        return setup()
    if args.step == "done":
        return finish(find_root() / ".runs" / "morning")
    if args.step != "prepare" or not args.run:
        ap.error("setup, prepare busy|weekly, done, or spend")
    now = datetime.now(timezone.utc)
    today = date.fromisoformat(args.today) if args.today else now.astimezone(LOCAL).date()
    prepare(args.run, today, find_root() / ".runs" / "morning", now)


if __name__ == "__main__":
    main()
