import UIKit

/// A logo as a small circle shows it: its own ink without the empty border its file carries, and how
/// far that ink reaches from its middle, so the circle can size it to sit wholly inside (Jesse,
/// 2026-11-10: The House's square logo broke out of its circle and Sal's lost its ends under the
/// ring). A round badge reaches about half its width and fills the circle (Jesse, 2026-10-24: "make it
/// fit the icon better"); a square or a wordmark reaches to its corners and sits smaller. Worked out
/// from the picture itself, so a new logo needs no marking.
struct LogoFit {
    let image: UIImage
    /// The farthest ink from the trimmed image's middle, over its width: 0.5 for a full round badge,
    /// about 0.71 for a full square. A circle of diameter d shows the image `d / 2 / reach` wide.
    let reach: CGFloat

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
            reach = 0.71
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
            reach = 0.71
            return
        }
        let sx = CGFloat(cg.width) / CGFloat(n), sy = CGFloat(cg.height) / CGFloat(n)
        let box = CGRect(x: CGFloat(minX) * sx, y: CGFloat(minY) * sy,
                         width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy).integral
        let trimmed = cg.cropping(to: box).map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) }
        self.image = trimmed ?? image

        // Each ink pixel's far corner from the box's middle, in the file's pixels: never under the truth.
        let cx = CGFloat(minX + maxX + 1) / 2, cy = CGFloat(minY + maxY + 1) / 2
        var far: CGFloat = 0
        for y in minY...maxY { for x in minX...maxX where ink[y * n + x] {
            let dx = max(abs(CGFloat(x) - cx), abs(CGFloat(x + 1) - cx)) * sx
            let dy = max(abs(CGFloat(y) - cy), abs(CGFloat(y + 1) - cy)) * sy
            far = max(far, (dx * dx + dy * dy).squareRoot())
        } }
        reach = far / (CGFloat(maxX - minX + 1) * sx)
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
