#!/usr/bin/env python3
"""
find_calendars.py — look for event feeds on the websites the registry already knows.

The registry lists PLACES. Events are what a place's sources produce (ADR-013), and the
best producer by far is a machine-readable feed. The city proved it: its calendar page was
an unreadable JavaScript shell, and behind it sat three iCal feeds and an RSS one carrying
Rocktoberfest with date, time, address and description (ADR-012).

So this walks every entry that has a real URL and asks four questions of each site:

  1. Does it publish iCal?   .ics, /iCalendar.aspx, feed=calendar — the best answer.
  2. Does it publish RSS or Atom?  Second best; dated items, no JavaScript.
  3. Does it have an events PAGE?  /events, /calendar, /shows, /whats-on — needs a
     fetch source and probably a human to confirm it carries real dates.
  4. Does it link a Facebook page?  Recorded, not fetched. That is Apify's job.

It writes findings, never entries. Promoting a place from `listed` to `watched` crosses
the publishing line and stays a per-entry decision (ADR-011), so the output is a report
for a human, not a registry edit.

Politeness: reuses run.py's fetch, so robots.txt and Crawl-delay are obeyed
(ADR-014). One page per site — this does not crawl.
"""

import argparse, json, re, sys
from pathlib import Path
from urllib.parse import urljoin, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load, is_todo
from run import fetch

ICAL = re.compile(r'href=["\']([^"\']*(?:\.ics|ical|iCalendar|feed=calendar)[^"\']*)["\']', re.I)
FEED = re.compile(r'<link[^>]+type=["\']application/(?:rss|atom)\+xml["\'][^>]*>', re.I)
HREF = re.compile(r'href=["\']([^"\']+)["\']', re.I)
EVENTPAGE = re.compile(r'href=["\']([^"\']*/(?:events?|calendar|shows?|whats-?on|happenings)/?[^"\']*)["\']', re.I)
FACEBOOK = re.compile(r'href=["\'](https?://(?:www\.)?facebook\.com/[^"\'?#]+)["\']', re.I)


def looks_social(u):
    return any(h in u for h in ("facebook.com", "instagram.com", "twitter.com", "x.com",
                                "linkedin.com", "youtube.com", "tiktok.com"))


def verify_ical(u):
    """A link is not a calendar. Fetch it and count events, or it does not count.

    The first pass reported 9 iCal feeds. Every one held ZERO events: the pattern had
    matched `/ical` inside theme asset paths. A finding nobody opened is a guess.
    """
    try:
        _st, body = fetch(u)
    except Exception:
        return 0
    return body.count("BEGIN:VEVENT")


def verify_feed(u, host):
    """Same-host, and count dated items.

    The Middy was credited with a feed belonging to visitstcloud.com, because the page
    links there and `<link rel=alternate>` was taken on trust. A feed on someone else's
    domain is that site's news, not this place's.
    """
    if urlparse(u).netloc.replace("www.", "") != host.replace("www.", ""):
        return 0
    try:
        _st, body = fetch(u)
    except Exception:
        return 0
    return body.count("<item") + body.count("<entry")


def scan(url, verify=True):
    out = {"ical": [], "feed": [], "events": [], "facebook": []}
    status, html = fetch(url)
    for m in ICAL.findall(html):
        out["ical"].append(urljoin(url, m))
    for tag in FEED.findall(html):
        h = HREF.search(tag)
        if h:
            out["feed"].append(urljoin(url, h.group(1)))
    host = urlparse(url).netloc
    for m in EVENTPAGE.findall(html):
        full = urljoin(url, m)
        if urlparse(full).netloc == host and not looks_social(full):
            out["events"].append(full)
    for m in FACEBOOK.findall(html):
        if "/sharer" not in m and "/plugins" not in m:
            out["facebook"].append(m)
    for k in out:
        seen, uniq = set(), []
        for v in out[k]:
            if v not in seen:
                seen.add(v); uniq.append(v)
        out[k] = uniq[:4]

    if verify:
        out["ical"] = [u for u in out["ical"] if verify_ical(u) > 0]
        kept = []
        for u in out["feed"]:
            n = verify_feed(u, host)
            if n:
                kept.append(u)
        out["feed"] = kept
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".")
    ap.add_argument("--limit", type=int, default=0, help="stop after N sites (testing)")
    args = ap.parse_args()

    root = find_root(args.root)
    entries, _ = load(root)

    targets = []
    for e in entries:
        for s in e.get("sources") or []:
            u = s.get("url")
            if not u or is_todo(u) or s.get("method") not in ("fetch", None):
                continue
            if looks_social(u):
                continue
            targets.append((e["_name"], e.get("id"), u))
            break
    if args.limit:
        targets = targets[:args.limit]
    print(f"[calendars] {len(targets)} sites with a real URL\n", flush=True)

    found, nothing, failed = [], [], []
    for i, (name, eid, url) in enumerate(targets, 1):
        try:
            r = scan(url)
        except Exception as ex:
            failed.append((name, url, str(ex)[:70]))
            print(f"  [{i}/{len(targets)}] {name}: FAILED {str(ex)[:50]}", flush=True)
            continue
        hits = {k: v for k, v in r.items() if v}
        if hits:
            found.append({"name": name, "id": eid, "url": url, **hits})
            bits = ", ".join(f"{len(v)} {k}" for k, v in hits.items())
            print(f"  [{i}/{len(targets)}] {name}: {bits}", flush=True)
        else:
            nothing.append(name)
            print(f"  [{i}/{len(targets)}] {name}: —", flush=True)

    out = Path(root) / ".runs" / "calendars.json"
    out.write_text(json.dumps({"found": found, "nothing": nothing,
                               "failed": [{"name": n, "url": u, "why": w}
                                          for n, u, w in failed]}, indent=1))
    ical = sum(1 for f in found if f.get("ical"))
    feed = sum(1 for f in found if f.get("feed"))
    page = sum(1 for f in found if f.get("events"))
    fb = sum(1 for f in found if f.get("facebook"))
    print(f"\n[calendars] {len(found)} sites with something | ical {ical} | rss {feed} "
          f"| events page {page} | facebook {fb}")
    print(f"[calendars] {len(nothing)} with nothing, {len(failed)} unreachable")
    print(f"report: {out}")


if __name__ == "__main__":
    main()
