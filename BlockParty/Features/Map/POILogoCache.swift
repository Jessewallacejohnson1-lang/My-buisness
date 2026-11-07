//
//  POILogoCache.swift
//  Block Party — the one in-memory cache for logo and place pictures from Storage:
//  Search's logo wall and business pages, the map's bubbles, a game card's logos.
//
//  WHY NOT AsyncImage: it restarts from its placeholder every time a view is rebuilt,
//  which flashes. Here a set of URLs is prefetched once, so a view's `body` does a
//  synchronous dictionary lookup and renders its final state on its first frame.
//
//  Disk persistence rides the session's URLCache (logos are immutable per URL —
//  `.returnCacheDataElseLoad` means a relaunch re-fills memory from disk, offline).
//  Each image is decoded off the main thread as it lands, so the first look at the
//  logo wall doesn't stall decoding 69 of them at once.
//

import SwiftUI
import Combine

@MainActor
final class POILogoCache: ObservableObject {
    static let shared = POILogoCache()

    @Published private(set) var images: [URL: UIImage] = [:]
    /// Logos whose last fetch failed; asked for again, they leave until that try fails too.
    @Published private(set) var failed: Set<URL> = []
    private var inflight: Set<URL> = []

    private nonisolated static let memoryCacheBytes = 4 << 20
    private nonisolated static let diskCacheBytes = 50 << 20

    /// Own session + cache, isolated from the app's default so a burst of logo loads
    /// can never evict the photos' responses (and vice versa).
    private nonisolated static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: memoryCacheBytes, diskCapacity: diskCacheBytes)
        cfg.requestCachePolicy = .returnCacheDataElseLoad   // logos are immutable per URL
        return URLSession(configuration: cfg)
    }()

    /// What a view has asked for since the app last left the screen. Not published: `body` writes it.
    private var used: Set<URL> = []
    /// What leaving let go: a view asking again reads it back from disk.
    private var dropped: Set<URL> = []

    /// Leaving, every logo no view asked for lets go: the whole of Search's roster sits here from
    /// launch, 116 MB at 1 MB each, and iOS shuts the biggest apps down first (BP app backlog 21).
    private init() {
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { POILogoCache.shared.wentAway() }
        }
    }

    private func wentAway() {
        dropped.formUnion(images.keys.filter { !used.contains($0) })
        images = images.filter { used.contains($0.key) }
        used = []
    }

    /// A Search logo if it has arrived; nil until then (its tile shows the backdrop alone).
    func image(for url: URL) -> UIImage? {
        used.insert(url)
        // A turn later: this runs inside a view's `body`, and the read publishes when it lands.
        if images[url] == nil, dropped.remove(url) != nil { Task { prefetch([url]) } }
        return images[url]
    }

    /// Kick off loads for every logo URL not yet resolved. Callers pass the whole
    /// roster (deduped + in-flight-guarded here); publishes once per arriving image.
    func prefetch(_ urls: [URL]) {
        for url in urls where images[url] == nil && !inflight.contains(url) {
            inflight.insert(url)
            if failed.contains(url) { failed.remove(url) }
            Task {
                let raw = (try? await Self.session.data(from: url).0).flatMap { UIImage(data: $0) }
                let image = await raw?.byPreparingForDisplay() ?? raw
                inflight.remove(url)
                if let image { images[url] = image } else { failed.insert(url) }
                // A failed fetch stays absent → glyph fallback; the next prefetch
                // (foreground retry) may try again.
            }
        }
    }
}
