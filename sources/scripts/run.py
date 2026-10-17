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
"""
import argparse, hashlib, html, json, os, re, socket, sys, threading, time, zlib
import urllib.request, urllib.error, urllib.parse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).parent))
from registry import find_root, load, validate, is_todo

UA = "BlockPartyBot/1.0 (+https://blockpartystjoe.com)"
MAX_BYTES = 2_000_000
TIMEOUT = 20
# Applied when robots.txt cannot be read, so an unknown host is crawled gently rather
# than at full speed. Matches the delay stjosephchamber.com asks for when it answers.
UNKNOWN_ROBOTS_DELAY = 10.0
NOW = datetime.now(timezone.utc)


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


def _open(req):
    """urlopen, with one retry after a dropped connection. stjosephmn.gov resets some
    connections outright (2026-10-15); an HTTP answer is never retried."""
    try:
        return urllib.request.urlopen(req, timeout=TIMEOUT)
    except urllib.error.HTTPError:
        raise
    except (urllib.error.URLError, ConnectionError, TimeoutError):
        time.sleep(RETRY_WAIT)
        return urllib.request.urlopen(req, timeout=TIMEOUT)


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


def decoded(body, encoding):
    """Some servers send gzip although nobody asked (fabral.com, fivestarlogistics.com), which
    read as binary noise and changed fingerprint on every run. A cut-off body still decodes."""
    if body[:2] == b"\x1f\x8b" or encoding == "gzip":
        return zlib.decompressobj(31).decompress(body)
    if encoding == "deflate":
        return zlib.decompressobj().decompress(body)
    return body


def fetch(url, data=None, headers=None):
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
        with _open(req) as r:
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


class Supabase:
    def __init__(self):
        self.url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        self.key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not self.url or not self.key:
            sys.exit("--write needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in env. Never put the key in the repo.")

    def call(self, method, path, body=None, prefer=None):
        headers = {"apikey": self.key, "Authorization": f"Bearer {self.key}",
                   "Content-Type": "application/json"}
        if prefer:
            headers["Prefer"] = prefer
        data = json.dumps(body, default=str).encode() if body is not None else None
        req = urllib.request.Request(f"{self.url}/rest/v1/{path}", data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                txt = r.read().decode()
                return json.loads(txt) if txt else None
        except urllib.error.HTTPError as e:
            sys.exit(f"Supabase {method} {path} failed {e.code}: {e.read().decode()[:400]}\n"
                     "Is the sources table migrated? See supabase/migrations/20261014120000_source_registry.sql")

    def upsert_registry(self, rows):
        self.call("POST", "sources?on_conflict=entry_id,url", rows,
                  prefer="resolution=merge-duplicates,return=minimal")

    def state(self):
        """Yesterday's fingerprints, and which pages were ever checked (a cleared fingerprint
        forces a read; a page never checked is new and only gets its starting copy)."""
        rows = self.call("GET", "sources?select=entry_id,url,last_hash,last_checked_at") or []
        return ({f"{r['entry_id']}|{r['url']}": r.get("last_hash") for r in rows},
                {f"{r['entry_id']}|{r['url']}" for r in rows if r.get("last_checked_at")})

    def record(self, entry_id, url, fields):
        q = f"sources?entry_id=eq.{entry_id}&url=eq.{urllib.parse.quote(url, safe='')}"
        self.call("PATCH", q, fields, prefer="return=minimal")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--include-proposed", action="store_true")
    ap.add_argument("--only", help="entry id")
    ap.add_argument("--town", help="e.g. st-joseph-mn")
    ap.add_argument("--tier", help="only entries of this tier, e.g. watched")
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    if a.write and a.include_proposed:
        sys.exit("Refusing: --include-proposed is for dry-run tests only (ADR-008).")

    root = find_root()
    entries, errors = load(root)
    errors += validate(entries)
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
        prev, seen = db.state()
        print(f"synced {len(rows)} source rows")
    else:
        prev = json.loads(local_state_path.read_text()) if local_state_path.exists() else {}
        seen = set(prev)

    jobs, agent_tasks, skipped = [], [], []
    for e in picked:
        for s in e["sources"]:
            ref = {"entry_id": e["id"], "name": e["_name"], "town": e["_town"],
                   "url": s["url"], "trust": s.get("trust"), "kind": s.get("kind")}
            if is_todo(s["url"]):
                skipped.append({**ref, "why": "url TODO"})
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
        key = f"{ref['entry_id']}|{ref['url']}"
        t0 = time.time()
        try:
            status, raw = fetch(ref["url"])
            text = to_text(raw)
            h = fingerprint(text)
            changed = prev.get(key) != h
            fname = f"{ref['entry_id']}--{hashlib.md5(ref['url'].encode()).hexdigest()[:6]}.md"
            if changed:
                (snap_dir / fname).write_text(
                    f"---\nentry_id: {ref['entry_id']}\nurl: {ref['url']}\nfetched_at: {NOW.isoformat()}\n"
                    f"hash: {h}\ntrust: {ref['trust']}\n---\n\n{text}\n", encoding="utf-8")
            return {**ref, "ok": True, "http": status, "hash": h, "changed": changed,
                    "first_seen": key not in seen, "snapshot": fname if changed else None,
                    "chars": len(text), "secs": round(time.time() - t0, 1)}
        except Exception as ex:
            return {**ref, "ok": False, "error": str(ex)[:300], "secs": round(time.time() - t0, 1)}

    with ThreadPoolExecutor(max_workers=a.workers) as pool:
        results = list(pool.map(work, jobs))

    new_state = dict(prev)
    for r in results:
        key = f"{r['entry_id']}|{r['url']}"
        if r["ok"]:
            new_state[key] = r["hash"]
        if db:
            fields = {"last_checked_at": NOW.isoformat()}
            fields.update({"last_hash": r["hash"], "last_error": None} if r["ok"]
                          else {"last_error": r["error"]})
            if r["ok"] and r["changed"]:
                fields["last_changed_at"] = NOW.isoformat()
            db.record(r["entry_id"], r["url"], fields)
    if not db:
        local_state_path.write_text(json.dumps(new_state, indent=1))

    changed = [r for r in results if r["ok"] and r["changed"]]
    failed = [r for r in results if not r["ok"]]
    report = {"mode": "write" if db else "dry-run", "at": NOW.isoformat(), "run_dir": str(run_dir),
              "fetched": len(results), "changed": changed, "failed": failed,
              "unchanged": [r["entry_id"] for r in results if r["ok"] and not r["changed"]],
              "agent_tasks": agent_tasks, "skipped": skipped}
    (run_dir / "report.json").write_text(json.dumps(report, indent=1))

    print(f"[{report['mode']}] fetched {len(results)} | changed {len(changed)} | "
          f"failed {len(failed)} | agent tasks {len(agent_tasks)} | skipped {len(skipped)}")
    for r in changed:
        print(f"  CHANGED {r['entry_id']} {'(first seen) ' if r['first_seen'] else ''}-> snapshots/{r['snapshot']}")
    for r in failed:
        print(f"  FAILED  {r['entry_id']} {r['url']}: {r['error']}")
    for t in agent_tasks:
        print(f"  SEARCH  {t['entry_id']}: \"{t['query']}\" site:{t['site']}")
    print(f"report: {run_dir / 'report.json'}")


if __name__ == "__main__":
    main()
