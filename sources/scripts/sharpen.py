#!/usr/bin/env python3
"""
sharpen.py: a flyer too small for the card, made clear to read (BP app event-photos 19; Jesse, 2026-11-13, on Apollo's
379 px SpongeBob poster: "can you make it clear to read", then "add it to automating events").

The flyer goes 4x through Real-ESRGAN's anime model (made for flat art and lettering), which redraws big words crisp.
Text only a few pixels tall at the source comes out re-lettered with made-up words ("Dnlod on mo torlo" for "Based on
the series"), so a text finder marks each line shorter than FINE_PX and those lines are blended back from a plain
enlargement: soft, but the words the flyer has. Both models run on onnxruntime's CPU, on a Mac or in the cloud:
sources/models/weights/ (realesrgan-x4plus-anime.onnx from Real-ESRGAN's own weights, convert_realesrgan.py there;
text-lines.onnx, PaddleOCR's PP-OCRv4 text detector as RapidOCR ships it, Apache-2.0). onnxruntime is the morning's
library only (ci-packages.txt "-"; numpy every routine's): without them `sharpen` answers None and the flyer waits.

  python3 sources/scripts/sharpen.py <picture> <out.png>
  python3 sources/scripts/sharpen.py --selftest
"""
import sys
from pathlib import Path

WEIGHTS = Path(__file__).resolve().parent.parent / "models" / "weights"
FINE_PX = 13      # a text line under this tall at the source, padded as found, comes out re-lettered (the SpongeBob
                  # poster's credits were 9 to 12 px, its dates and prices 14 and up)
TILE, OVERLAP = 192, 12  # the 4x model runs a tile at a time: the whole of a 1000 px flyer would want gigabytes
LONG_SIDE = 1600  # as place_photos.save_picture keeps a picture
PLAIN_FROM = 700  # a flyer this wide reads as it is in the card; the 4x model on it took 57 s of an M4's CPU at
                  # 999 px, minutes on the cloud's, and 4 s at the poster's 379
_sessions = {}


def session(name):
    import onnxruntime as ort
    if name not in _sessions:
        _sessions[name] = ort.InferenceSession(str(WEIGHTS / name), providers=["CPUExecutionProvider"])
    return _sessions[name]


def upscale(rgb):
    """rgb: an H x W x 3 float array, 0..1. Its 4x, a tile at a time, each tile run with OVERLAP of its neighbours
    so no seam shows."""
    import numpy as np
    h, w, _ = rgb.shape
    out = np.zeros((h * 4, w * 4, 3), np.float32)
    run = session("realesrgan-x4plus-anime.onnx")
    for y in range(0, h, TILE):
        for x in range(0, w, TILE):
            y0, x0, y1, x1 = max(y - OVERLAP, 0), max(x - OVERLAP, 0), min(y + TILE + OVERLAP, h), min(x + TILE + OVERLAP, w)
            got = run.run(None, {"image": rgb[y0:y1, x0:x1].transpose(2, 0, 1)[None].copy()})[0][0].transpose(1, 2, 0)
            ty, tx = min(y + TILE, h), min(x + TILE, w)
            out[y * 4:ty * 4, x * 4:tx * 4] = got[(y - y0) * 4:(ty - y0) * 4, (x - x0) * 4:(tx - x0) * 4]
    return np.clip(out, 0, 1)


def blobs(rows):
    """Each 4-connected patch of True in rows (a list of lists of bool) as (x0, y0, x1, y1), ends included. Rows are
    read as runs, so a text map's few thousand runs label fast in plain Python."""
    parent, boxes, prev = {}, {}, []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for y, row in enumerate(rows):
        runs, x, n = [], 0, len(row)
        while x < n:
            if row[x]:
                s = x
                while x < n and row[x]:
                    x += 1
                k = len(parent)
                parent[k] = k
                boxes[k] = [s, y, x - 1, y]
                for (ps, pe, pk) in prev:
                    if ps <= x - 1 and pe >= s:
                        a, b = find(pk), find(k)
                        if a != b:
                            parent[b] = a
                runs.append((s, x - 1, k))
            x += 1
        prev = runs
    merged = {}
    for k, (x0, y0, x1, y1) in boxes.items():
        r = find(k)
        m = merged.setdefault(r, [x0, y0, x1, y1])
        m[0], m[1], m[2], m[3] = min(m[0], x0), min(m[1], y0), max(m[2], x1), max(m[3], y1)
    return [tuple(m) for m in merged.values()]


def fine_print(im):
    """The boxes (x0, y0, x1, y1, the source's pixels) of each text line shorter than FINE_PX. The detector marks a
    line's middle; its own clean-up grows that by 0.8 of the mark's height on every side (DBNet's unclip, ratio 1.6),
    so a line is 2.6 marks tall. It reads a 2x copy: tiny text hides at 1x."""
    import numpy as np
    from PIL import Image
    k = max(1.0, min(2.0, LONG_SIDE / max(im.size)))
    w, h = (max(32, round(im.width * k / 32) * 32), max(32, round(im.height * k / 32) * 32))
    bgr = np.asarray(im.convert("RGB").resize((w, h), Image.LANCZOS), np.float32)[:, :, ::-1] / 255
    x = ((bgr - (0.485, 0.456, 0.406)) / (0.229, 0.224, 0.225)).astype(np.float32).transpose(2, 0, 1)[None]
    text = session("text-lines.onnx").run(None, {"x": x})[0][0, 0] > 0.3
    sx, sy = im.width / w, im.height / h
    out = []
    for x0, y0, x1, y1 in blobs(text.tolist()):
        mark = (y1 - y0 + 1) * sy
        if mark * 2.6 < FINE_PX:
            pad = mark * 0.8 + 1
            out.append((x0 * sx - pad, y0 * sy - pad, (x1 + 1) * sx + pad, (y1 + 1) * sy + pad))
    return out


def sharpen(im):
    """A PIL image 4x and clear (at most LONG_SIDE), its fine print soft; one PLAIN_FROM wide or LONG_SIDE long as it
    is; None when this Python can't run the models."""
    if im.width >= PLAIN_FROM or max(im.size) >= LONG_SIDE:  # reads as it is; for a tall one the 4x would be thrown away
        return im
    try:
        import numpy as np
        import onnxruntime  # noqa: F401
    except ImportError:
        return None
    from PIL import Image, ImageDraw, ImageFilter
    rgb = im.convert("RGB")
    sharp = Image.fromarray((upscale(np.asarray(rgb, np.float32) / 255) * 255).round().astype(np.uint8))
    mask = Image.new("L", sharp.size, 0)
    for x0, y0, x1, y1 in fine_print(rgb):
        ImageDraw.Draw(mask).rectangle((x0 * 4, y0 * 4, x1 * 4, y1 * 4), fill=255)
    out = Image.composite(rgb.resize(sharp.size, Image.LANCZOS), sharp, mask.filter(ImageFilter.GaussianBlur(6)))
    out.thumbnail((LONG_SIDE, LONG_SIDE), Image.LANCZOS)
    return out


def selftest():
    ok = 0

    def check(cond, what):
        nonlocal ok
        if not cond:
            sys.exit(f"selftest failed: {what}")
        ok += 1
    T, F = True, False
    check(sorted(blobs([[T, T, F, F, T],
                        [F, T, F, F, T],
                        [F, F, F, F, F],
                        [T, F, T, T, T]])) == [(0, 0, 1, 1), (0, 3, 0, 3), (2, 3, 4, 3), (4, 0, 4, 1)],
          "each touching patch is one box, a gap row or column parts them")
    check(blobs([[T, F, T], [T, T, T]]) == [(0, 0, 2, 1)], "a U joins at its foot")
    check((WEIGHTS / "realesrgan-x4plus-anime.onnx").stat().st_size > 17_000_000
          and (WEIGHTS / "text-lines.onnx").stat().st_size > 4_000_000, "both models are in the repo")
    print(f"sharpen.py selftest: {ok} passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif len(sys.argv) == 3:
        from PIL import Image
        got = sharpen(Image.open(sys.argv[1]))
        sys.exit("sharpen.py: needs numpy and onnxruntime (python3 sources/scripts/ready.py morning)") if got is None \
            else (got.save(sys.argv[2]), print(f"{sys.argv[2]}: {got.width}x{got.height}"))
    else:
        print(__doc__)
