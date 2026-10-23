#!/usr/bin/env python3
"""
social.py: the social watch's script half (registry ADR-020, amended 2026-10-22). Places'
public Facebook and Instagram posts, read through Apify and never logged in, laid out exactly
as morning.py lays out changed pages, so the routine's next steps are the morning job's own:
the cheap model flags (flag.md), the routine's model judges (judge.md), and `morning.py titles`
and `morning.py write` write Events and News. The routine's steps are sources/models/social.md.

  prepare busy    the busy list's pages (sources/social/<town>.json, "busy": true), at 6pm and
                  9pm Chicago: posts since the last busy check that finished
  prepare weekly  every other page, Thursdays at 3pm: posts since the last weekly check that
                  finished (7 days the first time), plus the busy list's Facebook Events tabs
  done            after `morning.py write`: marks this check finished, so the next one reads
                  from when it started. A check that stopped early (the plan's usage limit hit
                  the 9pm one on 2026-10-22) never marks, and the next reads its posts too.
  spend           one line for the morning report, "Apify: $X of $19 this month", with a
                  heads-up past $15 and at the cap (Jesse, 2026-10-22: no slowdown, just say)

The mark lives in Apify's own storage (the named key-value store `bp-social-watch`, records
`last-busy` and `last-weekly`), so it survives each routine's throwaway copy.

Everything lands in .runs/morning/, the morning job's folder (each routine runs in its own copy
of the repository). In the cloud, Apify's REST API is called with no key: the environment's
network secret for api.apify.com adds it on the way out, so the token never enters the session.
APIFY_TOKEN in the environment is used when set; on a Mac with neither, the calls go through
Composio. Each actor run is started once and has its own spending
cap: a retried start is a second paid run (2026-10-05).

  python3 sources/scripts/social.py prepare busy|weekly [--since ISO] [--today YYYY-MM-DD]
  python3 sources/scripts/social.py done
  python3 sources/scripts/social.py spend
  python3 sources/scripts/social.py --selftest
"""

import argparse, json, os, shutil, subprocess, sys, time, urllib.error, urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from read_events import LOCAL
from check_flags import batches, message

TOWN = "st-joseph-mn"
API = "https://api.apify.com/v2"
SLOTS = ((18, 0), (21, 0))  # the busy list's checks, Chicago time
POSTS = 20  # most posts read per page per check; a busy page posts a few a day at most
ACTORS = {  # (actor, spending cap in USD per run) for each kind of read
    ("busy", "facebook"): ("apify~facebook-posts-scraper", 0.40),
    ("busy", "instagram"): ("apify~instagram-post-scraper", 0.20),
    ("weekly", "facebook"): ("apify~facebook-posts-scraper", 2.50),
    ("weekly", "instagram"): ("apify~instagram-post-scraper", 0.75),
    ("weekly", "events"): ("apify~facebook-events-scraper", 1.00),
}
EMPTY = {"no_items", "not_available", "not_found", "Restricted profile"}
HEADS_UP = 15.0
STORE = "bp-social-watch"
OVERLAP = timedelta(minutes=10)  # a post that lands while the last check ran is read again, never lost
LOOKBACK = {"busy": timedelta(days=8), "weekly": timedelta(days=15)}  # a mark older than this is a broken one


def since_for(run, now, last=None):
    """Where a check starts reading. With the last finished check's start (`last`): from there,
    less a few minutes, but never further back than LOOKBACK. Without one (the first check, or the
    store unreadable), the schedule's: the busy list from the last 6pm or 9pm check at least two
    and a half hours back, the weekly run from 7 days and an hour back."""
    if last:
        return max(last - OVERLAP, now - LOOKBACK[run]).astimezone(LOCAL)
    if run == "weekly":
        return now - timedelta(days=7, hours=1)
    local = now.astimezone(LOCAL)
    slots = [datetime(d.year, d.month, d.day, h, m, tzinfo=LOCAL)
             for d in (local.date() - timedelta(days=1), local.date()) for h, m in SLOTS]
    return max(s for s in slots if s <= local - timedelta(hours=2, minutes=30))


def pages_for(run, root):
    """The pages a run reads: busy or not, and never one Facebook hides from logged-out readers."""
    pages = json.loads((root / "sources" / "social" / f"{TOWN}.json").read_text())
    return [p for p in pages if p["busy"] == (run == "busy") and not p.get("hidden")]


def events_tab(url):
    return url.rstrip("/") + "/upcoming_hosted_events"


def actor_input(kind, urls, since):
    stamp = since.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    if kind == "facebook":
        return {"startUrls": [{"url": u} for u in urls], "resultsLimit": POSTS, "onlyPostsNewerThan": stamp}
    if kind == "instagram":
        return {"username": urls, "resultsLimit": POSTS, "onlyPostsNewerThan": stamp}
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
    r = subprocess.run(["composio", "execute", slug, "-d", json.dumps(args)], stdin=subprocess.DEVNULL,
                       capture_output=True, text=True, timeout=120)
    d = json.loads(r.stdout)
    if d.get("storedInFile"):
        d = json.loads(Path(d["outputFilePath"]).read_text())
    if not d.get("successful", True):
        raise RuntimeError(f"{slug}: {str(d.get('error'))[:200]}")
    d = d.get("data", d)
    return d.get("data", d) if isinstance(d, dict) else d


def start(actor, body, cap):
    if direct():
        return _http("POST", f"/acts/{actor}/runs?maxTotalChargeUsd={cap}&timeout=600", body)["data"]
    return _composio("APIFY_RUN_ACTOR", {"actorId": actor, "body": body, "waitForFinish": 0,
                                        "maxTotalChargeUsd": cap, "timeout": 600})


def status(run_id):
    if direct():
        return _http("GET", f"/actor-runs/{run_id}")["data"]
    return _composio("APIFY_ACTOR_RUN_GET", {"runId": run_id})


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


def _store(method, path, body=None):
    """The mark's store: the REST API in the cloud, Composio's proxy on a Mac. None for a missing record."""
    if direct():
        try:
            return _http(method, path, body)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise
    cmd = ["composio", "proxy", API + path, "--toolkit", "apify", "-X", method]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
    d = json.loads(r.stdout) if r.stdout.strip() else {}
    if isinstance(d, dict) and d.get("error"):
        if "not-found" in str(d["error"].get("type", "")):
            return None
        raise RuntimeError(f"Apify store: {d['error']}")
    return d


def _store_id():
    return _store("POST", f"/key-value-stores?name={STORE}")["data"]["id"]  # makes it the first time, finds it after


def last_check(run):
    rec = _store("GET", f"/key-value-stores/{_store_id()}/records/last-{run}")
    return datetime.fromisoformat(rec["started_at"]) if rec and rec.get("started_at") else None


def mark_check(run, started_at):
    _store("PUT", f"/key-value-stores/{_store_id()}/records/last-{run}", {"started_at": started_at})


def run_all(jobs, wait_s=480):
    """Start every job once, then wait for all of them: {name: (status, cost, items)}."""
    started, done = {}, {}
    for name, (actor, body, cap) in jobs.items():
        try:
            started[name] = start(actor, body, cap)["id"]
        except Exception as e:  # never retried: a second start is a second paid run
            done[name] = (f"start failed: {e}", 0.0, [])
    deadline = time.time() + wait_s
    while started and time.time() < deadline:
        for name, run_id in list(started.items()):
            s = status(run_id)
            if s["status"] in ("SUCCEEDED", "FAILED", "ABORTED", "TIMED-OUT"):
                done[name] = (s["status"], float(s.get("usageTotalUsd") or 0), items(s["defaultDatasetId"]))
                del started[name]
        if started:
            time.sleep(15)
    for name, run_id in started.items():
        done[name] = (f"still running after {wait_s} s (run {run_id}); its posts wait for the next check", 0.0, [])
    return done


# ---- posts become pages, the way the cheap model reads them ----

def when_text(stamp):
    try:
        t = datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).astimezone(LOCAL)
    except ValueError:
        return str(stamp)
    return f"{t:%A, %B} {t.day} at {t:%-I:%M %p}"


def post_pages(kind, rows, by_url):
    """Apify's rows as pages: one post each, with who posted it, where and when. An empty row
    (a page with nothing new, hidden, gone) is no page; a hidden one is reported."""
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
            pid, url = r.get("id") or r.get("eventId") or r.get("url"), r.get("url")
        else:
            text = r.get("text") if kind == "facebook" else r.get("caption")
            if not (text or "").strip():
                continue
            stamp = r.get("time") or r.get("timestamp")
            body = (f"{page['name'] if page else 'A St. Joseph place'} posted this on {kind.title()} "
                    f"on {when_text(stamp)}:\n\n{text}")
            pid, url = r.get("postId") or r.get("id") or r.get("shortCode"), r.get("url")
        if not page or not pid:
            continue
        pages.append({"file": f"{kind}-{pid}", "url": url or page["url"], "entry_id": page["entry_id"],
                      "name": page["name"], "category": page.get("category"), "trust": "official", "text": body})
    return pages, hidden


def prepare(run, today, since, out, started):
    root = find_root()
    if out.exists():
        shutil.rmtree(out)
    (out / "batches").mkdir(parents=True)
    category = {e["id"]: e.get("category") for e in load(root)[0]}
    pages = pages_for(run, root)
    for p in pages:
        p["category"] = category.get(p["entry_id"])
    by_kind = {k: [p for p in pages if p["kind"] == k] for k in ("facebook", "instagram")}
    jobs = {k: (*ACTORS[(run, k)][:1], actor_input(k, [p["url"] for p in ps], since), ACTORS[(run, k)][1])
            for k, ps in by_kind.items() if ps}
    if run == "weekly":
        busy_fb = [p for p in pages_for("busy", root) if p["kind"] == "facebook"]
        for p in busy_fb:
            p["category"] = category.get(p["entry_id"])
        if busy_fb:
            jobs["events"] = (ACTORS[("weekly", "events")][0], actor_input("events", [p["url"] for p in busy_fb], since),
                              ACTORS[("weekly", "events")][1])
        by_kind["events"] = busy_fb
    done = run_all(jobs)

    posts, failed, cost = [], [], 0.0
    for kind, (state, spent, rows) in done.items():
        cost += spent
        by_url = {p["url"].rstrip("/").lower(): p for p in by_kind[kind]}
        if kind == "events":
            by_url = {events_tab(u): p for u, p in by_url.items()} | by_url
        got, hidden = post_pages(kind, rows, by_url)
        posts += got
        failed += [f"{kind}: {h}" for h in hidden]
        if state != "SUCCEEDED":
            failed.append(f"{kind} check: {state}")
    for i, b in enumerate(batches(posts), 1):
        (out / "batches" / f"batch-{i}.txt").write_text(message(b, today))
    (out / "pages.json").write_text(json.dumps([{k: v for k, v in p.items() if k != "text"} for p in posts], indent=1))
    (out / "feeds.jsonl").write_text("")
    try:
        import write_judged
        interests = write_judged.interest_ids()
    except Exception as e:  # no database keys (a dry run on a Mac): the judge then uses null
        interests, _ = [], failed.append(f"interest ids unread: {e}")
    summary = {"today": str(today), "run": run, "since": since.isoformat(), "fetched": len(pages) + (len(by_kind.get("events", [])) if run == "weekly" else 0),
               "changed": len(posts), "first_seen": 0, "to_read": len(posts),
               "batches": len(list((out / "batches").iterdir())), "failed": failed, "readers": [],
               "interests": interests, "apify_usd": round(cost, 3), "started_at": started.isoformat(),
               "complete": all(state == "SUCCEEDED" for state, _, _ in done.values()) and len(done) == len(jobs)}
    (out / "prepare.json").write_text(json.dumps(summary, indent=1))
    print(f"[social] {run}: {summary['fetched']} pages checked since {since.astimezone(LOCAL):%a %b %-d %-I:%M %p}, "
          f"{len(posts)} new posts in {summary['batches']} batches ({out / 'batches'}), Apify ${cost:.2f}")
    for f in failed:
        print(f"[social] FAILED {f}")


def finish(out):
    """After the write: mark this check finished, unless one of its Apify reads failed, in which
    case the next check reads its window again."""
    prep = json.loads((out / "prepare.json").read_text())
    if not prep.get("complete"):
        return print(f"[social] {prep['run']}: not marked finished (a read failed), so the next check reads from "
                     f"{datetime.fromisoformat(prep['since']).astimezone(LOCAL):%a %b %-d %-I:%M %p} again")
    try:
        mark_check(prep["run"], prep["started_at"])
    except Exception as e:  # the next check then reads the schedule's window, which may miss a skipped one
        return print(f"[social] FAILED marking {prep['run']} finished ({e}): check the Apify network secret")
    print(f"[social] {prep['run']}: marked finished; the next check reads from "
          f"{datetime.fromisoformat(prep['started_at']).astimezone(LOCAL) - OVERLAP:%a %b %-d %-I:%M %p}")


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
    check(since_for("busy", t(22, 18, 2)) == t(21, 21, 0), "a 6pm check reads from last night's 9pm")
    check(since_for("busy", t(22, 21, 1)) == t(22, 18, 0), "a 9pm check reads from 6pm")
    check(since_for("busy", t(22, 15, 30)) == t(21, 21, 0), "a hand-started afternoon run reads from last night")
    check(since_for("busy", t(22, 20, 25)) == t(21, 21, 0), "a 6pm run that starts late still reads from last night")
    check(since_for("weekly", t(22, 15, 0)) == t(15, 14, 0), "the weekly run reads 7 days and an hour")
    check(since_for("busy", t(23, 18, 0), last=t(22, 18, 17)) == t(22, 18, 7), "after a skipped 9pm check, 6pm reads from the last finished one")
    check(since_for("busy", t(22, 21, 0), last=t(22, 18, 1)) == t(22, 17, 51), "a normal 9pm check reads from 6pm, a little overlap")
    check(since_for("busy", t(23, 18, 0), last=t(1, 18, 0)) == t(15, 18, 0), "a mark weeks old reads 8 days back at most")
    check(since_for("weekly", t(29, 15, 0), last=t(22, 15, 2)) == t(22, 14, 52), "the weekly run reads from last week's")
    check(actor_input("facebook", ["u"], t(22, 18, 0))["onlyPostsNewerThan"] == "2026-10-22T23:00:00", "the window is sent in UTC")
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
    check(spend_line(8.4, 19) == "Apify: $8.40 of $19 this month", "the plain spend line")
    check("Heads-up" in spend_line(15.2, 19) and "cap is reached" in spend_line(19, 19), "the heads-up and the cap")
    print(f"social.py selftest: {ok} passed, 0 failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["prepare", "done", "spend"])
    ap.add_argument("run", nargs="?", choices=["busy", "weekly"])
    ap.add_argument("--since", help="ISO time to read from, instead of the schedule's")
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.step == "spend":
        return spend()
    if args.step == "done":
        return finish(find_root() / ".runs" / "morning")
    if args.step != "prepare" or not args.run:
        ap.error("prepare busy|weekly, done, or spend")
    now = datetime.now(timezone.utc)
    if args.since:
        since = datetime.fromisoformat(args.since).astimezone(LOCAL)
    else:
        try:
            last = last_check(args.run)
        except Exception as e:  # the store unreadable: the schedule's window, and say so
            last, _ = None, print(f"[social] last finished check unreadable ({e}); reading the schedule's window")
        since = since_for(args.run, now, last)
    today = date.fromisoformat(args.today) if args.today else now.astimezone(LOCAL).date()
    prepare(args.run, today, since, find_root() / ".runs" / "morning", now)


if __name__ == "__main__":
    main()
