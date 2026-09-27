//
//  FeedCardMedia.swift
//  Block Party — feed-card image loading and image-source presentation helpers.
//

import Foundation
import ImageIO
import SwiftUI

struct FeedCardURLPhoto: View {
    let url: URL
    /// Fired once the downsampled bitmap has actually decoded and is on screen. The
    /// feed card uses it to hold its fallback typography until the photo exists, so it
    /// never animates into photo-mode over an undownloaded flat-ink frame.
    var onReady: (() -> Void)? = nil
    /// Fired once when the bitmap could not be loaded at all, so a caller can drop
    /// the photo instead of holding a placeholder over it forever.
    var onFailure: (() -> Void)? = nil

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let targetPixelWidth = max(
                1,
                Int((proxy.size.width * displayScale).rounded(.up))
            )

            FeedCardDownsampledPhoto(
                request: FeedCardImageRequest(
                    url: url,
                    maxPixelSize: targetPixelWidth
                ),
                onReady: onReady,
                onFailure: onFailure
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct FeedCardDownsampledPhoto: View {
    let request: FeedCardImageRequest
    var onReady: (() -> Void)? = nil
    var onFailure: (() -> Void)? = nil

    /// The bitmap this view loaded, tagged with its URL so a view handed a new URL never
    /// shows the old photo.
    @State private var loaded: (url: URL, image: CGImage)?

    /// What to draw: this view's own bitmap, else one already drawn elsewhere for the
    /// same URL at another size (the card's, when the event page asks for a wider one).
    private var image: CGImage? {
        if let loaded, loaded.url == request.url { return loaded.image }
        return FeedCardShownBitmaps.bitmap(for: request.url)
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                // Ink, not a light fill: the card's title is white and already sits on
                // top during this beat, so a pale placeholder would swallow it. This
                // way the load-in reads as the card's own fallback treatment.
                Rectangle().fill(Hue.ink)
            }
        }
        .task(id: request) {
            let loadedImage = await FeedCardImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            if let loadedImage {
                FeedCardShownBitmaps.remember(loadedImage, for: request.url)
                // Cross-fade the photograph in rather than hard-cutting it over the ink.
                withAnimation(.easeOut(duration: 0.2)) { loaded = (request.url, loadedImage) }
            }
            // A photo already on screen at another size has not failed.
            if image != nil { onReady?() } else { onFailure?() }
        }
    }
}

/// The newest bitmap drawn for each photo URL, at whatever size, readable without
/// waiting on the loader. The event page asks for a wider copy of the photo its card
/// just drew, so its hero flashed a skeleton over a photo already on screen (design.md
/// "Don't flash"); it now draws this one at once and swaps in the wider one when it
/// decodes. The same 12-photo bound as `FeedCardImageLoader`.
@MainActor
enum FeedCardShownBitmaps {
    private static var bitmaps: [URL: CGImage] = [:]
    private static var order: [URL] = []

    static func bitmap(for url: URL) -> CGImage? { bitmaps[url] }

    static func remember(_ bitmap: CGImage, for url: URL) {
        bitmaps[url] = bitmap
        order.removeAll { $0 == url }
        order.append(url)
        if order.count > 12 { bitmaps[order.removeFirst()] = nil }
    }
}

private nonisolated struct FeedCardImageRequest: Hashable, Sendable {
    let url: URL
    let maxPixelSize: Int
}

private actor FeedCardImageLoader {
    static let shared = FeedCardImageLoader()

    private static let maxCachedImages = 12
    private var cache: [FeedCardImageRequest: CGImage] = [:]
    private var cacheOrder: [FeedCardImageRequest] = []

    func image(for request: FeedCardImageRequest) async -> CGImage? {
        if let cached = cache[request] {
            touch(request)
            return cached
        }

        let source: CGImageSource?
        if request.url.isFileURL {
            source = CGImageSourceCreateWithURL(request.url as CFURL, nil)
        } else {
            guard let data = await remoteData(from: request.url) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }

        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: request.maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        insert(thumbnail, for: request)
        return thumbnail
    }

    private func remoteData(from url: URL) async -> Data? {
        do {
            // Through `mediaRequest`, so a Google Places photo carries the bundle-id
            // header its key checks. Every other URL goes out as before.
            let (data, response) = try await URLSession.shared.data(for: GooglePlacesService.mediaRequest(for: url))
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func touch(_ request: FeedCardImageRequest) {
        cacheOrder.removeAll { $0 == request }
        cacheOrder.append(request)
    }

    private func insert(_ image: CGImage, for request: FeedCardImageRequest) {
        cache[request] = image
        touch(request)

        while cacheOrder.count > Self.maxCachedImages {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}

/// The scrim that keeps a card's overlaid white title legible on a real photograph.
///
/// The title had only ever been seen against flat ink, where a single 0 → 0.55 ramp
/// over the bottom 40% was plenty; a bright frame (a noon sky, a sunlit lawn) washed
/// it out. This covers more of the image so the ramp starts well above the copy, and
/// leans a little deeper at the very bottom — but it stays a shadow, not a black bar.
/// The last of the contrast is carried by `feedCardPhotoTypeShadow()` on the copy
/// itself, which is cheaper visually than blanketing the photograph.
struct FeedCardPhotoScrim: View {
    /// Height of the image this scrim sits on; the scrim covers `coverage` of it.
    let imageHeight: CGFloat
    /// Which edge the copy sits against. `.top` is the posting header floating over
    /// the photograph; it is a shorter, lighter ramp than the title's, because it
    /// carries one line of chrome rather than a headline.
    var edge: VerticalEdge = .bottom

    private static let coverage: CGFloat = 0.58
    private static let topCoverage: CGFloat = 0.3
    private static let stops: [Gradient.Stop] = [
        .init(color: .black.opacity(0), location: 0),
        .init(color: .black.opacity(0.18), location: 0.45),
        .init(color: .black.opacity(0.68), location: 1),
    ]
    private static let topStops: [Gradient.Stop] = [
        .init(color: .black.opacity(0.45), location: 0),
        .init(color: .black.opacity(0.14), location: 0.55),
        .init(color: .black.opacity(0), location: 1),
    ]

    var body: some View {
        switch edge {
        case .bottom:
            LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
                .frame(height: imageHeight * Self.coverage)
        case .top:
            LinearGradient(stops: Self.topStops, startPoint: .top, endPoint: .bottom)
                .frame(height: imageHeight * Self.topCoverage)
        }
    }
}

extension View {
    /// Soft ink halo for white type sitting directly on a photograph. The scrim does
    /// most of the work; this catches what a scrim can't — a bright patch landing
    /// exactly under a letterform.
    func feedCardPhotoTypeShadow() -> some View {
        shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }
}

extension FeedCardImageSource {
    /// Whether a photograph is on screen. An unresolved `venueLookup` is not one yet —
    /// the card shows the fallback treatment until (and unless) it resolves.
    var isPhoto: Bool {
        switch self {
        case .eventPhoto, .placesPhoto: true
        case .venueLookup, .fallback: false
        }
    }

    /// Google ToS: a Places photo's author attributions must be displayed wherever the
    /// image appears. nil when there are none, so no empty caption capsule renders.
    var attribution: String? {
        guard case .placesPhoto(_, let attribution) = self, !attribution.isEmpty
        else { return nil }
        return attribution
    }

    /// Whether the card renders the ink fallback treatment (flat ink, big title).
    var isFallback: Bool {
        switch self {
        case .venueLookup, .fallback: true
        case .eventPhoto, .placesPhoto: false
        }
    }
}
