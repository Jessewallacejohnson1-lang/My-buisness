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
// bilinear coverage
func cover(_ fx: Double, _ fy: Double) -> Double {
    let x0 = Int(floor(fx)), y0 = Int(floor(fy))
    guard x0 >= 0, y0 >= 0, x0+1 < W, y0+1 < H else { return 0 }
    let tx = fx - Double(x0), ty = fy - Double(y0)
    func lum(_ x: Int, _ y: Int) -> Double {
        let i = (y * W + x) * 4
        let l = 0.2126*Double(px[i]) + 0.7152*Double(px[i+1]) + 0.0722*Double(px[i+2])
        return max(0, min(1, 1 - l/255))
    }
    let a0 = lum(x0,y0)*(1-tx) + lum(x0+1,y0)*tx
    let a1 = lum(x0,y0+1)*(1-tx) + lum(x0+1,y0+1)*tx
    return a0*(1-ty) + a1*ty
}
let cx = Double(a[2])!, cy = Double(a[3])!, rad = Double(a[4])!
// clock angle: 12 o'clock = 0, increasing clockwise
var hits: [Double] = []
for deg in stride(from: 0.0, to: 360.0, by: 0.5) {
    let th = (deg - 90) * .pi / 180          // screen coords, y down, 0deg = 12 o'clock
    let x = cx + rad * cos(th), y = cy + rad * sin(th)
    let c = cover(x, y)
    if c > 0.5 { hits.append(deg) }
}
if hits.isEmpty { print("no ink at r=\(rad)"); exit(0) }
// find contiguous runs (wrapping)
var runs: [(Double, Double)] = []
var start = hits[0], prev = hits[0]
for d in hits.dropFirst() {
    if d - prev > 1.0 { runs.append((start, prev)); start = d }
    prev = d
}
runs.append((start, prev))
for (s, e) in runs {
    print(String(format: "run %.1fdeg .. %.1fdeg  (sweep %.1f)  = %.2f o'clock .. %.2f o'clock",
                 s, e, e-s, s/30, e/30))
}
