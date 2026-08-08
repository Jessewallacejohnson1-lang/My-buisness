#!/usr/bin/env python3
"""Calibrate build.LOCK — where the lockup's ink bbox sits relative to the
letterform origin — by rendering a probe and measuring it.

Run this whenever the hat geometry changes; paste the printed dict into build.py.
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
sys.path.insert(0, HERE)
import build

PROBE_W = 600.0          # small enough that the hat's overhang can't clip the canvas
OX, OY = 200.0, 300.0    # probe origin for the letterform box


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True, cwd=ROOT, check=True).stdout


def main():
    L = dict(build.L)
    L.update(letters_w=PROBE_W, letters_x=OX, letters_y=OY)
    svg, _ = build.build(L=L, tile=False)
    p_svg = os.path.join(ROOT, 'probe.svg')
    p_png = os.path.join(ROOT, 'probe.png')
    open(p_svg, 'w').write(svg)
    sh('swift', os.path.join(HERE, 'render.swift'), p_svg, p_png, '1024', '--alpha')
    m = json.loads(sh('swift', os.path.join(HERE, 'measure.swift'), p_png, '--alpha'))

    x0, y0, x1, y1 = m['bbox']
    lock = {
        'x0': round((x0 - OX) / PROBE_W, 4),
        'y0': round((y0 - OY) / PROBE_W, 4),
        'x1': round((x1 + 1 - OX) / PROBE_W, 4),
        'y1': round((y1 + 1 - OY) / PROBE_W, 4),
    }
    print('measured bbox:', m['bbox'], '->', m['bbox_size'])
    print('\nLOCK = ' + repr(lock).replace("'", '') .replace('{', 'dict(').replace('}', ')'))
    print(f"\nlockup aspect (w/h): {(lock['x1']-lock['x0'])/(lock['y1']-lock['y0']):.4f}")
    print(f"lockup w = {lock['x1']-lock['x0']:.4f} x letters_w")
    print(f"lockup h = {lock['y1']-lock['y0']:.4f} x letters_w")

    # Verify: rebuild at the real size with auto-centring and confirm it lands centred.
    build.LOCK.update(lock)
    L2 = dict(build.L)
    L2.update(letters_x=None, letters_y=None)
    svg2, info = build.build(L=L2, tile=False)
    open(p_svg, 'w').write(svg2)
    sh('swift', os.path.join(HERE, 'render.swift'), p_svg, p_png, '1024', '--alpha')
    m2 = json.loads(sh('swift', os.path.join(HERE, 'measure.swift'), p_png, '--alpha'))
    print(f"\nverify @ letters_w={L2['letters_w']}: bbox {m2['bbox']} size {m2['bbox_size']}")
    print(f"  off-centre by dx={m2['dx_to_center']:.1f} dy={m2['dy_to_center']:.1f} px")
    print(f"  contentFraction = {m2['content_fraction']:.4f}")


if __name__ == '__main__':
    main()
