import UIKit

/// A logo as a small circle shows it: its own ink without the empty border its file carries, and
/// whether that ink is a round badge (JoeTown's, Milk & Honey's), which then fills the whole circle
/// instead of sitting small inside a white ring (Jesse, 2026-10-24: "make it fit the icon better").
/// Worked out from the picture itself, so a new logo needs no marking.
struct LogoFit {
    let image: UIImage
    let round: Bool

    /// Side of the copy the ink is read from: enough to find the border, cheap enough for a feed.
    private static let sample = 96
    /// How far from white a pixel must be to count as ink (out of 255), on a white ground.
    private static let inkStep = 24

    @MainActor private static var cache: [URL: LogoFit] = [:]

    @MainActor static func of(_ image: UIImage, url: URL) -> LogoFit {
        if let fit = cache[url] { return fit }
        let fit = LogoFit(image)
        cache[url] = fit
        return fit
    }

    init(_ image: UIImage) {
        guard let cg = image.cgImage, let ink = Self.ink(cg) else {
            self.image = image
            round = false
            return
        }
        let n = Self.sample
        // The ink's box in the sample, then in the file's own pixels.
        var minX = n, minY = n, maxX = -1, maxY = -1
        for y in 0..<n { for x in 0..<n where ink[y * n + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else {
            self.image = image
            round = false
            return
        }
        let sx = CGFloat(cg.width) / CGFloat(n), sy = CGFloat(cg.height) / CGFloat(n)
        let box = CGRect(x: CGFloat(minX) * sx, y: CGFloat(minY) * sy,
                         width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy).integral
        let trimmed = cg.cropping(to: box).map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) }
        self.image = trimmed ?? image

        // Round: about as wide as tall, its corners empty and its middle full.
        let w = maxX - minX + 1, h = maxY - minY + 1
        let share = { (x0: Int, y0: Int, side: Int) -> Double in
            var hit = 0
            for y in y0..<(y0 + side) { for x in x0..<(x0 + side) where ink[y * n + x] { hit += 1 } }
            return Double(hit) / Double(side * side)
        }
        let aspect = Double(w) / Double(h)
        if aspect >= 0.88, aspect <= 1.12, min(w, h) >= 12 {
            let k = max(1, min(w, h) * 12 / 100), c = max(1, min(w, h) * 30 / 100)
            let corners = [(minX, minY), (maxX - k + 1, minY), (minX, maxY - k + 1), (maxX - k + 1, maxY - k + 1)]
            let cornerInk = corners.map { share($0.0, $0.1, k) }.max() ?? 1
            let middle = share(minX + w / 2 - c / 2, minY + h / 2 - c / 2, c)
            round = cornerInk < 0.08 && middle > 0.35
        } else {
            round = false
        }
    }

    /// Which pixels of a `sample`-square copy, drawn on white, are ink.
    private static func ink(_ cg: CGImage) -> [Bool]? {
        let n = sample
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return nil }
        let white = 255 - inkStep
        return (0..<(n * n)).map { i in min(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]) < white }
    }
}
