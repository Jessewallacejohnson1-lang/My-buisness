#!/usr/bin/env python3
"""Run the source registry: validate -> sync -> fetch -> hash -> report.

Dry-run is the default (ADR-009): fetches for real, writes nothing to Supabase,
keeps local state in .runs/state.json so repeat test runs still show changes.
--write syncs md -> `sources` table and stores runtime state in Supabase.

Usage:
  python3 run.py                      # dry-run, active entries
  python3 run.py --only krewe         # one entry
  python3 run.py --town st-joseph-mn  # one town
  python3 run.py --tier watched       # only watched entries (the morning job)
  python3 run.py --include-proposed   # also test proposed entries (never with --write)
  python3 run.py --write              # prod: needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
  python3 run.py --selftest           # when a page goes through Firecrawl, with fake sites
"""
import argparse, hashlib, html, json, os, re, shutil, socket, sys, threading, time, zlib
import urllib.request, urllib.error, urllib.parse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).parent))
from registry import find_root, load, validate, is_todo
from db import Db, DbError
import composio

UA = "BlockPartyBot/1.0 (+https://blockpartystjoe.com)"
MAX_BYTES = 2_000_000
TIMEOUT = 20
# Applied when robots.txt cannot be read, so an unknown host is crawled gently rather
# than at full speed. Matches the delay stjosephchamber.com asks for when it answers.
UNKNOWN_ROBOTS_DELAY = 10.0
NOW = datetime.now(timezone.utc)
CHICAGO = ZoneInfo("America/Chicago")
# Set aside (sources/CONTEXT.md; BP app smooth-mornings 04): a watched page failing three mornings
# in a row is skipped by the morning job except on its weekly try, until it reads again.
ASIDE_AFTER = 3   # mornings failing in a row, counted by reads: a morning that didn't run counts for nothing
TRY_DAY = 0       # Monday (the agent's default; smooth-mornings map, Not yet specified)
CLEAR = {"last_error": None, "failing_since": None, "failing_reads": 0, "set_aside_at": None}
GOV = "gov"       # an entry's category for the town's own offices: its failing pages are named every morning


FEED = re.compile(r"<(rss|feed|rdf:RDF)\b")
FEED_ITEM = re.compile(r"(?is)<(item|entry)\b.*?</\1>")


def feed_text(raw):
    """An RSS or Atom feed as its items, one block each with its date, so a model reading it
    keeps the dates. The channel's own build time is left out: it changes on every request."""
    blocks = []
    for m in FEED_ITEM.finditer(raw):
        item = m.group(0)

        def tag(*names):
            for n in names:
                t = re.search(rf"(?is)<{n}\b[^>]*>(.*?)</{n}>", item)
                if t:
                    return re.sub(r"(?s)<!\[CDATA\[(.*?)\]\]>", r"\1", t.group(1)).strip()
            return ""
        href = re.search(r'<link[^>]+href=["\']([^"\']+)', item)
        lines = [to_text(html.unescape(tag("title"))), tag("pubDate", "published", "updated", "dc:date"),
                 tag("link") or (href.group(1) if href else ""),
                 to_text(html.unescape(tag("description", "summary", "content:encoded", "content")))[:600]]
        blocks.append("\n".join(ln for ln in lines if ln))
    return "\n\n".join(blocks)


def to_text(raw):
    """HTML -> plain text good enough for hashing + an LLM reading the snapshot."""
    head = raw[:600]
    if FEED.search(head) and "<html" not in head.lower():
        return feed_text(raw)
    s = re.sub(r"(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\1>", " ", raw)
    s = re.sub(r"(?i)<br\s*/?>|</(p|div|li|h[1-6]|tr|section|article)>", "\n", s)
    s = re.sub(r"(?s)<[^>]+>", " ", s)
    s = html.unescape(s)
    lines = [re.sub(r"[ \t\r\f\v]+", " ", ln).strip() for ln in s.split("\n")]
    return "\n".join(ln for ln in lines if ln)


# A time to the second is the page's own clock ("Page generated at 10/16/2026, 3:45:36 AM",
# a feed's build time), never news, so it is left out of the fingerprint with its date. The
# snapshot a model reads keeps it.
STAMP = re.compile(r"(?:(?:\w{3},?\s+)?\d{1,2}\s+\w{3}\s+\d{4}\s+|\d{1,4}[/-]\d{1,2}[/-]\d{1,4}[,T ]?\s*)?"
                   r"\b\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\s*(?:[AP]M\b)?\s*(?:Z|[+-]\d{2}:?\d{2})?", re.I)


def fingerprint(text):
    return hashlib.sha256(STAMP.sub("", text).encode()).hexdigest()


_robots = {}          # host -> robots rules, or None (None = no restrictions known)
_crawl_delay = {}     # host -> seconds requested by robots.txt
_last_hit = {}        # host -> monotonic time of the last request, for crawl-delay
_unreadable = {}      # host -> why its robots.txt could not be read this run
_host_lock = defaultdict(threading.Lock)  # one request at a time per server (see server_of)
_server = {}          # host -> the server address it resolves to
_server_hit = {}      # server -> monotonic time of its last request
SERVER_GAP = 1.0      # seconds between two requests to one server
final_url = {}         # url -> where it landed after redirects (the page picker's same-site check)
STAY_OUT = [(False, "/")]
RETRY_WAIT = 5.0      # seconds before the one retry of a dropped connection


def parse_robots(text, agent="blockpartybot"):
    """The rules that apply to us, as (allow, path pattern) pairs (RFC 9309 s2.2).

    The groups naming our product token, else every `*` group, combined. Python's
    RobotFileParser keeps only the first `*` group, and Finalsite sites (Kennedy) put
    their page exclusions in a second one, so it missed them.
    """
    groups, cur = [], None
    for raw in text.splitlines():
        key, _, value = raw.split("#", 1)[0].partition(":")
        key, value = key.strip().lower(), value.strip()
        if key == "user-agent":
            if cur is None or cur["rules"] or cur["closed"]:
                cur = {"agents": set(), "rules": [], "closed": False}
                groups.append(cur)
            cur["agents"].add(value.lower())
        elif cur is not None and key in ("allow", "disallow"):
            cur["closed"] = True
            if value:
                cur["rules"].append((key == "allow", value))
        elif cur is not None and key:
            cur["closed"] = True    # Crawl-delay and the like end the user-agent lines
    mine = [g for g in groups if agent in g["agents"]] or [g for g in groups if "*" in g["agents"]]
    return [r for g in mine for r in g["rules"]]


def allowed(rules, path):
    """RFC 9309 s2.2.2: the longest matching rule wins, Allow on a tie; `*` is any run of
    characters and a final `$` ends the path. No match means allowed."""
    if path == "/robots.txt":
        return True
    best_len, best = -1, True
    for allow, pattern in rules:
        rx = re.escape(pattern).replace(r"\*", ".*")
        rx = rx[:-2] + "$" if rx.endswith(r"\$") else rx
        if re.match(rx, path) and (len(pattern) > best_len or (len(pattern) == best_len and allow)):
            best_len, best = len(pattern), allow
    return best


def _load_robots(base):
    """Read robots.txt with OUR user-agent, and follow RFC 9309 on failure.

    urllib's RobotFileParser.read() uses urllib's default user-agent, which some WAFs
    reject, and turns any 401/403 into disallow-all. stjosephchamber.com was written off
    as blocking us on exactly that path: its robots.txt says `User-agent: *` with a
    Crawl-delay and NO Disallow, and its pages serve us HTTP 200 all day. The 403s were
    throttling, because we were ignoring the crawl delay it asked for.

    RFC 9309 s2.3.1: 4xx means no robots.txt exists, and a crawler may access the site;
    5xx and network failures mean unknown, and we stay out. That is the rule here.
    """
    req = urllib.request.Request(base + "/robots.txt", headers={"User-Agent": UA})
    try:
        with _open(req) as r:
            text = r.read(MAX_BYTES).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if 400 <= e.code < 500:
            # No robots.txt to obey (RFC 9309) — but a host that refuses its own
            # robots.txt is usually throttling, not welcoming. Default to the polite
            # delay rather than zero: stjosephchamber.com serves robots.txt sometimes
            # and 403s it other times, and the 403s are what happen when we go too fast.
            return None, UNKNOWN_ROBOTS_DELAY
        _unreadable[base] = f"HTTP {e.code}"
        return STAY_OUT, 0.0        # 5xx: server is unwell, do not crawl it
    except Exception as e:
        _unreadable[base] = str(e)[:120]
        return STAY_OUT, 0.0        # unreachable: unknown, so stay out
    delay = 0.0
    for line in text.splitlines():
        if line.lower().startswith("crawl-delay:"):
            try:
                delay = max(delay, float(line.split(":", 1)[1].strip()))
            except ValueError:
                pass
    return parse_robots(text), delay


def robots_ok(url):
    p = urlparse(url)
    base = f"{p.scheme}://{p.netloc}"
    if base not in _robots:
        _robots[base], _crawl_delay[base] = _load_robots(base)
        # Reading robots.txt IS a request. Without counting it, the first real fetch
        # lands milliseconds later and a crawl-delay host answers 403 — which is what
        # made stjosephchamber.com look like it was blocking us.
        _last_hit[p.netloc] = time.monotonic()
    rules = _robots[base]
    return rules is None or allowed(rules, (p.path or "/") + (f"?{p.query}" if p.query else ""))


def _respect_crawl_delay(url):
    """Sleep out whatever robots.txt asked for. It is the one thing it asked for."""
    host = urlparse(url).netloc
    delay = _crawl_delay.get(f"{urlparse(url).scheme}://{host}", 0.0)
    if delay <= 0:
        return
    last = _last_hit.get(host)
    if last is not None:
        wait = delay - (time.monotonic() - last)
        if wait > 0:
            time.sleep(wait)
    _last_hit[host] = time.monotonic()


def _open(req, timeout=TIMEOUT):
    """urlopen, with one retry after a dropped connection. stjosephmn.gov resets some
    connections outright (2026-10-15); an HTTP answer is never retried."""
    try:
        return urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError:
        raise
    except (urllib.error.URLError, ConnectionError, TimeoutError):
        time.sleep(RETRY_WAIT)
        return urllib.request.urlopen(req, timeout=timeout)


def server_of(host):
    """Many small sites share one server (Weebly, Wix, GoDaddy), so politeness is per server,
    not per name: on 2026-10-17 four Weebly sites fetched side by side answered 429 and three
    sites on one shared address reset the connection."""
    if host not in _server:
        try:
            _server[host] = socket.gethostbyname(host.split(":")[0])
        except OSError:
            _server[host] = host
    return _server[host]


def deadline(minutes):
    """When a timed part stops starting new work (None: never); a part's work then has 3 minutes to end."""
    return time.monotonic() + minutes * 60 if minutes else None


def late(stop, grace=0):
    return stop is not None and time.monotonic() > stop + grace


def part_state():
    """What this run knows that the next part of a timed run (a new process) must too: each site's
    robots rules and Crawl-delay, each host's server, when each host and server was last asked (on
    the wall clock, since each process has its own monotonic one) and the Firecrawl pages spent."""
    gap = time.time() - time.monotonic()
    return {"robots": _robots, "crawl_delay": _crawl_delay, "unreadable": _unreadable, "server": _server,
            "last_hit": {h: t + gap for h, t in _last_hit.items()},
            "server_hit": {s: t + gap for s, t in _server_hit.items()}, "firecrawl_used": _firecrawl_used}


def resume_part(state):
    """The previous part's part_state, so robots.txt isn't read again and Crawl-delay and the gap
    between two requests to one server hold across parts, as they do within one."""
    global _firecrawl_used
    gap = time.time() - time.monotonic()
    for name, known in (("robots", _robots), ("crawl_delay", _crawl_delay), ("unreadable", _unreadable),
                        ("server", _server)):
        known.update(state.get(name) or {})
    _last_hit.update({h: t - gap for h, t in (state.get("last_hit") or {}).items()})
    _server_hit.update({s: t - gap for s, t in (state.get("server_hit") or {}).items()})
    _firecrawl_used = state.get("firecrawl_used", _firecrawl_used)


def decoded(body, encoding):
    """Some servers send gzip although nobody asked (fabral.com, fivestarlogistics.com), which
    read as binary noise and changed fingerprint on every run. A cut-off body still decodes."""
    if body[:2] == b"\x1f\x8b" or encoding == "gzip":
        return zlib.decompressobj(31).decompress(body)
    if encoding == "deflate":
        return zlib.decompressobj().decompress(body)
    return body


def fetch(url, data=None, headers=None, timeout=TIMEOUT):
    """GET, or POST when `data` is given (511's GraphQL). Robots and Crawl-delay either way,
    and one request at a time to any one server, a second apart: parallel requests made
    stjosephmn.gov drop connections, which then read as a robots refusal."""
    p = urlparse(url)
    server = server_of(p.netloc)
    with _host_lock[server]:
        wait = SERVER_GAP - (time.monotonic() - _server_hit.get(server, -SERVER_GAP))
        if wait > 0:
            time.sleep(wait)
        _server_hit[server] = time.monotonic()
        if not robots_ok(url):
            why = _unreadable.get(f"{p.scheme}://{p.netloc}")
            if why:
                raise RuntimeError(f"robots.txt could not be read ({why}); staying out this run, try again next run")
            raise RuntimeError("robots.txt disallows -> switch method to search_snippet")
        _respect_crawl_delay(url)
        req = urllib.request.Request(url, data=data,
                                     headers={"User-Agent": UA, "Accept": "text/html,*/*", **(headers or {})})
        with _open(req, timeout) as r:
            final_url[url] = r.geturl()
            body = r.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                body = body[:MAX_BYTES]
            try:
                body = decoded(body, (r.headers.get("Content-Encoding") or "").lower())
            except zlib.error:
                pass  # not compressed after all: read it as it came
            charset = r.headers.get_content_charset() or "utf-8"
            return r.status, body.decode(charset, errors="replace")


# Firecrawl names itself as a crawler, so it is not a browser in disguise (ADR-014). It reads a
# page whose server refuses our address (eight GoDaddy sites and Kwik Trip reset or 403'd the
# cloud routine from 2026-10-16 while answering the Mac) or builds its text in JavaScript.
# Jesse, 2026-10-22: "use for blocked and java", and later that day dropped the robots.txt and
# feed limits: a page our own fetch must stay out of by robots.txt goes through Firecrawl too.
FIRECRAWL = "https://api.firecrawl.dev/v1/scrape"
FIRECRAWL_CAP = 30    # ponytail: credits per run (1 a page); the plan has 1,000 a month
JS_TEXT = 200         # fewer characters than this from a plain fetch = built by JavaScript
FEED_KINDS = {"ical", "rss"}             # read raw through Firecrawl, so the feed parser still sees items
SOCIAL_KINDS = {"facebook", "instagram"}  # Firecrawl refuses them ("we do not support this site"); Apify reads them (ADR-020)
GONE = re.compile(r"HTTP Error (404|410)")  # the page is gone: Firecrawl gets the same 404 and spends a credit
_firecrawl_used = 0
_firecrawl_lock = threading.Lock()


def firecrawl(url, fmt="markdown"):
    """One Firecrawl scrape, through FIRECRAWL_API_KEY (the cloud routine) or Composio (the Mac).
    Link query strings are cut: GoDaddy's banner link carries a fresh timestamp on every read."""
    global _firecrawl_used
    with _firecrawl_lock:
        if _firecrawl_used >= FIRECRAWL_CAP:
            raise RuntimeError(f"Firecrawl cap of {FIRECRAWL_CAP} pages reached this run")
        _firecrawl_used += 1
    body = {"url": url, "formats": [fmt], "onlyMainContent": True}
    key = os.environ.get("FIRECRAWL_API_KEY")
    if key:
        req = urllib.request.Request(FIRECRAWL, data=json.dumps(body).encode(), headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=90) as r:
            d = json.load(r)
    elif shutil.which("composio"):
        d = composio.execute("FIRECRAWL_SCRAPE", body) or {}
    else:
        raise RuntimeError("no FIRECRAWL_API_KEY to read it through Firecrawl")
    d = d.get("data", d)
    text = d.get(fmt) or ""
    code = (d.get("metadata") or {}).get("statusCode") or 200
    if code >= 400 or not text.strip():
        raise RuntimeError(f"Firecrawl read nothing (HTTP {code})")
    return re.sub(r"(\]\([^)\s?]*)\?[^)\s]*", r"\1", text)


def read_page(url, kind, get=None, scrape=None):
    """One page as (http status, text, via), via "fetch" or "firecrawl". Our fetch first; Firecrawl
    when it is refused (robots.txt included) or reads under JS_TEXT characters. Raises when the page
    is gone, is social, or neither can read it. `get` and `scrape` stand in for fetch and firecrawl
    in the self-test."""
    get, scrape = get or fetch, scrape or firecrawl
    try:
        status, raw = get(url)
    except Exception as ex:
        if GONE.search(str(ex)) or kind in SOCIAL_KINDS:
            raise
        try:
            text = to_text(scrape(url, "rawHtml")) if kind in FEED_KINDS else scrape(url)
        except Exception as fc:
            raise RuntimeError(f"{str(ex)[:150]}; Firecrawl: {str(fc)[:120]}") from None
        return 200, text, "firecrawl"
    text = to_text(raw)
    if len(text) < JS_TEXT and kind not in FEED_KINDS | SOCIAL_KINDS:
        try:
            return status, scrape(url), "firecrawl"
        except Exception:
            pass  # keep the little the plain fetch read
    return status, text, "fetch"


def selftest():
    page = "<p>" + "Plant Bingo Oct 24 at the taproom. " * 10 + "</p>"

    def site(answer):
        def get(url):
            if isinstance(answer, Exception):
                raise answer
            return 200, answer
        return get
    calls = []

    def scrape(url, fmt="markdown"):
        calls.append(fmt)
        return "BEGIN:VEVENT\nSUMMARY:Bingo" if fmt == "rawHtml" else "Read through Firecrawl"

    def case(answer, kind="website"):
        calls.clear()
        try:
            return read_page("https://x/", kind, site(answer), scrape)
        except RuntimeError as ex:
            return str(ex)
    checks = [
        (case(page)[2] == "fetch" and not calls, "a normal page is ours, no credit spent"),
        (case(ConnectionResetError(104, "Connection reset by peer"))[2] == "firecrawl", "a refused page goes through Firecrawl"),
        (case(RuntimeError("robots.txt disallows -> switch method to search_snippet"))[2] == "firecrawl",
         "a robots.txt no goes through Firecrawl (Jesse, 2026-10-22)"),
        (case("<div id=app></div>")[1] == "Read through Firecrawl", "a JavaScript page is read through Firecrawl"),
        (str(case(RuntimeError("HTTP Error 404: Not Found"))).startswith("HTTP Error 404") and not calls,
         "a gone page spends no credit"),
        (str(case(RuntimeError("HTTP Error 403: Forbidden"), "facebook")).startswith("HTTP Error 403") and not calls,
         "Facebook is left to Apify"),
        (case(RuntimeError("HTTP Error 403: Forbidden"), "ical")[2] == "firecrawl" and calls == ["rawHtml"],
         "a refused feed is read raw"),
        (case("", "ical")[2] == "fetch" and not calls, "a short feed is not taken for a JavaScript page"),
        (one_bad_row_is_one_line(), "a row the database refuses is one report line; the rest are recorded"),
        (polite_across_parts(), "a timed run's next part reads no robots.txt again and waits out its Crawl-delay"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def one_bad_row_is_one_line():
    """fetch_watched against a fake database that answers 500 to one page's PATCH, offline."""
    import contextlib, io, tempfile
    g = globals()
    patched = {"read_page": lambda url, kind: (200, f"Plant Bingo Oct 24 at {url}", "fetch"),
               "validate": lambda e: [], "NOW": datetime(2026, 10, 26, tzinfo=timezone.utc)}
    saved = {k: g[k] for k in (*patched, "find_root")}, urllib.request.urlopen, dict(os.environ)
    entries = [{"id": i, "_name": i, "_town": "st-joseph-mn", "_extra": {}, "status": "active", "tier": "watched",
                "sources": [{"url": f"https://{i}/", "method": "fetch"}]} for i in ("a", "b", "c")]
    recorded = []

    def urlopen(req, timeout=None):
        if req.get_method() == "PATCH":
            if "b%2F" in req.full_url:
                raise urllib.error.HTTPError(req.full_url, 500, "Internal Server Error", {},
                                             io.BytesIO(b'{"message":"canceling statement due to statement timeout"}'))
            recorded.append(req.full_url)
        return contextlib.nullcontext(io.BytesIO(b"[]" if req.get_method() == "GET" else b""))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            g.update(patched, find_root=lambda *a: Path(tmp))
            urllib.request.urlopen = urlopen
            os.environ.update(SUPABASE_URL="https://fake.invalid", SUPABASE_SERVICE_ROLE_KEY="fake")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                report = fetch_watched(entries, Supabase())
    finally:
        g.update(saved[0])
        urllib.request.urlopen = saved[1]
        os.environ.clear()
        os.environ.update(saved[2])
    lines = [l for l in out.getvalue().splitlines() if "NOT RECORDED" in l]
    return (len(lines) == 1 and "NOT RECORDED b https://b/: Supabase PATCH" in lines[0]
            and "500" in lines[0] and "statement timeout" in lines[0]
            and len(recorded) == 2 and [u["entry_id"] for u in report["unrecorded"]] == ["b"])


def polite_across_parts():
    """Two parts of a timed run against a fake site asking a 10-second Crawl-delay, offline on fake
    clocks: the second part is a new process with its own monotonic clock, 3 seconds later."""
    import http.client, io
    g, asked = globals(), []

    class Clock:
        def __init__(self, mono, wall):
            self.mono, self.wall = mono, wall

        def monotonic(self):
            return self.mono

        def time(self):
            return self.wall

        def sleep(self, s):
            self.mono, self.wall = self.mono + s, self.wall + s

    class Answer(io.BytesIO):
        status, headers = 200, http.client.HTTPMessage()

        def geturl(self):
            return asked[-1][1]

    def urlopen(req, timeout=None):
        asked.append((g["time"].wall, req.full_url))
        return Answer(b"User-agent: *\nCrawl-delay: 10\n" if req.full_url.endswith("/robots.txt") else b"<p>Trivia</p>")
    known = (_robots, _crawl_delay, _unreadable, _server, _last_hit, _server_hit)
    saved = g["time"], urllib.request.urlopen, [dict(d) for d in known]
    try:
        urllib.request.urlopen = urlopen
        for d in known:
            d.clear()
        _server["slow.invalid"] = "10.0.0.9"
        g["time"] = Clock(100.0, 5000.0)
        fetch("https://slow.invalid/a")
        state = json.loads(json.dumps(part_state()))
        for d in known:
            d.clear()
        g["time"] = Clock(7.0, g["time"].wall + 3)
        resume_part(state)
        fetch("https://slow.invalid/b")
    finally:
        g["time"], urllib.request.urlopen = saved[:2]
        for d, was in zip(known, saved[2]):
            d.clear()
            d.update(was)
    return ([u for _, u in asked] == ["https://slow.invalid/robots.txt", "https://slow.invalid/a", "https://slow.invalid/b"]
            and asked[2][0] - asked[1][0] >= 10)


class Supabase(Db):
    """The `sources` table's runtime state, over the shared client (db.py)."""

    def __init__(self):
        super().__init__("--write needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in env. Never put the key in the repo.")

    def upsert_registry(self, rows):
        self.rest("POST", "sources?on_conflict=entry_id,url", rows,
                  prefer="resolution=merge-duplicates,return=minimal")

    def state(self):
        """Yesterday's fingerprints, which pages were ever checked (a cleared fingerprint
        forces a read; a page never checked is new and only gets its starting copy), and each
        page with an error, failing or set aside."""
        rows = self.rest("GET", "sources?select=entry_id,url,last_hash,last_checked_at,"
                                "last_error,failing_since,failing_reads,set_aside_at") or []
        return ({f"{r['entry_id']}|{r['url']}": r.get("last_hash") for r in rows},
                {f"{r['entry_id']}|{r['url']}" for r in rows if r.get("last_checked_at")},
                {f"{r['entry_id']}|{r['url']}": {k: r.get(k) for k in (*CLEAR, "last_checked_at")} for r in rows
                 if any(r.get(k) for k in CLEAR)})

    def record(self, entry_id, url, fields):
        q = f"sources?entry_id=eq.{entry_id}&url=eq.{urllib.parse.quote(url, safe='')}"
        self.rest("PATCH", q, fields, prefer="return=minimal")

    def commit_fingerprints(self, changed):
        """Changed pages' new fingerprints (fetch_watched's report["changed"]), saved once
        their events are written, so the next run sees them unchanged. A first-seen page's
        starting copy was saved when it was fetched."""
        now = datetime.now(timezone.utc).isoformat()
        for r in changed:
            if not r.get("first_seen"):
                self.record(r["entry_id"], r["url"], {"last_hash": r["hash"], "last_changed_at": now})


def day(stamp):
    """A stored time's day in Chicago, where mornings are counted."""
    return datetime.fromisoformat(stamp).astimezone(CHICAGO).date()


def set_aside(r, was, today, counted=True):
    """The fetch table's memory of a failing page, as the fields to record with this result and
    its mark for the report: since when it has been failing and how many mornings' reads in a row
    (both cleared by a good read), and when it was set aside, on its ASIDE_AFTER-th failed morning.
    A morning's second read (a rerun) adds nothing, nor does a read where most pages failed at once
    (`counted` False: the network, not the pages). A set-aside page that reads is back; one tried
    and failing again is "still"."""
    reads, since, aside = was.get("failing_reads") or 0, was.get("failing_since"), was.get("set_aside_at")
    if r["ok"]:
        return ({"failing_since": None, "failing_reads": 0, "set_aside_at": None} if reads or since or aside else {},
                {"aside": "back", "since": aside} if aside else {})
    if not counted:
        return {}, {}
    if aside:
        return {}, {"aside": "still"}
    if reads and was.get("last_checked_at") and day(was["last_checked_at"]) == today:
        return {}, {}
    memo = {"failing_reads": reads + 1, "failing_since": since or NOW.isoformat()}
    if reads + 1 < ASIDE_AFTER:
        return memo, {}
    return {**memo, "set_aside_at": NOW.isoformat()}, {"aside": "set", "since": memo["failing_since"]}


def aside_lines(report, today):
    """The morning report's words on failing pages: how many failed today, naming the town's own
    offices' pages; a read where most failed at once, counted against none; each page the morning it
    is set aside and the morning it is back; and on the weekly try's day, how many set-aside pages
    were tried again and still fail."""
    gov = [f"{r['entry_id']} {r['url']} ({r['error']})" for r in report["failed"] if r.get("category") == GOV]
    lines = [f"Failed today: {len(report['failed'])}" + (f", the town's own among them: {'; '.join(gov)}" if gov else "")]
    if report["uncounted"]:
        lines.append(f"{len(report['failed'])} of {report['fetched']} pages failed, not counted")
    lines += [f"Set aside: {r['entry_id']} {r['url']}: {r['error']} (failing since {day(r['since']):%b %-d}); "
              f"tried again on Mondays" for r in report["set_aside"]]
    lines += [f"Back: {r['entry_id']} {r['url']} reads again (set aside since {day(r['since']):%b %-d})"
              for r in report["back"]]
    if today.weekday() == TRY_DAY and report["still"]:
        lines.append(f"Pages set aside: {len(report['still'])}, tried again today and still failing. Fixing a page's "
                     "address or retiring a place is the registry job's, with Jesse's yes (source-registry skill)")
    return lines


def fetch_watched(entries, db, picked=None, workers=6, done=(), stop=None, run_dir=None, today=None):
    """Validate the registry, sync it (with `db`), fetch `picked` (default: every active watched
    entry), save the changed pages' snapshots and return the report (also in report.json).

    A page's check time and error are recorded now, but a changed page's new fingerprint waits
    for db.commit_fingerprints, which the caller runs once the page's events are written: a
    morning that dies after fetching then reads the same pages again tomorrow. A page seen for
    the first time saves its starting copy now; nothing is read from it (ADR-022).

    A page failing three mornings in a row is set aside (set_aside). The morning job passes its
    `today`: a set-aside page is then skipped, except on Mondays. By hand (no `today`) every page
    is fetched. The sync clears the error rows of pages no longer watched.

    A timed part (morning.py prepare) passes the earlier parts' results as `done`, which are not
    fetched again, one `run_dir` for every part, and `stop` (deadline): no page starts after it.
    The report covers every part so far; `left` counts the pages still to fetch, and the returned
    `results` (not in report.json) carry every page's result to the next part."""
    errors = validate(entries)
    if errors:
        print("\n".join("ERROR " + e for e in errors))
        sys.exit("Registry invalid. Fix before running.")
    if picked is None:
        picked = [e for e in entries if e["status"] == "active" and e.get("tier", "listed") == "watched"]
    root = find_root()
    if run_dir is None:
        run_dir = root / ".runs" / NOW.strftime("%Y%m%d-%H%M%S")
        n = 1
        while run_dir.exists():
            n += 1
            run_dir = root / ".runs" / f"{NOW.strftime('%Y%m%d-%H%M%S')}-{n}"
    snap_dir = run_dir / "snapshots"
    snap_dir.mkdir(parents=True, exist_ok=True)
    local_state_path = root / ".runs" / "state.json"

    if db:
        # Sync first (ADR-002): md -> sources, registry fields only, every entry incl. paused/retired.
        rows = [{"entry_id": e["id"], "url": s["url"], "town": e["_town"], "name": e["_name"],
                 "status": e["status"], "kind": s.get("kind"), "method": s["method"],
                 "trust": s.get("trust"), "place_id": e.get("place_id"),
                 "extra": {**e["_extra"], **{k: v for k, v in s.items()
                                              if k not in ("url", "kind", "method", "trust")}}}
                for e in entries for s in e["sources"] if not is_todo(s["url"])]
        db.upsert_registry(rows)
        prev, seen, failing = db.state()
        print(f"synced {len(rows)} source rows")
    else:
        prev = json.loads(local_state_path.read_text()) if local_state_path.exists() else {}
        seen, failing = set(prev), {}

    # Only a watched page's error means anything: the rest (a page retired, re-addressed or no longer
    # watched, the first test's rows) are cleared, so they never read as today's trouble.
    watched = {f"{e['id']}|{s['url']}" for e in entries if e["status"] == "active"
               and e.get("tier", "listed") == "watched" for s in e["sources"] if s["method"] == "fetch"}
    unrecorded = []
    for key in [k for k in failing if k not in watched]:
        entry_id, url = key.split("|", 1)
        try:
            db.record(entry_id, url, CLEAR)
            del failing[key]
        except DbError as ex:
            unrecorded.append({"entry_id": entry_id, "url": url, "error": str(ex)[:300]})
    aside_on = today or NOW.astimezone(CHICAGO).date()

    jobs, agent_tasks, skipped = [], [], []
    for e in picked:
        for s in e["sources"]:
            ref = {"entry_id": e["id"], "name": e["_name"], "town": e["_town"],
                   "url": s["url"], "trust": s.get("trust"), "kind": s.get("kind"), "category": e.get("category")}
            aside = (failing.get(f"{e['id']}|{s['url']}") or {}).get("set_aside_at")
            if is_todo(s["url"]):
                skipped.append({**ref, "why": "url TODO"})
            elif s["method"] == "fetch" and aside and today and today.weekday() != TRY_DAY:
                skipped.append({**ref, "why": f"set aside since {day(aside):%b %-d}, tried on Mondays"})
            elif s["method"] == "fetch":
                jobs.append(ref)
            elif s["method"] == "search_snippet":
                town = e["_town"].removesuffix("-mn").replace("-", " ")
                name = e["_name"]
                q = f"{name} MN" if town.replace(".", "") in name.lower().replace(".", "") else f"{name} {town} MN"
                agent_tasks.append({**ref, "query": q,
                                    "site": urlparse(s["url"]).netloc})
            else:
                skipped.append({**ref, "why": f"method {s['method']} not run by this script"})

    def work(ref):
        if late(stop):
            return None  # left for the next part
        key = f"{ref['entry_id']}|{ref['url']}"
        t0 = time.time()
        try:
            status, text, via = read_page(ref["url"], ref["kind"])
            h = fingerprint(text)
            changed = prev.get(key) != h
            fname = f"{ref['entry_id']}--{hashlib.md5(ref['url'].encode()).hexdigest()[:6]}.md"
            if changed:
                (snap_dir / fname).write_text(
                    f"---\nentry_id: {ref['entry_id']}\nurl: {ref['url']}\nfetched_at: {NOW.isoformat()}\n"
                    f"hash: {h}\ntrust: {ref['trust']}\nvia: {via}\n---\n\n{text}\n", encoding="utf-8")
            return {**ref, "ok": True, "http": status, "via": via, "hash": h, "changed": changed,
                    "first_seen": key not in seen, "snapshot": fname if changed else None,
                    "chars": len(text), "secs": round(time.time() - t0, 1)}
        except Exception as ex:
            return {**ref, "ok": False, "error": str(ex)[:300], "secs": round(time.time() - t0, 1)}

    page = lambda r: f"{r['entry_id']}|{r['url']}"
    order, had = {page(j): i for i, j in enumerate(jobs)}, {page(r) for r in done}
    todo = [j for j in jobs if page(j) not in had]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        new = [r for r in pool.map(work, todo) if r]

    # Most pages failing in one read is our network or the cloud's, not the pages: counted against none.
    so_far = [*done, *new]
    counted = sum(not r["ok"] for r in so_far) * 2 <= len(so_far)
    new_state = dict(prev)
    for r in new:
        key = f"{r['entry_id']}|{r['url']}"
        if r["ok"]:
            new_state[key] = r["hash"]
        if db:
            fields = {"last_checked_at": NOW.isoformat()}
            fields.update({"last_error": None} if r["ok"] else {"last_error": r["error"]})
            if r["ok"] and r["changed"] and r["first_seen"]:
                fields.update({"last_hash": r["hash"], "last_changed_at": NOW.isoformat()})
            memo, mark = set_aside(r, failing.get(key) or {}, aside_on, counted)
            try:
                db.record(r["entry_id"], r["url"], {**fields, **memo})
                r.update(mark)  # named only once it is recorded, so it is named once
            except DbError as ex:  # one bad row is one report line; the rest still get recorded
                unrecorded.append({"entry_id": r["entry_id"], "url": r["url"], "error": str(ex)[:300]})
    if not db:
        local_state_path.write_text(json.dumps(new_state, indent=1))

    # In the registry's order, so pages read over several parts lie as one run's would.
    results = sorted([*done, *new], key=lambda r: order.get(page(r), len(order)))
    changed = [r for r in results if r["ok"] and r["changed"]]
    failed = [r for r in results if not r["ok"]]
    marked = lambda how: [r for r in results if r.get("aside") == how]
    report = {"mode": "write" if db else "dry-run", "at": NOW.isoformat(), "run_dir": str(run_dir),
              "fetched": len(results), "changed": changed, "failed": failed,
              "unchanged": [r["entry_id"] for r in results if r["ok"] and not r["changed"]],
              "agent_tasks": agent_tasks, "skipped": skipped, "unrecorded": unrecorded,
              "set_aside": marked("set"), "back": marked("back"), "still": marked("still"), "uncounted": not counted,
              "left": len(todo) - len(new)}
    (run_dir / "report.json").write_text(json.dumps(report, indent=1))

    print(f"[{report['mode']}] fetched {len(results)} | changed {len(changed)} | "
          f"failed {len(failed)} | agent tasks {len(agent_tasks)} | skipped {len(skipped)} | "
          f"through Firecrawl {sum(r.get('via') == 'firecrawl' for r in results)}"
          + (f" | not recorded {len(unrecorded)}" if unrecorded else "")
          + ("" if counted else f" | {len(failed)} of {len(results)} pages failed, not counted")
          + (f" | left for the next part {report['left']}" if report["left"] else ""))
    for r in changed:
        print(f"  CHANGED {r['entry_id']} {'(first seen) ' if r['first_seen'] else ''}-> snapshots/{r['snapshot']}")
    for r in failed:
        print(f"  FAILED  {r['entry_id']} {r['url']}: {r['error']}" + (" (set aside now)" if r.get("aside") == "set" else ""))
    for r in report["back"]:
        print(f"  BACK    {r['entry_id']} {r['url']}: reads again after being set aside")
    for u in unrecorded:
        print(f"  NOT RECORDED {u['entry_id']} {u['url']}: {u['error']}")
    for t in agent_tasks:
        print(f"  SEARCH  {t['entry_id']}: \"{t['query']}\" site:{t['site']}")
    print(f"report: {run_dir / 'report.json'}")
    return {**report, "results": results}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--include-proposed", action="store_true")
    ap.add_argument("--only", help="entry id")
    ap.add_argument("--town", help="e.g. st-joseph-mn")
    ap.add_argument("--tier", help="only entries of this tier, e.g. watched")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.write and a.include_proposed:
        sys.exit("Refusing: --include-proposed is for dry-run tests only (ADR-008).")

    entries, errors = load(find_root())
    if errors:
        print("\n".join("ERROR " + e for e in errors))
        sys.exit("Registry invalid. Fix before running.")
    statuses = {"active", "proposed"} if a.include_proposed else {"active"}
    picked = [e for e in entries if e["status"] in statuses
              and (not a.only or e["id"] == a.only)
              and (not a.town or e["_town"] == a.town)
              and (not a.tier or e.get("tier", "listed") == a.tier)]
    if not picked:
        sys.exit("Nothing selected. Check --only/--town, or entries are still status: proposed.")

    db = Supabase() if a.write else None  # fail fast on missing env, before touching disk
    report = fetch_watched(entries, db, picked, a.workers)
    if db:  # by hand nothing reads the pages after, so their fingerprints move now
        db.commit_fingerprints(report["changed"])


if __name__ == "__main__":
    main()
