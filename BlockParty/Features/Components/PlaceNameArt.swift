//
//  PlaceNameArt.swift
//  Block Party — a place's name in its own lettering at the bottom centre of its photo, on the
//  Event page and a business page (BP app follows 02, Jesse 2026-10-22: "the name of the place ...
//  in whatever their font is that they use on their website"). The lettering is cut out of the
//  place's own logo as a white picture (`public.place_names`, `references/place-name/cut_names.py`)
//  and tinted here: white over a dark photo, ink over a light one, as the part of the photo it sits
//  on decides (Jesse: "white or black, whatever works with the photo"). Mock Jesse said yes to:
//  https://claude.ai/artifact/BRrG2EJX2d6nJhYPRdHxKU
//

import ImageIO
import SwiftUI
import UIKit

extension PlaceNameArt {
    /// The box the lettering fits in, and its bottom above the photo's visible edge (the mock's).
    static let maxWidth: CGFloat = 176
    static let maxHeight: CGFloat = 84
    static let bottom: CGFloat = 18
}

struct PlaceNameArt: View {
    let name: URL
    /// The photo under it now; nil while none is on screen.
    let photo: URL?
    /// The place's name, for VoiceOver.
    let spoken: String

    @State private var lettering: UIImage?
    @State private var onDark = true

    var body: some View {
        ZStack {
            if let lettering {
                Image(uiImage: lettering)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(onDark ? Hue.nameOnDark : Hue.nameOnLight)
                    // A soft shadow lifts it off a busy photo: dark under white, faint under ink.
                    .shadow(color: Hue.nameShadow.opacity(onDark ? 0.45 : 0.12), radius: 1, y: 1)
                    .shadow(color: Hue.nameShadow.opacity(onDark ? 0.35 : 0), radius: 7, y: 3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: Self.maxWidth, maxHeight: Self.maxHeight)
        .animation(Motion.smooth, value: lettering != nil)
        .animation(Motion.smooth, value: onDark)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(spoken)
        .task(id: name) { lettering = await Self.image(name) }
        .task(id: photo) {
            guard let photo, let dark = await Self.isDark(photo) else { return }
            onDark = dark
        }
    }

    private static func image(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    /// Whether the band the lettering covers (the middle half, from 70% down to 95%) is dark:
    /// its average lightness under half. Read off a 48 px copy, from the shared cache the pages'
    /// photos load through. nil when the photo can't be read: the lettering stays as it is.
    nonisolated static func isDark(_ url: URL) async -> Bool? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 48,
              ] as CFDictionary)
        else { return nil }
        return lightness(image, in: CGRect(x: 0.25, y: 0.70, width: 0.5, height: 0.25)).map { $0 < 0.5 }
    }

    /// The average lightness (0 black, 1 white) of `band`, as shares of the image.
    nonisolated static func lightness(_ image: CGImage, in band: CGRect) -> Double? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let x0 = Int(band.minX * Double(w)), x1 = max(x0 + 1, Int(band.maxX * Double(w)))
        let y0 = Int(band.minY * Double(h)), y1 = max(y0 + 1, Int(band.maxY * Double(h)))
        var sum = 0.0, count = 0.0
        for y in y0..<min(y1, h) {
            for x in x0..<min(x1, w) {
                let i = (y * w + x) * 4
                sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
                count += 1
            }
        }
        return count > 0 ? sum / count / 255 : nil
    }
}
