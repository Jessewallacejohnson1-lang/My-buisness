#!/usr/bin/env python3
"""
fetch_place_logos.py — find + normalize brand logos for map POIs.

For each row in Supabase `places`, resolve the business's website (Google Places
details for real ChIJ* ids, text search for synthetic hygge-stjoe-* ids), then walk
a candidate ladder on the site itself:

    apple-touch-icon → square-ish og:image → largest <link rel=icon> → /favicon.ico
    → Google favicon service (sz=256; upscaled-default-globe rejected)

Candidates are auto-filtered (min 96px source, aspect ≤ 2.5:1 after trim, not
near-blank) and normalized: trim uniform border → pad square with a 12% white
margin → 256×256 PNG in build/place-logos/approved/{row-uuid}.png. Every attempt
is recorded in build/place-logos/manifest[-N].json for the vision-verification
pass. Only the business's OWN assets are stored — Google Places content is used
transiently for website resolution and never persisted (ToS).

Usage:
    python3 scripts/fetch_place_logos.py                 # whole roster
    python3 scripts/fetch_place_logos.py --batch 2/8     # rows 2 mod 8 (agent fan-out)
    python3 scripts/fetch_place_logos.py --ids UUID ...  # specific rows
    python3 scripts/fetch_place_logos.py --contact-sheet # regenerate HTML sheet only

Keys are parsed from the gitignored Swift config files (same trick as
review_park_photos.py) — nothing secret lands in this script or the manifest.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "place-logos"
APPROVED = OUT / "approved"
CANDIDATES = OUT / "candidates"

MIN_SOURCE_PX = 96
MAX_ASPECT = 2.5
OUTPUT_PX = 256
MARGIN_FRAC = 0.12
UA = "Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15"
TIMEOUT = 20


def parse_swift_constant(path: Path, pattern: str) -> str:
    m = re.search(pattern, path.read_text())
    if not m:
        sys.exit(f"could not parse key from {path}")
    return m.group(1)


GOOGLE_KEY = parse_swift_constant(
    ROOT / "BlockParty" / "Config" / "GooglePlacesConfig.swift",
    r'"([A-Za-z0-9_\-]{30,})"',
)
SUPABASE_URL = parse_swift_constant(
    ROOT / "BlockParty" / "Backend" / "SupabaseConfig.swift",
    r'"(https://[a-z0-9]+\.supabase\.co)"',
)
SUPABASE_ANON = parse_swift_constant(
    ROOT / "BlockParty" / "Backend" / "SupabaseConfig.swift",
    r'"(eyJ[A-Za-z0-9_\-\.]+)"',
)


def http_get(url: str, headers: dict | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read()


def http_json(url: str, headers: dict | None = None, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={"User-Agent": UA, "Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp)


# ---------- roster ----------

def fetch_roster() -> list[dict]:
    url = f"{SUPABASE_URL}/rest/v1/places?select=id,place_id,name,family&order=name"
    rows = http_json(url, headers={"apikey": SUPABASE_ANON, "Authorization": f"Bearer {SUPABASE_ANON}"})
    return rows


# ---------- website resolution (Google, transient only) ----------

def resolve_website(place: dict) -> str | None:
    pid = place.get("place_id") or ""
    headers = {"X-Goog-Api-Key": GOOGLE_KEY}
    try:
        if pid.startswith("ChIJ"):
            data = http_json(
                f"https://places.googleapis.com/v1/places/{pid}",
                headers={**headers, "X-Goog-FieldMask": "websiteUri,displayName"},
            )
            return data.get("websiteUri")
        # Synthetic id → text search by name, scoped to town.
        data = http_json(
            "https://places.googleapis.com/v1/places:searchText",
            headers={**headers, "X-Goog-FieldMask": "places.websiteUri,places.displayName"},
            body={"textQuery": f"{place['name']} St. Joseph MN", "pageSize": 1},
        )
        places = data.get("places") or []
        return places[0].get("websiteUri") if places else None
    except Exception:
        return None


# ---------- candidate discovery on the site itself ----------

class IconParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.icons: list[tuple[str, int]] = []   # (href, declared size)
        self.og_image: str | None = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "link":
            rel = (a.get("rel") or "").lower()
            href = a.get("href")
            if not href:
                return
            if "apple-touch-icon" in rel:
                self.icons.append((href, 1000))          # best signal, rank first
            elif "icon" in rel:
                size = 0
                m = re.match(r"(\d+)x", a.get("sizes") or "")
                if m:
                    size = int(m.group(1))
                self.icons.append((href, size))
        elif tag == "meta" and (a.get("property") == "og:image" or a.get("name") == "og:image"):
            if a.get("content"):
                self.og_image = a.get("content")


def site_candidates(website: str) -> list[tuple[str, str]]:
    """Ordered (kind, url) candidates for a site."""
    base = website if website.startswith("http") else f"https://{website}"
    parsed = urllib.parse.urlparse(base)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    out: list[tuple[str, str]] = []
    try:
        html = http_get(base).decode("utf-8", "replace")
        p = IconParser()
        p.feed(html)
        icons = sorted(p.icons, key=lambda t: -t[1])
        for href, rank in icons:
            kind = "apple-touch-icon" if rank == 1000 else "link-icon"
            out.append((kind, urllib.parse.urljoin(base, href)))
        if p.og_image:
            out.append(("og-image", urllib.parse.urljoin(base, p.og_image)))
    except Exception:
        pass
    out.append(("favicon.ico", f"{origin}/favicon.ico"))
    out.append(("google-favicon", f"https://www.google.com/s2/favicons?domain={parsed.netloc}&sz=256"))
    return out


# ---------- filtering + normalization ----------

def load_image(data: bytes) -> Image.Image | None:
    try:
        img = Image.open(io.BytesIO(data))
        if getattr(img, "n_frames", 1) > 1:          # .ico — pick the largest frame
            best, best_px = None, 0
            for i in range(img.n_frames):
                img.seek(i)
                if img.size[0] * img.size[1] > best_px:
                    best_px = img.size[0] * img.size[1]
                    best = img.copy()
            img = best
        return img.convert("RGBA")
    except Exception:
        return None


def flatten_white(img: Image.Image) -> Image.Image:
    bg = Image.new("RGB", img.size, (255, 255, 255))
    bg.paste(img, mask=img.split()[3])
    return bg


def trim_uniform_border(img: Image.Image) -> Image.Image:
    bg = Image.new("RGB", img.size, img.getpixel((0, 0)))
    diff = ImageChops.difference(img, bg)
    bbox = diff.getbbox()
    return img.crop(bbox) if bbox else img


def reject_reason(img: Image.Image, kind: str) -> str | None:
    w, h = img.size
    if min(w, h) < MIN_SOURCE_PX:
        return f"too small ({w}x{h})"
    trimmed = trim_uniform_border(img)
    tw, th = trimmed.size
    if tw == 0 or th == 0:
        return "blank"
    aspect = max(tw, th) / max(1, min(tw, th))
    if kind == "og-image" and aspect > 1.6:
        return f"og:image not square-ish ({tw}x{th})"
    if aspect > MAX_ASPECT:
        return f"extreme aspect ({tw}x{th})"
    grey = trimmed.convert("L")
    lo, hi = grey.getextrema()
    if hi - lo < 12:
        return "near-blank (no contrast)"
    return None


def normalize(img: Image.Image) -> Image.Image:
    img = trim_uniform_border(img)
    w, h = img.size
    side = max(w, h)
    margin = int(side * MARGIN_FRAC)
    canvas = Image.new("RGB", (side + 2 * margin, side + 2 * margin), (255, 255, 255))
    canvas.paste(img, (margin + (side - w) // 2, margin + (side - h) // 2))
    return canvas.resize((OUTPUT_PX, OUTPUT_PX), Image.LANCZOS)


# ---------- per-place ----------

def process_place(place: dict) -> dict:
    entry = {
        "id": place["id"],
        "place_id": place.get("place_id"),
        "name": place["name"],
        "family": place.get("family"),
        "website": None,
        "attempts": [],
        "status": "missing",
        "source_url": None,
        "candidate": None,
        "source_px": None,
    }
    website = resolve_website(place)
    entry["website"] = website
    if not website:
        entry["attempts"].append({"kind": "resolve-website", "reason": "no websiteUri"})
        return entry
    if "facebook.com" in website or "instagram.com" in website:
        # Social-only presence: the scripted ladder can't fetch profile pictures
        # reliably; left for the agent's targeted hunt.
        entry["attempts"].append({"kind": "social-only", "reason": website})
        return entry

    for kind, url in site_candidates(website):
        att = {"kind": kind, "url": url}
        try:
            data = http_get(url)
        except Exception as e:
            att["reason"] = f"fetch failed: {e.__class__.__name__}"
            entry["attempts"].append(att)
            continue
        if kind == "google-favicon" and len(data) < 1200:
            att["reason"] = "default-globe (tiny payload)"
            entry["attempts"].append(att)
            continue
        img = load_image(data)
        if img is None:
            att["reason"] = "not decodable"
            entry["attempts"].append(att)
            continue
        att["source_px"] = f"{img.size[0]}x{img.size[1]}"
        flat = flatten_white(img)
        reason = reject_reason(flat, kind)
        if reason:
            att["reason"] = reason
            entry["attempts"].append(att)
            # keep rejected candidates on disk for the vision pass / retries
            CANDIDATES.mkdir(parents=True, exist_ok=True)
            try:
                flat.save(CANDIDATES / f"{place['id']}-{kind}.png")
            except Exception:
                pass
            continue
        APPROVED.mkdir(parents=True, exist_ok=True)
        normalize(flat).save(APPROVED / f"{place['id']}.png")
        att["reason"] = "chosen"
        entry["attempts"].append(att)
        entry["status"] = "chosen"
        entry["source_url"] = url
        entry["candidate"] = kind
        entry["source_px"] = att["source_px"]
        break
    return entry


# ---------- contact sheet ----------

def contact_sheet(manifests: list[Path]) -> None:
    entries = []
    for m in manifests:
        entries.extend(json.loads(m.read_text()))
    entries.sort(key=lambda e: (e.get("name") or "").lower())
    tiles = []
    for e in entries:
        png = APPROVED / f"{e['id']}.png"
        if e["status"] != "chosen" or not png.exists():
            continue
        tiles.append(f"""
        <div class="tile" id="{e['id']}">
          <img class="big" src="approved/{e['id']}.png">
          <div class="pin"><img src="approved/{e['id']}.png"></div>
          <div class="name">{e['name']}</div>
          <div class="src">{e['candidate']} · {e.get('source_px') or ''}</div>
        </div>""")
    html = f"""<!doctype html><meta charset="utf-8">
    <style>
      body {{ font: 13px -apple-system, sans-serif; background:#f6f5f2; margin:24px; }}
      .grid {{ display:grid; grid-template-columns:repeat(4, 1fr); gap:20px; }}
      .tile {{ background:#fff; border:1px solid #ddd; border-radius:12px; padding:14px; text-align:center; }}
      .big {{ width:160px; height:160px; border:1px solid #eee; border-radius:8px; }}
      .pin {{ width:26px; height:26px; border-radius:50%; overflow:hidden; border:1.5px solid #c9c6c0;
             margin:8px auto; }}
      .pin img {{ width:26px; height:26px; }}
      .name {{ font-weight:600; margin-top:4px; }}
      .src {{ color:#888; font-size:11px; }}
    </style>
    <h2>place-logos — {len(tiles)} chosen of {len(entries)} places</h2>
    <div class="grid">{''.join(tiles)}</div>"""
    (OUT / "contact_sheet.html").write_text(html)
    print(f"contact sheet: {OUT / 'contact_sheet.html'} ({len(tiles)} tiles)")


# ---------- main ----------

def import_candidate(uuid: str, src: str, kind: str) -> None:
    """Agent-found logo (URL or local file) through the same filter + normalize path."""
    data = http_get(src) if src.startswith("http") else Path(src).read_bytes()
    img = load_image(data)
    if img is None:
        sys.exit(f"[rejected] {uuid}: not decodable")
    flat = flatten_white(img)
    reason = reject_reason(flat, kind)
    if reason:
        sys.exit(f"[rejected] {uuid}: {reason}")
    APPROVED.mkdir(parents=True, exist_ok=True)
    normalize(flat).save(APPROVED / f"{uuid}.png")
    # One file per import — parallel agents never contend on a shared manifest.
    out = OUT / f"manifest-import-{uuid}.json"
    out.write_text(json.dumps([{
        "id": uuid, "name": None, "status": "chosen", "candidate": kind,
        "source_url": src if src.startswith("http") else f"file:{src}",
        "source_px": f"{img.size[0]}x{img.size[1]}", "attempts": [],
    }], indent=2))
    print(f"[chosen ] {uuid} ({kind}, {img.size[0]}x{img.size[1]})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", help="i/n — process rows where index %% n == i")
    ap.add_argument("--ids", nargs="*", help="specific place row uuids")
    ap.add_argument("--contact-sheet", action="store_true", help="regenerate sheet only")
    ap.add_argument("--import", dest="import_args", nargs=2, metavar=("UUID", "URL_OR_PATH"),
                    help="run an agent-found logo through the same filter+normalize path")
    ap.add_argument("--kind", default="agent-hunt", help="source label for --import")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    if args.import_args:
        import_candidate(args.import_args[0], args.import_args[1], args.kind)
        return
    if args.contact_sheet:
        contact_sheet(sorted(OUT.glob("manifest*.json")))
        return

    roster = fetch_roster()
    suffix = ""
    if args.ids:
        roster = [p for p in roster if p["id"] in set(args.ids)]
        suffix = "-ids"
    elif args.batch:
        i, n = (int(x) for x in args.batch.split("/"))
        roster = [p for k, p in enumerate(roster) if k % n == i]
        suffix = f"-{i}"

    results = []
    for place in roster:
        entry = process_place(place)
        results.append(entry)
        print(f"[{entry['status']:7}] {entry['name']}  ({entry.get('candidate') or entry['attempts'][-1].get('reason','') if entry['attempts'] else ''})")

    out = OUT / f"manifest{suffix}.json"
    out.write_text(json.dumps(results, indent=2))
    chosen = sum(1 for r in results if r["status"] == "chosen")
    print(f"\n{chosen}/{len(results)} chosen → {out}")


if __name__ == "__main__":
    main()
