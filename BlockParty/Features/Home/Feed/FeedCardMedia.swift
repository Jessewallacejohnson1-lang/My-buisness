//
//  FeedCardMedia.swift
//  Block Party — feed-card image loading and image-source presentation helpers.
//

import Foundation
import ImageIO
import SwiftUI

struct FeedCardURLPhoto: View {
    let url: URL

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
                )
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct FeedCardDownsampledPhoto: View {
    let request: FeedCardImageRequest

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Hue.fill)
            }
        }
        .task(id: request) {
            let loadedImage = await FeedCardImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            image = loadedImage
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

extension FeedCardImageSource {
    var isPhoto: Bool {
        switch self {
        case .eventPhoto, .placesPhoto: true
        case .fallback: false
        }
    }

    var attribution: String? {
        if case .placesPhoto(_, let attribution) = self { attribution } else { nil }
    }

    var isFallback: Bool {
        if case .fallback = self { true } else { false }
    }
}
