#!/usr/bin/env python3
"""
social.py: the social watch's script half (registry ADR-020, amended 2026-10-22). Places'
public Facebook and Instagram posts, read through Apify and never logged in, laid out exactly
as morning.py lays out changed pages, so the routine's next steps are the morning job's own:
the cheap model flags (flag.md), the routine's model judges (judge.md), and `morning.py titles`
and `morning.py write` write Events and News. The routine's steps are sources/models/social.md.

Apify reads the pages on its own clock (Jesse, 2026-10-23: "apify has direct sourcing"), so a
check never waits on the Claude plan: saved tasks `bp-<run>-<kind>` hold each list's pages, and
schedules start them, the busy list at 6pm and 9pm Chicago and every other page (plus the busy
list's Facebook Events tabs) on Thursdays at 3pm. The routines come half an hour or more later
and read whatever Apify saved since the last check they finished, so one the plan's usage limit
skipped (the 9pm one on 2026-10-22) is read by the next.

  setup           makes or updates the tasks and schedules from sources/social/<town>.json; run it
                  after the list changes (prepare also refreshes the tasks' pages)
  prepare busy    the busy list's Apify runs that finished since the last busy check
  prepare weekly  the weekly runs that finished since the last weekly check
  done            after `morning.py write`: marks those runs read, so the next check starts after
                  them. A check that stopped early never marks, and the next reads its runs too.
                  It repeats the pictures line, so the answer carries what pictures cost.
  spend           one line for the morning report, "Apify: $X of $19 this month", with a
                  heads-up past $15 and at the cap (Jesse, 2026-10-22: no slowdown, just say)

A post whose caption is short or gives no time of day also gets its pictures read (Jesse,
2026-10-26): Obbink's trivia night on Oct 29 was on its picture alone, under a one-line caption
("come out to the cocktail lounge…"), and the judge dropped it as a teaser. prepare downloads
up to PICTURES of the post's pictures from the address Apify saved, shrunk, into
.runs/morning/pictures/, and the post's page names them for the cheap model to open. Apify
already returns the addresses, so this costs nothing on Apify; it costs the Claude plan the
tokens of looking at them, which prepare prints as one `[social] pictures` line.

The mark lives in Apify's own storage (the named key-value store `bp-social-watch`, records
`read-busy` and `read-weekly`), so it survives each routine's throwaway copy.

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

import argparse, io, json, math, os, re, shutil, sys, tempfile, time, urllib.error, urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
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


def by_name(path):
    return {x["name"]: x for x in api("GET", f"{path}?limit=1000")["data"]["items"]}


def page_lists(root):
    """{(run, kind): pages} for every task: each list's own pages, and the busy list's Facebook
    pages again for the weekly Events tabs."""
    category = {e["id"]: e.get("category") for e in load(root)[0]}
    out = {}
    for run in ("busy", "weekly"):
        for p in pages_for(run, root):
            p["category"] = category.get(p["entry_id"])
            out.setdefault((run, p["kind"]), []).append(p)
    out[("weekly", "events")] = [p for p in out.get(("busy", "facebook"), [])]
    return {k: v for k, v in out.items() if k in ACTORS}


def sync_tasks(root):
    """Each task's pages as the list now has them; makes a task that is missing."""
    tasks, ids = by_name("/actor-tasks"), {}
    for (run, kind), pages in page_lists(root).items():
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
    ids = sync_tasks(root)
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


def runs_since(run, mark, now, wait_s=480):
    """{kind: [finished runs]} of a run's tasks since the mark, waiting up to wait_s for one that
    started within the last 90 minutes and is still going. Runs older than LOOKBACK are never read."""
    tasks = {n: x for n, x in by_name("/actor-tasks").items() if n.startswith(f"bp-{run}-")}
    floor = max(mark, now - LOOKBACK[run]) if mark else now - LOOKBACK[run]
    deadline = time.time() + wait_s
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
        if not waiting or time.time() > deadline:
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
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read(15_000_000)
    im = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    im.thumbnail((LONG_SIDE, LONG_SIDE))
    im.save(dest, "JPEG", quality=88)
    return im.size


def add_pictures(pages, folder, fetch=fetch_picture):
    """Every page with pictures gets them downloaded and named at its end, for the cheap model
    to open. A picture that won't download is a line in the summary, and its page keeps Meta's
    description. Returns the counts for the cost line."""
    folder.mkdir(parents=True, exist_ok=True)
    read, posts, tokens, failed = 0, 0, 0, []
    for p in pages:
        pics = p.pop("pictures", [])
        if not pics:
            continue
        lines = []
        for i, pic in enumerate(pics, 1):
            dest = folder / f"{p['file']}-{i}.jpg"
            try:
                w, h = fetch(pic["url"], dest)
                read, tokens = read + 1, tokens + picture_tokens(w, h)
                lines.append(f"Picture {i}: {dest}")
            except Exception as e:
                failed.append(f"{p['name']} {p['file']} picture {i}: {e}")
            if pic["about"]:
                lines.append(f"Meta's own description of picture {i}: {pic['about']}")
        if any(ln.startswith("Picture ") for ln in lines):
            posts += 1
            lines.insert(0, "The post's caption doesn't say much, so its pictures come with it. Open each "
                            "picture below with the Read tool and read every word on it: those words are "
                            "part of this post.")
        if lines:
            p["text"] += "\n\n" + "\n".join(lines)
    return {"read": read, "posts": posts, "tokens": tokens, "failed": failed}


def pictures_line(pics):
    """One line for the answer: what reading pictures added to this check's cost."""
    if not pics or not pics.get("read"):
        return "[social] pictures: none read" + (f" ({len(pics['failed'])} would not download)" if pics and pics.get("failed") else "")
    m = pics["tokens"] / 1e6
    return (f"[social] pictures: {pics['read']} read on {pics['posts']} posts with a short caption or no time "
            f"({pics['tokens']:,} picture tokens): about ${m * CHEAP_PER_M:.3f} for the cheap model, and up to "
            f"${m * JUDGE_PER_M:.3f} more if the judge opens every one, on the Claude plan; nothing on Apify"
            + (f"; {len(pics['failed'])} would not download" if pics["failed"] else ""))


def post_pages(kind, rows, by_url):
    """Apify's rows as pages: one post each, with who posted it, where and when. An empty row
    (a page with nothing new, hidden, gone) is no page; a hidden one is reported. A post whose
    caption needs its pictures carries their addresses under `pictures`, for add_pictures; one
    with no caption but a picture is a page too, since its words may all be on the picture."""
    pages, hidden = [], []
    for r in rows:
        src = (r.get("inputUrl") or r.get("facebookUrl") or "").rstrip("/").lower()
        if not src and r.get("ownerUsername"):
            src = f"https://www.instagram.com/{r['ownerUsername'].lower()}"
        if r.get("error") in EMPTY or r.get("error"):
            if r.get("error") != "no_items":
                hidden.append(f"{src}: {r.get('error')}")
            continue
        page = by_url.get(src) or next((p for u, p in by_url.items() if u and u in src), None)
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


def prepare(run, today, out, now):
    root = find_root()
    if out.exists():
        shutil.rmtree(out)
    (out / "batches").mkdir(parents=True)
    lists = page_lists(root)
    failed = []
    try:
        sync_tasks(root)  # the next run reads the list as it is now
    except Exception as e:
        failed.append(f"task pages not refreshed: {e}")
    try:
        mark = last_read(run)
    except Exception as e:  # the store unreadable: the last LOOKBACK of runs, and say so
        mark, _ = None, failed.append(f"last read unreadable ({e}); reading every run of the last {LOOKBACK[run].days} days")
    found, waiting = runs_since(run, mark, now)
    failed += [f"{n} still running after 8 minutes; its posts wait for the next check" for n in waiting]

    posts, cost, until, states = [], 0.0, mark, []
    for kind, runs in found.items():
        by_url = {p["url"].rstrip("/").lower(): p for p in lists.get((run, kind), [])}
        if kind == "events":
            by_url = {events_tab(u): p for u, p in by_url.items()} | by_url
        for r in runs:
            cost += float(r.get("usageTotalUsd") or 0)
            finished = datetime.fromisoformat(r["finishedAt"].replace("Z", "+00:00"))
            until = max(until, finished) if until else finished
            states.append(r["status"])
            got, hidden = post_pages(kind, items(r["defaultDatasetId"]), by_url)
            posts += got
            failed += [f"{kind}: {h}" for h in hidden]
            if r["status"] != "SUCCEEDED":
                failed.append(f"{kind} run {r['id']} at {finished.astimezone(LOCAL):%a %-I:%M %p}: {r['status']}")
    seen, unique = set(), []
    for p in posts:  # overlapping windows read a post twice; one page each
        if p["file"] not in seen:
            seen.add(p["file"]), unique.append(p)
    posts = unique
    pics = add_pictures(posts, out / "pictures")
    failed += [f"picture not downloaded: {f}" for f in pics["failed"]]
    for i, text in enumerate(layout(posts, today), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(text)
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in posts], indent=1))
    (out / "feeds.jsonl").write_text("")
    try:
        import write_judged
        interests = write_judged.interest_ids()
    except Exception as e:  # no database keys (a dry run on a Mac): the judge then uses null
        interests, _ = [], failed.append(f"interest ids unread: {e}")
    runs = sum(len(v) for v in found.values())
    checked = sum(len(v) for (r, _), v in lists.items() if r == run)
    summary = {"today": str(today), "run": run, "since": mark.isoformat() if mark else None,
               "fetched": checked, "changed": len(posts), "first_seen": 0, "to_read": len(posts),
               "batches": len(list((out / "batches").iterdir())), "failed": failed, "readers": [],
               "interests": interests, "apify_usd": round(cost, 3), "apify_runs": runs,
               "read_until": until.isoformat() if until and runs else None, "pictures": pics}
    (out / "prepare.json").write_text(json.dumps(summary, indent=1))
    since = f"since {mark.astimezone(LOCAL):%a %b %-d %-I:%M %p}" if mark else "of the last days"
    print(f"[social] {run}: {runs} Apify runs {since}, {checked} pages, {len(posts)} new posts in "
          f"{summary['batches']} batches ({out / 'batches'}), Apify ${cost:.2f}")
    print(pictures_line(pics))
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
        return print(f"Apify: spend unknown, Apify refused the request (HTTP {e.code}): check the routine's network secret")
    end = d.get("monthlyUsageCycle", {}).get("endAt", "")[:10]
    print(spend_line(float(d["current"]["monthlyUsageUsd"]), float(d["limits"]["maxMonthlyUsageUsd"]))
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
    print(f"social.py selftest: {ok} passed, 0 failed")


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
        return spend()
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
