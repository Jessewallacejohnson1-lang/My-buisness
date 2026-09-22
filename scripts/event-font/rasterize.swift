import AppKit

// Paths: argv[1] = alphabet sheet PNG, argv[2] = work directory.
let sheetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "alphabet-sheet.png"
let work = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/event-font-build"

let img = NSImage(contentsOfFile: sheetPath)!
var rr = NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
let cg = img.cgImage(forProposedRect: &rr, context: nil, hints: nil)!

let tsv = try! String(contentsOfFile: work + "/glyphs.tsv", encoding: .utf8)
let SCALE = 6

func bmp(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

var count = 0
for line in tsv.split(separator: "\n") {
    let f = line.split(separator: "\t").map { Int($0)! }
    guard f.count == 6 else { continue }
    let (band, idx, x0, x1, y0, y1) = (f[0], f[1], f[2], f[3], f[4], f[5])
    let pad = 1
    let cw = x1 - x0 + 1 + pad * 2, ch = y1 - y0 + 1 + pad * 2
    let cut = cg.cropping(to: CGRect(x: x0 - pad, y: y0 - pad, width: cw, height: ch))!
    let ow = cw * SCALE, oh = ch * SCALE
    let ctx = bmp(ow, oh)
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor.white); ctx.fill(CGRect(x: 0, y: 0, width: ow, height: oh))
    ctx.draw(cut, in: CGRect(x: 0, y: 0, width: ow, height: oh))
    let out = ctx.makeImage()!
    var buf = [UInt8](repeating: 0, count: ow * oh * 4)
    let m = CGContext(data: &buf, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    m.draw(out, in: CGRect(x: 0, y: 0, width: ow, height: oh))
    var s = "P1\n\(ow) \(oh)\n"
    s.reserveCapacity(ow * oh * 2 + 32)
    for y in 0..<oh {
        var row = ""
        row.reserveCapacity(ow * 2)
        for x in 0..<ow {
            let i = (y * ow + x) * 4
            let lum = (Int(buf[i]) * 299 + Int(buf[i+1]) * 587 + Int(buf[i+2]) * 114) / 1000
            row += lum < 140 ? "1 " : "0 "
        }
        s += row + "\n"
    }
    try! s.write(toFile: work + "/glyphs/b\(band)_\(idx).pbm", atomically: true, encoding: .utf8)
    count += 1
}
print("wrote \(count) pbm files at \(SCALE)x")
