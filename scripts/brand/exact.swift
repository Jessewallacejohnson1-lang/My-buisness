// exact.swift — ship the source render itself as the icon, 1:1.
//
// The artwork is a rounded tile floating on black. An iOS icon must be full-bleed (iOS
// applies its own squircle mask), so this crops to the tile FACE — the largest centred
// square inside the tile's bounding box — and scales it to 1024 with high-quality
// resampling. Nothing is redrawn; the glossy letterforms are the original pixels.
//
// Emits all three assets plus the alpha template, and measures the lockup so
// contentFraction can be updated.
//
// usage: swift exact.swift <src.png> <outDir> <tileX> <tileY> <tileW> <tileH>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let ICON = 1024, INSET = 72
let CROP = ICON - 2 * INSET          // 880

let a = CommandLine.arguments
let outDir = a[2]
let tx = Int(a[3])!, ty = Int(a[4])!, tw = Int(a[5])!, th = Int(a[6])!

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let full = CGImageSourceCreateImageAtIndex(src, 0, nil)!

// Largest centred square inside the tile bbox — avoids any aspect distortion.
let side = min(tw, th)
let sx = tx + (tw - side) / 2, sy = ty + (th - side) / 2
print("tile face crop: (\(sx),\(sy)) \(side)x\(side)  ->  \(ICON)x\(ICON)")

func write(_ img: CGImage, _ path: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                              UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { fatalError("write failed \(path)") }
}

/// Draw a source rect into a square RGB context of `size`, no alpha channel.
func scaled(_ img: CGImage, from r: CGRect, to size: Int, alpha: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast
                                           : CGImageAlphaInfo.noneSkipLast).rawValue)!
    ctx.interpolationQuality = .high
    let cropped = img.cropping(to: r)!
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

// 1. AppIcon — full-bleed, no alpha.
let faceRect = CGRect(x: sx, y: sy, width: side, height: side)
let icon = scaled(full, from: faceRect, to: ICON)
write(icon, "\(outDir)/AppIcon.png")

// 2. LaunchMark — the documented 72/1024 inset crop of those same pixels.
let lm = CGContext(data: nil, width: CROP, height: CROP, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
lm.interpolationQuality = .high
lm.draw(icon.cropping(to: CGRect(x: INSET, y: INSET, width: CROP, height: CROP))!,
        in: CGRect(x: 0, y: 0, width: CROP, height: CROP))
let launch = lm.makeImage()!
write(launch, "\(outDir)/LaunchMark.png")

// 3. MarkTemplate — alpha = the coral letterform coverage, same geometry.
//    Read the icon's pixels and score each one on how coral it is, so the antialiased
//    edges of the render carry into the template instead of hard-clipping.
let w = icon.width, h = icon.height
var px = [UInt8](repeating: 0, count: w * h * 4)
px.withUnsafeMutableBytes { raw in
    let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(icon, in: CGRect(x: 0, y: 0, width: w, height: h))
}
var alpha = [UInt8](repeating: 0, count: w * h)
var lx0 = w, ly0 = h, lx1 = -1, ly1 = -1
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let R = Int(px[i]), B = Int(px[i + 2])
        // Coral-ness: red lead over blue, ramped so edge pixels get partial alpha.
        let lead = Double(R - B)
        let v = max(0, min(1, (lead - 12) / 45)) * max(0, min(1, (Double(R) - 40) / 60))
        let av = UInt8((v * 255).rounded())
        alpha[y * w + x] = av
        if av > 40 {
            if x < lx0 { lx0 = x }; if x > lx1 { lx1 = x }
            if y < ly0 { ly0 = y }; if y > ly1 { ly1 = y }
        }
    }
}
var tbuf = [UInt8](repeating: 0, count: CROP * CROP * 4)
for y in 0..<CROP {
    for x in 0..<CROP {
        let d = (y * CROP + x) * 4
        tbuf[d] = 0; tbuf[d + 1] = 0; tbuf[d + 2] = 0
        tbuf[d + 3] = alpha[(y + INSET) * w + (x + INSET)]
    }
}
let tctx = CGContext(data: &tbuf, width: CROP, height: CROP, bitsPerComponent: 8,
                     bytesPerRow: CROP * 4, space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
write(tctx.makeImage()!, "\(outDir)/MarkTemplate.png")

// 4. Measure the lockup for contentFraction (defined against the 880 LaunchMark).
let lw = lx1 - lx0 + 1, lh = ly1 - ly0 + 1
print("lockup on the 1024 tile: \(lw)x\(lh) at (\(lx0),\(ly0))")
print(String(format: "lockup as fraction of 1024: %.4f", Double(max(lw, lh)) / Double(ICON)))
print(String(format: "contentFraction (of the 880 LaunchMark): %.4f", Double(max(lw, lh)) / Double(CROP)))
print(String(format: "lockup centre offset from tile centre: dx %.1f  dy %.1f",
             Double(lx0 + lx1) / 2 - Double(ICON - 1) / 2,
             Double(ly0 + ly1) / 2 - Double(ICON - 1) / 2))
