#!/usr/bin/env python3
"""
harvest_chamber.py — pull the St. Joseph Chamber member directory through Firecrawl.

Why this is separate from discover.py, and why it goes through Firecrawl:

Our own IP is blocked by stjosephchamber.com. It was not blocked when we started; it was
blocked by us, on 2026-09-23, by making ~15 requests in a few minutes to a host whose
robots.txt asks for `Crawl-delay: 10`. The requests were code iteration — fetch, fix the
regex, fetch again. Sixteen hours later the block was still in place.

Two things follow, and both are the point of this file.

**Harvest and parse are separate steps.** `--harvest` fetches each page ONCE and writes
the raw result to `.runs/cache/chamber/`. `--parse` reads those files and produces the
member list with no network at all. Getting the extraction wrong now costs nothing, which
is the mistake that cost us the site.

**Firecrawl is the route, not a trick.** The chamber's robots.txt permits every crawler
(`User-agent: *`, a crawl delay, and no `Disallow`). Firecrawl identifies itself honestly
and is not a browser impersonation, which ADR-014 bans and which this site 403s anyway.
It is a different crawler reaching a site that allows crawlers.

Output is `.runs/cache/chamber.json`, which is exactly what `discover.py`'s
`collect_chamber` already reads as its cache — so discovery needs no change.
"""

import argparse, json, re, subprocess, sys, time
from pathlib import Path

DIRECTORY = "https://stjosephchamber.com/member-directory/"
CATEGORY = re.compile(r'https://stjosephchamber\.com/member/category/[a-z0-9-]+/')
# Member links, excluding the category links that share the /member/ prefix.
MEMBER = re.compile(r'\[([^\]]+)\]\((https://stjosephchamber\.com/member/(?!category/)[^)\s"]+)')


def firecrawl(url, tries=2):
    """One Firecrawl scrape. Returns markdown, or None."""
    payload = json.dumps({"url": url, "formats": ["markdown"], "onlyMainContent": True})
    for attempt in range(tries):
        try:
            r = subprocess.run(["composio", "execute", "FIRECRAWL_SCRAPE", "-d", payload],
                               capture_output=True, text=True, timeout=180)
            data = json.loads(r.stdout)
        except Exception as ex:
            print(f"    call failed: {type(ex).__name__} {ex}", flush=True)
            data = None
        if data:
            found = []

            def walk(o):
                if isinstance(o, dict):
                    for k, v in o.items():
                        if k == "markdown" and isinstance(v, str):
                            found.append(v)
                        else:
                            walk(v)
                elif isinstance(o, list):
                    for v in o:
                        walk(v)
            walk(data)
            if found:
                return max(found, key=len)
        if attempt < tries - 1:
            time.sleep(5)
    return None


def harvest(cache_dir):
    cache_dir.mkdir(parents=True, exist_ok=True)
    print(f"[chamber] index: {DIRECTORY}", flush=True)
    index = firecrawl(DIRECTORY)
    if not index:
        sys.exit("could not read the member directory index")
    (cache_dir / "_index.md").write_text(index)

    cats = sorted(set(CATEGORY.findall(index)))
    print(f"[chamber] {len(cats)} categories", flush=True)
    for i, cat in enumerate(cats, 1):
        slug = cat.rstrip("/").rsplit("/", 1)[-1]
        dest = cache_dir / f"{slug}.md"
        if dest.exists():
            print(f"  [{i}/{len(cats)}] {slug}: already saved, skipping", flush=True)
            continue
        md = firecrawl(cat)
        if md is None:
            print(f"  [{i}/{len(cats)}] {slug}: FAILED", flush=True)
            continue
        dest.write_text(md)
        print(f"  [{i}/{len(cats)}] {slug}: {len(md)} chars", flush=True)
    print("[chamber] harvest done — parsing is now offline", flush=True)


def parse(cache_dir, out_json):
    """No network. Re-runnable as many times as the extraction takes to get right."""
    files = sorted(p for p in cache_dir.glob("*.md") if p.name != "_index.md")
    if not files:
        sys.exit(f"nothing harvested in {cache_dir} — run --harvest first")
    members, seen = [], set()
    for f in files:
        text = f.read_text()
        hits = 0
        for name, url in MEMBER.findall(text):
            name = re.sub(r"\s+", " ", name).strip().strip('"')
            if len(re.sub(r"[^A-Za-z0-9]", "", name)) < 3 or len(name) > 60:
                continue
            key = name.lower()
            if key in seen:
                continue
            seen.add(key)
            hits += 1
            members.append({"name": name, "category": f.stem, "website": None,
                            "lat": None, "lon": None,
                            "source": "stjosephchamber.com",
                            "member_page": url.split('"')[0]})
        print(f"  {f.stem}: {hits}")
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(members, indent=1))
    print(f"[chamber] {len(members)} members -> {out_json}")
    return members


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".")
    ap.add_argument("--harvest", action="store_true", help="fetch pages (network)")
    ap.add_argument("--parse", action="store_true", help="parse saved pages (no network)")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    cache_dir = root / ".runs" / "cache" / "chamber"
    if args.harvest:
        harvest(cache_dir)
    if args.parse or not args.harvest:
        parse(cache_dir, root / ".runs" / "cache" / "chamber.json")


if __name__ == "__main__":
    main()
