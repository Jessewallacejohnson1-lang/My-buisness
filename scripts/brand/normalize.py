#!/usr/bin/env python3
"""Normalize potrace SVG output into clean absolute-coordinate paths.

potrace emits relative commands under a flipping group transform
(`translate(0,H) scale(0.05,-0.05)`). This bakes that transform in, converts
everything to absolute cubics, splits the subpaths, and reports geometry so the
letterforms can be re-laid-out precisely inside a new tile.
"""
from __future__ import annotations
import re, sys, json

NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')


def parse_path(d: str):
    """Return list of subpaths; each is (start, [('C', p1, p2, p3) | ('L', p)])."""
    toks = re.findall(r'[MmLlHhVvCcSsZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?', d)
    i, cur, start, cmd = 0, (0.0, 0.0), (0.0, 0.0), None
    subs, seg = [], []
    prev_c2 = None

    def flush():
        nonlocal seg
        if seg:
            subs.append((start, seg))
        seg = []

    while i < len(toks):
        t = toks[i]
        if re.match(r'[A-Za-z]', t):
            cmd = t
            i += 1
            if cmd in 'Zz':
                flush()
                cur = start
                prev_c2 = None
                continue
        rel = cmd.islower()
        n = lambda k: float(toks[i + k])
        if cmd in 'Mm':
            p = (n(0), n(1))
            if rel:
                p = (cur[0] + p[0], cur[1] + p[1])
            flush()
            cur = start = p
            i += 2
            cmd = 'l' if rel else 'L'   # implicit lineto for extra pairs
            prev_c2 = None
        elif cmd in 'Ll':
            p = (n(0), n(1))
            if rel:
                p = (cur[0] + p[0], cur[1] + p[1])
            seg.append(('L', p))
            cur = p
            i += 2
            prev_c2 = None
        elif cmd in 'Hh':
            x = n(0)
            p = (cur[0] + x, cur[1]) if rel else (x, cur[1])
            seg.append(('L', p)); cur = p; i += 1; prev_c2 = None
        elif cmd in 'Vv':
            y = n(0)
            p = (cur[0], cur[1] + y) if rel else (cur[0], y)
            seg.append(('L', p)); cur = p; i += 1; prev_c2 = None
        elif cmd in 'Cc':
            pts = [(n(0), n(1)), (n(2), n(3)), (n(4), n(5))]
            if rel:
                pts = [(cur[0] + a, cur[1] + b) for a, b in pts]
            seg.append(('C', *pts)); prev_c2 = pts[1]; cur = pts[2]; i += 6
        elif cmd in 'Ss':
            pts = [(n(0), n(1)), (n(2), n(3))]
            if rel:
                pts = [(cur[0] + a, cur[1] + b) for a, b in pts]
            c1 = (2 * cur[0] - prev_c2[0], 2 * cur[1] - prev_c2[1]) if prev_c2 else cur
            seg.append(('C', c1, pts[0], pts[1])); prev_c2 = pts[0]; cur = pts[1]; i += 4
        else:
            i += 1
    flush()
    return subs


def apply_xf(subs, a, d_, e, f):
    """Affine (scale a,d_ + translate e,f) applied to every point."""
    T = lambda p: (p[0] * a + e, p[1] * d_ + f)
    out = []
    for start, seg in subs:
        out.append((T(start), [(s[0], *[T(p) for p in s[1:]]) for s in seg]))
    return out


def bbox(subs):
    xs, ys = [], []
    for start, seg in subs:
        xs.append(start[0]); ys.append(start[1])
        for s in seg:
            for p in s[1:]:
                xs.append(p[0]); ys.append(p[1])
    return min(xs), min(ys), max(xs), max(ys)


def area(sub):
    """Signed shoelace area of a subpath (curve endpoints only) — sign gives winding."""
    start, seg = sub
    pts = [start] + [s[-1] for s in seg]
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a / 2


def fmt(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def to_d(subs):
    out = []
    for start, seg in subs:
        out.append(f'M{fmt(start[0])} {fmt(start[1])}')
        for s in seg:
            if s[0] == 'L':
                out.append(f'L{fmt(s[1][0])} {fmt(s[1][1])}')
            else:
                (a, b), (c, dd), (e, f) = s[1], s[2], s[3]
                out.append(f'C{fmt(a)} {fmt(b)} {fmt(c)} {fmt(dd)} {fmt(e)} {fmt(f)}')
        out.append('Z')
    return ''.join(out)


def main():
    svg = open(sys.argv[1]).read()
    target = float(sys.argv[2]) if len(sys.argv) > 2 else 1024.0

    m = re.search(r'transform="translate\(([-\d.]+),([-\d.]+)\)\s*scale\(([-\d.]+),([-\d.]+)\)"', svg)
    tx, ty, sx, sy = (float(g) for g in m.groups()) if m else (0, 0, 1, 1)

    all_subs = []
    for d in re.findall(r'\sd="([^"]+)"', svg):
        all_subs += apply_xf(parse_path(d), sx, sy, tx, ty)

    # Drop specks: anything under 0.02% of the largest subpath by |area|.
    # Keep the area paired with its own subpath — counters are real geometry and
    # must survive; only true trace noise gets dropped.
    scored = [(s, abs(area(s))) for s in all_subs]
    big = max(a for _, a in scored)
    kept_pairs = [(s, a) for s, a in scored if a >= big * 0.0002]
    keep = [s for s, _ in kept_pairs]
    dropped = len(all_subs) - len(keep)

    x0, y0, x1, y1 = bbox(keep)
    w, h = x1 - x0, y1 - y0
    # Fit the lockup into `target` on its long side, centred, origin at 0,0.
    s = target / max(w, h)
    placed = apply_xf(keep, s, s, -x0 * s, -y0 * s)

    px0, py0, px1, py1 = bbox(placed)
    info = {
        'source_bbox': [x0, y0, x1, y1],
        'source_size': [w, h],
        'aspect': w / h,
        'subpaths_in': len(all_subs),
        'subpaths_kept': len(keep),
        'subpaths_dropped': dropped,
        'normalized_bbox': [px0, py0, px1, py1],
        'scale': s,
    }
    print(json.dumps(info, indent=2), file=sys.stderr)

    # Emit each kept subpath separately so outer contours and counters stay inspectable.
    print('=== subpath census (largest first) ===', file=sys.stderr)
    for i, (sub, a) in enumerate(sorted(kept_pairs, key=lambda t: -t[1])):
        bx = bbox([sub])
        print(f'  {i}: |area|={a:10.0f} winding={"CW" if area(sub)<0 else "CCW"} '
              f'bbox=({bx[0]:.0f},{bx[1]:.0f})-({bx[2]:.0f},{bx[3]:.0f}) '
              f'{bx[2]-bx[0]:.0f}x{bx[3]-bx[1]:.0f}', file=sys.stderr)

    open(sys.argv[3], 'w').write(to_d(placed))
    print(f'\nwrote {sys.argv[3]} ({len(to_d(placed))} chars)', file=sys.stderr)


if __name__ == '__main__':
    main()
