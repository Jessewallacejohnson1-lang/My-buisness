#!/usr/bin/env python3
"""Run the source registry: validate -> sync -> fetch -> hash -> report.

Dry-run is the default (ADR-009): fetches for real, writes nothing to Supabase,
keeps local state in .runs/state.json so repeat test runs still show changes.
--write syncs md -> `sources` table and stores runtime state in Supabase.

Usage:
  python3 run.py                      # dry-run, active entries
  python3 run.py --only krewe         # one entry
  python3 run.py --town st-joseph-mn  # one town
  python3 run.py --include-proposed   # also test proposed entries (never with --write)
  python3 run.py --write              # prod: needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
"""
import argparse, hashlib, html, json, os, re, sys, time
import urllib.request, urllib.robotparser, urllib.error, urllib.parse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).parent))
from registry import find_root, load, validate, is_todo

UA = "BlockPartyBot/1.0 (+https://blockpartystjoe.com)"
MAX_BYTES = 2_000_000
TIMEOUT = 20
NOW = datetime.now(timezone.utc)


def to_text(raw):
    """HTML -> plain text good enough for hashing + an LLM reading the snapshot."""
    s = re.sub(r"(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\1>", " ", raw)
    s = re.sub(r"(?i)<br\s*/?>|</(p|div|li|h[1-6]|tr|section|article)>", "\n", s)
    s = re.sub(r"(?s)<[^>]+>", " ", s)
    s = html.unescape(s)
    lines = [re.sub(r"[ \t\r\f\v]+", " ", ln).strip() for ln in s.split("\n")]
    return "\n".join(ln for ln in lines if ln)


_robots = {}
def robots_ok(url):
    p = urlparse(url)
    base = f"{p.scheme}://{p.netloc}"
    if base not in _robots:
        rp = urllib.robotparser.RobotFileParser(base + "/robots.txt")
        try:
            rp.read()
        except Exception:
            rp = None  # unreachable robots.txt -> treat as allowed
        _robots[base] = rp
    rp = _robots[base]
    return rp is None or rp.can_fetch(UA, url)


def fetch(url):
    if not robots_ok(url):
        raise RuntimeError("robots.txt disallows -> switch method to search_snippet")
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,*/*"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        body = r.read(MAX_BYTES + 1)
        if len(body) > MAX_BYTES:
            body = body[:MAX_BYTES]
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
                     "Is the sources table migrated? See references/sources-table.sql")

    def upsert_registry(self, rows):
        self.call("POST", "sources?on_conflict=entry_id,url", rows,
                  prefer="resolution=merge-duplicates,return=minimal")

    def state(self):
        rows = self.call("GET", "sources?select=entry_id,url,last_hash") or []
        return {f"{r['entry_id']}|{r['url']}": r.get("last_hash") for r in rows}

    def record(self, entry_id, url, fields):
        q = f"sources?entry_id=eq.{entry_id}&url=eq.{urllib.parse.quote(url, safe='')}"
        self.call("PATCH", q, fields, prefer="return=minimal")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--include-proposed", action="store_true")
    ap.add_argument("--only", help="entry id")
    ap.add_argument("--town", help="e.g. st-joseph-mn")
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
              and (not a.town or e["_town"] == a.town)]
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
        prev = db.state()
        print(f"synced {len(rows)} source rows")
    else:
        prev = json.loads(local_state_path.read_text()) if local_state_path.exists() else {}

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
            h = hashlib.sha256(text.encode()).hexdigest()
            changed = prev.get(key) != h
            fname = f"{ref['entry_id']}--{hashlib.md5(ref['url'].encode()).hexdigest()[:6]}.md"
            if changed:
                (snap_dir / fname).write_text(
                    f"---\nentry_id: {ref['entry_id']}\nurl: {ref['url']}\nfetched_at: {NOW.isoformat()}\n"
                    f"hash: {h}\ntrust: {ref['trust']}\n---\n\n{text}\n", encoding="utf-8")
            return {**ref, "ok": True, "http": status, "hash": h, "changed": changed,
                    "first_seen": key not in prev, "snapshot": fname if changed else None,
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
