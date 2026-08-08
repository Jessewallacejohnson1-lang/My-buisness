#!/usr/bin/env python3
"""Build the Block Party mark as a single SVG from parametric geometry.

The script BP letterforms are traced vector (work/bp-lockup.d, normalized to a
1000-unit-wide box). Everything else — the party hat, its wrapped stripes, the
rolled brim, the pompom — is generated here, so it stays crisp, editable, and
tunable without ever touching a raster.

usage: build.py <out.svg> [--flat KEY=VAL ...]
"""
from __future__ import annotations
import sys, math, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
LETTERS = open(os.path.join(HERE, 'bp-lockup.d')).read().strip()

# The traced letterform box, in its own units.
LET_W, LET_H = 1000.0, 834.66

# ─────────────────────────────────────────── palette

P = dict(
    tile      = '#111111',   # brand `ink` — the icon is an ink tile
    accent    = '#FA5A34',   # single accent hue (flattened from the shipped coral-orange)
    hat_body  = '#FAFAF7',   # brand `paper`
    hat_strip = '#FA5A34',
    pompom    = '#FA5A34',
)

# ─────────────────────────────────────────── layout

# Every hat number below is derived from the shipped Aug-2026 icon, measured in its
# own 1024 space and expressed as a fraction of the letterform width (727 there), so
# the proportions carry over exactly at any lockup size. See docs in the handoff.
REF = dict(
    letters_w   = 727.0,     # shipped letters bbox width
    apex        = (254.0, 181.0),
    letters_org = (156.0, 234.0),
    axis_len    = 238.6,     # apex -> brim centre
    half_w      = 110.0,
    pompom_r    = 31.5,
    pompom_off  = 29.5,      # apex -> pompom centre (pompom overlaps the apex)
    tilt        = -22.0,     # negative = base swings RIGHT, matching the reference
    overhang    = 113.0,     # how far the pompom rises above the letters' top
)

L = dict(
    canvas      = 1024.0,
    letters_w   = 780.0,     # the one scale knob: letterform width in canvas units
    letters_x   = None,      # None = auto-centre the finished lockup
    letters_y   = None,
    hat_tilt    = REF['tilt'],
    sag_ratio   = 0.23,      # brim ellipse dip, as a share of half-width
    stripes     = 4,
    stripe_frac = 0.50,      # share of each band that is stripe
    stripe_top  = 0.20,      # first stripe starts this far down the axis
    corner_ratio= 0.30,      # base-corner rounding, as a share of half-width
    brim_ratio  = 0.13,      # solid band at the base = the brim, share of axis length
    gap_ratio   = 0.010,     # knockout gap separating the hat from the B beneath
)


def geometry(L):
    """Resolve every hat dimension from the single `letters_w` knob.

    All hat numbers are reference fractions, so changing the lockup scale keeps the
    proportions the reference established — nothing drifts.
    """
    K = L['letters_w'] / REF['letters_w']
    hw = REF['half_w'] * K
    return dict(
        K=K,
        H=REF['axis_len'] * K,
        W=hw,
        S=hw * L['sag_ratio'],
        dx=(REF['apex'][0] - REF['letters_org'][0]) * K,
        dy=(REF['apex'][1] - REF['letters_org'][1]) * K,
        corner=hw * L['corner_ratio'],
        brim=REF['axis_len'] * K * L['brim_ratio'],
        pom_r=REF['pompom_r'] * K,
        pom_gap=(REF['pompom_off'] - REF['pompom_r']) * K,   # negative = overlaps apex
        gap=L['letters_w'] * L['gap_ratio'],
    )


# Where the lockup's ink bbox sits relative to the letterform origin, as fractions of
# letters_w. Measured once from a rendered probe (see fit.py) so auto-centring needs
# no render loop at build time.
LOCK = dict(x0=0.0, y0=-0.155, x1=1.0, y1=0.845)   # -> the lockup is exactly square

# With the hat off the lockup is just the traced letterform box, which is exactly the
# normalized trace extent — no probe render needed.
LOCK_BARE = dict(x0=0.0, y0=0.0, x1=1.0, y1=LET_H / LET_W)


def f(v: float) -> str:
    s = f'{v:.2f}'.rstrip('0').rstrip('.')
    return s if s not in ('-0', '') else '0'


# ─────────────────────────────────────────── cone geometry
# Local frame: apex at (0,0), axis down +y. At axial distance y the cone's
# half-width is w = W*y/H and its cross-section ellipse sags by s = S*y/H.

def edge(y: float, H: float, W: float, S: float):
    """Half-width and sag of the cross-section at axial distance y."""
    t = y / H
    return W * t, S * t


def cone_outline(H, W, S, grow=0.0, corner=0.0) -> str:
    """Full cone silhouette: apex, right side, brim arc, left side.

    Where the straight side meets the sagging brim arc the angle is acute, which
    renders as a spike. `corner` rounds both base corners by trimming the side and
    the arc back and bridging them with a quadratic through the original corner —
    the rolled-rim read, without a separate overhanging rim shape.
    """
    w = W + grow
    apex = (0.0, -grow)
    P0, C, P2 = (-w, H), (0.0, H + 2 * S), (w, H)

    if corner <= 0:
        return f'M0 {f(-grow)}L{f(w)} {f(H)}Q0 {f(H + 2 * S)} {f(-w)} {f(H)}Z'

    def bez(t):
        return ((1 - t) ** 2 * P0[0] + 2 * (1 - t) * t * C[0] + t ** 2 * P2[0],
                (1 - t) ** 2 * P0[1] + 2 * (1 - t) * t * C[1] + t ** 2 * P2[1])

    side_len = math.hypot(w, H + grow)
    ux, uy = w / side_len, (H + grow) / side_len          # apex -> right base corner
    pR = (P2[0] - corner * ux, P2[1] - corner * uy)
    pL = (P0[0] + corner * ux, P0[1] - corner * uy)

    # Trim the brim arc by roughly `corner` of arc length at each end.
    t0 = min(0.40, corner / math.hypot(2 * (C[0] - P0[0]), 2 * (C[1] - P0[1])))
    t1 = max(0.60, 1 - corner / math.hypot(2 * (P2[0] - C[0]), 2 * (P2[1] - C[1])))
    A0, A1 = bez(t0), bez(t1)
    # de Casteljau control for the surviving middle span (symmetric in t0,t1).
    Cm = ((1 - t0) * (1 - t1) * P0[0] + (t0 * (1 - t1) + t1 * (1 - t0)) * C[0] + t0 * t1 * P2[0],
          (1 - t0) * (1 - t1) * P0[1] + (t0 * (1 - t1) + t1 * (1 - t0)) * C[1] + t0 * t1 * P2[1])

    return (f'M{f(apex[0])} {f(apex[1])}'
            f'L{f(pR[0])} {f(pR[1])}'
            f'Q{f(P2[0])} {f(P2[1])} {f(A1[0])} {f(A1[1])}'
            f'Q{f(Cm[0])} {f(Cm[1])} {f(A0[0])} {f(A0[1])}'
            f'Q{f(P0[0])} {f(P0[1])} {f(pL[0])} {f(pL[1])}'
            'Z')


def band(y0, y1, H, W, S, grow=0.0) -> str:
    """A stripe wrapping the cone between axial depths y0 (top) and y1 (bottom)."""
    w0, s0 = edge(y0, H, W, S); w0 += grow
    w1, s1 = edge(y1, H, W, S); w1 += grow
    return (f'M{f(-w0)} {f(y0)}'
            f'Q0 {f(y0 + 2 * s0)} {f(w0)} {f(y0)}'
            f'L{f(w1)} {f(y1)}'
            f'Q0 {f(y1 + 2 * s1)} {f(-w1)} {f(y1)}'
            'Z')


def build(P=P, L=L, tile=True, hat=True) -> tuple[str, dict]:
    C = L['canvas']
    G = geometry(L)
    H, W, S = G['H'], G['W'], G['S']
    LWc = L['letters_w']
    K = LOCK if hat else LOCK_BARE

    # Auto-centre: place the letterform origin so the finished lockup's ink bbox
    # lands dead centre on the tile.
    lx, ly = L['letters_x'], L['letters_y']
    if lx is None:
        lx = (C - (K['x1'] - K['x0']) * LWc) / 2 - K['x0'] * LWc
    if ly is None:
        ly = (C - (K['y1'] - K['y0']) * LWc) / 2 - K['y0'] * LWc

    xf = f"translate({f(lx + G['dx'])},{f(ly + G['dy'])}) rotate({f(L['hat_tilt'])})"

    els: list[str] = []
    if tile:
        els.append(f'<rect x="0" y="0" width="{f(C)}" height="{f(C)}" fill="{P["tile"]}"/>')

    # Letterforms, scaled from the 1000-unit trace box into canvas units.
    s = LWc / LET_W
    els.append(
        f'<path d="{LETTERS}" fill="{P["accent"]}" fill-rule="evenodd" '
        f'transform="translate({f(lx)},{f(ly)}) scale({f(s)})"/>')

    if not hat:
        # Bare monogram: the letterforms alone. No hat means no knockout gap either —
        # nothing overlaps the B, so there is nothing to separate it from.
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
               f'viewBox="0 0 {f(C)} {f(C)}">\n  ' + '\n  '.join(els) + '\n</svg>\n')
        return svg, {'canvas': C, 'letters_x': lx, 'letters_y': ly, 'hat': False, **G}

    g, pom_r = G['gap'], G['pom_r']
    pom_cy = -pom_r - G['pom_gap']

    # Knockout: the hat silhouette grown by `gap`, in the tile colour, so the hat
    # reads as sitting IN FRONT of the B rather than merging into it. Two shapes
    # cover the whole mark — the cone (grown sideways and past its base) and the
    # pompom, which sits above the apex.
    if g > 0 and tile:
        els.append(f'<path d="{cone_outline(H + g, W, S, grow=g, corner=G["corner"] + g)}" '
                   f'fill="{P["tile"]}" transform="{xf}"/>')
        els.append(f'<circle cx="0" cy="{f(pom_cy)}" r="{f(pom_r + g)}" '
                   f'fill="{P["tile"]}" transform="{xf}"/>')

    # Cone body — one clean wedge. The solid band left below the last stripe reads
    # as the brim, so there is no separate overhanging rim to break up at 40px.
    els.append(f'<path d="{cone_outline(H, W, S, corner=G["corner"])}" '
               f'fill="{P["hat_body"]}" transform="{xf}"/>')

    # Wrapped stripes: bands that follow the cone's cross-section, so they read as
    # going AROUND the cone rather than lying flat across it.
    n = int(L['stripes'])
    top, bot = H * L['stripe_top'], H - G['brim']
    pitch = (bot - top) / n
    for i in range(n):
        y0 = top + i * pitch
        y1 = y0 + pitch * L['stripe_frac']
        els.append(f'<path d="{band(y0, y1, H, W, S)}" fill="{P["hat_strip"]}" transform="{xf}"/>')

    els.append(f'<circle cx="0" cy="{f(pom_cy)}" r="{f(pom_r)}" '
               f'fill="{P["pompom"]}" transform="{xf}"/>')

    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
           f'viewBox="0 0 {f(C)} {f(C)}">\n  ' + '\n  '.join(els) + '\n</svg>\n')
    return svg, {'canvas': C, 'letters_x': lx, 'letters_y': ly, **G}


if __name__ == '__main__':
    out = sys.argv[1]
    tile = True
    for a in sys.argv[2:]:
        if a == '--no-tile':
            tile = False
            continue
        if '=' in a:
            k, v = a.lstrip('-').split('=', 1)
            if k in P:
                P[k] = v
            elif k in L:
                L[k] = float(v)
            else:
                raise SystemExit(f'unknown key {k}')
    svg, info = build(tile=tile)
    open(out, 'w').write(svg)
    print(f'wrote {out} ({len(svg)} bytes)')
