// crop.swift — crop a region out of a PNG and scale it, for close inspection.
// usage: swift crop.swift <in.png> <out.png> <x> <y> <w> <h> <outSize>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let rect = CGRect(x: Int(a[3])!, y: Int(a[4])!, width: Int(a[5])!, height: Int(a[6])!)
let out = Int(a[7])!
let cropped = img.cropping(to: rect)!

let ctx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .none    // nearest-neighbour: show the real pixels
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: out, height: out))
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dst)
print("cropped \(rect) -> \(a[2]) @\(out)px")
