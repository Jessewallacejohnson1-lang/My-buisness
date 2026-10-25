"""Build BP Body (Regular, Medium, SemiBold, Bold) from font-sheet.png.

The sheet is Jesse's reference for the body face: one weight, drawn grey on white.
Each glyph is cut out, upsampled, thresholded and traced with potrace. The heavier
weights are the same raster grown by a few pixels before tracing, then fitted back
to the regular glyph's height so x-height and cap height stay put.

    uv run --with fonttools --with pillow --with numpy python build.py [out_dir]   # and potrace

See README.md for what the sheet lacks.
"""
import os, re, subprocess, sys, tempfile, xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageFilter
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.reverseContourPen import ReverseContourPen
import unicodedata
from fontTools.svgLib.path import parse_path
from fontTools.misc.transform import Transform
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
UP = 8            # upsample before tracing; the sheet's x-height is only ~43 px
INK = 165         # luminance threshold after upsampling
U = 12.5          # font units per sheet pixel: cap height ~56.5 px -> ~706 units
SB = 32           # side bearing, fitted so a set line matches the sheet's sample lines
STRAIGHT, ROUND = 58, 28   # letters and digits: a stem side gets more room than a bowl
SPACE = 257       # word gap on the sample lines, less two side bearings
WEIGHTS = [("Regular", 400, 0), ("Medium", 500, 4), ("SemiBold", 600, 9), ("Bold", 700, 14)]

# One band per row of the sheet: pixel rows to scan, baseline, and the characters
# left to right. A tuple is one glyph made of several separate marks.
BANDS = [
    ((218, 276), 275, list("ABCDEFGHIJKLM")),
    ((308, 372), 368, list("NOPQRSTUVWXYZ")),
    ((466, 544), 528, list("abcdefghijklm")),
    ((563, 637), 620, list("nopqrstuvwxyz")),
    ((729, 791), 790, list("0123456789")),
    ((888, 966), 954, [".", ",", ":", ";", "!", "?", ("…", 3), "'", "‘", "’",
                       ("“", 2), ("”", 2)]),
    # No letter on this row; the baseline puts the hyphen at ~38% of x-height and
    # the brackets 10 px under it, where this kind of face carries them.
    ((975, 1056), 1040, ["-", "–", "—", "_", "(", ")", "[", "]", "{", "}"]),
    ((1135, 1216), 1205, list("@#$%&*+=/\\|")),
    ((1234, 1305), 1296, ["<", ">", "^", "~", "`", "€", "£", "¥", "¢",
                          "©", "®", ("™", 2), "°", "•", "·"]),
]

sheet = np.array(Image.open(os.path.join(HERE, "font-sheet.png")).convert("L"))


def spans(y0, y1):
    col = (sheet[y0:y1 + 1] < 160).sum(0)
    out, s = [], None
    for x, v in enumerate(col):
        if v and s is None: s = x
        if not v and s is not None: out.append((s, x - 1)); s = None
    return out


def glyph_boxes():
    for (y0, y1), base, chars in BANDS:
        sp = spans(y0, y1)
        want = sum(c[1] if isinstance(c, tuple) else 1 for c in chars)
        assert len(sp) == want, f"band {y0}: {len(sp)} marks, expected {want}"
        for c in chars:
            ch, n = c if isinstance(c, tuple) else (c, 1)
            group, sp = sp[:n], sp[n:]
            x0, x1 = group[0][0], group[-1][1]
            rows = np.nonzero((sheet[y0:y1 + 1, x0:x1 + 1] < 160).any(1))[0]
            yield ch, x0, x1, y0 + rows[0], y0 + rows[-1], base


def trace(x0, x1, y0, y1, grow, work):
    pad = 3
    cut = Image.fromarray(sheet[y0 - pad:y1 + pad + 1, x0 - pad:x1 + pad + 1])
    big = cut.resize((cut.width * UP, cut.height * UP), Image.LANCZOS)
    if grow:
        big = big.filter(ImageFilter.MinFilter(grow * 2 + 1))   # dark ink spreads
    bw = big.point(lambda v: 0 if v < INK else 255).convert("1")
    pbm, svg = work + "/g.pbm", work + "/g.svg"
    bw.save(pbm)
    subprocess.run(["potrace", "-b", "svg", "--flat", "-a", "1.0", "-O", "0.2", "-t", "4",
                    "-o", svg, pbm], check=True)
    g = ET.parse(svg).getroot().find("{http://www.w3.org/2000/svg}g")
    tx, ty, sx, sy = map(float, re.match(
        r"translate\(([-\d.]+),([-\d.]+)\)\s*scale\(([-\d.]+),([-\d.]+)\)", g.get("transform")).groups())
    rec = RecordingPen()
    # potrace pixels (y down, upsampled, padded) back to sheet pixels
    to_sheet = Transform().translate(x0 - pad, y0 - pad).scale(1 / UP).translate(tx, ty).scale(sx, sy)
    for p in g.findall("{http://www.w3.org/2000/svg}path"):
        parse_path(p.get("d"), TransformPen(rec, to_sheet))
    return rec


def bounds(rec):
    bp = BoundsPen(None); rec.replay(bp); return bp.bounds


def side_bearings(ch, x0, x1, y0, y1):
    """A side whose ink runs most of the glyph's height (a stem) gets STRAIGHT,
    anything else ROUND; punctuation keeps SB. Without it 'Ul' and 'll' touched."""
    if not ch.isalnum():
        return SB, SB
    ink = sheet[y0:y1 + 1, x0:x1 + 1] < 160
    edge = lambda cols: STRAIGHT if ink[:, cols].any(1).mean() > 0.6 else ROUND
    return edge(slice(0, 3)), edge(slice(-3, None))


ACCENTS = {"\u0300": "grave", "\u0301": "acute", "\u0302": "circumflex", "\u0303": "tilde",
           "\u0308": "dieresis", "\u030A": "ring", "\u0327": "cedilla"}
ACCENTED = "ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿ"


def contours(glyph):
    """A glyph's outline as one RecordingPen per contour."""
    rec = RecordingPen(); glyph.draw(rec, None)
    out, cur = [], RecordingPen()
    for op, args in rec.value:
        cur.value.append((op, args))
        if op in ("closePath", "endPath"):
            out.append(cur); cur = RecordingPen()
    return out


def joined(recs):
    r = RecordingPen()
    for c in recs: r.value += c.value
    return r


def add_accents(glyphs, adv, cmap):
    """The sheet has no accented letters. Build them from its own marks: ` for
    the grave (mirrored for the acute), ^, ~ and ° shrunk, i's dot twice for the
    dieresis, and the comma under the letter for the cedilla."""
    g = lambda ch: glyphs[cmap[ord(ch)]]
    i_parts = sorted(contours(g("i")), key=lambda c: bounds(c)[1])
    stem, dot = joined(i_parts[:-1]), i_parts[-1]
    pen = TTGlyphPen(None); stem.replay(pen)
    glyphs["uni0131"], adv["uni0131"] = pen.glyph(), adv[cmap[ord("i")]]
    cmap[0x131] = "uni0131"

    def mark(ch, scale):
        r = RecordingPen()
        g(ch).draw(TransformPen(r, Transform().scale(scale)), None)
        return r
    grave = mark("`", 1.0)
    acute = RecordingPen()
    grave.replay(TransformPen(ReverseContourPen(acute), Transform().scale(-1, 1)))
    dx0, _, dx1, _ = bounds(dot)
    two = RecordingPen()
    dot.replay(two)
    dot.replay(TransformPen(two, Transform().translate((dx1 - dx0) * 1.9, 0)))
    marks = {"grave": grave, "acute": acute, "circumflex": mark("^", 0.6),
             "tilde": mark("~", 0.72), "ring": mark("\u00B0", 0.78), "dieresis": two,
             "cedilla": mark(",", 0.8)}

    for ch in ACCENTED:
        base_ch, acc = unicodedata.normalize("NFD", ch)[:2]
        base_name = "uni0131" if base_ch == "i" else cmap[ord(base_ch)]
        cap = base_ch.isupper()
        m = marks[ACCENTS[acc]]
        s = 0.9 if cap else 1.0
        base = joined(contours(glyphs[base_name]))
        bx0, _, bx1, _ = bounds(base)
        mx0, my0, mx1, my1 = bounds(m)
        if ACCENTS[acc] == "cedilla":
            ty = -my1 * s + 10          # hangs from the baseline
        else:
            ty = (706 + 50 if cap else 537 + 70) - my0 * s
        tx = (bx0 + bx1) / 2 - (mx0 + mx1) / 2 * s
        pen = TTGlyphPen(None)
        base.replay(pen)
        m.replay(TransformPen(pen, Transform().translate(tx, ty).scale(s)))
        name = f"uni{ord(ch):04X}"
        glyphs[name], adv[name] = pen.glyph(), adv[base_name]
        cmap[ord(ch)] = name


def build(style, weight, grow, work):
    glyphs, adv = {}, {}
    cmap = {}
    digit_w = 0
    for ch, x0, x1, y0, y1, base in glyph_boxes():
        rec = trace(x0, x1, y0, y1, grow, work)
        bx0, by0, bx1, by1 = bounds(rec)
        # vertical: fit the grown ink back to the regular ink's top and bottom
        sy = (y1 + 1 - y0) / (by1 - by0)
        left, right = side_bearings(ch, x0, x1, y0, y1)
        t = (Transform().translate(left, 0).scale(U, -U)
             .translate(0, -base).translate(0, y0).scale(1, sy).translate(-bx0, -by0))
        name = f"uni{ord(ch):04X}"
        pen = TTGlyphPen(None)
        rec.replay(TransformPen(Cu2QuPen(pen, 1.0, reverse_direction=True), t))
        glyphs[name] = pen.glyph()
        adv[name] = round((bx1 - bx0) * U + left + right)
        cmap[ord(ch)] = name
        if ch.isdigit(): digit_w = max(digit_w, adv[name])
    # tabular figures behind `tnum` (what `.monospacedDigit()` asks for): every
    # digit on the widest digit's advance, ink centred
    for d in "0123456789":
        n = f"uni{ord(d):04X}"
        pen = TTGlyphPen(None)
        glyphs[n].draw(TransformPen(pen, Transform().translate((digit_w - adv[n]) / 2, 0)), None)
        glyphs[n + ".tnum"], adv[n + ".tnum"] = pen.glyph(), digit_w
    # the sheet has no straight double quote: two straight singles
    q = "uni0027"; pen = TTGlyphPen(None)
    glyphs[q].draw(pen, None)
    w = adv[q] - 2 * SB
    glyphs[q].draw(TransformPen(pen, Transform().translate(w + SB * 0.6, 0)), None)
    glyphs["uni0022"], adv["uni0022"] = pen.glyph(), round(adv[q] + w + SB * 0.6)
    cmap[0x22] = "uni0022"
    add_accents(glyphs, adv, cmap)
    for name, width, cps in [("space", SPACE, (0x20, 0xA0)), (".notdef", SPACE, ())]:
        glyphs[name], adv[name] = TTGlyphPen(None).glyph(), width
        for cp in cps: cmap[cp] = name

    order = [".notdef"] + sorted(n for n in glyphs if n != ".notdef")
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({n: glyphs[n] for n in order})
    fb.setupHorizontalMetrics({n: (adv[n], glyphs[n].xMin if hasattr(glyphs[n], "xMin") else 0) for n in order})
    # SF Pro's line height (1.19 em) and cap ratio, so layouts keep their spacing
    fb.setupHorizontalHeader(ascent=950, descent=-240)
    ps = f"BPBody-{style}"
    fb.setupNameTable({"familyName": "BP Body", "styleName": style, "psName": ps,
                       "version": "Version 0.1", "copyright": "Drawn for Block Party."})
    fb.setupOS2(sTypoAscender=950, sTypoDescender=-240, sTypoLineGap=0, usWinAscent=950,
                usWinDescent=240, sxHeight=537, sCapHeight=706, usWeightClass=weight,
                achVendID="BPTY", fsType=0,
                fsSelection=0x40 if style == "Regular" else 0)
    fb.setupPost()
    digits = " ".join(f"uni{ord(d):04X}" for d in "0123456789")
    tnum = " ".join(f"uni{ord(d):04X}.tnum" for d in "0123456789")
    addOpenTypeFeaturesFromString(fb.font, f"feature tnum {{ sub [{digits}] by [{tnum}]; }} tnum;")
    out = os.path.join(OUT, ps + ".ttf")
    fb.save(out)
    print("wrote", out, len(order), "glyphs")


with tempfile.TemporaryDirectory() as work:
    for style, weight, grow in WEIGHTS:
        build(style, weight, grow, work)
