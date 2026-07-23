#!/usr/bin/env python3
"""Render the approved place-logos into captioned montage PNGs for the vision-
verification pass: each tile shows the 256px logo, a 26px circular pin preview
(what the map badge actually crops to), the business name, and the row uuid's
first 8 chars so verdicts can be keyed back to rows."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "place-logos"
APPROVED = OUT / "approved"

TILE_W, TILE_H = 220, 260
COLS, ROWS = 4, 5   # 20 tiles per montage


def entries() -> list[dict]:
    by_id: dict[str, dict] = {}
    for mf in sorted(OUT.glob("manifest*.json")):
        for e in json.loads(mf.read_text()):
            if e.get("status") == "chosen":
                prev = by_id.get(e["id"])
                # keep the one with a name (batch manifests) over imports
                if prev is None or (prev.get("name") is None and e.get("name")):
                    by_id[e["id"]] = {**(prev or {}), **e}
    named = {e["id"]: e.get("name") for mf in OUT.glob("manifest-[0-9].json")
             for e in json.loads(mf.read_text())}
    for uid, e in by_id.items():
        if not e.get("name"):
            e["name"] = named.get(uid) or uid[:8]
    out = [e for e in by_id.values() if (APPROVED / f"{e['id']}.png").exists()]
    out.sort(key=lambda e: (e["name"] or "").lower())
    return out


def circle_crop(img: Image.Image, d: int) -> Image.Image:
    img = img.resize((d, d), Image.LANCZOS)
    mask = Image.new("L", (d, d), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, d, d), fill=255)
    out = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    out.paste(img, mask=mask)
    return out


def main() -> None:
    es = entries()
    per = COLS * ROWS
    for m in range(0, len(es), per):
        chunk = es[m:m + per]
        sheet = Image.new("RGB", (COLS * TILE_W, ((len(chunk) + COLS - 1) // COLS) * TILE_H), (246, 245, 242))
        draw = ImageDraw.Draw(sheet)
        for i, e in enumerate(chunk):
            x, y = (i % COLS) * TILE_W, (i // COLS) * TILE_H
            logo = Image.open(APPROVED / f"{e['id']}.png").convert("RGB")
            big = ImageOps.contain(logo, (150, 150))
            sheet.paste(big, (x + 35, y + 12))
            pin = circle_crop(logo, 52)   # 26pt @2x — the real map crop
            sheet.paste(pin, (x + 84, y + 168), pin)
            draw.ellipse((x + 84, y + 168, x + 136, y + 220), outline=(180, 178, 172), width=2)
            name = (e["name"] or "")[:30]
            draw.text((x + 8, y + 224), f"{e['id'][:8]}  {name}", fill=(40, 40, 40))
        n = m // per
        path = OUT / f"montage-{n}.png"
        sheet.save(path)
        print(f"{path}  ({len(chunk)} tiles)")


if __name__ == "__main__":
    main()
