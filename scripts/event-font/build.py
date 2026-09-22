import collections, os, re, sys, xml.etree.ElementTree as ET
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.svgLib.path import parse_path
from fontTools.misc.transform import Transform

REVERSE = "--reverse" in sys.argv
WORK = os.environ.get("EVENT_FONT_WORK", "/tmp/event-font-build")
OUT = os.environ.get("EVENT_FONT_OUT", WORK + "/BPEventHeading-Regular.ttf")

LABELS = {
    0: list("abcdefghijklm"),
    1: list("nopqrstuvwxyz"),
    2: list("ABCDEFGHIJKLM"),
    3: list("NOPQRSTUVWXYZ"),
    4: list("0123456789"),
    5: ['.', ',', ':', ';', '!', '?', '&', '@', '#', '+', '-', '/', '(', ')'],
}
AGL = {'.': 'period', ',': 'comma', ':': 'colon', ';': 'semicolon', '!': 'exclam',
       '?': 'question', '&': 'ampersand', '@': 'at', '#': 'numbersign', '+': 'plus',
       '-': 'hyphen', '/': 'slash', '(': 'parenleft', ')': 'parenright'}
DIGIT = dict(zip("0123456789", "zero one two three four five six seven eight nine".split()))

rows = collections.defaultdict(list)
for line in open(WORK + '/glyphs.tsv'):
    b, i, x0, x1, y0, y1 = map(int, line.split())
    rows[b].append(dict(band=b, i=i, x0=x0, x1=x1, y0=y0, y1=y1))
for b in rows:
    rows[b].sort(key=lambda r: r['x0'])
    for r, ch in zip(rows[b], LABELS[b]):
        r['ch'] = ch

DESCENDERS = set("gjpqyQ") | {',', ';', '(', ')', '/'}
baselines = {}
for b, gl in rows.items():
    cands = sorted(r['y1'] for r in gl if r['ch'] not in DESCENDERS)
    baselines[b] = cands[len(cands) // 2]

def median(v):
    v = sorted(v); return v[len(v) // 2]

XH_LETTERS = {0: set("acegm"), 1: set("nopqrsuvwxyz")}
xh = {b: median(baselines[b] - r['y0'] for r in rows[b] if r['ch'] in XH_LETTERS[b]) for b in (0, 1)}
cap = {b: median(baselines[b] - r['y0'] for r in rows[b] if r['ch'] not in 'OGCQS') for b in (2, 3)}
digit_h = median(baselines[4] - r['y0'] for r in rows[4] if r['ch'] not in '0368')
bang_h = [baselines[5] - r['y0'] for r in rows[5] if r['ch'] == '!'][0]

ASC_PX = median(baselines[0] - r['y0'] for r in rows[0] if r['ch'] in 'bdfhikl')
S0 = 750.0 / ASC_PX
X_TARGET = xh[0] * S0
C_TARGET = ((cap[2] + cap[3]) / 2) * S0
DESC_TARGET = median(r['y1'] - baselines[0] for r in rows[0] if r['ch'] in 'gj') * S0

SCALES = {0: X_TARGET / xh[0], 1: X_TARGET / xh[1],
          2: C_TARGET / cap[2], 3: C_TARGET / cap[3],
          4: C_TARGET / digit_h, 5: C_TARGET / bang_h}

print(f"asc_px={ASC_PX} S0={S0:.3f}  x-height={X_TARGET:.0f}  cap={C_TARGET:.0f}  desc={DESC_TARGET:.0f}")
print("per-band scale:", {b: round(s, 3) for b, s in SCALES.items()})

SB = 38          # side bearing, units — tuned so a set line matches the sheet
SPACE_ADV = 215

def traced(path):
    tree = ET.parse(path)
    ns = '{http://www.w3.org/2000/svg}'
    g = tree.getroot().find(f'{ns}g')
    m = re.match(r'translate\(([-\d.]+),([-\d.]+)\)\s*scale\(([-\d.]+),([-\d.]+)\)', g.get('transform'))
    tx, ty, sx, sy = map(float, m.groups())
    rec = RecordingPen()
    outer = TransformPen(rec, Transform(sx, 0, 0, sy, tx, ty))
    for p in g.findall(f'{ns}path'):
        parse_path(p.get('d'), outer)
    return rec

def bbox(rec):
    xs, ys = [], []
    for op, args in rec.value:
        for pt in args:
            if isinstance(pt, tuple):
                xs.append(pt[0]); ys.append(pt[1])
    return min(xs), min(ys), max(xs), max(ys)

glyphs, advances = {}, {}

def add(name, rec, target):
    tx0, ty0, tx1, ty1 = target
    sx0, sy0, sx1, sy1 = bbox(rec)
    sx = (tx1 - tx0) / (sx1 - sx0)
    sy = (ty1 - ty0) / (sy1 - sy0)
    t = Transform().translate(tx0, ty0).scale(sx, -sy).translate(-sx0, -sy1)
    pen = TTGlyphPen(None)
    rec.replay(TransformPen(Cu2QuPen(pen, 1.0, reverse_direction=REVERSE), t))
    glyphs[name] = pen.glyph()
    advances[name] = int(round(tx1 + SB))

for b, gl in rows.items():
    s = SCALES[b]
    base = baselines[b]
    for r in gl:
        ch = r['ch']
        name = DIGIT.get(ch) or AGL.get(ch) or ch
        rec = traced(f"{WORK}/glyphs/b{b}_{r['i']}.svg")
        w = (r['x1'] - r['x0'] + 1) * s
        top = (base - r['y0']) * s
        bot = -(r['y1'] - base) * s
        add(name, rec, (SB, bot, SB + w, top))

# --- synthesized: straight and typographic quotes, from the measured stem width
STEM = median((r['x1'] - r['x0'] + 1) * SCALES[r['band']] for r in rows[0] + rows[1] if r['ch'] in 'il')
def bar(name, n):
    pen = TTGlyphPen(None)
    top, bot, gap = C_TARGET, C_TARGET * 0.66, STEM * 0.55
    for k in range(n):
        x = SB + k * (STEM + gap)
        pen.moveTo((x, bot)); pen.lineTo((x, top))
        pen.lineTo((x + STEM, top)); pen.lineTo((x + STEM, bot)); pen.closePath()
    glyphs[name] = pen.glyph()
    advances[name] = int(round(SB * 2 + n * STEM + (n - 1) * gap))
bar("quotesingle", 1); bar("quotedbl", 2)
for src, dst in [("quotesingle", "quoteright"), ("quotedbl", "quotedblright")]:
    glyphs[dst] = glyphs[src]; advances[dst] = advances[src]

pen = TTGlyphPen(None); glyphs["space"] = pen.glyph(); advances["space"] = SPACE_ADV
pen = TTGlyphPen(None); glyphs[".notdef"] = pen.glyph(); advances[".notdef"] = SPACE_ADV

order = [".notdef"] + sorted(n for n in glyphs if n != ".notdef")
cmap = {}
for b, gl in rows.items():
    for r in gl:
        cmap[ord(r['ch'])] = DIGIT.get(r['ch']) or AGL.get(r['ch']) or r['ch']
cmap.update({0x20: "space", 0x27: "quotesingle", 0x22: "quotedbl",
             0x2019: "quoteright", 0x201D: "quotedblright", 0x2018: "quoteright",
             0x201C: "quotedbl"})

fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)
fb.setupGlyf(glyphs)
fb.setupHorizontalMetrics({n: (advances[n], glyphs[n].xMin if hasattr(glyphs[n], "xMin") else 0) for n in order})
fb.setupHorizontalHeader(ascent=int(750), descent=-int(round(DESC_TARGET)))
fb.setupNameTable({
    "familyName": "BP Event Heading", "styleName": "Regular",
    "psName": "BPEventHeading-Regular", "version": "Version 0.1",
    "copyright": "Drawn for Block Party.",
})
fb.setupOS2(sTypoAscender=750, sTypoDescender=-int(round(DESC_TARGET)), sTypoLineGap=0,
            usWinAscent=800, usWinDescent=int(round(DESC_TARGET)) + 20,
            sxHeight=int(round(X_TARGET)), sCapHeight=int(round(C_TARGET)),
            achVendID="BPTY", fsType=0)
fb.setupPost()
fb.save(OUT)
print("wrote", OUT, "glyphs:", len(order), "stem:", round(STEM))
