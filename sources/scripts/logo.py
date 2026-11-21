#!/usr/bin/env python3
"""One logo, from the business's own file to what ships: the one logo module behind every logo in the app (BP app
logo-cutouts 06). Search's logos and their map pins (BP app logo-3d, and place_logos.py each morning), Town card logos
(place-photos) and team logos (clean_logo.py) all go through it, on a Mac or in the cloud. It knows no folder: the
caller hands in the file.

    import logo
    got = logo.make(<their file>, <its options>)   # a Logo:
        got.image   the finished logo, 512 px square, see-through, lit unless thin (what Search shows)
        got.bare    the same before the enamel (the check sheets judge it)
        got.webp    got.image as the WebP that ships
        got.pin     its map pin: the logo on a white square, 256 px PNG
        got.hue     its main colour as a hue, None for a grey logo (hue_of)
    logo.shipped(im)   a Logo from a logo already finished (a 3D render, sized with fit_image)
    logo.x4(im)        a small picture drawn at 4x by Real-ESRGAN, None with no engine here
    logo.VERSION       this file's own hash: a logo made with another version is made again (place_logos.py check)

The steps, in make's order: crop (option `crop`), sharp (Real-ESRGAN under 600 px), cut (`keep`, `keep_box`),
fine_print (`trim`), fit_image (sized to WALL, then clean), thin_share/`gloss`, enamel. A `photo: true` logo (a
picture of their sign, pin only) is kept whole. The options are BP app's flat.json entry for the place, also kept as
notes.json beside their file in the private place-sources bucket.

    python3 sources/scripts/logo.py selftest
"""
import colorsys
import hashlib
import io
import math
import os
import shutil
import subprocess
import sys
import tempfile
from collections import namedtuple
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

VERSION = hashlib.sha1(Path(__file__).read_bytes()).hexdigest()[:8]
# The ink area every logo is sized to: 0.9 of the median business logo's as first cut (2026-10-02), fixed so a new
# or swapped logo never resizes the rest.
WALL = 0.21081772595643997
PT5 = 32  # 5 pt at the wall's 80 pt, in the 512 px a logo ships at: lettering under this can't be read

Logo = namedtuple('Logo', 'image bare webp pin hue')


def alpha(im):
    return np.asarray(im.getchannel('A'), np.float32) / 255


def scale(im, target, px=512):
    """How many times fit() enlarges this logo."""
    im = im.crop(im.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox())
    a = alpha(im)
    side = max(im.size)
    return px * min(1, max(.62, (target / (a.sum() / side ** 2)) ** .5)) / side


def fit_image(im, target, px=512, keep=None):
    """A logo sized like the flat set (same ink area, never under .62x) and centered optically:
    halfway between its box center and its ink's center, as the flat logos are. A flat logo
    (`keep` given: its flat.json keep) is cleaned once it sits at its final size."""
    im = im.crop(im.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox())
    a = alpha(im)
    side = max(im.size)
    area = a.sum() / side ** 2
    s = min(1, max(.62, (target / area) ** .5))
    up = px * s / side  # how many times the file is enlarged
    w, h = round(im.width * px * s / side), round(im.height * px * s / side)
    im = im.resize((w, h), Image.LANCZOS)
    a = alpha(im)
    ys, xs = np.indices(a.shape)
    cx, cy = (xs * a).sum() / a.sum(), (ys * a).sum() / a.sum()
    x = min(max(round((px - w) / 2 + (w / 2 - cx) / 2), 0), px - w)  # never past the edge: a
    y = min(max(round((px - h) / 2 + (h / 2 - cy) / 2), 0), px - h)  # full-width wordmark lost its u
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    out.paste(im, (x, y))
    if keep is not None:
        out = clean(out, up, keep)
    return out


def blur(x, s):
    """Gaussian blur in float (an 8-bit blur bands the lighting), separable, edge-padded."""
    r = int(3 * s) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    k /= k.sum()
    for axis in (0, 1):
        p = np.pad(x, [(r, r) if a == axis else (0, 0) for a in range(x.ndim)], mode='edge')
        x = sum(w * np.take(p, np.arange(i, i + x.shape[axis]), axis=axis) for i, w in enumerate(k))
    return x


def lum(rgb):
    return rgb @ np.array([.2126, .7152, .0722])


def ink(rgb, al):
    """The colour of the ink beside each pixel: nearby opaque pixels that aren't near-white,
    weighted to the deepest, so a thin letter (no pixel far from its edge) still has its
    colour and the pale pixels between letters don't count. Returns (colour, how much ink)."""
    L = lum(rgb)
    w = ((al > 0.9) & ~((L > 0.86) & (rgb.max(-1) - rgb.min(-1) < 0.12))) * (1 - L) ** 3
    W = blur(w, 2.0)
    C = np.stack([blur(rgb[..., c] * w, 2.0) for c in range(3)], -1) / np.maximum(W, 1e-6)[..., None]
    return C, W


def thinned(rgb, C):
    """How much of ink C each pixel holds if it is C thinned with white (t), and how far it is
    from being that (residual): a light colour of the logo's own is far, a pale fringe near."""
    t = np.clip(((1 - rgb) * (1 - C)).sum(-1) / np.maximum(((1 - C) ** 2).sum(-1), 1e-6), 0, 1)
    return t, np.linalg.norm((1 - rgb) - t[..., None] * (1 - C), axis=-1)


def box(m, r):
    """How many of m's pixels lie in the (2r+1)-square around each pixel."""
    c = np.pad(np.pad(m.astype(np.int32), r).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    n = 2 * r + 1
    return c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]


def clean(im, up=1.0, keep=False):
    """The micro clean-up every flat logo gets at its final size (Jesse, 2026-11-07: "make the
    micro details clean", Ace's e still had white in it), changing no shape or ink colour:
    1. Pale fringe and white slivers the cut left (a pixel that is the ink beside it thinned
       with white) take that ink's colour and the see-through it implies: no white rim, no
       white in a small letter's hole. A logo keeping white (keep) is cleaned along its cut
       edge only, so its own white fill and the seam around it stay.
    2. Pale specks standing alone (a few light pixels with no ink near) go.
    3. A small file stretched up (`up` times) has its stair-stepped edge smoothed and pulled
       back to a crisp line; a hairline too thin for that keeps its own edge."""
    a = np.asarray(im.convert('RGBA'), float) / 255
    rgb, al = a[..., :3].copy(), a[..., 3].copy()
    clear = (al < 0.5).astype(float)
    near_edge = blur(clear, 1.5) > 0.02
    C, W = ink(rgb, al)
    t, res = thinned(rgb, C)
    where = near_edge if keep else al > 0
    fringe = where & (W > 0.002) & ((1 - C).max(-1) > 0.15) & (lum(rgb) > lum(C) + 0.04) & (al > 0) & (res < 0.10)
    al = np.where(fringe, al * t, al)
    rgb = np.where(fringe[..., None], C, rgb)
    solid = al > 0.5
    # (pale specks only, the leftovers of a white or faint grey page: a dark dot is a period,
    # and HHAIRBY.HANNA's sits alone between letter-spaced capitals)
    core = solid & (lum(rgb) > 0.7) & (box(solid, 4) < 14) & (box(solid, 4) == box(solid, 9))
    al = np.where((blur(core.astype(float), 1.0) > 0.05) & (box(solid, 9) < 14), 0, al)
    if up > 1.3:
        tight = np.clip((blur(al, 0.45 * up) - 0.5) * min(1.4 * up, 6.0) + 0.5, 0, 1)
        al = np.where(blur(al, 1.5) < 0.55, al, tight)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), al]) * 255).round().astype(np.uint8), 'RGBA')


def pale(im, keep=False):
    """What still reads as white or washed out on a logo: opaque pixels that are the ink beside
    them mostly thinned with white, or white itself. On a logo keeping white (keep) only what
    touches its cut edge counts, as a rim; its own white fill doesn't."""
    a = np.asarray(im.convert('RGBA'), float) / 255
    rgb, al = a[..., :3], a[..., 3]
    C, W = ink(rgb, al)
    t, res = thinned(rgb, C)
    white = (lum(rgb) > 0.88) & (rgb.max(-1) - rgb.min(-1) < 0.1)
    out = (al > 0.5) & (((W > 0.002) & ((1 - C).max(-1) > 0.15) & (t < 0.6) & (res < 0.12)) | white)
    return out & (blur((al < 0.5).astype(float), 1.5) > 0.02) if keep else out


def enamel(im, rim=0.004, body=0.02, depth=0.12, groove=0.45, diffuse=1.0, shade=0.55,
           sharp=1.3, broad=0.42, gloss=0.24, light=(-0.25, -0.6, 1.0)):
    """A flat logo lit like the 3D enamel pins (Jesse, 2026-10-11; bolder 2026-11-07, "i love
    it"; brighter 2026-11-08, "both" on the Logo Lift mock: more light on top slopes, less
    shade below, a stronger sheen), by code alone so nothing is redrawn. Its colours are sharpened a touch, then its
    outline and colour edges become a two-scale height map (a thin crisp raised edge on a
    rounded body), lit from above-left: a sharp white line on top edges, a broad soft sheen,
    bottom edges in soft shade, a gloss over the top half. A flat area keeps its colour
    under the gloss."""
    from PIL import ImageFilter
    L = np.array(light, float); L /= np.linalg.norm(L)
    H = (L + [0, 0, 1]) / np.linalg.norm(L + [0, 0, 1])
    a = np.asarray(im.convert('RGBA'), float) / 255
    al = a[..., 3]
    # see-through pixels take the colour of the ink beside them first, so sharpening and the
    # median below never pull a dark rim in from whatever colour hides under transparency
    fill = np.stack([blur(a[..., c] * al, 2.0) for c in range(3)], -1) / np.maximum(blur(al, 2.0), 1e-6)[..., None]
    base = Image.fromarray((np.clip(np.where(al[..., None] > 0.02, a[..., :3], fill), 0, 1) * 255).round().astype(np.uint8), 'RGB')
    rgb = np.asarray(base.filter(ImageFilter.UnsharpMask(radius=1.6, percent=90, threshold=2)), float) / 255
    n = max(al.shape)
    # where one colour meets another: a shallow groove, so each area reads as its own fill;
    # read from a median-cleaned copy so JPEG speckle inside a fill stays flat
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
    # thin strokes (small text, hairlines, a badge's white letters) take a third of the shade
    # and little shine: shaded all over they go grey, and shine reads as white specks
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
    return Image.fromarray((np.dstack([out, al]) * 255).round().astype(np.uint8), 'RGBA')


def no_ticks(glint, n):
    """The shine without its lone glints: one under 1.2% of the logo across reads as a white tick,
    not light (between American Family's white letters on its band, 2026-11-08). A glint that runs on
    along an edge stays."""
    glint = glint.copy()
    for p in parts_of(glint > .3):
        ys, xs = np.nonzero(p)
        if max(np.ptp(ys), np.ptp(xs)) + 1 < n * .012:
            glint[grow(grow(p))] = 0
    return glint


def on_white(im):
    page = Image.new('RGBA', im.size, (255, 255, 255, 255))
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


def held_fill(white):
    """Page white a badge's outline would hold if its gaps were shut (Sartell's shield: two gaps in
    its line let the page in, so its white fill went and only the S's loops stayed white). The ink
    grown up to a tenth of the logo wide, its holes filled, shrunk back; only big parts count, not
    white between letters. Opt-in (`keep: "fill"`): closing every badge's gaps filled the white
    between words and laurels on 11 of 46 badges (2026-11-11)."""
    r = max(2, round(max(white.shape) * .05))
    p = 2 * r
    shape = ~outside(blur(np.pad(~white, p).astype(np.float32), r / 2) < .03)  # grown round, holes filled
    shape = (blur(shape.astype(np.float32), r / 2) > .97)[p:-p, p:-p]          # shrunk back a little past it
    held = np.zeros_like(white)
    for part in parts_of(white & shape & outside(white)):
        if part.sum() >= .02 * white.size:
            held |= part
    return held


def parts_of(mask):
    """Each 4-connected part of mask."""
    im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8)).copy()
    for y, x in zip(*np.nonzero(mask)):
        if im.getpixel((int(x), int(y))) == 255:
            ImageDraw.floodfill(im, (int(x), int(y)), 128)
            part = np.asarray(im) == 128
            im.paste(0, mask=Image.fromarray(part))
            yield part


def white_of(rgb):
    """cut's white: light and grey (rgb as floats 0-1)."""
    return (rgb @ np.float32([.2126, .7152, .0722]) > .9) & (rgb.max(-1) - rgb.min(-1) < .08)


def cut(im, keep=False, box=None, hull=0):
    """A logo off its white page. White is un-blended from every pixel near it ("colour to
    alpha"), so edges keep no pale rim, and white the logo encloses (the inside of a b or an
    o) goes too, unless `keep`: a badge's white fill is part of the logo. Even then a letter's
    hole near the page goes; one inside the badge stays white. `keep='all'` keeps every white
    the logo encloses, for white letters and petals drawn right by the page. `keep='fill'` is
    `keep=True` for a badge whose outline has gaps (`held_fill`). White inside
    `box` (left, top, right, bottom, as shares of the image) always stays: white words on a
    thin banner sit as near the page as a letter's hole does. `hull` (px): the page is only the white outside the
    logo's outline shut over gaps up to that wide, so white joined to the page through a thin gap in its own outline
    stays (Bemidji's keyline round the B, a team logo; used with keep='all').
    A file already cut out goes on white first: many sit on their own white square."""
    s = np.asarray(on_white(im).convert('RGB'), np.float32) / 255
    white = white_of(s)
    bg = white
    if keep:
        bg = outside(white)
    if hull:
        ink = Image.fromarray((~white).astype(np.uint8) * 255)
        shut = ink.filter(ImageFilter.MaxFilter(2 * hull + 1)).filter(ImageFilter.MinFilter(2 * hull + 1))
        bg = bg & outside(np.asarray(shut) < 128)
    if keep == 'fill':
        bg &= ~held_fill(white)
    if keep in (True, 'fill'):
        # a small hole goes when, growing out from it, it meets the page before any white the
        # logo keeps: a letter's hole on the page (Milbert & Johnson's bold o's sit a whole
        # stroke from it), not one inside the badge's white
        # (a JPEG speck of white beside a letter's hole can't hold it back: they held the
        # Farmers' Market's O; a badge's white letters hold each other)
        reach = max(4, round(max(im.size) / 20))  # a bold letter's stroke
        small, holds = [], np.zeros_like(white)
        for part in parts_of(white & ~bg):
            n = part.sum()
            if n >= max(4, .00005 * white.size):
                holds |= part
            if n < .004 * white.size:
                ys, xs = np.nonzero(part)
                small.append((part, np.s_[max(ys.min() - reach, 0):ys.max() + reach + 1, max(xs.min() - reach, 0):xs.max() + reach + 1]))
        # It must also meet the page through one ink, as a letter's hole does: a white letter in
        # a badge (Joetown's J, its 20) crosses its band and the badge's outline first.
        for part, win in small:
            g, page, src = part[win], bg[win], s[win]
            rest = holds[win] & ~g
            crossed = []
            for _ in range(reach):
                ring = grow(g) & ~g
                g = g | ring
                if (g & page).any():
                    c = np.concatenate(crossed) if crossed else np.ones((1, 3))
                    if (c / np.linalg.norm(c, axis=1, keepdims=True)).std(0).max() < .08:
                        bg = bg | part
                    break
                if (g & rest).any():
                    break
                c = 1 - src[ring]  # which ink, however thinned with white at its edge
                crossed.append(c[np.linalg.norm(c, axis=1) > .25])
    if box:
        h, w = white.shape
        inside = np.zeros_like(white)
        inside[round(box[1] * h):round(box[3] * h), round(box[0] * w):round(box[2] * w)] = True
        bg &= ~(inside & ~outside(white))
    blend = (1 - s).max(-1)  # how little white could have made this pixel
    near = bg
    for _ in range(max(2, round(max(im.size) / 200))):  # the blended edge is a pixel or two wide
        near = grow(near)
    a = np.where(bg & (blend < .06), 0, np.where(near, blend, 1))
    rgb = (s - (1 - a[..., None])) / np.maximum(a[..., None], 1e-6)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), a]) * 255).round().astype(np.uint8), 'RGBA')


def sharp(im, least=600):
    """A small file made crisp: Real-ESRGAN (its anime model, made for flat art) draws it at 4x, so the edges stop
    going soft when the wall blows it up. Their drawing, not a redraw: every shape and colour stays (checked by eye
    2026-11-07 on the eight softest). Unchanged with no engine here (x4)."""
    big = x4(on_white(im)) if min(im.size) < least else None
    return big.convert('RGBA') if big else im


def fine_print(im, small=PT5, wide=PT5 * 1.5, least=4):
    """The logo without its fine print: a line of small letters (under `small` px tall, `wide` px
    wide, `least` or more in a row) at the top or bottom edge, with the rest of its line (punctuation,
    descenders, letters that touch), anything smaller beyond it and an underline of its own. A line
    goes whole or not at all (Consumer Directions lost DIRECTI and kept ONS, St John the Baptist
    kept "h &", 2026-11-08): a quarter of its letters at 95% of `small` or taller keep it (a name's
    capitals; Ace's "The helpful place." at 97% reads, Woodcrest's COUNTRY MANOR at 93% doesn't: Jesse,
    2026-11-13, as the Clean Logos mock of 2026-11-08 had them).
    The cut's specks start no line. A badge's ring or a mark
    running across the words holds the line (a tagline goes; words inside a badge stay); a mark
    beside the words doesn't. Returns the trimmed logo, or None when nothing goes. Jesse,
    2026-11-07: lettering that can't be read at 80 pt goes; the mark and the big name stay."""
    a = alpha(im) > .5
    if not a.any():
        return None
    label = np.zeros(a.shape, np.int32)
    T, B_, L, R = [], [], [], []
    for i, p in enumerate(parts_of(a), 1):
        label[p] = i
        py, px = np.nonzero(p)
        T.append(py.min()); B_.append(py.max() + 1); L.append(px.min()); R.append(px.max() + 1)
    t, b, l, r = (lambda i: T[i - 1]), (lambda i: B_[i - 1]), (lambda i: L[i - 1]), (lambda i: R[i - 1])
    h, w = (lambda i: b(i) - t(i)), (lambda i: r(i) - l(i))
    gone = set()
    while True:
        keep = [i for i in range(1, len(T) + 1) if i not in gone]
        speck = lambda i: max(h(i), w(i)) < small / 6  # the cut's crumbs, smaller than any letter
        tiny = [i for i in keep if h(i) < small and w(i) < wide and not speck(i)]
        hit = None
        for edge in (-1, 1):  # the bottom edge, then the top
            cand = sorted(tiny, key=lambda i: edge * (t(i) + b(i)))
            if len(cand) < least:
                continue
            c0 = (t(cand[0]) + b(cand[0])) / 2
            row = [i for i in cand if abs((t(i) + b(i)) / 2 - c0) < small / 2]
            if len(row) < least:
                continue
            rt, rb = min(map(t, row)), max(map(b, row))
            while True:  # the rest of its line, out to its last letter; not the next line's i-dot
                reach = [i for i in row if not speck(i)]  # a speck doesn't carry the line on to a mark beside it
                rl, rr = min(map(l, reach)), max(map(r, reach))
                more = [i for i in keep if i not in row and h(i) < 2 * small and l(i) <= rr + small and r(i) >= rl - small
                        and (rt - small <= t(i) < rb + small / 8 and rt < b(i) <= rb + small  # on it, or a comma under it
                             or max(h(i), w(i)) < small / 3 and rt - small / 2 <= t(i) and b(i) <= rt)]  # its i-dots
                if not more:
                    break
                row += more
            letters = [h(i) for i in row if not speck(i)]
            if 4 * sum(x >= .95 * small for x in letters) >= len(letters):
                continue  # a quarter of its letters can be read: it stays
            rt, rb = min(map(t, row)), max(map(b, row))
            rest = [i for i in keep if i not in row]
            if any(b(i) > rt and t(i) < rb and min(r(i), rr) - max(l(i), rl) > .2 * (rr - rl) for i in rest):
                continue  # a ring or a mark runs across the words
            beyond = [i for i in rest if (t(i) >= rb - 1 if edge < 0 else b(i) <= rt + 1)]
            if any(h(i) >= small for i in beyond):
                continue
            rules = [i for i in rest if i not in beyond and h(i) < .5 * small and w(i) > 2 * small
                     and 0 <= (rt - b(i) if edge < 0 else t(i) - rb) <= small]  # its underline
            hit = row + beyond + rules
            break
        if not hit:
            break
        gone.update(hit)
    keep = [i for i in range(1, len(T) + 1) if i not in gone]
    if not gone or not keep:  # all of it small lettering: it stays, as no logo is left without it
        return None
    px = np.asarray(im).copy()
    went, kept = np.isin(label, list(gone)), np.isin(label, keep)
    px[grow(grow(went)) & ~kept, 3] = 0  # with their anti-aliased edge, which the label misses
    px[(box(went, round(small / 2)) > 0) & ~(box(kept, 3) > 0), 3] = 0  # and the pale crumbs around them
    kt, kb, kl, kr = min(map(t, keep)), max(map(b, keep)), min(map(l, keep)), max(map(r, keep))
    m = round(0.02 * max(kb - kt, kr - kl))
    return Image.fromarray(px).crop((max(kl - m, 0), max(kt - m, 0), min(kr + m, im.width), min(kb + m, im.height)))


def thin_share(im, px=3):
    """How much of the ink is within px of an edge: 1.0 is all hairlines. Over .7 the enamel's
    shine would be wider than the strokes (line art, thin wordmarks), so they ship as drawn."""
    a = im.getchannel('A')
    ink = np.asarray(a) > 128
    core = np.asarray(a.filter(ImageFilter.MinFilter(2 * px + 1))) > 128
    return 1 - core.sum() / max(ink.sum(), 1)


def solid_box(im):
    """The logo's box, ignoring the faint haze Codex leaves across the canvas."""
    return im.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox()


def pin_png(im, photo=False):
    """A map pin: the logo trimmed, centred on a white square with a margin, 256 px, as the
    map has always drawn them (full bleed in a circle). A photo of a sign keeps a thin margin."""
    im = im.convert('RGBA')
    if photo:
        rgb = im.convert('RGB').point(lambda v: 255 if v < 235 else 0).convert('L')
        im = im.crop(rgb.getbbox() or (0, 0, *im.size))
    else:
        im = im.crop(solid_box(im) or (0, 0, *im.size))
    side = round(max(im.size) * (1.04 if photo else 1.2))
    sq = Image.new('RGBA', (side, side), (255, 255, 255, 255))
    sq.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    buf = io.BytesIO()
    sq.convert('RGB').resize((256, 256), Image.LANCZOS).save(buf, 'PNG', optimize=True)
    return buf.getvalue()



def make(src, o=None):
    """A logo as Search shows it, from their file at `src` and `o`, its flat.json entry: cropped (`crop`), sharpened,
    cut (`keep`, `keep_box`), its fine print trimmed (`trim: false` keeps it), sized, cleaned and lit unless its
    strokes are thin (`gloss` forces either way; Joetown Burgers' crest, Jesse 2026-10-19). A pin-only place gets the
    very same logo for its pin; `photo: true` (a picture of their sign) is kept whole."""
    o = o or {}
    im = Image.open(src).convert('RGBA')
    if o.get('crop'):  # the logo's part of their picture (left, top, right, bottom, as shares)
        l, t, r, b = o['crop']
        im = im.crop((round(l * im.width), round(t * im.height), round(r * im.width), round(b * im.height)))
    if o.get('photo'):
        return shipped(im, photo=True)
    im = sharp(im)
    im.thumbnail((1024, 1024), Image.LANCZOS)  # twice the 512 px it ships at is plenty: a 2500 px crest took 6 minutes to cut
    out = cut(im, o.get('keep', False), o.get('keep_box'))
    if not out.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox():
        raise ValueError('nothing left after the cut: a logo drawn in white')
    if o.get('trim', True):
        f = scale(out, WALL)
        out = fine_print(out, small=PT5 / f, wide=PT5 * 1.5 / f) or out
    bare = fit_image(out, WALL, keep=o.get('keep', False) or bool(o.get('keep_box')))
    lit = o.get('gloss', thin_share(bare) < .7)
    return shipped(enamel(bare) if lit else bare, bare)


def webp(im):
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=90)
    return buf.getvalue()


# --- Real-ESRGAN and the main colour -------------------------------------------------------------------------------

GPU = Path('~/.local/bin/realesrgan-ncnn-vulkan').expanduser()  # Real-ESRGAN's own build, on Jesse's Mac only
GPU_MODELS = Path('~/.local/share/realesrgan/models').expanduser()
CACHE = Path(os.environ.get('BP_X4_CACHE', '~/Library/Caches/block-party/x4')).expanduser()  # the Mac's one cache


def x4(im):
    """`im` drawn at 4x by Real-ESRGAN's anime model (made for flat art and lettering): their drawing, not a redraw,
    every shape and colour kept. RGB in (a logo goes on white first: see-through pixels count as their colour) and
    out; None with no engine here. Jesse's Mac runs the model's own GPU build, cached by the picture's bytes so a
    re-run gives the same pixels; the cloud runs sharpen.py's copy of the same model on onnxruntime (the morning's
    library only). Flat logos, small flyers and team logos all go through here."""
    buf = io.BytesIO()
    im.convert('RGB').save(buf, 'PNG')
    if GPU.exists():
        cache = CACHE / (hashlib.sha1(buf.getvalue()).hexdigest()[:16] + '.png')
        if not cache.exists():
            CACHE.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory() as t:
                src, out = Path(t) / 'in.png', Path(t) / 'out.png'
                src.write_bytes(buf.getvalue())
                subprocess.run([str(GPU), '-i', str(src), '-o', str(out), '-n', 'realesrgan-x4plus-anime', '-m',
                                str(GPU_MODELS), '-s', '4'], check=True, capture_output=True)
                shutil.move(out, cache)  # whole or not at all: a run cut short leaves no half picture in the cache
        return Image.open(cache).convert('RGB')
    try:
        import onnxruntime  # noqa: F401
    except ImportError:
        return None
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from sharpen import upscale
    out = upscale(np.asarray(im.convert('RGB'), np.float32) / 255)
    return Image.fromarray((out * 255).round().astype(np.uint8), 'RGB')


def hue_of(im):
    """The backdrop and shadow hue Search gives a logo: its main colour, the mean hue (weighted by how
    colourful) of the colourful pixels within 30° of the hue most of them share; None when under 5% of it is
    colourful (a black, white or grey logo). Not the mean of all of them: navy and gold averaged to
    green (St. Joseph Catholic School, 2026-11-08)."""
    px = [p for p in np.asarray(im.convert('RGBA').resize((96, 96))).reshape(-1, 4).tolist() if p[3] > 128]
    hw = []
    for r, g, b, _ in px:
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        w = s * (1 - abs(2 * l - 1))  # chroma
        if w > 0.25:
            hw.append((h * 360, w))
    if not px or len(hw) < 0.05 * len(px):
        return None
    near = lambda a, b: abs((a - b + 180) % 360 - 180) <= 30
    peak = max(range(0, 360, 5), key=lambda c: sum(near(h, c) for h, _ in hw))  # the most pixels of one colour
    xs = sum(w * math.cos(math.radians(h)) for h, w in hw if near(h, peak))
    ys = sum(w * math.sin(math.radians(h)) for h, w in hw if near(h, peak))
    return round((math.degrees(math.atan2(ys, xs)) + 360) % 360) % 360


def shipped(im, bare=None, photo=False):
    """A Logo from a finished logo `im` (`bare`: the same before its enamel). Its pin is drawn from the WebP that
    ships, so the pin is the Search logo exactly as the app has it."""
    bare = im if bare is None else bare
    data = webp(im)
    return Logo(im, bare, data, pin_png(im if photo else Image.open(io.BytesIO(data)), photo), hue_of(bare))


def selftest():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        _make_checks(tmp)
    # a black ring with a white centre, anti-aliased onto white, on a white page
    ys, xs = np.mgrid[:64, :64]
    d = np.hypot(ys - 31.5, xs - 31.5)
    ink = np.clip(np.minimum(d - 12, 24 - d) + .5, 0, 1)
    small = np.clip(np.minimum(np.hypot(ys - 5.5, xs - 5.5) - 2, 4 - np.hypot(ys - 5.5, xs - 5.5)) + .5, 0, 1)
    ink = np.maximum(ink, small)  # a little o by the corner, its hole on the page
    page = Image.fromarray(np.dstack([np.uint8((1 - ink) * 255)] * 3 + [np.full((64, 64), 255, np.uint8)]), 'RGBA')
    for keep, box in ((False, None), (True, None), ('all', None), (False, (.4, .4, .6, .6))):
        out = cut(page, keep, box)
        a = alpha(out)
        assert a[0, 0] == 0, 'page corner stays'
        assert (a[31, 31] == 1) == bool(keep or box), 'centre white kept for a badge or inside the box'
        assert (a[5, 5] == 1) == (keep == 'all'), "the little o's hole goes unless every white is kept"
        assert np.abs(np.asarray(on_white(out), np.float32) - np.asarray(page, np.float32)).max() <= 16, 'same logo on white (page noise under 6% goes)'
        rim = (a > 0) & (a < 1)
        assert (np.asarray(out)[..., :3][rim] < 8).all(), 'no pale rim: edge pixels stay ink'
    # the ring with a gap cut in it (Sartell's shield): its centre is page unless keep='fill'
    gapped = np.asarray(page).copy()
    gapped[30:34, 40:64, :3] = 255
    for keep in (True, 'fill'):
        a = alpha(cut(Image.fromarray(gapped, 'RGBA'), keep))
        assert a[0, 0] == 0 and a[5, 5] == 0, 'page and the little o keep going'
        assert (a[31, 31] == 1) == (keep == 'fill'), "a gapped badge's fill stays only with keep='fill'"
    # hull: the page is only white outside the outline shut over gaps up to r px (Bemidji's keyline, a team logo)
    for hull in (0, 5):
        a = alpha(cut(Image.fromarray(gapped, 'RGBA'), 'all', hull=hull))
        assert a[63, 0] == 0 and a[5, 5] == 1, 'page goes, every enclosed white stays'  # (0, 0): shut by the o beside it
        assert (a[31, 31] == 1) == bool(hull), 'white joined to the page through a 4 px gap stays with hull=5'
    # enamel: the shape stays, the top edge catches the light, the bottom edge falls in shade,
    # and the middle of a fill below the gloss keeps its colour
    sq = Image.new('RGBA', (200, 200), (0, 0, 0, 0))
    sq.paste((200, 40, 40, 255), (40, 40, 160, 160))
    lit = np.asarray(enamel(sq), float)
    assert (lit[..., 3] == np.asarray(sq)[..., 3]).all(), 'alpha untouched'
    assert lit[43, 100, :3].sum() > lit[100, 100, :3].sum() > lit[157, 100, :3].sum(), 'lit from above'
    assert np.abs(lit[140, 100, :3] - [200, 40, 40]).max() <= 2, 'a flat area keeps its colour'
    assert lit[41, 100, 1] > 40, 'no dark rim pulled in from under the transparency'
    g = np.zeros((512, 512)); g[50, 100:160] = 1; g[300:303, 300:303] = 1   # an edge's line, and a tick
    g = no_ticks(g, 512)
    assert g[50, 100:160].all() and not g[300:303, 300:303].any(), 'a lone glint goes, a line of light stays'

    # clean: a red square with a pale pink sliver through it, a green leaf on navy, a stray
    # speck and a period beside a letter
    a = np.zeros((200, 200, 4), np.uint8)
    a[40:160, 40:160] = (200, 40, 40, 255)
    a[40:160, 99] = (245, 215, 215, 255)                                   # the cut left a pale sliver
    a[170:190, 40:60] = (20, 30, 90, 255); a[176:184, 46:54] = (60, 200, 90, 255)  # leaf on navy
    a[5:7, 180:182] = (225, 225, 225, 255)                                 # a pale speck, nothing near
    a[5:7, 10:12] = (30, 30, 30, 255)                                      # a dark dot alone: a period
    a[170:190, 120:126] = (30, 30, 30, 255); a[186:189, 129:132] = (30, 30, 30, 255)  # an l and its period
    c = np.asarray(clean(Image.fromarray(a, 'RGBA')), float)
    assert c[100, 99, 3] < 60, 'the pale sliver goes'
    assert np.abs(c[100, 70] - [200, 40, 40, 255]).max() <= 1, 'the red fill stays'
    assert np.abs(c[180, 50] - [60, 200, 90, 255]).max() <= 1, "a light colour of the logo's own stays"
    assert c[6, 181, 3] == 0, 'a lone pale speck goes'
    assert c[6, 11, 3] == 255, 'a lone dark dot stays'
    assert c[187, 130, 3] == 255, 'a period beside its letter stays'
    kept = a.copy(); kept[60:140, 60:140] = (255, 255, 255, 255)           # a badge's own white fill
    assert (np.asarray(clean(Image.fromarray(kept, 'RGBA'), keep=True))[100, 100] == 255).all(), 'kept white stays'
    assert pale(Image.fromarray(a, 'RGBA'))[100, 99] and not pale(Image.fromarray(np.uint8(c), 'RGBA'))[100, 70], 'pale finds the sliver'

    # keep=True: a bold o on the page loses its hole even a whole stroke from the page (the
    # badge's own white centre staying is the ring test above)
    ys, xs = np.mgrid[:256, :256]
    d = np.hypot(ys - 127.5, xs - 127.5)
    o = np.clip(np.minimum(d - 6, 16 - d) + .5, 0, 1)                      # Milbert's o: hole 12 px, stroke 10 px
    page = Image.fromarray(np.dstack([np.uint8((1 - o) * 255)] * 3 + [np.full((256, 256), 255, np.uint8)]), 'RGBA')
    assert alpha(cut(page, True))[127, 127] == 0, "a bold o's hole on the page goes"
    # fine print: a line of small letters under the mark goes; inside a badge's ring it stays;
    # hairlines count as thin, a block does not
    mark = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    dr = ImageDraw.Draw(mark)
    dr.rectangle([40, 40, 216, 150], fill=(200, 0, 0, 255))
    for i in range(8):
        dr.rectangle([40 + i * 22, 170, 52 + i * 22, 182], fill=(0, 0, 0, 255))
    trimmed = fine_print(mark, small=20, wide=30)
    assert trimmed and trimmed.height <= 124 and trimmed.width >= 176 and alpha(trimmed).sum() >= 176 * 110, 'the tagline under the mark goes, the mark stays whole'
    under = mark.copy()
    ImageDraw.Draw(under).rectangle([40, 158, 216, 160], fill=(0, 0, 0, 255))
    assert fine_print(under, small=20, wide=30).height <= 124, 'its underline goes with it'
    badge = mark.copy()
    ImageDraw.Draw(badge).ellipse([4, 4, 252, 252], outline=(0, 0, 0, 255), width=6)
    assert fine_print(badge, small=20, wide=30) is None, "letters inside a badge's ring stay"
    assert fine_print(Image.new('RGBA', (64, 64), (0, 0, 0, 255)), small=20, wide=30) is None, 'one block: nothing to trim'
    crumbs = mark.copy()
    ImageDraw.Draw(crumbs).rectangle([0, 40, 12, 200], fill=(0, 0, 0, 255))  # a mark down beside the tagline
    ImageDraw.Draw(crumbs).rectangle([120, 188, 121, 189], fill=(0, 0, 0, 90))  # pale, so no part of its own
    left = fine_print(crumbs, small=20, wide=30)
    assert left and alpha(left)[120:, 20:].max() == 0, "the line's pale crumbs go with it"
    words = Image.new('RGBA', (256, 64), (0, 0, 0, 0))
    for i in range(8):
        ImageDraw.Draw(words).rectangle([20 + i * 22, 20, 32 + i * 22, 32], fill=(0, 0, 0, 255))
    assert fine_print(words, small=20, wide=30) is None, 'a logo that is all fine print keeps it'
    touching = mark.copy()
    ImageDraw.Draw(touching).rectangle([220, 170, 255, 182], fill=(0, 0, 0, 255))
    assert fine_print(touching, small=20, wide=30).height <= 124, 'letters that touch, beside the rest of the line, go with it'
    name = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    dr = ImageDraw.Draw(name)
    dr.rectangle([40, 40, 216, 150], fill=(200, 0, 0, 255))
    for i in range(8):  # a name's line: small letters, and a capital in three that can be read
        dr.rectangle([40 + i * 22, 184 - (22 if i % 3 == 0 else 16), 52 + i * 22, 184], fill=(0, 0, 0, 255))
    assert fine_print(name, small=20, wide=30) is None, "a name's capitals keep its whole line"
    beside = mark.copy()
    ImageDraw.Draw(beside).rectangle([0, 150, 30, 196], fill=(0, 0, 0, 255))
    left = fine_print(beside, small=20, wide=30)
    assert left and alpha(left)[134:146, 40:52].max() == 0 and alpha(left)[120:150, 5:25].min() == 1, \
        "a mark beside the words doesn't hold them, and stays"
    specks = mark.copy()
    ImageDraw.Draw(specks).rectangle([0, 152, 12, 186], fill=(0, 0, 0, 255))  # a mark beside, as short as a letter
    for x in (17, 24, 31):
        ImageDraw.Draw(specks).rectangle([x, 176, x + 1, 177], fill=(0, 0, 0, 255))
    left = fine_print(specks, small=20, wide=30)
    assert left and alpha(left)[134:146, 40:52].max() == 0 and alpha(left)[:, :12].max() == 1, \
        'specks between the words and a mark beside them leave the mark'
    dotted = Image.new('RGBA', (256, 128), (0, 0, 0, 0))
    dr = ImageDraw.Draw(dotted)
    for i in range(8):
        dr.rectangle([40 + i * 22, 20, 52 + i * 22, 32], fill=(0, 0, 0, 255))  # a tagline above the name
    dr.rectangle([40, 58, 200, 100], fill=(0, 0, 0, 255))
    dr.rectangle([210, 46, 216, 52], fill=(0, 0, 0, 255))  # the name's i: its dot, then its stem
    dr.rectangle([210, 58, 216, 100], fill=(0, 0, 0, 255))
    assert fine_print(dotted, small=20, wide=30).height >= 54, "the tagline goes, the next line's i keeps its dot"
    dots = mark.copy()
    ImageDraw.Draw(dots).rectangle([84, 164, 87, 167], fill=(0, 0, 0, 255))  # its own i's dot, above the line
    ImageDraw.Draw(dots).rectangle([120, 181, 122, 186], fill=(0, 0, 0, 255))  # a comma under it
    assert fine_print(dots, small=20, wide=30).height <= 124, "the tagline's own i-dots and commas go with it"
    hair = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    ImageDraw.Draw(hair).line([0, 128, 255, 128], fill=(0, 0, 0, 255), width=2)
    assert thin_share(hair) > .9 and thin_share(mark) < .3, 'hairlines are thin, a block is not'
    im = Image.new('RGBA', (500, 200), (0, 0, 0, 3))  # Codex's faint haze doesn't count as logo
    im.paste((200, 0, 0, 255), (50, 50, 450, 150))
    assert solid_box(im) == (50, 50, 450, 150), solid_box(im)
    navy = Image.new('RGBA', (40, 60), (25, 40, 120, 255))
    navy.paste((205, 160, 30, 255), (0, 0, 40, 25))  # navy and gold (St. Joseph Catholic School)
    assert hue_of(Image.new('RGBA', (120, 60), (220, 30, 30, 255))) == 0, 'a red logo gets a red hue'
    assert hue_of(Image.new('RGBA', (40, 40), (90, 90, 90, 255))) is None, 'a grey one none'
    assert hue_of(navy) in range(220, 236), 'navy and gold give the main colour, not green between them'
    assert hue_of(Image.new('RGBA', (40, 40), (255, 0, 1, 255))) == 0, 'a hue a hair under 360 is 0, never 360'
    _x4_checks()
    print('selftest ok')


def _make_checks(tmp):
    """make() on fixture files, with no Search folder: their file and its options in, a Logo out."""
    tmp = Path(tmp)
    page = Image.new('RGB', (300, 200), (255, 255, 255))   # their file: a red mark left, a smaller blue one right,
    dr = ImageDraw.Draw(page)                              # a line of small letters along the bottom
    dr.rectangle([20, 30, 150, 140], fill=(210, 30, 30))
    dr.rectangle([190, 60, 260, 120], fill=(30, 60, 200))
    for i in range(10):
        dr.rectangle([20 + i * 24, 176, 28 + i * 24, 184], fill=(0, 0, 0))
    page.save(tmp / 'theirs.png')
    drawn = []
    global x4
    live_x4, x4 = x4, lambda im: (drawn.append(im.size), im.resize((im.width * 4, im.height * 4)))[1]
    try:
        got = make(tmp / 'theirs.png', {})
        kept = make(tmp / 'theirs.png', {'trim': False})
        left = make(tmp / 'theirs.png', {'crop': [0, 0, .58, .8]})
        flat = make(tmp / 'theirs.png', {'gloss': False})
        photo = make(tmp / 'theirs.png', {'photo': True})
    finally:
        x4 = live_x4
    assert drawn[0] == (300, 200), 'a file under 600 px is drawn at 4x first'
    assert got.image.size == (512, 512) and got.image.mode == 'RGBA' and alpha(got.image)[0, 0] == 0, 'a 512 px logo, cut out'
    assert Image.open(io.BytesIO(got.webp)).size == (512, 512), 'it ships as WebP'
    pin = Image.open(io.BytesIO(got.pin))
    assert pin.size == (256, 256) and pin.getpixel((2, 2)) == (255, 255, 255), 'its pin: on a white square, 256 px'
    assert got.hue in range(0, 11) or got.hue in range(350, 361), f'its hue is its main colour, red: {got.hue}'
    black = lambda L: int(((np.asarray(L.bare)[..., :3].max(-1) < 60) & (alpha(L.bare) > .5)).sum())
    assert black(kept) > 1000 and black(got) < 50, 'the small letters go, unless trim: false keeps them'
    assert left.hue in range(0, 11) or left.hue in range(350, 361), 'crop keeps the part of their file named'
    assert (np.asarray(left.bare)[..., 2] > 150).sum() < 50, '... and the blue mark outside it goes'
    assert np.array_equal(np.asarray(flat.image), np.asarray(flat.bare)), 'gloss: false ships it as drawn'
    assert not np.array_equal(np.asarray(got.image), np.asarray(got.bare)), 'a thick logo gets the enamel'
    white = Image.new('RGBA', (300, 200), (0, 0, 0, 0))  # a logo drawn in white, for a dark header
    ImageDraw.Draw(white).rectangle([40, 40, 260, 160], fill=(255, 255, 255, 255))
    white.save(tmp / 'white.png')
    try:
        make(tmp / 'white.png', {'keep': True})
        assert False, 'a logo drawn in white raises'
    except ValueError as e:
        assert 'drawn in white' in str(e), e
    sign = Image.open(io.BytesIO(photo.pin))
    assert sign.size == (256, 256) and photo.hue is not None, 'a photo of their sign: a pin of the whole picture'


def _x4_checks():
    """x4() with a stand-in GPU build (a plain 4x resize that logs each run): drawn once, then from the cache; with
    neither engine, None."""
    global GPU, CACHE
    live = GPU, CACHE
    with tempfile.TemporaryDirectory() as tmp:
        fake, runs = Path(tmp) / 'realesrgan', Path(tmp) / 'runs'
        fake.write_text(f'#!/bin/sh\necho "$@" >> {runs}\n{sys.executable} -c "import sys; from PIL import Image; '
                        f'i = Image.open(sys.argv[1]); i.resize((i.width * 4, i.height * 4)).save(sys.argv[2])" "$2" "$4"\n')
        fake.chmod(0o755)
        GPU, CACHE = fake, Path(tmp) / 'cache'
        try:
            im = Image.new('RGB', (10, 6), (200, 30, 30))
            first, again = x4(im), x4(im.copy())
            args = runs.read_text().split()
            GPU = Path(tmp) / 'none'
            try:
                import onnxruntime  # noqa: F401
                onnx = True
            except ImportError:
                onnx = False
            other = x4(Image.new('RGB', (5, 5)))
        finally:
            GPU, CACHE = live
    assert first.size == (40, 24) and first.mode == 'RGB' and args.count('-i') == 1 \
        and 'realesrgan-x4plus-anime' in args and args[args.index('-s') + 1] == '4', "x4: the anime model at 4x"
    assert again.tobytes() == first.tobytes() and args.count('-i') == 1, 'x4: the same picture again comes from the cache'
    assert (other.size == (20, 20)) if onnx else other is None, 'x4: with no GPU build, onnxruntime, else None'


if __name__ == '__main__':
    if sys.argv[1:] in (['selftest'], ['--selftest']):
        selftest()
    else:
        sys.exit(__doc__)
