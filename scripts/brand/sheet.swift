// sheet.swift — contact sheet: render each SVG at a ladder of real icon sizes so the
// small-size read (the only one that matters on a home screen) can be judged directly.
//
// usage: swift sheet.swift <out.png> <label:file.svg> [<label:file.svg> ...]
import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

// @3x app icon, spotlight, settings, notification. Override with BP_SIZES=300,120
let SIZES: [Int] = ProcessInfo.processInfo.environment["BP_SIZES"]
    .map { $0.split(separator: ",").compactMap { Int($0) } } ?? [180, 120, 87, 60, 40]
let PAD = 26, LABEL_H = 30, ROW_GAP = 26, TOP = 46

let args = CommandLine.arguments
let outPath = args[1]
let entries = args.dropFirst(2).map { s -> (String, String) in
    let p = s.split(separator: ":", maxSplits: 1).map(String.init)
    return (p[0], p[1])
}

func loadPNG(_ p: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Render an SVG via the sibling render.swift, at `size`, into a temp PNG.
func renderSVG(_ svg: String, _ size: Int) -> CGImage {
    let tmp = NSTemporaryDirectory() + "sheet-\(abs(svg.hashValue))-\(size).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    p.arguments = [FileManager.default.currentDirectoryPath + "/work/render.swift", svg, tmp, "\(size)"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try! p.run(); p.waitUntilExit()
    guard let img = loadPNG(tmp) else { fatalError("render failed for \(svg) @\(size)") }
    return img
}

let rowW = PAD + SIZES.reduce(0) { $0 + $1 + PAD }
let rowH = SIZES.max()! + LABEL_H + ROW_GAP
let W = rowW, H = TOP + entries.count * rowH + PAD

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.55, green: 0.55, blue: 0.56, alpha: 1))   // neutral grey ground
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 15, bold: Bool = false) {
    let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
    // Foundation-only build: use the CoreText attribute keys directly.
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1),
    ]
    let astr = CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(astr)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

// CoreGraphics origin is bottom-left; lay rows out from the top.
for (r, (label, file)) in entries.enumerated() {
    let rowTop = CGFloat(H - TOP - r * rowH)
    var x = CGFloat(PAD)
    for s in SIZES {
        // .svg entries re-render at each size (true vector); .png entries (the shipped
        // reference) are downscaled, which is exactly how they'd degrade on device.
        let img = file.hasSuffix(".svg") ? renderSVG(file, s) : loadPNG(file)!
        let y = rowTop - CGFloat(s)
        ctx.draw(img, in: CGRect(x: x, y: y, width: CGFloat(s), height: CGFloat(s)))
        if r == 0 { text("\(s)px", x, rowTop + 12, size: 13) }
        x += CGFloat(s + PAD)
    }
    text(label, CGFloat(PAD), rowTop - CGFloat(SIZES.max()!) - 20, size: 15, bold: true)
}

let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dst)
print("wrote \(outPath) (\(W)x\(H)), \(entries.count) rows x \(SIZES.count) sizes")
