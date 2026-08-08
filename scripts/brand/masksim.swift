// masksim.swift — simulate how iOS masks an app icon, so baked-in corner rounding can
// be caught BEFORE it ships. Composites the masked icon over a light ground, which is
// where a dark double-corner or a cut bezel would show up worst.
//
// usage: swift masksim.swift <icon.png> <out.png> <size>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let size = a.count > 3 ? Int(a[3])! : 512
let CORNER: CGFloat = 0.2237          // Apple's icon corner ratio

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!

let pad = size / 8
let W = size + pad * 2
let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .high

// A light ground — the worst case for spotting dark corner artefacts.
ctx.setFillColor(CGColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))

let r = CGRect(x: pad, y: pad, width: size, height: size)
ctx.saveGState()
let path = CGPath(roundedRect: r, cornerWidth: CGFloat(size) * CORNER,
                  cornerHeight: CGFloat(size) * CORNER, transform: nil)
ctx.addPath(path)
ctx.clip()
ctx.draw(img, in: r)
ctx.restoreGState()

let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dst)
print("masked \(a[1]) at corner ratio \(CORNER) -> \(a[2])")
