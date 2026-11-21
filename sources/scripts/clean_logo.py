#!/usr/bin/env python3
"""
clean_logo.py: the team logo recipe (BP app game-card 25-29), on the logo module's steps (logo.py, BP app
logo-cutouts 06). A team logo stands bare on a game's page and casts a shadow on the game card (game-card 26), so a
logo that is a white box shows its box. The morning's `team_logos.py keep` runs each new team's logo through `clean`;
BP app's teams.py runs every team's through `process`, with its per-team exceptions (`ex`). One recipe, both places.

- A white box is cut off, keeping every white the logo encloses (a badge's white fill, its white letters). When the
  cut takes nothing, a grey frame round the box may be holding the white in: 4 px are trimmed and the cut tried again.
- A coloured box is the logo's own, left whole.
- Then the pale fringe and stray specks go, any white or light grey band 3 px wide or more is put back (an outline
  the logo draws), it goes to 512 px on its long side, and it is lit like the Search logos unless it is mostly
  hairlines (lit, its shine would be wider than its strokes).
- A file under 240 px on its long side is drawn at 4x first (game-card 29) by logo.x4: a boxed file on white, then cut
  as above; a file already cut out has its colour (bled under the see-through) and its alpha drawn at 4x apart and put
  together, with no cut.

  python3 sources/scripts/clean_logo.py --selftest
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import logo  # noqa: E402  (cut, clean, enamel, thin_share, x4: the one logo module)

SMALL = 240  # 80 pt at 3x: a file under this on its long side is drawn at 4x first (game-card 25's, 29)
OUT = 512    # the long side a cleaned logo goes live at
TRIM = 4     # a grey hairline frame that stops the cut: this many px trimmed (at the work size)
BIG = 1024   # a boxed file is cut at this long side at most (as logo.make: twice the 512 it ships at)
KEEP = "all"  # every white the logo encloses stays
THIN = 0.7   # over this share of its ink within 3 px of an edge, a logo ships as drawn, not lit


def clean(im):
    """The recipe on one new team's logo: (the logo to put live, what was done, in words). Raises ValueError when the
    cut leaves nothing, so the team waits rather than taking a blank."""
    r = process(im.convert("RGBA"))
    if "final" not in r:
        raise ValueError(r["flags"][0])
    return r["final"], r["done"] + r["flags"]


def process(live, ex=None):
    """The recipe on one logo, with a team's exceptions `ex` (BP app teams.py EXCEPTIONS: keep, hull, white,
    letter_holes, specks, clean, lit, pad). A dict: bare (512, before the lit look), final, done and flags in words,
    and how the new file maps back onto the one it came from (work size, scale k, crop box) for teams.py's checks;
    with nothing left after the cut, only done and flags."""
    ex = ex or {}
    live = live.convert("RGBA")
    done, flags = [], []
    box = boxed(live)
    im, k = live, 1.0
    if max(live.size) < SMALL:
        big = x4(live) if ex.get("white") or box else x4_apart(live)  # on white at 4x and cut: its white inside stays
        if big is None:
            done.append(f"not drawn at 4x: under {SMALL} px ({max(live.size)}), and no Real-ESRGAN here")
        else:
            im, k = big, 4.0
            done.append("drawn at 4x on white" if ex.get("white") else "drawn at 4x")
    elif box and max(im.size) > BIG:
        s = BIG / max(im.size)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        k = s
    work = im.size
    ox = oy = 0
    cut = False
    if ex.get("letter_holes"):
        im, cut = logo.cut(im, keep=False), True
        done.append("letter holes cut")
    elif box or ex.get("white"):
        keep = ex.get("keep", KEEP)
        out = logo.cut(im, keep=keep, hull=ex.get("hull", 0))
        if not went(im, out):  # nothing went: a grey frame may hold the white in
            t = TRIM * (4 if k == 4.0 else 1)
            inner = im.crop((t, t, im.width - t, im.height - t))
            cut_inner = logo.cut(inner, keep=keep)
            if went(inner, cut_inner):
                out, ox, oy = cut_inner, t, t
                done.append("frame trimmed")
        if went(im, out) or k == 4.0 and cover(out) < 0.95:  # a 4x on white is all opaque, so any cut counts
            im, cut = out, True
            if box:
                done.append("cut off its white box")
        elif box == "white":
            flags.append("still a box: the cut removed nothing")
        elif box == "coloured":
            done.append("own coloured box, left whole")
    if ex.get("specks"):
        a = np.asarray(im).copy()
        ink = a[..., 3] > 24
        share = ex["specks"] if isinstance(ex["specks"], float) else 0.001
        for part in logo.parts_of(ink):
            if part.sum() < share * ink.sum():
                a[logo.grow(logo.grow(part)), 3] = 0
        im = Image.fromarray(a, "RGBA")
        done.append("specks dropped")
    bb = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if not bb:
        return {"done": done, "flags": flags + ["nothing left after the cut"]}
    im = im.crop(bb)
    crop = (ox + bb[0], oy + bb[1], ox + bb[2], oy + bb[3])
    s = min(1, OUT / max(im.size))
    if s < 1:
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    detail = max(im.size)  # its long side before any plain stretch (a 4x counts as drawn)
    bare = im if ex.get("clean") is False else keeping_white(im)
    if max(bare.size) < OUT:
        s = OUT / max(bare.size)
        bare = bare.resize((round(bare.width * s), round(bare.height * s)), Image.LANCZOS)
    thin = logo.thin_share(bare)
    lit = ex.get("lit", thin < THIN)
    done.append("lit" if lit else "as drawn" if "lit" in ex else "as drawn: thin")
    final = logo.enamel(bare) if lit else bare
    if ex.get("pad"):
        side = [round(v * ex["pad"]) for v in final.size]
        canvas = Image.new("RGBA", final.size, (0, 0, 0, 0))
        canvas.alpha_composite(final.resize(side, Image.LANCZOS), ((final.width - side[0]) // 2, (final.height - side[1]) // 2))
        final = canvas
        done.append(f"fills {ex['pad']:.0%} of its box")
    return {"bare": bare, "final": final, "done": done, "flags": flags, "work": work, "k": k, "crop": crop,
            "trim": ox, "cut": cut, "detail": round(detail), "thin": round(thin, 3)}


def x4(im):
    """Real-ESRGAN's 4x of the logo on white, as RGBA (logo.x4); None with no engine here."""
    big = logo.x4(logo.on_white(im))
    return big and big.convert("RGBA")


def x4_apart(im):
    """A small file already cut out, drawn at 4x without losing its silhouette: its colour (bled under the
    see-through) and its alpha (as a grey picture) each drawn at 4x, then put together. No cut: on white then cut took
    Lake Forest's white outlines and filled Minneapolis North's ring (game-card 25)."""
    colour = x4(bleed(im))
    if colour is None:
        return None
    grey = im.getchannel("A")
    alpha = x4(Image.merge("RGBA", (grey, grey, grey, Image.new("L", im.size, 255)))).convert("L")
    return Image.merge("RGBA", (*colour.split()[:3], alpha))


def bleed(im):
    """The colour under the see-through pixels: each takes the colour of the ink nearest it, widening until every
    pixel has one, so a 4x of the colour draws no dark or white rim along the logo's edge."""
    a = np.asarray(im.convert("RGBA"), np.float32) / 255
    al, rgb = a[..., 3], a[..., :3].copy()
    have = al > 0.02
    for s in (1, 2, 4, 8, 16, 32, 64):
        if have.all():
            break
        w = logo.blur(al, s)
        fill = np.stack([logo.blur(a[..., c] * al, s) for c in range(3)], -1) / np.maximum(w, 1e-6)[..., None]
        new = ~have & (w > 1e-4)
        rgb[new], have = fill[new], have | new
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).round().astype(np.uint8), "RGB").convert("RGBA")


def ring(im):
    """Share of the border's pixels that are opaque, and share that are white."""
    w, h = im.size
    px = [im.getpixel((x, y)) for x in range(w) for y in (0, h - 1)] + [im.getpixel((x, y)) for y in range(h) for x in (0, w - 1)]
    return sum(p[3] > 200 for p in px) / len(px), sum(p[3] > 200 and min(p[:3]) > 235 for p in px) / len(px)


def cover(im):
    """Share of the picture that is opaque."""
    hist = im.getchannel("A").histogram()
    return sum(hist[201:]) / (im.width * im.height)


def boxed(im):
    """'white', 'coloured' or None: is the file a box (its border opaque), and of what. A grey hairline frame reads as
    coloured here; the cut then finds the white inside it."""
    opaque, white = ring(im.convert("RGBA"))
    return None if opaque <= 0.5 else "white" if white > 0.5 else "coloured"


def went(before, after):
    """The cut took something off."""
    return cover(after) < min(0.95, cover(before) - 0.02)


def keeping_white(im):
    """logo.clean (every logo gets it), keeping the white the logo draws itself: an opaque white or light grey band
    3 px wide or more is its outline or fill, not the 1-2 px pale fringe an older cut left (clean alone took the
    outline of Delano, Robbinsdale, East Grand Forks, Maple Lake, Montevideo and St. Cloud)."""
    from PIL import ImageFilter
    out = np.asarray(logo.clean(im, 1.0, True)).copy()
    a = np.asarray(im.convert("RGBA"))
    rgb = a[..., :3].astype(np.float32) / 255
    light = (rgb @ np.float32([0.2126, 0.7152, 0.0722]) > 0.75) & (rgb.max(-1) - rgb.min(-1) < 0.1)
    band = Image.fromarray(((a[..., 3] > 200) & light).astype(np.uint8) * 255)
    zone = np.asarray(band.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(7))) > 127
    out[zone] = a[zone]
    return Image.fromarray(out, "RGBA")


# --- Self-test ------------------------------------------------------------------------------------------------------

def badge(frame=False, side=300):
    """A red badge on a white box, with its own white fill and a red mark inside it."""
    im = Image.new("RGBA", (side, side), (255, 255, 255, 255))
    d, u = ImageDraw.Draw(im), side / 300
    d.ellipse([40 * u, 40 * u, 260 * u, 260 * u], fill=(180, 20, 30, 255))
    d.ellipse([80 * u, 80 * u, 220 * u, 220 * u], fill=(255, 255, 255, 255))   # the badge's own white fill
    d.rectangle([140 * u, 120 * u, 160 * u, 180 * u], fill=(180, 20, 30, 255))  # a mark inside it
    if frame:
        d.rectangle([0, 0, side - 1, side - 1], outline=(150, 150, 150, 255))
    return im


def selftest():
    checks = []
    ok = lambda cond, why: checks.append((bool(cond), why))
    big = badge(side=1500)
    r = process(big)
    ok(r["k"] == BIG / 1500 and r["work"] == (BIG, BIG) and r["done"][-2:] == ["cut off its white box", "lit"],
       f"a big boxed file is cut at {BIG} px: {r['k']}, {r['work']}, {r['done']}")
    r = process(badge(), {"lit": False, "pad": 0.8})
    ok(r["done"][-2:] == ["as drawn", "fills 80% of its box"] and r["final"].getchannel("A").getbbox()[0] > 40,
       f"a team's exceptions: not lit, padded: {r['done']}")
    for frame in (False, True):
        out, done = clean(badge(frame))
        a = np.asarray(out)
        mid = a[a.shape[0] // 2, a.shape[1] // 4]  # in the white fill, left of the mark
        ok(out.size == (OUT, OUT) and a[0, 0, 3] == 0 and mid[3] == 255 and mid[:3].min() > 230
           and ("frame trimmed" in done) == frame and done[-2:] == ["cut off its white box", "lit"],
           f"a badge on a white box{' in a grey 1 px frame' if frame else ''} is cut off it, keeps its white fill and "
           f"is lit at {OUT} px: {done}")
    shape = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    ImageDraw.Draw(shape).polygon([(150, 20), (280, 260), (20, 260)], fill=(20, 60, 160, 255))
    out, done = clean(shape)
    ink_ = np.asarray(out.getchannel("A")) > 128
    ok(done == ["lit"] and abs(ink_.mean() - 0.5) < 0.03, f"a logo already cut out keeps its shape: {done}, "
                                                          f"{ink_.mean():.0%} of its square inked")
    coloured = Image.new("RGBA", (300, 300), (20, 40, 120, 255))
    ImageDraw.Draw(coloured).ellipse([90, 90, 210, 210], fill=(255, 255, 255, 255))
    out, done = clean(coloured)
    ok(done[0] == "own coloured box, left whole" and out.getchannel("A").getextrema() == (255, 255),
       f"a coloured box is the logo's own: {done}")
    hairline = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
    ImageDraw.Draw(hairline).ellipse([20, 20, 380, 380], outline=(20, 60, 160, 255), width=3)
    out, done = clean(hairline)
    ok(done == ["as drawn: thin"], f"line art ships as drawn, not lit: {done}")
    global x4
    real, small = x4, badge(side=100)
    try:
        x4 = lambda rgb: None  # no Real-ESRGAN, as on GitHub
        out, done = clean(small)
        ok(max(out.size) == OUT and done[:2] == ["not drawn at 4x: under 240 px (100), and no Real-ESRGAN here",
                                                 "cut off its white box"],
           f"with no Real-ESRGAN a small file is cleaned at its own size, and says so: {done}")
        x4 = lambda rgb: rgb.convert("RGBA").resize((rgb.width * 4, rgb.height * 4), Image.LANCZOS)  # the model's stand-in
        out, done = clean(small)
        a = np.asarray(out)
        mid = a[a.shape[0] // 2, a.shape[1] // 4]
        ok(max(out.size) == OUT and a[0, 0, 3] == 0 and mid[3] == 255 and mid[:3].min() > 230
           and done[:2] == ["drawn at 4x", "cut off its white box"],
           f"a small boxed logo is drawn at 4x, then cut off its box at {OUT} px, its white fill kept: {done}")
        tiny = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        ImageDraw.Draw(tiny).polygon([(50, 7), (93, 87), (7, 87)], fill=(20, 60, 160, 255))
        out, done = clean(tiny)
        ink_ = np.asarray(out.getchannel("A")) > 128
        ok(done[0] == "drawn at 4x" and "cut off its white box" not in done
           and abs(ink_.mean() - 0.5) < 0.04 and max(out.size) == OUT,
           f"a small logo already cut out is drawn at 4x apart, keeps its shape, and isn't cut: {done}, "
           f"{ink_.mean():.0%} inked")
    finally:
        x4 = real
    blank = Image.new("RGBA", (300, 300), (255, 255, 255, 255))
    ImageDraw.Draw(blank).rectangle([0, 0, 299, 299], outline=(150, 150, 150, 255))
    try:
        clean(blank)
        ok(False, "a white box with nothing on it raises")
    except ValueError as e:
        ok(str(e) == "nothing left after the cut", "a white box with nothing on it raises")
    failed = [why for good, why in checks if not good]
    for why in failed:
        print(f"FAIL {why}")
    print(f"clean_logo.py selftest: {len(checks) - len(failed)} passed, {len(failed)} failed")
    return not failed


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(0 if selftest() else 1)
    sys.exit(__doc__)
