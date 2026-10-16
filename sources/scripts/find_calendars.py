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

By default it writes findings, never entries. Promoting a place from `listed` to `watched`
crosses the publishing line, so that takes Jesse's approval (ADR-022):

  --pick      up to three pages per listed place -> .runs/picks.json, for his approval page
  --promote   his ticks (the approval page's saved choices) applied to the registry file

Politeness: reuses run.py's fetch, so robots.txt and Crawl-delay are obeyed
(ADR-014). One page per site — this does not crawl.
"""

import argparse, html, json, re, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load, is_todo
from run import fetch, to_text, final_url

ICAL = re.compile(r'href=["\']([^"\']*(?:\.ics|ical|iCalendar|feed=calendar)[^"\']*)["\']', re.I)
FEED = re.compile(r'<link[^>]+type=["\']application/(?:rss|atom)\+xml["\'][^>]*>', re.I)
HREF = re.compile(r'href=["\']([^"\']+)["\']', re.I)
EVENTPAGE = re.compile(r'href=["\']([^"\']*/(?:events?|calendar|shows?|whats-?on|happenings)/?[^"\']*)["\']', re.I)
FACEBOOK = re.compile(r'href=["\'](https?://(?:www\.)?facebook\.com/[^"\'?#]+)["\']', re.I)
# The page picker (watch-every-place 06): a link counts by its path or by the words on it.
ANCHOR = re.compile(r'<a\b[^>]*?href=["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', re.I | re.S)
# Words count only as a whole menu label ("Events", "Upcoming events"), never inside one
# ("Show supplies", "Special orders", "Radio show").
EVENT_WORDS = re.compile(r"^\W*(upcoming |our |all |community )?(events?|calendar|events? calendar|shows?|what'?s on|happenings|live music)\W*$", re.I)
EVENT_PATH = re.compile(r"/(events?|calendar|shows?|whats-?on|happenings)(/|$|\.)", re.I)
NEWS_WORDS = re.compile(r"^\W*(our |latest |weekly |daily )?(specials?|deals|happy hour|news|blog|announcements?|bulletins?|updates|news (&|and) events)\W*$", re.I)
NEWS_PATH = re.compile(r"/(specials?|happy-hour|news|blog|announcements?|bulletins?|updates)(/|$|\.)", re.I)
NOT_A_PAGE = re.compile(r"\.(pdf|jpe?g|png|gif|docx?|zip|mp4)(\?|$)|^(mailto|tel|javascript):", re.I)
GCAL = re.compile(r'calendar\.google\.com/calendar/(?:u/\d+/)?embed\?[^"\']*?src=([^&"\']+)', re.I)
# An entry's yaml block (group 2) and the Notes line after its fence (group 4), as registry.py reads it.
ENTRY_BLOCK = re.compile(r"^(##\s+.+?\s*\n+```ya?ml\n)(.*?)(\n```)(\nNotes:[^\n]*)?", re.M | re.S)
CANONICAL = re.compile(r'<link[^>]+rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']', re.I)


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


def bare(host):
    return host.lower().removeprefix("www.")


def links(url, page):
    """The page's own links, first one first: (url, words on it). Same site only, pages only."""
    hosts = {bare(urlparse(url).netloc)}
    canon = CANONICAL.search(page)
    if canon:
        hosts.add(bare(urlparse(urljoin(url, canon.group(1))).netloc))
    seen, out = set(), []
    for href, inner in ANCHOR.findall(page):
        href = html.unescape(href.strip())
        if NOT_A_PAGE.search(href):
            continue
        try:
            full = urljoin(url, href).split("#")[0]
            host = bare(urlparse(full).netloc)
        except ValueError:  # a hand-typed link like http://[phonenumber]
            continue
        if host not in hosts or full.rstrip("/") == url.rstrip("/") or full in seen:
            continue
        seen.add(full)
        out.append((full, re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", inner))).strip()))
    return out


def first_match(found, words, path):
    """The first link whose whole label says it, else the shortest whose path does (the list,
    not one event on it)."""
    said = [u for u, t in found if t and words.search(t)]
    pathed = sorted((u for u, _ in found if path.search(urlparse(u).path)), key=lambda u: len(urlparse(u).path))
    return (said or pathed or [None])[0]


def readable(u):
    """A picked page has to load and carry text: one built by JavaScript reads as nothing."""
    try:
        _st, page = fetch(u)
    except Exception:
        return False
    return len(to_text(page)) >= 200


def pick_from(url, page, ical_events=verify_ical, feed_items=verify_feed, loads=readable):
    """Up to three pages for a place (Jesse, 2026-10-14): its feed first, then its events page,
    then a specials or news page, else the homepage. An iCal feed stands in for the events page
    it feeds, so a place with one doesn't get that page read by a model too."""
    picks = []
    host = urlparse(url).netloc
    icals = [urljoin(url, m) for m in ICAL.findall(page)]
    icals += [f"https://calendar.google.com/calendar/ical/{unquote(m)}/public/basic.ics"
              for m in GCAL.findall(page)]
    ical = next((u for u in dict.fromkeys(icals) if ical_events(u) > 0), None)
    if ical:
        picks.append({"url": ical, "why": "calendar feed", "kind": "ical"})
    feeds = [urljoin(url, HREF.search(t).group(1)) for t in FEED.findall(page) if HREF.search(t)]
    feed = next((u for u in dict.fromkeys(feeds) if "comments" not in u and feed_items(u, host) > 0), None)
    if feed:
        picks.append({"url": feed, "why": "news feed", "kind": "rss"})
    found = links(url, page)
    events = None if ical else first_match(found, EVENT_WORDS, EVENT_PATH)
    if events and loads(events):
        picks.append({"url": events, "why": "events page", "kind": "website"})
    news = first_match([(u, t) for u, t in found if u != events], NEWS_WORDS, NEWS_PATH)
    if news and not feed and loads(news):
        picks.append({"url": news, "why": "specials or news page", "kind": "website"})
    if not picks:
        picks.append({"url": url, "why": "homepage", "kind": "website"})
    return picks[:3]


def pick(entry, url):
    """One place: its picked pages, or why its site can't be read."""
    row = {"id": entry["id"], "name": entry["_name"], "category": entry.get("category"),
           "status": entry["status"], "url": url}
    try:
        _st, page = fetch(url)
    except Exception as ex:
        refused = "disallows" in str(ex)  # a robots.txt that won't load is a site that won't
        return {**row, "state": "refused" if refused else "broken", "why": str(ex)[:120]}
    if "cloudflare" in urlparse(final_url.get(url, url)).netloc:  # sent to a bot check's help page
        return {**row, "state": "refused", "why": "the site sends bots to a Cloudflare check"}
    if len(to_text(page)) < 200:
        return {**row, "state": "empty", "why": "the page is built by JavaScript, so a plain fetch reads almost nothing"}
    try:
        pages = pick_from(final_url.get(url, url), page)
        return {**row, "state": "ok", "pages": [{**p, "url": final_url.get(p["url"], p["url"])} for p in pages]}
    except Exception as ex:  # one odd site is named, never stops the run
        return {**row, "state": "broken", "why": f"picking failed: {str(ex)[:100]}"}


def page_key(u):
    p = urlparse(u)
    return bare(p.netloc) + p.path.rstrip("/") + (f"?{p.query}" if p.query else "")


def mark_same(rows, watched):
    """A place whose pages sit on a watched place's website, or are all pages another place
    already has, would be read twice: it gets `same_as` and starts unticked."""
    seen = {}
    for r in sorted((r for r in rows if r["state"] == "ok"), key=lambda r: r["name"]):
        keys = [page_key(p["url"]) for p in r["pages"]]
        host = next((watched[bare(urlparse(p["url"]).netloc)] for p in r["pages"]
                     if bare(urlparse(p["url"]).netloc) in watched), None)
        if host:
            r["same_as"] = host
        elif all(k in seen for k in keys):
            r["same_as"] = seen[keys[0]]
        else:
            for k in keys:
                seen.setdefault(k, r["name"])


def pick_all(root, workers=8):
    """Every listed place with a website (watched ones already have their pages)."""
    entries, _ = load(root)
    watched = {bare(urlparse(s["url"]).netloc): e["_name"] for e in entries if e.get("tier") == "watched"
               for s in e.get("sources") or [] if s.get("url") and not is_todo(s["url"]) and not looks_social(s["url"])}
    targets = []
    for e in entries:
        if e.get("tier", "listed") != "listed":
            continue
        web = [s["url"] for s in e.get("sources") or [] if s.get("url") and not is_todo(s["url"])
               and not looks_social(s["url"]) and s.get("kind") not in ("ical", "rss")]
        if web:
            targets.append((e, web[0]))
    print(f"[pick] {len(targets)} places with a website", flush=True)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        rows = list(pool.map(lambda t: pick(*t), targets))
    mark_same(rows, watched)
    out = Path(root) / ".runs" / "picks.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(rows, indent=1))
    by = {}
    for r in rows:
        by[r["state"]] = by.get(r["state"], 0) + 1
    whys = {}
    for r in rows:
        for p in r.get("pages", []):
            whys[p["why"]] = whys.get(p["why"], 0) + 1
    print(f"[pick] {by} | pages {whys} | same site twice {sum('same_as' in r for r in rows)}")
    print(f"report: {out}")


UNREVIEWED = "Unreviewed — tier `listed`, so it publishes nothing until promoted."
PROMOTED = "Watched since {day}: Jesse approved it in one batch with its picked pages (ADR-022)."
PLAIN_URL = re.compile(r"[A-Za-z0-9:/._~%?&=+@!$,;*()\-]+")


def yaml_url(u):
    return u if PLAIN_URL.fullmatch(u) else json.dumps(u)


def source_lines(s):
    lines = [f"  - url: {yaml_url(s['url'])}"]
    lines += [f"    {k}: {v}" for k, v in s.items() if k != "url"]
    return lines


def promote_block(block, entry, pages):
    """One entry's yaml block, made watched and active, its website replaced by its picked pages.
    Other sources (a Facebook page) stay; every other key stays as written."""
    trust = next((s.get("trust") for s in entry["sources"] if s.get("kind", "website") == "website"), None) or "official"
    kept = [s for s in entry["sources"] if looks_social(s.get("url", "")) or s.get("method") != "fetch"]
    sources = [{"url": g["url"], "kind": g["kind"], "method": "fetch", "trust": trust} for g in pages] + kept
    head = block.split("\nsources:", 1)[0].splitlines()
    head = [("status: active" if ln.startswith("status:") else "tier: watched" if ln.startswith("tier:") else ln)
            for ln in head]
    if not any(ln.startswith("tier:") for ln in head):
        head.insert(next(i for i, ln in enumerate(head) if ln.startswith("status:")) + 1, "tier: watched")
    return "\n".join(head + ["sources:"] + [ln for src in sources for ln in source_lines(src)])


def promote(root, picks, choices, day):
    """Jesse's approval page, applied: every ticked place he can read becomes watched and active
    with its picked pages (ADR-022). Unticked places and unreadable sites stay listed."""
    off_places, off_pages = set(choices.get("unticked_places", [])), set(choices.get("unticked_pages", []))
    want = {r["id"]: [g for g in r["pages"] if f"{r['id']}|{g['url']}" not in off_pages]
            for r in picks if r["state"] == "ok" and r["id"] not in off_places}
    want = {k: v for k, v in want.items() if v}
    entries = {e["id"]: e for e in load(root)[0]}
    done = 0
    for rel in sorted({entries[i]["_file"] for i in want if i in entries}):
        done += promote_file(Path(root) / rel, want, entries, day)
    print(f"[promote] {done} places watched and active; {len(want) - done} not found")


def promote_file(path, want, entries, day):
    text = path.read_text(encoding="utf-8")
    out, at, done = [], 0, 0
    for m in ENTRY_BLOCK.finditer(text):
        eid = re.search(r"^id:\s*(\S+)", m.group(2), re.M)
        if not eid or eid.group(1) not in want:
            continue
        e = entries[eid.group(1)]
        out.append(text[at:m.start(2)])
        out.append(promote_block(m.group(2), e, want[eid.group(1)]))
        notes = m.group(4) or ""
        line = PROMOTED.format(day=day)
        # A hand-written note runs over several lines, so the line goes first, never mid-sentence.
        notes = (notes.replace(UNREVIEWED, line) if UNREVIEWED in notes
                 else notes.replace("Notes: ", "Notes: " + line + " ", 1) if notes.strip() else "\nNotes: " + line)
        out.append(m.group(3) + notes)
        at = m.end()
        done += 1
    out.append(text[at:])
    path.write_text("".join(out), encoding="utf-8")
    return done


def selftest():
    page = """<head><link rel="alternate" type="application/rss+xml" href="/comments/feed/"></head>
    <a href="/about">About</a><a href="https://x.com/events/">Events</a><a href="/news/">News</a>
    <a href="mailto:a@b.c">Mail</a><a href="http://[phonenumber]">Call</a><a href="https://other.com/calendar">Calendar</a>"""
    url = "https://www.x.com/"
    no = lambda *a: 0
    checks = []
    got = pick_from(url, page, no, no, lambda u: True)
    checks.append(([p["why"] for p in got] == ["events page", "specials or news page"], "events, then news"))
    checks.append((got[0]["url"] == "https://x.com/events/", "same site with or without www"))
    got = pick_from(url, page + '<a href="/cal.ics">iCal</a>', lambda u: 3, no, lambda u: True)
    checks.append(([p["why"] for p in got] == ["calendar feed", "specials or news page"],
                   "a calendar feed stands in for its events page"))
    got = pick_from(url, "<a href='/about'>About us</a>", no, no, lambda u: True)
    checks.append((got == [{"url": url, "why": "homepage", "kind": "website"}], "nothing found: the homepage"))
    got = pick_from(url, page, no, no, lambda u: False)
    checks.append(([p["why"] for p in got] == ["homepage"], "a page that won't load isn't picked"))
    embed = '<iframe src="https://calendar.google.com/calendar/embed?src=abc%40group.calendar.google.com&ctz=x">'
    got = pick_from(url, embed, lambda u: 1, no, lambda u: True)
    checks.append((got[0]["url"] == "https://calendar.google.com/calendar/ical/abc@group.calendar.google.com/public/basic.ics",
                   "an embedded Google Calendar becomes its public feed"))
    rows = [{"name": "B Park", "state": "ok", "pages": [{"url": "https://city.gov/calendar"}]},
            {"name": "A Park", "state": "ok", "pages": [{"url": "http://www.city.gov/calendar/"}]},
            {"name": "Shop", "state": "ok", "pages": [{"url": "https://shop.com/"}]},
            {"name": "Campus office", "state": "ok", "pages": [{"url": "https://www.college.edu/news/"}]}]
    mark_same(rows, {"college.edu": "College"})
    checks.append(([r.get("same_as") for r in rows] == ["A Park", None, None, "College"],
                   "same pages twice, or a watched place's website, start unticked"))
    got = first_match([("https://x.com/event/summer-benefit/", "Gala"), ("https://x.com/events/", "See all")],
                      EVENT_WORDS, EVENT_PATH)
    checks.append((got == "https://x.com/events/", "the events list, not one event on it"))
    checks.append((not EVENT_WORDS.search("Show supplies") and EVENT_WORDS.search("Upcoming Events"),
                   "a word counts only as the whole menu label"))
    block = "id: bar\nstatus: proposed\ntier: listed\ncategory: amenity=bar\nadded_by: agent:discover\nsources:\n  - url: https://bar.com\n    kind: website\n    method: fetch\n    trust: official"
    entry = {"sources": [{"url": "https://bar.com", "kind": "website", "method": "fetch", "trust": "official"},
                         {"url": "https://www.facebook.com/bar", "kind": "facebook", "method": "search_snippet", "trust": "official"}]}
    got = promote_block(block, entry, [{"url": "https://bar.com/events/?ical=1", "kind": "ical"},
                                       {"url": "https://bar.com/a b", "kind": "website"}])
    checks.append((got.splitlines()[1:3] == ["status: active", "tier: watched"] and "category: amenity=bar" in got
                   and "  - url: https://bar.com/events/?ical=1\n    kind: ical\n    method: fetch\n    trust: official" in got
                   and '  - url: "https://bar.com/a b"' in got and "https://www.facebook.com/bar" in got
                   and "url: https://bar.com\n" not in got, "a promoted entry: watched, active, its picked pages, Facebook kept"))
    bad = [m for ok, m in checks if not ok]
    print(f"{len(checks) - len(bad)} passed, {len(bad)} failed" + "".join(f"\n  FAILED {m}" for m in bad))
    sys.exit(1 if bad else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".")
    ap.add_argument("--limit", type=int, default=0, help="stop after N sites (testing)")
    ap.add_argument("--pick", action="store_true", help="up to three pages per listed place -> .runs/picks.json")
    ap.add_argument("--promote", metavar="CHOICES_JSON",
                    help="apply Jesse's approval page (.runs/picks.json + his ticks) to the registry file")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()

    root = find_root(args.root)
    if args.pick:
        return pick_all(root)
    if args.promote:
        from datetime import date
        picks = json.loads((Path(root) / ".runs" / "picks.json").read_text())
        return promote(root, picks, json.loads(Path(args.promote).read_text()), date.today().isoformat())
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
