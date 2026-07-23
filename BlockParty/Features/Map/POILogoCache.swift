//
//  POILogoCache.swift
//  Block Party — in-memory brand-logo images for map POI markers.
//
//  WHY NOT AsyncImage: annotation views are torn down and rebuilt continuously during
//  pan/zoom cluster churn, and AsyncImage restarts from its placeholder on every
//  rebuild — visible flashing on the pins. Here the whole (small-town) logo set is
//  prefetched once right after `places` loads, so a marker's `body` does a synchronous
//  dictionary lookup and renders its final state on its first frame.
//
//  Disk persistence rides the session's URLCache (logos are immutable per URL —
//  `.returnCacheDataElseLoad` means a relaunch re-fills memory from disk, offline).
//

import SwiftUI
import Combine

@MainActor
final class POILogoCache: ObservableObject {
    static let shared = POILogoCache()

    @Published private(set) var images: [URL: UIImage] = [:]
    private var inflight: Set<URL> = []

    private nonisolated static let memoryCacheBytes = 4 << 20
    private nonisolated static let diskCacheBytes = 50 << 20

    /// Own session + cache, isolated from the app's default so a burst of logo loads
    /// can never evict Google photo responses (and vice versa).
    private nonisolated static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: memoryCacheBytes, diskCapacity: diskCacheBytes)
        cfg.requestCachePolicy = .returnCacheDataElseLoad   // logos are immutable per URL
        return URLSession(configuration: cfg)
    }()

    /// The logo for a POI if it is already resolved — synchronous by design (see header).
    func resolvedImage(for poi: POI) -> UIImage? {
        #if DEBUG
        if Self.stubEnabled { return Self.stubImage(for: poi) }
        #endif
        guard let url = poi.logoURL else { return nil }
        return images[url]
    }

    /// Kick off loads for every logo URL not yet resolved. Callers pass the whole
    /// roster (deduped + in-flight-guarded here); publishes once per arriving image.
    func prefetch(_ urls: [URL]) {
        for url in urls where images[url] == nil && !inflight.contains(url) {
            inflight.insert(url)
            Task {
                let image = (try? await Self.session.data(from: url))
                    .flatMap { UIImage(data: $0.0) }
                inflight.remove(url)
                if let image { images[url] = image }
                // A failed fetch stays absent → glyph fallback; the next prefetch
                // (foreground retry) may try again.
            }
        }
    }

    #if DEBUG
    /// `-poi-logo-stub`: every POI renders a deterministic code-drawn mark so the
    /// pin/detail logo layout can be screenshot-verified before any real data exists.
    nonisolated static let stubEnabled =
        ProcessInfo.processInfo.arguments.contains("-poi-logo-stub")

    private static var stubImages: [String: UIImage] = [:]

    /// A deterministic fake “brand mark” per POI: colored rounded tile + monogram on
    /// white, matching the pipeline's normalized output (256px, white-padded square).
    private static func stubImage(for poi: POI) -> UIImage {
        if let cached = stubImages[poi.id] { return cached }
        let palette: [UIColor] = [
            UIColor(red: 0.76, green: 0.22, blue: 0.18, alpha: 1),   // brick
            UIColor(red: 0.13, green: 0.29, blue: 0.53, alpha: 1),   // navy
            UIColor(red: 0.16, green: 0.42, blue: 0.27, alpha: 1),   // pine
            UIColor(red: 0.83, green: 0.53, blue: 0.10, alpha: 1),   // amber
            UIColor(red: 0.35, green: 0.20, blue: 0.47, alpha: 1),   // plum
        ]
        let hash = abs(poi.id.hashValue)
        let color = palette[hash % palette.count]
        let monogram = String(poi.name.prefix(1)).uppercased()

        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let tile = CGRect(x: 30, y: 30, width: 196, height: 196)
            color.setFill()
            UIBezierPath(roundedRect: tile, cornerRadius: 44).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 110, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let text = NSAttributedString(string: monogram, attributes: attrs)
            let bounds = text.boundingRect(with: size, options: [], context: nil)
            text.draw(at: CGPoint(x: tile.midX - bounds.width / 2,
                                  y: tile.midY - bounds.height / 2))
        }
        stubImages[poi.id] = image
        return image
    }
    #endif
}
