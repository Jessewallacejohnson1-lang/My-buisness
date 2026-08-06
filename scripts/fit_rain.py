#!/usr/bin/env python3
"""Fit ballistic parameters per tracked sprite from track_rain.swift's TSV.

Reports per-track least-squares fits of y = y0 + v0*t + 1/2 g t^2 (split at the floor
contact) and x = x0 + vx*t, in physical pixels and in points (@3x). See
docs/town-rain-reference-measurements.md for the method and the numbers these produced.

    python3 scripts/fit_rain.py blobs.tsv          # masks the reference app's animated logo
    python3 scripts/fit_rain.py blobs.tsv nomask   # no mask (use for simulator captures)
"""
import sys, math
from collections import defaultdict

LOGOMASK = (len(sys.argv) < 3)
SCALE = 3.0          # @3x — 1206x2622 px == 402x874 pt
W_PX, H_PX = 1206.0, 2622.0

rows = []
with open(sys.argv[1] if len(sys.argv)>1 else "blobs.tsv") as f:
    f.readline()
    for line in f:
        p = line.rstrip("\n").split("\t")
        if len(p) < 10:
            continue
        fi, t, x, y, w, h, pix, nx, ny, col = p
        rows.append(dict(f=int(fi), t=float(t), x=float(x), y=float(y), w=float(w),
                         h=float(h), pix=int(pix), nx=float(nx), ny=float(ny), col=col))

# Mask the reference app's top-left logo, which wiggles and so survives the median plate.
rows = [d for d in rows if not (d["nx"] < 0.22 and d["ny"] < 0.135 and LOGOMASK)]

byframe = defaultdict(list)
for d in rows:
    byframe[d["f"]].append(d)

# drop exact-duplicate frames (AVAssetImageGenerator repeats on dropped source frames)
ks = sorted(byframe)
dedup = set()
prev_sig = None
for k in ks:
    sig = tuple(sorted((round(d["x"], 1), round(d["y"], 1)) for d in byframe[k]))
    if sig == prev_sig:
        dedup.add(k)
    prev_sig = sig
print(f"duplicate frames dropped: {len(dedup)}")
ks = [k for k in ks if k not in dedup]

# --- track linking (nearest neighbour, tolerant of 1-2 frame gaps) ---
tracks, active = [], []
for k in ks:
    dets = byframe[k][:]
    used = set()
    for tr in active[:]:
        last = tr[-1]
        gap = k - last["f"]
        if gap > 5:
            active.remove(tr); continue
        # predict with last known velocity
        if len(tr) >= 2:
            dt = tr[-1]["t"] - tr[-2]["t"]
            pvx = (tr[-1]["x"] - tr[-2]["x"]) / dt if dt else 0
            pvy = (tr[-1]["y"] - tr[-2]["y"]) / dt if dt else 0
        else:
            pvx = pvy = 0
        best, bd = None, 1e9
        for i, d in enumerate(dets):
            if i in used: continue
            dt = d["t"] - last["t"]
            px_ = last["x"] + pvx * dt
            py_ = last["y"] + pvy * dt
            dist = math.hypot(d["x"] - px_, d["y"] - py_)
            if dist < 130 and dist < bd:
                best, bd = i, dist
        if best is not None:
            used.add(best); tr.append(dets[best])
    for i, d in enumerate(dets):
        if i not in used:
            nt = [d]; tracks.append(nt); active.append(nt)

tracks = [t for t in tracks if len(t) >= 6]
tracks.sort(key=lambda t: t[0]["t"])
print(f"tracks (>=6 samples): {len(tracks)}\n")

def lsq_quad(ts, ys):
    """least-squares y = a + b t + c t^2 -> returns (a,b,c)"""
    n = len(ts)
    S = [sum(t ** k for t in ts) for k in range(5)]
    Sy = [sum(y * t ** k for t, y in zip(ts, ys)) for k in range(3)]
    # normal equations 3x3
    A = [[S[0], S[1], S[2]], [S[1], S[2], S[3]], [S[2], S[3], S[4]]]
    b = [Sy[0], Sy[1], Sy[2]]
    # gaussian elimination
    for i in range(3):
        p = max(range(i, 3), key=lambda r: abs(A[r][i]))
        A[i], A[p] = A[p], A[i]; b[i], b[p] = b[p], b[i]
        for r in range(i + 1, 3):
            m = A[r][i] / A[i][i]
            for c in range(i, 3): A[r][c] -= m * A[i][c]
            b[r] -= m * b[i]
    x = [0, 0, 0]
    for i in (2, 1, 0):
        x[i] = (b[i] - sum(A[i][c] * x[c] for c in range(i + 1, 3))) / A[i][i]
    return x

def lsq_lin(ts, xs):
    n = len(ts); st = sum(ts); stt = sum(t * t for t in ts)
    sx = sum(xs); stx = sum(t * x for t, x in zip(ts, xs))
    d = n * stt - st * st
    b = (n * stx - st * sx) / d
    a = (sx - b * st) / n
    return a, b

spawn_times = []
summ = []
for i, tr in enumerate(tracks):
    # split at bounce: local maximum of y
    ymax_i = max(range(len(tr)), key=lambda j: tr[j]["y"])
    segs = []
    if 3 <= ymax_i <= len(tr) - 4:
        segs = [("fall", tr[:ymax_i + 1]), ("bounce", tr[ymax_i:])]
    else:
        segs = [("fall", tr)]
    t0 = tr[0]["t"]
    spawn_times.append(t0)
    print(f"=== track {i}  spawn t={t0:.3f}s  x0={tr[0]['x']:.0f}px ({tr[0]['x']/SCALE:.0f}pt)  "
          f"y0={tr[0]['y']:.0f}px  n={len(tr)}  color {tr[0]['col']}")
    for name, seg in segs:
        if len(seg) < 4: continue
        ts = [d["t"] - seg[0]["t"] for d in seg]
        a, b, c = lsq_quad(ts, [d["y"] for d in seg])
        xa, xb = lsq_lin(ts, [d["x"] for d in seg])
        g = 2 * c
        rms = math.sqrt(sum((y - (a + b * t + c * t * t)) ** 2 for t, y in zip(ts, [d["y"] for d in seg])) / len(seg))
        print(f"    {name:6s} n={len(seg):3d} dur={ts[-1]:.3f}s  "
              f"vy0={b:8.1f}px/s ({b/SCALE:7.1f}pt/s)  g={g:9.1f}px/s^2 ({g/SCALE:8.1f}pt/s^2)  "
              f"vx={xb:8.1f}px/s ({xb/SCALE:7.1f}pt/s)  fitRMS={rms:.1f}px")
        summ.append((name, b, g, xb))
    # bbox size when fully on-screen (not clipped by an edge)
    inner = [d for d in tr if d["x"] > 90 and d["x"] < W_PX - 90 and d["y"] > 260]
    if inner:
        ws = [d["w"] for d in inner]; hs = [d["h"] for d in inner]
        print(f"    bbox: w {min(ws):.0f}-{max(ws):.0f}px  h {min(hs):.0f}-{max(hs):.0f}px  "
              f"=> ~{max(max(ws), max(hs))/SCALE:.1f}pt sprite")

print("\n=== SPAWN CADENCE ===")
for a, b in zip(spawn_times, spawn_times[1:]):
    print(f"  t={a:.3f} -> {b:.3f}   dt={b-a:.3f}s")

falls = [s for s in summ if s[0] == "fall"]
bounces = [s for s in summ if s[0] == "bounce"]
def stat(v):
    v = sorted(v); n = len(v)
    return f"n={n} min={v[0]:.1f} med={v[n//2]:.1f} max={v[-1]:.1f} mean={sum(v)/n:.1f}"
print("\n=== AGGREGATE (physical px) ===")
print("fall   g   :", stat([s[2] for s in falls]))
print("fall   vy0 :", stat([s[1] for s in falls]))
print("fall   vx  :", stat([s[3] for s in falls]))
if bounces:
    print("bounce g   :", stat([s[2] for s in bounces]))
    print("bounce vy0 :", stat([s[1] for s in bounces]))
print("\n=== AGGREGATE (points, @3x) ===")
print("fall   g   :", stat([s[2] / SCALE for s in falls]))
print("fall   vy0 :", stat([s[1] / SCALE for s in falls]))
print("fall   vx  :", stat([s[3] / SCALE for s in falls]))
