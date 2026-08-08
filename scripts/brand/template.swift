// template.swift — turn a white-on-black silhouette render into a template asset:
// RGBA where alpha is the artwork's antialiased coverage and RGB is black.
//
// iOS template rendering reads alpha only, so the colour channels just need to be
// stable; black keeps the PNG small and predictable in any previewer.
//
// usage: swift template.swift <silhouette.png> <out.png> <inset> <cropSize>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 5 else { fatalError("usage: template.swift <in.png> <out.png> <inset> <crop>") }
let inset = Int(a[3])!, crop = Int(a[4])!

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

// Crop + convert luminance -> alpha. Rec.709 luma keeps the coral and paper areas
// weighted the way the eye sees them; both are pure white here, so any AA ramp in
// between maps straight onto coverage.
var out = [UInt8](repeating: 0, count: crop * crop * 4)
var covered = 0
for y in 0..<crop {
    for x in 0..<crop {
        let s = ((y + inset) * w + (x + inset)) * 4
        let lum = 0.2126 * Double(px[s]) + 0.7152 * Double(px[s + 1]) + 0.0722 * Double(px[s + 2])
        let alpha = UInt8(max(0, min(255, lum.rounded())))
        let d = (y * crop + x) * 4
        // Premultiplied black: RGB stays 0, alpha carries the shape.
        out[d] = 0; out[d + 1] = 0; out[d + 2] = 0; out[d + 3] = alpha
        if alpha > 8 { covered += 1 }
    }
}

let ctx = CGContext(data: &out, width: crop, height: crop, bitsPerComponent: 8,
                    bytesPerRow: crop * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dst) else { fatalError("png write failed") }
print("template \(crop)x\(crop) RGBA, coverage \(String(format: "%.2f%%", Double(covered) / Double(crop * crop) * 100)) -> \(a[2])")
