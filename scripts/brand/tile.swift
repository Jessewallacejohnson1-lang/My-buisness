// tile.swift — locate the rounded tile's face inside the source render.
//
// The artwork is a dark rounded tile floating on a pure-black ground. To ship it as an
// iOS icon it must be FULL-BLEED (iOS applies its own squircle mask), so the black
// surround and the baked corner rounding have to be cropped off. This finds the tile's
// bounding box, and reports how far in the corners are rounded so the crop can be taken
// inside the rounding rather than through it.
//
// usage: swift tile.swift <in.png> [lumaThreshold]
import Foundation
import CoreGraphics
import ImageIO

let a = CommandLine.arguments
let thr = a.count > 2 ? Double(a[2])! : 6.0

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

@inline(__always) func luma(_ x: Int, _ y: Int) -> Double {
    let i = (y * w + x) * 4
    return 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
}

// Outer bbox of anything brighter than the black ground.
var x0 = w, y0 = h, x1 = -1, y1 = -1
for y in 0..<h {
    for x in 0..<w where luma(x, y) > thr {
        if x < x0 { x0 = x }; if x > x1 { x1 = x }
        if y < y0 { y0 = y }; if y > y1 { y1 = y }
    }
}
print("tile bbox: (\(x0),\(y0))-(\(x1),\(y1))  =  \(x1 - x0 + 1) x \(y1 - y0 + 1)")

// Scan the centre row/column to confirm the flat faces (unrounded spans).
let cy = (y0 + y1) / 2, cx = (x0 + x1) / 2
var rowL = x0, rowR = x1, colT = y0, colB = y1
while rowL < w && luma(rowL, cy) <= thr { rowL += 1 }
while rowR > 0 && luma(rowR, cy) <= thr { rowR -= 1 }
while colT < h && luma(cx, colT) <= thr { colT += 1 }
while colB > 0 && luma(cx, colB) <= thr { colB -= 1 }
print("centre row span: \(rowL)..\(rowR)   centre col span: \(colT)..\(colB)")

// Corner rounding: at each row from the top, how far in does the tile start?
// The inset shrinks to 0 once past the corner radius.
print("corner profile (row -> left edge inset from tile bbox):")
for dy in [0, 2, 5, 10, 20, 40, 60, 80, 100, 130, 160] {
    let y = y0 + dy
    guard y <= y1 else { continue }
    var x = x0
    while x <= x1 && luma(x, y) <= thr { x += 1 }
    print("  +\(dy): \(x - x0)")
}
