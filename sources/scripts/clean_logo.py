#!/usr/bin/env python3
"""
clean_logo.py: a new team's logo cut off its white box, cleaned and lit before it goes live (BP app game-card 28).

Since BP app game-card 26 a team logo stands bare on a game's page and casts a shadow on the game card, so a logo
that is a white box shows its box. `team_logos.py keep` runs each logo it puts live through `clean` here. The recipe
is game-card 25's (BP app docs/plans/game-card/assets/25-clean-logos/clean_team_logos.py), with the logo skill's
cut, clean, enamel and thin_share (BP app .claude/skills/logo-3d/build.py), copied as the cloud can't see BP app.
Only the part a new team takes is copied: no per-team exceptions, no Real-ESRGAN, no checks against a live file.

- A white box is cut off, keeping every white the logo encloses (a badge's white fill, its white letters). When the
  cut takes nothing, a grey frame round the box may be holding the white in: 4 px are trimmed and the cut tried again.
- A coloured box is the logo's own, left whole.
- Then the pale fringe and stray specks go, any white or light grey band 3 px wide or more is put back (an outline
  the logo draws), it goes to 512 px on its long side, and it is lit like the Search logos unless it is mostly
  hairlines (lit, its shine would be wider than its strokes).
- A file under 240 px on its long side goes live as found: the 4x that redraws it runs only on the Mac, so its
  report line says to redraw it there.

  python3 sources/scripts/clean_logo.py --selftest
"""

import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SMALL = 240  # 80 pt at 3x: a file under this on its long side needs game-card 25's 4x, which the cloud doesn't have
OUT = 512    # the long side a cleaned logo goes live at
TRIM = 4     # a grey hairline frame that stops the cut: this many px trimmed
THIN = 0.7   # over this share of its ink within 3 px of an edge, a logo ships as drawn, not lit


def clean(im):
    """The recipe on one logo: (the logo to put live, what was done, in words). Raises ValueError when the cut leaves
    nothing, so the team waits rather than taking a blank."""
    im = im.convert("RGBA")
    if max(im.size) < SMALL:
        return im, [f"under {SMALL} px ({max(im.size)}), so it went live as found: redraw it on the Mac "
                    "(BP app game-card 25)"]
    done = []
    box = boxed(im)
    if box:
        out = cut(im)
        if not went(im, out):  # nothing went: a grey frame may hold the white in
            inner = im.crop((TRIM, TRIM, im.width - TRIM, im.height - TRIM))
            cut_inner = cut(inner)
            if went(inner, cut_inner):
                out = cut_inner
                done.append("a grey frame trimmed")
        if went(im, out):
            im = out
            done.append("cut off its white box")
        elif box == "white":
            done.append("still a white box: the cut took nothing off")
        else:
            done.append("its own coloured box, left whole")
    bb = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if not bb:
        raise ValueError("nothing left after the cut")
    im = im.crop(bb)
    if max(im.size) > OUT:
        s = OUT / max(im.size)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    bare = keeping_white(im)
    if max(bare.size) < OUT:
        s = OUT / max(bare.size)
        bare = bare.resize((round(bare.width * s), round(bare.height * s)), Image.LANCZOS)
    lit = thin_share(bare) < THIN
    done.append("lit" if lit else "as drawn: mostly hairlines")
    return (enamel(bare) if lit else bare), done


# --- game-card 25's recipe -----------------------------------------------------------------------------------------

def ring(im):
    """Share of the border's pixels that are opaque, and share that are white."""
    w, h = im.size
    px = [im.getpixel((x, y)) for x in range(w) for y in (0, h - 1)] + [im.getpixel((x, y)) for y in range(h) for x in (0, w - 1)]
    return sum(p[3] > 200 for p in px) / len(px), sum(p[3] > 200 and min(p[:3]) > 235 for p in px) / len(px)


def cover(im):
    hist = im.getchannel("A").histogram()
    return sum(hist[201:]) / (im.width * im.height)


def boxed(im):
    """'white', 'coloured' or None: is the file a box (its border opaque), and of what. A grey hairline frame reads as
    coloured here; the cut then finds the white inside it."""
    opaque, white = ring(im)
    return None if opaque <= 0.5 else "white" if white > 0.5 else "coloured"


def went(before, after):
    """The cut took something off."""
    return cover(after) < min(0.95, cover(before) - 0.02)


def keeping_white(im):
    """`tidy`, keeping the white the logo draws itself: an opaque white or light grey band 3 px wide or more is its
    outline or fill, not the 1-2 px pale fringe an older cut left (tidy alone took the outline of Delano, Robbinsdale,
    East Grand Forks, Maple Lake, Montevideo and St. Cloud)."""
    out = np.asarray(tidy(im)).copy()
    a = np.asarray(im.convert("RGBA"))
    rgb = a[..., :3].astype(np.float32) / 255
    light = (rgb @ np.float32([0.2126, 0.7152, 0.0722]) > 0.75) & (rgb.max(-1) - rgb.min(-1) < 0.1)
    band = Image.fromarray(((a[..., 3] > 200) & light).astype(np.uint8) * 255)
    zone = np.asarray(band.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(7))) > 127
    out[zone] = a[zone]
    return Image.fromarray(out, "RGBA")


# --- the logo skill's build.py: cut, clean (here `tidy`), enamel, thin_share -----------------------------------------

def blur(x, s):
    """Gaussian blur in float (an 8-bit blur bands the lighting), separable, edge-padded."""
    r = int(3 * s) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    k /= k.sum()
    for axis in (0, 1):
        p = np.pad(x, [(r, r) if a == axis else (0, 0) for a in range(x.ndim)], mode="edge")
        x = sum(w * np.take(p, np.arange(i, i + x.shape[axis]), axis=axis) for i, w in enumerate(k))
    return x


def lum(rgb):
    return rgb @ np.array([.2126, .7152, .0722])


def ink(rgb, al):
    """The colour of the ink beside each pixel: nearby opaque pixels that aren't near-white, weighted to the deepest,
    so a thin letter still has its colour and the pale pixels between letters don't count. (colour, how much ink)"""
    L = lum(rgb)
    w = ((al > 0.9) & ~((L > 0.86) & (rgb.max(-1) - rgb.min(-1) < 0.12))) * (1 - L) ** 3
    W = blur(w, 2.0)
    C = np.stack([blur(rgb[..., c] * w, 2.0) for c in range(3)], -1) / np.maximum(W, 1e-6)[..., None]
    return C, W


def thinned(rgb, C):
    """How much of ink C each pixel holds if it is C thinned with white (t), and how far it is from being that
    (residual): a light colour of the logo's own is far, a pale fringe near."""
    t = np.clip(((1 - rgb) * (1 - C)).sum(-1) / np.maximum(((1 - C) ** 2).sum(-1), 1e-6), 0, 1)
    return t, np.linalg.norm((1 - rgb) - t[..., None] * (1 - C), axis=-1)


def box(m, r):
    """How many of m's pixels lie in the (2r+1)-square around each pixel."""
    c = np.pad(np.pad(m.astype(np.int32), r).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    n = 2 * r + 1
    return c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]


def tidy(im):
    """build.clean(im, 1.0, keep=True), changing no shape or ink colour: pale fringe and white slivers along the cut
    edge take the ink beside them and the see-through it implies (the logo's own white fill stays), and pale specks
    standing alone go."""
    a = np.asarray(im.convert("RGBA"), float) / 255
    rgb, al = a[..., :3].copy(), a[..., 3].copy()
    near_edge = blur((al < 0.5).astype(float), 1.5) > 0.02
    C, W = ink(rgb, al)
    t, res = thinned(rgb, C)
    fringe = near_edge & (W > 0.002) & ((1 - C).max(-1) > 0.15) & (lum(rgb) > lum(C) + 0.04) & (al > 0) & (res < 0.10)
    al = np.where(fringe, al * t, al)
    rgb = np.where(fringe[..., None], C, rgb)
    solid = al > 0.5
    # pale specks only, the leftovers of a white or faint grey page: a dark dot is a period
    core = solid & (lum(rgb) > 0.7) & (box(solid, 4) < 14) & (box(solid, 4) == box(solid, 9))
    al = np.where((blur(core.astype(float), 1.0) > 0.05) & (box(solid, 9) < 14), 0, al)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), al]) * 255).round().astype(np.uint8), "RGBA")


def enamel(im, rim=0.004, body=0.02, depth=0.12, groove=0.45, diffuse=1.0, shade=0.55,
           sharp=1.3, broad=0.42, gloss=0.24, light=(-0.25, -0.6, 1.0)):
    """A flat logo lit like the 3D enamel pins, by code alone so nothing is redrawn: colours sharpened a touch, its
    outline and colour edges a two-scale height map lit from above-left (a sharp white line on top edges, a broad soft
    sheen, bottom edges in soft shade, a gloss over the top half). A flat area keeps its colour under the gloss."""
    L = np.array(light, float); L /= np.linalg.norm(L)
    H = (L + [0, 0, 1]) / np.linalg.norm(L + [0, 0, 1])
    a = np.asarray(im.convert("RGBA"), float) / 255
    al = a[..., 3]
    # see-through pixels take the colour of the ink beside them first, so sharpening and the median below never pull
    # a dark rim in from whatever colour hides under transparency
    fill = np.stack([blur(a[..., c] * al, 2.0) for c in range(3)], -1) / np.maximum(blur(al, 2.0), 1e-6)[..., None]
    base = Image.fromarray((np.clip(np.where(al[..., None] > 0.02, a[..., :3], fill), 0, 1) * 255).round().astype(np.uint8), "RGB")
    rgb = np.asarray(base.filter(ImageFilter.UnsharpMask(radius=1.6, percent=90, threshold=2)), float) / 255
    n = max(al.shape)
    # where one colour meets another: a shallow groove, read from a median-cleaned copy so JPEG speckle stays flat
    med = np.asarray(base.filter(ImageFilter.MedianFilter(5)), float) / 255
    soft = np.stack([blur(med[..., c] * al, 1.2) for c in range(3)], -1)
    edge = np.max([np.hypot(*np.gradient(soft[..., c])) for c in range(3)], 0)
    edge = np.clip((edge - 0.03) / 0.10, 0, 1) * (al > 0.5)
    h = 0.45 * (blur(al, n * rim) - groove * blur(edge, n * 0.002)) \
        + 0.55 * (blur(al, n * body) - groove * blur(edge, n * 0.005))
    dy, dx = np.gradient(h * n * depth)
    N = np.dstack([-dx, -dy, np.ones_like(h)])
    N /= np.linalg.norm(N, axis=-1, keepdims=True)
    ndl = np.clip(N @ L, 0, None) / L[2]  # 1 on a flat area
    lit = np.where(ndl < 1, 1 - shade * (1 - ndl), 1 + diffuse * (np.clip(ndl, 0, 1.6) - 1))
    # thin strokes take a third of the shade and little shine: shaded all over they go grey, shine reads as specks
    thick = np.clip((blur(al, n * 0.008) - 0.45) / 0.35, 0, 1)
    lit = 1 + (np.clip(lit, 0.45, 1.4) - 1) * (0.35 + 0.65 * thick)
    out = np.clip(rgb * lit[..., None], 0, 1)
    ndh = np.clip(N @ H, 0, None)
    spec = sharp * np.clip(ndh ** 220 - H[2] ** 220, 0, None) / (1 - H[2] ** 220) \
        + broad * np.clip(ndh ** 14 - H[2] ** 14, 0, None) / (1 - H[2] ** 14)
    out = 1 - (1 - out) * (1 - no_ticks(np.clip(spec * thick, 0, 1), n)[..., None])
    ys = np.where(al.max(1) > 0.5)[0]
    top, height = (ys[0], ys[-1] - ys[0] + 1) if len(ys) else (0, n)
    y = (np.arange(al.shape[0])[:, None] - top) / height
    sheen = gloss * np.clip(1 - y / 0.5, 0, 1) ** 1.6
    out = out + (1 - out) * sheen[..., None]
    return Image.fromarray((np.dstack([out, al]) * 255).round().astype(np.uint8), "RGBA")


def no_ticks(glint, n):
    """The shine without its lone glints: one under 1.2% of the logo across reads as a white tick, not light. A glint
    that runs on along an edge stays."""
    glint = glint.copy()
    for p in parts_of(glint > .3):
        ys, xs = np.nonzero(p)
        if max(np.ptp(ys), np.ptp(xs)) + 1 < n * .012:
            glint[grow(grow(p))] = 0
    return glint


def on_white(im):
    page = Image.new("RGBA", im.size, (255, 255, 255, 255))
    page.alpha_composite(im)
    return page


def grow(m):
    g = m.copy()
    g[1:] |= m[:-1]; g[:-1] |= m[1:]; g[:, 1:] |= m[:, :-1]; g[:, :-1] |= m[:, 1:]
    return g


def outside(mask):
    """The part of mask joined to the image's edge."""
    im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8)).copy()  # fromarray is read-only
    h, w = mask.shape
    for x, y in [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]:
        if im.getpixel((x, y)) == 255:
            ImageDraw.floodfill(im, (x, y), 128)
    return np.asarray(im) == 128


def parts_of(mask):
    """Each 4-connected part of mask."""
    im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8)).copy()
    for y, x in zip(*np.nonzero(mask)):
        if im.getpixel((int(x), int(y))) == 255:
            ImageDraw.floodfill(im, (int(x), int(y)), 128)
            part = np.asarray(im) == 128
            im.paste(0, mask=Image.fromarray(part))
            yield part


def cut(im):
    """build.cut(im, keep='all'): a logo off its white page. White joined to the image's edge is un-blended from every
    pixel near it ("colour to alpha"), so edges keep no pale rim; every white the logo encloses stays."""
    s = np.asarray(on_white(im).convert("RGB"), np.float32) / 255
    white = (s @ np.float32([.2126, .7152, .0722]) > .9) & (s.max(-1) - s.min(-1) < .08)
    bg = outside(white)
    blend = (1 - s).max(-1)  # how little white could have made this pixel
    near = bg
    for _ in range(max(2, round(max(im.size) / 200))):  # the blended edge is a pixel or two wide
        near = grow(near)
    a = np.where(bg & (blend < .06), 0, np.where(near, blend, 1))
    rgb = (s - (1 - a[..., None])) / np.maximum(a[..., None], 1e-6)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), a]) * 255).round().astype(np.uint8), "RGBA")


def thin_share(im, px=3):
    """How much of the ink is within px of an edge: 1.0 is all hairlines."""
    a = im.getchannel("A")
    ink_ = np.asarray(a) > 128
    core = np.asarray(a.filter(ImageFilter.MinFilter(2 * px + 1))) > 128
    return 1 - core.sum() / max(ink_.sum(), 1)


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
    for frame in (False, True):
        out, done = clean(badge(frame))
        a = np.asarray(out)
        mid = a[a.shape[0] // 2, a.shape[1] // 4]  # in the white fill, left of the mark
        ok(out.size == (OUT, OUT) and a[0, 0, 3] == 0 and mid[3] == 255 and mid[:3].min() > 230
           and ("a grey frame trimmed" in done) == frame and done[-2:] == ["cut off its white box", "lit"],
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
    ok(done[0] == "its own coloured box, left whole" and out.getchannel("A").getextrema() == (255, 255),
       f"a coloured box is the logo's own: {done}")
    hairline = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
    ImageDraw.Draw(hairline).ellipse([20, 20, 380, 380], outline=(20, 60, 160, 255), width=3)
    out, done = clean(hairline)
    ok(done == ["as drawn: mostly hairlines"], f"line art ships as drawn, not lit: {done}")
    small = badge(side=200)
    out, done = clean(small)
    ok(out.tobytes() == small.tobytes() and done[0].startswith("under 240 px (200), so it went live as found"),
       f"a file too small to clean without the 4x goes live as found, and says so: {done}")
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
