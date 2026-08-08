// render.swift — a tiny, dependency-free renderer for the SVG subset this logo uses.
// The point is that the shipped .svg and every exported .png come from the SAME
// geometry, so they cannot drift.
//
// Supported: <svg viewBox>, <rect> (with rx), <circle>, <path d fill fill-rule>,
// <polygon points>, and a per-element `transform="translate(x,y) rotate(d) scale(s)"`.
// Fills are #RGB/#RRGGBB/none, with optional fill-opacity.
//
// usage: swift render.swift <in.svg> <out.png> <pixelSize> [--alpha] [--bg #RRGGBB]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - path data parser (absolute + relative, all cubic/line commands)

func cgPath(fromD d: String) -> CGPath {
    let p = CGMutablePath()
    var i = d.startIndex
    var cur = CGPoint.zero, start = CGPoint.zero, prevC2: CGPoint? = nil
    var cmd: Character = "M"

    func skip() {
        while i < d.endIndex, d[i] == " " || d[i] == "," || d[i] == "\n" || d[i] == "\t" { i = d.index(after: i) }
    }
    func num() -> CGFloat {
        skip()
        var s = ""
        if i < d.endIndex, d[i] == "-" || d[i] == "+" { s.append(d[i]); i = d.index(after: i) }
        while i < d.endIndex, d[i].isNumber || d[i] == "." { s.append(d[i]); i = d.index(after: i) }
        if i < d.endIndex, d[i] == "e" || d[i] == "E" {
            s.append(d[i]); i = d.index(after: i)
            if i < d.endIndex, d[i] == "-" || d[i] == "+" { s.append(d[i]); i = d.index(after: i) }
            while i < d.endIndex, d[i].isNumber { s.append(d[i]); i = d.index(after: i) }
        }
        return CGFloat(Double(s) ?? 0)
    }
    func more() -> Bool {
        skip()
        guard i < d.endIndex else { return false }
        return d[i].isNumber || d[i] == "-" || d[i] == "+" || d[i] == "."
    }

    while true {
        skip()
        guard i < d.endIndex else { break }
        if d[i].isLetter { cmd = d[i]; i = d.index(after: i) }
        let rel = cmd.isLowercase
        switch Character(cmd.lowercased()) {
        case "m":
            var pt = CGPoint(x: num(), y: num())
            if rel { pt = CGPoint(x: cur.x + pt.x, y: cur.y + pt.y) }
            p.move(to: pt); cur = pt; start = pt; prevC2 = nil
            while more() {                       // extra pairs are implicit linetos
                var q = CGPoint(x: num(), y: num())
                if rel { q = CGPoint(x: cur.x + q.x, y: cur.y + q.y) }
                p.addLine(to: q); cur = q
            }
        case "l":
            repeat {
                var pt = CGPoint(x: num(), y: num())
                if rel { pt = CGPoint(x: cur.x + pt.x, y: cur.y + pt.y) }
                p.addLine(to: pt); cur = pt; prevC2 = nil
            } while more()
        case "h":
            repeat { let x = num(); let pt = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                     p.addLine(to: pt); cur = pt; prevC2 = nil } while more()
        case "v":
            repeat { let y = num(); let pt = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                     p.addLine(to: pt); cur = pt; prevC2 = nil } while more()
        case "c":
            repeat {
                var c1 = CGPoint(x: num(), y: num())
                var c2 = CGPoint(x: num(), y: num())
                var pt = CGPoint(x: num(), y: num())
                if rel {
                    c1 = CGPoint(x: cur.x + c1.x, y: cur.y + c1.y)
                    c2 = CGPoint(x: cur.x + c2.x, y: cur.y + c2.y)
                    pt = CGPoint(x: cur.x + pt.x, y: cur.y + pt.y)
                }
                p.addCurve(to: pt, control1: c1, control2: c2); prevC2 = c2; cur = pt
            } while more()
        case "s":
            repeat {
                var c2 = CGPoint(x: num(), y: num())
                var pt = CGPoint(x: num(), y: num())
                if rel {
                    c2 = CGPoint(x: cur.x + c2.x, y: cur.y + c2.y)
                    pt = CGPoint(x: cur.x + pt.x, y: cur.y + pt.y)
                }
                let c1 = prevC2.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                p.addCurve(to: pt, control1: c1, control2: c2); prevC2 = c2; cur = pt
            } while more()
        case "q":
            repeat {
                var c = CGPoint(x: num(), y: num())
                var pt = CGPoint(x: num(), y: num())
                if rel { c = CGPoint(x: cur.x + c.x, y: cur.y + c.y)
                         pt = CGPoint(x: cur.x + pt.x, y: cur.y + pt.y) }
                p.addQuadCurve(to: pt, control: c); cur = pt; prevC2 = nil
            } while more()
        case "z":
            p.closeSubpath(); cur = start; prevC2 = nil
        default:
            _ = num()
        }
    }
    return p
}

// MARK: - minimal SVG element scan

func attr(_ tag: String, _ name: String) -> String? {
    guard let r = tag.range(of: "\(name)=\"") else { return nil }
    let rest = tag[r.upperBound...]
    guard let e = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<e])
}
func fnum(_ tag: String, _ name: String, _ dflt: CGFloat = 0) -> CGFloat {
    attr(tag, name).flatMap { Double($0) }.map { CGFloat($0) } ?? dflt
}

func color(_ s: String?) -> CGColor? {
    guard var h = s, h != "none" else { return nil }
    if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
    return CGColor(red: CGFloat((v >> 16) & 255) / 255,
                   green: CGFloat((v >> 8) & 255) / 255,
                   blue: CGFloat(v & 255) / 255, alpha: 1)
}

/// Parse `transform="translate(a,b) rotate(d[,cx,cy]) scale(sx[,sy])"` into a CGAffineTransform.
func transform(_ s: String?) -> CGAffineTransform {
    guard let s else { return .identity }
    var t = CGAffineTransform.identity
    let re = try! NSRegularExpression(pattern: "(translate|rotate|scale|matrix)\\(([^)]*)\\)")
    for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
        let op = String(s[Range(m.range(at: 1), in: s)!])
        let args = String(s[Range(m.range(at: 2), in: s)!])
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0) }.map { CGFloat($0) }
        switch op {
        case "translate": t = t.translatedBy(x: args[0], y: args.count > 1 ? args[1] : 0)
        case "scale":     t = t.scaledBy(x: args[0], y: args.count > 1 ? args[1] : args[0])
        case "rotate":
            let r = args[0] * .pi / 180
            if args.count >= 3 {
                t = t.translatedBy(x: args[1], y: args[2]).rotated(by: r).translatedBy(x: -args[1], y: -args[2])
            } else { t = t.rotated(by: r) }
        case "matrix":    t = t.concatenating(CGAffineTransform(a: args[0], b: args[1], c: args[2],
                                                               d: args[3], tx: args[4], ty: args[5]))
        default: break
        }
    }
    return t
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 4 else { fatalError("usage: render.swift <in.svg> <out.png> <size> [--alpha] [--bg #hex]") }
let svg = try! String(contentsOfFile: args[1], encoding: .utf8)
let outPath = args[2]
let size = Int(args[3])!
let wantAlpha = args.contains("--alpha")
var bg: CGColor? = nil
if let bi = args.firstIndex(of: "--bg"), bi + 1 < args.count { bg = color(args[bi + 1]) }

// viewBox -> user units
var vb: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 1024, 1024)
if let v = attr(svg, "viewBox") {
    let n = v.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }.map { CGFloat($0) }
    if n.count == 4 { vb = (n[0], n[1], n[2], n[3]) }
}

// Non-square viewBoxes render at the viewBox aspect, so comparison strips and
// wordmark lockups work without a second tool.
let scale = CGFloat(size) / vb.2
let outH = Int((CGFloat(size) * vb.3 / vb.2).rounded())
let cs = CGColorSpaceCreateDeviceRGB()
let info = wantAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue
                     : CGImageAlphaInfo.noneSkipLast.rawValue
let ctx = CGContext(data: nil, width: size, height: outH, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs, bitmapInfo: info)!
ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

if let bg {
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: outH))
}

// SVG y-down -> CoreGraphics y-up
ctx.translateBy(x: 0, y: CGFloat(outH))
ctx.scaleBy(x: scale, y: -scale)
ctx.translateBy(x: -vb.0, y: -vb.1)

// Walk elements in document order.
let elemRE = try! NSRegularExpression(pattern: "<(rect|circle|ellipse|path|polygon)\\b[^>]*/?>")
let ns = svg as NSString
var painted = 0
for m in elemRE.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
    let tag = ns.substring(with: m.range)
    let kind = ns.substring(with: m.range(at: 1))
    guard let fill = color(attr(tag, "fill")) else { continue }
    let op = attr(tag, "fill-opacity").flatMap { Double($0) } ?? 1.0

    ctx.saveGState()
    ctx.concatenate(transform(attr(tag, "transform")))
    ctx.setFillColor(fill.copy(alpha: CGFloat(op))!)

    let path = CGMutablePath()
    switch kind {
    case "rect":
        let r = CGRect(x: fnum(tag, "x"), y: fnum(tag, "y"),
                       width: fnum(tag, "width"), height: fnum(tag, "height"))
        let rx = fnum(tag, "rx")
        if rx > 0 { path.addRoundedRect(in: r, cornerWidth: rx, cornerHeight: fnum(tag, "ry", rx)) }
        else { path.addRect(r) }
    case "circle":
        let c = CGPoint(x: fnum(tag, "cx"), y: fnum(tag, "cy")), rr = fnum(tag, "r")
        path.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    case "ellipse":
        let c = CGPoint(x: fnum(tag, "cx"), y: fnum(tag, "cy"))
        let rx = fnum(tag, "rx"), ry = fnum(tag, "ry")
        path.addEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    case "polygon":
        let n = (attr(tag, "points") ?? "").split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" })
            .compactMap { Double($0) }.map { CGFloat($0) }
        guard n.count >= 6 else { ctx.restoreGState(); continue }
        path.move(to: CGPoint(x: n[0], y: n[1]))
        for k in stride(from: 2, to: n.count - 1, by: 2) { path.addLine(to: CGPoint(x: n[k], y: n[k + 1])) }
        path.closeSubpath()
    case "path":
        guard let d = attr(tag, "d") else { ctx.restoreGState(); continue }
        path.addPath(cgPath(fromD: d))
    default: break
    }

    ctx.addPath(path)
    if attr(tag, "fill-rule") == "evenodd" { ctx.fillPath(using: .evenOdd) } else { ctx.fillPath() }
    ctx.restoreGState()
    painted += 1
}

guard let img = ctx.makeImage() else { fatalError("render failed") }
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, img, nil)
guard CGImageDestinationFinalize(dst) else { fatalError("png write failed") }
print("rendered \(painted) elements -> \(outPath) @ \(size)x\(outH) (alpha: \(wantAlpha))")
