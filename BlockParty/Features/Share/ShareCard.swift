//
//  ShareCard.swift
//  Block Party — the card a share shows and sends (BP app share-sheet 01).
//

import ImageIO
import SwiftUI

/// The share card, Hypelist's measured story card (216 x 385, BP app `references/share-sheet/SPEC.md`): its look's
/// fade with light along its edges and fine grain, the picture card in its middle, and the Block Party name under it,
/// 15% larger than the mock's first and 6 pt nearer the picture (Jesse, 2026-11-19). Plain views only, so
/// `ImageRenderer` draws exactly what the sheet shows.
struct ShareCard: View {
    let story: ShareStory
    let look: ShareLook
    /// The picture, decoded. Nil with a photo to come shows ink until it lands; nil with none, the yellow face.
    let photo: CGImage?

    var body: some View {
        VStack(spacing: ShareMetric.nameGap) {
            face
            BlockPartyWordmark(height: ShareMetric.name)
                .foregroundStyle(look.dark ? Hue.surface : Hue.ink)
        }
        .frame(width: ShareMetric.cardWidth, height: ShareMetric.cardHeight)
        .background(LinearGradient(stops: look.stops, startPoint: .top, endPoint: .bottom))
        .overlay { edges }
        .overlay { ShareGrain() }
        .clipShape(RoundedRectangle(cornerRadius: Radius.shareCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The picture card: the photo with its title and line over a shade, else the Event page's yellow with ink words.
    private var face: some View {
        let yellow = story.photo == nil
        return ZStack(alignment: .bottomLeading) {
            if let photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ShareMetric.faceWidth, height: ShareMetric.faceHeight)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(ShareMetric.shade)], startPoint: .top, endPoint: .bottom)
                    .frame(height: ShareMetric.faceHeight * ShareMetric.shadeReach)
            } else {
                (yellow ? Hue.brandDisc : Hue.ink)
            }
            VStack(alignment: .leading, spacing: ShareMetric.lineGap) {
                Text(story.title)
                    .font(.eventDisplay(ShareMetric.title, relativeTo: .title3))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                Text(story.line)
                    .font(.sans(12))
                    .opacity(ShareMetric.lineOpacity)
                    .lineLimit(1)
            }
            .foregroundStyle(yellow ? Hue.onBrandDisc : Hue.surface)
            .padding(ShareMetric.facePad)
            .frame(width: ShareMetric.faceWidth, alignment: .leading)
        }
        .frame(width: ShareMetric.faceWidth, height: ShareMetric.faceHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.shareFace, style: .continuous))
        .shadow(color: .black.opacity(ShareMetric.faceShadow), radius: ShareMetric.faceShadowRadius, y: ShareMetric.faceShadowY)
    }

    /// Light along the sides and the top, fading inward, as on Hypelist's card's edges.
    private var edges: some View {
        let light = Hue.surface.opacity(look.dark ? ShareMetric.edgeOnDark : ShareMetric.edgeOnPale)
        return ZStack {
            HStack(spacing: 0) {
                LinearGradient(colors: [light, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: ShareMetric.edge)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, light], startPoint: .leading, endPoint: .trailing)
                    .frame(width: ShareMetric.edge)
            }
            VStack(spacing: 0) {
                LinearGradient(colors: [light, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: ShareMetric.edgeTop)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }

    /// The picture, from the cache a card or page already filled, else fetched and decoded here.
    static func picture(_ url: URL) async -> CGImage? {
        if let shown = FeedCardImageLoader.shared.largest(for: url) { return shown }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: ShareMetric.decodePixels]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Fine grain over the card, about 3.8 brightness levels a pixel as Hypelist's: one pixel in two a touch lighter, the
/// other a touch darker, a third of a point each, the same pattern every time.
private struct ShareGrain: View {
    private static let tile: CGImage? = {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt32 = 7
        for i in stride(from: 0, to: bytes.count, by: 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let level: UInt8 = seed >> 31 == 0 ? 0 : 255
            let alpha = ShareMetric.grain
            // Premultiplied: white at `alpha` is (alpha, alpha, alpha, alpha), black is (0, 0, 0, alpha).
            bytes[i] = level == 0 ? 0 : alpha
            bytes[i + 1] = bytes[i]
            bytes[i + 2] = bytes[i]
            bytes[i + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        return provider.flatMap {
            CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }()

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 3)
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
        }
    }
}

/// The share sheet's measures, from Hypelist's (BP app `references/share-sheet/SPEC.md`), in points.
enum ShareMetric {
    /// The sheet's top, down the screen.
    static let sheetTop: CGFloat = 88
    static let titleTop: CGFloat = 29
    static let cardsTop: CGFloat = 88
    static let peopleTop: CGFloat = 542
    static let ruleTop: CGFloat = 635.7
    static let appsTop: CGFloat = 652

    static let cardWidth: CGFloat = 216
    static let cardHeight: CGFloat = 385
    /// The second look, off to the side, at 85%.
    static let sideScale: CGFloat = 0.85
    static let cardGap: CGFloat = 8

    static let faceWidth: CGFloat = 150
    static let faceHeight: CGFloat = 188
    static let facePad: CGFloat = 12
    static let title: CGFloat = 21
    static let lineGap: CGFloat = 4
    static let lineOpacity: Double = 0.9
    static let shade: Double = 0.7
    static let shadeReach: CGFloat = 0.65
    static let faceShadow: Double = 0.14
    static let faceShadowRadius: CGFloat = 15
    static let faceShadowY: CGFloat = 10

    static let name: CGFloat = 17.25
    static let nameGap: CGFloat = 16
    static let edge: CGFloat = 25
    static let edgeTop: CGFloat = 30
    static let edgeOnDark: Double = 0.3
    static let edgeOnPale: Double = 0.75
    static let grain: UInt8 = 9
    static let decodePixels = 900

    /// The round buttons: 58.5 across, 80 apart, the first 33.7 in, the word 9 under.
    static let circle: CGFloat = 58.5
    static let circleGap: CGFloat = 21.5
    static let rowSide: CGFloat = 33.7
    static let wordTop: CGFloat = 9
    static let wordWidth: CGFloat = 76
    static let glyph: CGFloat = 24
    static let badge: CGFloat = 22
    static let badgeRing: CGFloat = 2.5
    static let badgeGlyph: CGFloat = 11
    static let copiedHold: Duration = .seconds(1.5)
}
