// measure.swift — report the artwork bbox and coverage of a rendered mark.
//
// Two modes:
//   --alpha            treat any pixel with alpha > 0 as artwork
//   --not <#RRGGBB>    treat any pixel differing from that colour as artwork
//                      (this is how the icon's lockup is measured against its tile)
//
// Prints JSON so the fit loop can consume it.
// usage: swift measure.swift <in.png> [--alpha | --not #RRGGBB] [--tol N]
import Foundation
import CoreGraphics
import ImageIO

let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
px.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
}

let useAlpha = a.contains("--alpha")
var bgR = 0, bgG = 0, bgB = 0
if let i = a.firstIndex(of: "--not"), i + 1 < a.count {
    var s = a[i + 1]; if s.hasPrefix("#") { s.removeFirst() }
    let v = Int(s, radix: 16)!
    bgR = (v >> 16) & 255; bgG = (v >> 8) & 255; bgB = v & 255
}
let tol = a.firstIndex(of: "--tol").map { Int(a[$0 + 1])! } ?? 10

var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1, n = 0
// Weighted centroid, so optical centring can be checked against geometric centring.
var cx = 0.0, cy = 0.0, wsum = 0.0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let R = Int(px[i]), G = Int(px[i + 1]), B = Int(px[i + 2]), A = Int(px[i + 3])
        let isArt: Bool
        var weight = 1.0
        if useAlpha {
            isArt = A > 8
            weight = Double(A) / 255
        } else {
            let d = abs(R - bgR) + abs(G - bgG) + abs(B - bgB)
            isArt = d > tol
            weight = min(1.0, Double(d) / 120.0)
        }
        guard isArt else { continue }
        n += 1
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        cx += Double(x) * weight; cy += Double(y) * weight; wsum += weight
    }
}

guard n > 0 else { print("{\"error\":\"no artwork found\"}"); exit(1) }
let bw = x1 - x0 + 1, bh = y1 - y0 + 1
let out: [String: Any] = [
    "size": w,
    "bbox": [x0, y0, x1, y1],
    "bbox_size": [bw, bh],
    "long_side": max(bw, bh),
    "content_fraction": Double(max(bw, bh)) / Double(w),
    "coverage": Double(n) / Double(w * h),
    "centroid": [cx / wsum, cy / wsum],
    "bbox_center": [Double(x0 + x1) / 2, Double(y0 + y1) / 2],
    "canvas_center": Double(w - 1) / 2,
    // How far the mark must move to sit dead centre, in canvas units.
    "dx_to_center": Double(w - 1) / 2 - Double(x0 + x1) / 2,
    "dy_to_center": Double(h - 1) / 2 - Double(y0 + y1) / 2,
]
print(String(data: try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
             encoding: .utf8)!)
