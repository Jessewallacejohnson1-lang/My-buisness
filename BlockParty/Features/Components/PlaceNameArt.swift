//
//  PlaceNameArt.swift
//  Block Party — a place's name in its own lettering at the bottom centre of its photo, on the
//  Event page and a business page (BP app follows 02, Jesse 2026-10-22: "the name of the place ...
//  in whatever their font is that they use on their website"). The lettering is cut out of the
//  place's own logo as a white picture (`public.place_names`, `references/place-name/cut_names.py`)
//  and set white over a soft dark fade at the photo's foot, so it reads on any photo (Jesse,
//  2026-10-24: "business names ... need to be able to read"). A place whose letters
//  couldn't be cut or rebuilt shows its logo there instead, in its own colours. Mock Jesse said yes to:
//  https://claude.ai/artifact/BRrG2EJX2d6nJhYPRdHxKU
//

import SwiftUI
import UIKit

extension PlaceNameArt {
    /// The box the lettering fits in, and its bottom above the photo's visible edge: about 1.5x the
    /// first build's 176 x 84 at 18 (Jesse, 2026-10-24, https://claude.ai/artifact/Ara44s8FQX3yfMnbGFPXtH).
    static let maxWidth: CGFloat = 272
    static let maxHeight: CGFloat = 124
    static let bottom: CGFloat = 28
    /// An emblem's square where it lands, which stays the first build's size.
    static let emblemSide: CGFloat = 84
    /// How tall the dark fade under the lettering is, from the photo's foot.
    static let fadeHeight: CGFloat = 190

    /// The soft dark fade the lettering stands on, the photo's full width.
    static var fade: some View {
        LinearGradient(stops: [.init(color: Hue.nameShadow.opacity(0), location: 0),
                               .init(color: Hue.nameShadow.opacity(0.28), location: 0.45),
                               .init(color: Hue.nameShadow.opacity(0.6), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(maxWidth: .infinity)
            .frame(height: fadeHeight)
            .allowsHitTesting(false)
    }
}

struct PlaceNameArt: View {
    let name: PlaceName
    /// The place's name, for VoiceOver.
    let spoken: String

    @State private var lettering: UIImage?

    var body: some View {
        ZStack {
            if let lettering {
                Image(uiImage: lettering)
                    // An emblem keeps its own colours; lettering is white.
                    .renderingMode(name.emblem ? .original : .template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(Hue.nameOnDark)
                    // A soft shadow lifts it off a busy photo.
                    .shadow(color: Hue.nameShadow.opacity(0.45), radius: 1, y: 1)
                    .shadow(color: Hue.nameShadow.opacity(0.35), radius: 7, y: 3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: Self.maxWidth, maxHeight: Self.maxHeight)
        .animation(Motion.smooth, value: lettering != nil)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(spoken)
        .task(id: name) { lettering = await Self.image(name.url) }
    }

    private static func image(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
