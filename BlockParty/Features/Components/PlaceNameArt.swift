//
//  PlaceNameArt.swift
//  Block Party — a place's name in its own lettering, white and see-through, low on its business
//  page's cover behind its round logo, as Places' "Alex" (BP app place-pages 08, Jesse 2026-11-19,
//  Figma https://www.figma.com/design/ppu7STXAsjcB9uBIsVGNmx?node-id=1-2). The lettering is cut out
//  of the place's own logo as a white picture (`public.place_names` kind `name`,
//  `references/place-name/cut_names.py`). A place with only an emblem, or no cover, shows no name.
//

import SwiftUI
import UIKit

extension PlaceNameArt {
    /// The box the lettering fits in on a place's cover, behind its round logo (Jesse, 2026-11-19, BP app
    /// place-pages 08, Figma mock `references/business-profile/`): at most 330 x 138 pt, low on the cover.
    static let maxWidth: CGFloat = 330
    static let maxHeight: CGFloat = 138
    /// Its foot 34 pt under the logo's top, so the logo hides it: 18 pt above the cover's edge (the mock's).
    static let bottom: CGFloat = ProfileMetric.photo / 2 + ProfileMetric.ring - 34
    /// How much of the lettering shows: the rest is the photo through it (Jesse's pick, 60%, from the
    /// mock's 30, 40 and 60).
    static let seeThrough: Double = 0.6
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
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(Hue.nameOnDark)
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
