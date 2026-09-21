#!/usr/bin/env python3
"""Export every shipped Block Party mark from the wordmark master.

The Sep 19, 2026 logo is a flat two-colour lockup — black "BlockParty." on a
yellow field — so, unlike the retired painted renders, it can be cleaned
losslessly: every pixel is a coverage blend between exactly two inks. That is
what this script does. It reads the master, resolves each pixel to a coverage
value, and writes the assets back out from that coverage rather than from the
master's JPEG-era noise.

Outputs (see docs/brand/README.md):

  AppIcon.png   1024^2 RGB, full-bleed, no alpha
  LaunchMark.png 880^2 RGB, the 36/1024 inset crop
  Wordmark.png  the tight crop of the letterforms, black on ALPHA, for tinting

Usage: python3 scripts/brand/wordmark.py docs/brand/source-logo-1254.png
Requires: sips (macOS), for the two resamples only.
"""

import os
import struct
import subprocess
import sys
import zlib

YELLOW = (0xFC, 0xE8, 0x04)   # sampled: the master's field colour
INK = (0x00, 0x00, 0x00)      # sampled: the master's letterform colour

# Coverage below/above these reads as "clean field" / "clean ink". Without the
# dead zones the master's compression noise survives as a faint grey haze.
FLOOR, CEIL = 0.06, 0.94


def luma(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    pos, idat, width, height, depth, colour = 8, b"", None, None, None, None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
        elif kind == b"IDAT":
            idat += body
    assert depth == 8, "expected an 8-bit master"
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(idat)
    stride, out, prev, pos = width * channels, bytearray(), bytearray(width * channels), 0
    for _ in range(height):
        filt, pos = raw[pos], pos + 1
        line, pos = bytearray(raw[pos:pos + stride]), pos + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + a) & 255
            elif filt == 2:
                line[x] = (line[x] + b) & 255
            elif filt == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif filt == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out += line
        prev = line
    return width, height, channels, out


def write_png(path, width, height, channels, pixels):
    colour = {3: 2, 4: 6}[channels]
    stride = width * channels
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none. The art is flat, so this compresses fine.
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def coverage(width, height, channels, pixels):
    """Ink coverage, 0...1, for every pixel of the master."""
    field, ink = luma(YELLOW), luma(INK)
    out = [0.0] * (width * height)
    for i in range(width * height):
        o = i * channels
        t = (field - luma((pixels[o], pixels[o + 1], pixels[o + 2]))) / (field - ink)
        t = 0.0 if t < FLOOR else 1.0 if t > CEIL else min(max(t, 0.0), 1.0)
        out[i] = t
    return out


def main():
    master = sys.argv[1] if len(sys.argv) > 1 else "docs/brand/source-logo-1254.png"
    out_dir = os.path.dirname(master) or "."
    width, height, channels, pixels = read_png(master)
    cover = coverage(width, height, channels, pixels)
    print(f"master {width}x{height}")

    # 1. The cleaned full-bleed icon, at the master's own size.
    flat = bytearray(width * height * 3)
    for i, t in enumerate(cover):
        for c in range(3):
            flat[i * 3 + c] = round(YELLOW[c] + (INK[c] - YELLOW[c]) * t)
    clean = f"{out_dir}/clean-{width}.png"
    write_png(clean, width, height, 3, flat)

    # 2. The letterforms alone, tight, black on alpha — the tintable mark.
    xs = [i % width for i, t in enumerate(cover) if t > 0.5]
    ys = [i // width for i, t in enumerate(cover) if t > 0.5]
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    mw, mh = x1 - x0, y1 - y0
    mark = bytearray(mw * mh * 4)
    for y in range(mh):
        for x in range(mw):
            t = cover[(y0 + y) * width + x0 + x]
            o = (y * mw + x) * 4
            mark[o:o + 3] = bytes(INK)
            mark[o + 3] = round(t * 255)
    write_png(f"{out_dir}/wordmark-{mw}x{mh}.png", mw, mh, 4, mark)

    # 3. Resamples. sips does the filtering; nothing here needs to.
    icon = f"{out_dir}/AppIcon.png"
    subprocess.run(["sips", "-z", "1024", "1024", clean, "--out", icon],
                   check=True, stdout=subprocess.DEVNULL)
    inset = round(36 / 1024 * width)
    crop = width - 2 * inset
    launch = f"{out_dir}/LaunchMark.png"
    subprocess.run(["sips", "-c", str(crop), str(crop), clean, "--out", launch],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["sips", "-z", "880", "880", launch, "--out", launch],
                   check=True, stdout=subprocess.DEVNULL)

    print(f"wordmark bbox {mw}x{mh} at ({x0},{y0})")
    print(f"aspect {mw / mh:.4f}")
    print(f"contentFraction (of the {crop} crop): {max(mw, mh) / crop:.4f}")


if __name__ == "__main__":
    main()
