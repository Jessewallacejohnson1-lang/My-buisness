// mask.swift — build a CLEAN silhouette mask of the script BP letterforms.
//
// The source art is a 3-D bevelled render, so a naive colour threshold leaves
// hairline slivers where the bevel goes dark. Fix: threshold generously, keep the
// two largest components (B and P), then fill every interior hole below an area
// cutoff — slivers die, real counters survive.
//
// usage: swift mask.swift <in.png> <out.pbm> [holeMaxPx]
import Foundation
import CoreGraphics
import ImageIO

struct Raster { let w: Int, h: Int; var px: [UInt8] }

func loadPNG(_ p: String) -> Raster {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Raster(w: w, h: h, px: buf)
}

/// 4-connected labelling over `mask`; returns labels and per-label pixel counts.
func label(_ mask: [Bool], _ w: Int, _ h: Int) -> ([Int], [Int]) {
    var lab = [Int](repeating: -1, count: w * h)
    var counts: [Int] = []
    var stack: [Int] = []
    for s in 0..<(w * h) where mask[s] && lab[s] < 0 {
        let id = counts.count
        var n = 0
        stack.append(s); lab[s] = id
        while let p = stack.popLast() {
            n += 1
            let x = p % w, y = p / w
            if x > 0 { let q = p - 1; if mask[q] && lab[q] < 0 { lab[q] = id; stack.append(q) } }
            if x < w - 1 { let q = p + 1; if mask[q] && lab[q] < 0 { lab[q] = id; stack.append(q) } }
            if y > 0 { let q = p - w; if mask[q] && lab[q] < 0 { lab[q] = id; stack.append(q) } }
            if y < h - 1 { let q = p + w; if mask[q] && lab[q] < 0 { lab[q] = id; stack.append(q) } }
        }
        counts.append(n)
    }
    return (lab, counts)
}

/// Chamfer 3-4 distance transform: distance (x3) from every pixel to the nearest `set` pixel.
func distance(to set: [Bool], _ w: Int, _ h: Int) -> [Int] {
    let INF = Int.max / 4
    var d = set.map { $0 ? 0 : INF }
    @inline(__always) func rel(_ i: Int, _ j: Int, _ cost: Int) {
        let v = d[j] + cost
        if v < d[i] { d[i] = v }
    }
    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            if x > 0 { rel(i, i - 1, 3) }
            if y > 0 {
                rel(i, i - w, 3)
                if x > 0 { rel(i, i - w - 1, 4) }
                if x < w - 1 { rel(i, i - w + 1, 4) }
            }
        }
    }
    for y in stride(from: h - 1, through: 0, by: -1) {
        for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            if x < w - 1 { rel(i, i + 1, 3) }
            if y < h - 1 {
                rel(i, i + w, 3)
                if x < w - 1 { rel(i, i + w + 1, 4) }
                if x > 0 { rel(i, i + w - 1, 4) }
            }
        }
    }
    return d
}

/// Morphological closing with a (near-)disk of radius r: dilate then erode.
/// Bridges the dark bevel creases that split a highlight rim off the stroke body,
/// without changing the silhouette's overall size.
func close(_ m: [Bool], _ w: Int, _ h: Int, radius r: Int) -> [Bool] {
    guard r > 0 else { return m }
    let t = r * 3
    let dOut = distance(to: m, w, h)
    let dilated = dOut.map { $0 <= t }
    let dIn = distance(to: dilated.map { !$0 }, w, h)   // distance to background
    return dIn.indices.map { dIn[$0] > t }
}

let args = CommandLine.arguments
let img = loadPNG(args[1])
let outPath = args[2]
let holeMax = args.count > 3 ? Int(args[3])! : 3000
let closeR = args.count > 4 ? Int(args[4])! : 0
let w = img.w, h = img.h

// 1. Generous chromatic threshold — catches the dark bevel shading too.
var m = [Bool](repeating: false, count: w * h)
for i in stride(from: 0, to: w * h * 4, by: 4) {
    let R = Int(img.px[i]), G = Int(img.px[i + 1]), B = Int(img.px[i + 2]), A = Int(img.px[i + 3])
    guard A > 100 else { continue }
    m[i / 4] = R > 62 && (R - B) > 28 && R >= G - 8
}

// 1b. Close the bevel creases so highlight rims rejoin their stroke body.
if closeR > 0 {
    let before = m.filter { $0 }.count
    m = close(m, w, h, radius: closeR)
    print("closed r=\(closeR): \(before) -> \(m.filter { $0 }.count) px")
}

// 2. Keep the two largest components.
let (lab, counts) = label(m, w, h)
let top = counts.enumerated().sorted { $0.element > $1.element }.prefix(2).map { $0.offset }
print("components: \(counts.count); keeping \(top.map { "#\($0)(\(counts[$0]))" }.joined(separator: " "))")
let keepSet = Set(top)
for i in 0..<(w * h) { m[i] = lab[i] >= 0 && keepSet.contains(lab[i]) }

// 3. Fill interior holes under the area cutoff.
var inv = m.map { !$0 }
let (ilab, icounts) = label(inv, w, h)
var touchesEdge = [Bool](repeating: false, count: icounts.count)
for x in 0..<w {
    if ilab[x] >= 0 { touchesEdge[ilab[x]] = true }
    if ilab[(h - 1) * w + x] >= 0 { touchesEdge[ilab[(h - 1) * w + x]] = true }
}
for y in 0..<h {
    if ilab[y * w] >= 0 { touchesEdge[ilab[y * w]] = true }
    if ilab[y * w + w - 1] >= 0 { touchesEdge[ilab[y * w + w - 1]] = true }
}
var filled = 0, kept = 0
var fillIds = Set<Int>()
for id in 0..<icounts.count where !touchesEdge[id] {
    if icounts[id] < holeMax { fillIds.insert(id); filled += 1 } else { kept += 1 }
}
for i in 0..<(w * h) where ilab[i] >= 0 && fillIds.contains(ilab[i]) { m[i] = true }
print("holes: filled \(filled) (<\(holeMax)px), kept \(kept) real counters")
for id in 0..<icounts.count where !touchesEdge[id] && icounts[id] >= holeMax {
    print("  counter kept: \(icounts[id]) px")
}

// 4. Write P4 PBM (1 = black = traced).
var out = Data("P4\n\(w) \(h)\n".utf8)
let rowBytes = (w + 7) / 8
var bits = [UInt8](repeating: 0, count: rowBytes * h)
for y in 0..<h {
    for x in 0..<w where m[y * w + x] { bits[y * rowBytes + (x >> 3)] |= UInt8(0x80 >> (x & 7)) }
}
out.append(contentsOf: bits)
try! out.write(to: URL(fileURLWithPath: outPath))

var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
for i in 0..<(w * h) where m[i] {
    let x = i % w, y = i / w
    x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
}
print("mask bbox (\(x0),\(y0))-(\(x1),\(y1)) = \(x1-x0+1)x\(y1-y0+1)  -> \(outPath)")
