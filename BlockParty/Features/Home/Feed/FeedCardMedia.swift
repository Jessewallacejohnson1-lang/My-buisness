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
                onReady: onReady
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct FeedCardDownsampledPhoto: View {
    let request: FeedCardImageRequest
    var onReady: (() -> Void)? = nil

    @State private var image: CGImage?

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
            // Cross-fade the photograph in rather than hard-cutting it over the ink.
            withAnimation(.easeOut(duration: 0.2)) { image = loadedImage }
            if loadedImage != nil { onReady?() }
        }
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
            let (data, response) = try await URLSession.shared.data(from: url)
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
    /// Height of the image this scrim sits on; the scrim covers its bottom `coverage`.
    let imageHeight: CGFloat

    private static let coverage: CGFloat = 0.58
    private static let stops: [Gradient.Stop] = [
        .init(color: .black.opacity(0), location: 0),
        .init(color: .black.opacity(0.18), location: 0.45),
        .init(color: .black.opacity(0.68), location: 1),
    ]

    var body: some View {
        LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
            .frame(height: imageHeight * Self.coverage)
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
