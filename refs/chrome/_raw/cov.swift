// cov.swift — subpixel ink measurements by coverage (1 - luma/255).
// usage: cov <png> <mode> <args...>
import Foundation
import CoreGraphics
import ImageIO
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let W = img.width, H = img.height
var px = [UInt8](repeating: 0, count: W * H * 4)
px.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
}
func cover(_ x: Int, _ y: Int) -> Double {
    let i = (y * W + x) * 4
    let l = 0.2126*Double(px[i]) + 0.7152*Double(px[i+1]) + 0.0722*Double(px[i+2])
    return max(0, min(1, 1 - l/255))
}
let mode = a[2]
switch mode {
case "hrun":   // horizontal coverage runs on row y over [x0,x1): prints each run's total coverage + centroid
    let y = Int(a[3])!, x0 = Int(a[4])!, x1 = Int(a[5])!
    var sum = 0.0, wsum = 0.0, inRun = false
    var out: [String] = []
    for x in x0..<x1 {
        let c = cover(x, y)
        if c > 0.02 { sum += c; wsum += c * Double(x); inRun = true }
        else if inRun { out.append(String(format: "w=%.2f c=%.2f", sum, wsum/sum)); sum = 0; wsum = 0; inRun = false }
    }
    if inRun { out.append(String(format: "w=%.2f c=%.2f", sum, wsum/sum)) }
    print("y=\(y): " + out.joined(separator: "  |  "))
case "vrun":
    let x = Int(a[3])!, y0 = Int(a[4])!, y1 = Int(a[5])!
    var sum = 0.0, wsum = 0.0, inRun = false
    var out: [String] = []
    for y in y0..<y1 {
        let c = cover(x, y)
        if c > 0.02 { sum += c; wsum += c * Double(y); inRun = true }
        else if inRun { out.append(String(format: "w=%.2f c=%.2f", sum, wsum/sum)); sum = 0; wsum = 0; inRun = false }
    }
    if inRun { out.append(String(format: "w=%.2f c=%.2f", sum, wsum/sum)) }
    print("x=\(x): " + out.joined(separator: "  |  "))
case "bbox":  // coverage-weighted extremes: first/last x,y where coverage crosses 0.5
    let x0 = Int(a[3])!, y0 = Int(a[4])!, w = Int(a[5])!, h = Int(a[6])!
    var minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9, total = 0.0, cx = 0.0, cy = 0.0
    for y in y0..<(y0+h) { for x in x0..<(x0+w) {
        let c = cover(x,y)
        if c > 0.02 {
            total += c; cx += c*Double(x); cy += c*Double(y)
            // edge position with subpixel: treat pixel as covering [x, x+1)
            minx = min(minx, Double(x) + (1 - c)); maxx = max(maxx, Double(x) + c)
            miny = min(miny, Double(y) + (1 - c)); maxy = max(maxy, Double(y) + c)
        }
    }}
    print(String(format: "x %.2f..%.2f (w %.2f)  y %.2f..%.2f (h %.2f)  ink=%.1f  centroid(%.2f,%.2f)",
                 minx, maxx, maxx-minx, miny, maxy, maxy-miny, total, cx/total, cy/total))
default: break
}
