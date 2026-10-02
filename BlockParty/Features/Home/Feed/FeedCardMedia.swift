//
//  FeedCardMedia.swift
//  Block Party — feed-card image loading and image-source presentation helpers.
//

import Foundation
import ImageIO
import SwiftUI
import UIKit

struct FeedCardURLPhoto: View {
    let url: URL
    /// Fired once the downsampled bitmap has actually decoded and is on screen. The
    /// feed card uses it to hold its fallback typography until the photo exists, so it
    /// never animates into photo-mode over an undownloaded flat-ink frame.
    var onReady: (() -> Void)? = nil
    /// Fired once when the bitmap could not be loaded at all, so a caller can drop
    /// the photo instead of holding a placeholder over it forever.
    var onFailure: (() -> Void)? = nil
    /// What shows while the photo loads. Ink suits a card whose white title already
    /// sits on top; Search's tiles keep their own lighter fill showing through instead.
    var loadingFill: Color = Hue.ink

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            FeedCardDownsampledPhoto(
                request: FeedCardImageRequest(
                    url: url,
                    maxPixelSize: Self.pixelWidth(points: proxy.size.width, scale: displayScale)
                ),
                onReady: onReady,
                onFailure: onFailure,
                loadingFill: loadingFill
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The width to decode at, from whole points: the event page's hero measures
    /// 420.33 pt on iPhone Air, and rounding its pixels up asked for 1261 px against
    /// its card's 1260, so one photo decoded twice and took two of the cache's slots.
    static func pixelWidth(points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int(points.rounded() * scale))
    }
}

private struct FeedCardDownsampledPhoto: View {
    let request: FeedCardImageRequest
    var onReady: (() -> Void)? = nil
    var onFailure: (() -> Void)? = nil
    var loadingFill: Color = Hue.ink

    /// The bitmap this view loaded, tagged with its URL so a view handed a new URL never
    /// shows the old photo.
    @State private var loaded: (url: URL, image: CGImage)?

    /// What to draw: this view's own bitmap, else the largest one already decoded for
    /// the same photo, so a photo on screen elsewhere draws here in the first frame.
    private var image: CGImage? {
        if let loaded, loaded.url == request.url { return loaded.image }
        return FeedCardImageLoader.shared.largest(for: request.url)
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
                Rectangle().fill(loadingFill)
            }
        }
        .task(id: request) {
            let loadedImage = await FeedCardImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            if let loadedImage {
                // Cross-fade the photograph in rather than hard-cutting it over the ink.
                withAnimation(.easeOut(duration: 0.2)) { loaded = (request.url, loadedImage) }
            }
            // A photo already on screen at another size has not failed.
            if image != nil { onReady?() } else { onFailure?() }
        }
    }
}

private nonisolated struct FeedCardImageRequest: Hashable, Sendable {
    let url: URL
    let maxPixelSize: Int
}

/// Downsampled photos, the 12 used last, keyed by URL and pixel size. On the main
/// actor, so a view can draw a photo already decoded in the frame it appears; the
/// download and the decode run off it. Emptied on a memory warning. A photo shown
/// at another size (a venue photo on the page after its card) starts from
/// `largest(for:)`, never from a skeleton.
@MainActor
final class FeedCardImageLoader {
    static let shared = FeedCardImageLoader()

    private static let maxCachedImages = 12
    private var cache: [FeedCardImageRequest: CGImage] = [:]
    private var cacheOrder: [FeedCardImageRequest] = []

    private init() {
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                FeedCardImageLoader.shared.cache.removeAll()
                FeedCardImageLoader.shared.cacheOrder.removeAll()
            }
        }
    }

    /// The largest bitmap decoded for this photo at any size. Largest, so a host's
    /// 96 px avatar cut from the same file never stands in for a full-width photo.
    func largest(for url: URL) -> CGImage? {
        cache.filter { $0.key.url == url }.values.max { $0.width < $1.width }
    }

    fileprivate func image(for request: FeedCardImageRequest) async -> CGImage? {
        if let cached = cache[request] {
            touch(request)
            return cached
        }
        guard let thumbnail = await Self.decode(request) else { return nil }
        insert(thumbnail, for: request)
        return thumbnail
    }

    @concurrent
    private nonisolated static func decode(_ request: FeedCardImageRequest) async -> CGImage? {
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
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static func remoteData(from url: URL) async -> Data? {
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
    /// The photograph's address; nil for the two cases that are not a photo yet.
    var url: URL? {
        switch self {
        case .eventPhoto(let url), .placesPhoto(let url, _): url
        case .venueLookup, .fallback: nil
        }
    }

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
