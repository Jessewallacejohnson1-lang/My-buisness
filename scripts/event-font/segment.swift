import AppKit

// Paths: argv[1] = alphabet sheet PNG, argv[2] = work directory.
let sheetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "alphabet-sheet.png"
let work = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/event-font-build"
let img = NSImage(contentsOfFile: sheetPath)!
var rr = NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
let cg = img.cgImage(forProposedRect: &rr, context: nil, hints: nil)!
let W = cg.width, H = cg.height
var buf = [UInt8](repeating: 0, count: W * H * 4)
let c = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
func dark(_ x: Int, _ y: Int) -> Bool {
    let i = (y * W + x) * 4
    return (Int(buf[i]) * 299 + Int(buf[i+1]) * 587 + Int(buf[i+2]) * 114) / 1000 < 128
}
let bands = [(42, 156), (178, 281), (313, 399), (439, 534), (566, 655), (691, 788)]
for (bi, b) in bands.enumerated() {
    var colInk = [Int](repeating: 0, count: W)
    for x in 0..<W { for y in b.0...b.1 where dark(x, y) { colInk[x] += 1 } }
    var spans: [(Int, Int)] = []
    var s = -1
    for x in 0..<W {
        if colInk[x] > 0 && s < 0 { s = x }
        if colInk[x] == 0 && s >= 0 { if x - s >= 2 { spans.append((s, x - 1)) }; s = -1 }
    }
    if s >= 0 { spans.append((s, W - 1)) }
    for (gi, sp) in spans.enumerated() {
        var y0 = H, y1 = -1
        for x in sp.0...sp.1 { for y in b.0...b.1 where dark(x, y) { if y < y0 { y0 = y }; if y > y1 { y1 = y } } }
        print("\(bi)\t\(gi)\t\(sp.0)\t\(sp.1)\t\(y0)\t\(y1)")
    }
}
