//
//  BlockPartyColor.swift
//  Block Party — design tokens (colors)
//
//  Monochrome ink-on-paper system (July 2026): one warm page ground, white cards,
//  charcoal ink, and a compact neutral ramp with no accent colour.
//
//  DARK MODE (Aug 2026). Every token below is DYNAMIC: one light value, one dark
//  value, resolved by the system through a `UIColor` trait provider. Nothing in the
//  app asks which appearance it is in — a view that used `Hue.paper` before still
//  uses `Hue.paper`, and the whole app follows.
//
//  The dark ramp is the light one inverted around the same warmth, not a generic
//  grey scale: the cream page becomes #141412 and cards #1D1D1A, so a card still
//  reads as a lighter object sitting on the page rather than as a hairline box.
//
//  THE ONE EXCEPTION IS THE MAP. Mapbox renders LIGHT cartography in both
//  appearances (`BasemapPalette`), so ink drawn ON the map canvas must stay ink or
//  a pin badge turns white-on-white. Those call sites resolve their tokens through
//  `onLightCanvas` below rather than following the system. That is scoping, not an
//  opt-out: the canvas genuinely did not change.
//

import SwiftUI
import UIKit

extension Color {
    /// Build a Color from a 0xRRGGBB hex literal.
    ///
    /// `nonisolated` because the module defaults to MainActor isolation and a
    /// palette is not main-actor state: `CategoryGradient` and the other pure
    /// `nonisolated` token tables build their colours here, and an isolated
    /// initializer would trip the 0-warning bar at every one of those call sites.
    /// See the MainActor-default gotcha in CLAUDE.md.
    nonisolated init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// A token with two values: what it is on paper, and what it is in the dark.
    ///
    /// Built through `UIColor`'s trait provider rather than through SwiftUI's
    /// `@Environment(\.colorScheme)` because a token has to resolve where there is
    /// no view — `Color.hexString` hands values to Mapbox's runtime style setters,
    /// and a `ShapeStyle` is read far from any environment.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(bp: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// This token as it renders in LIGHT appearance, whatever the device is set to.
    ///
    /// For anything drawn over a ground that does NOT follow the system appearance.
    /// Exactly one such ground exists: the Mapbox basemap, which is light
    /// cartography in both modes. A marker over it keeps its light-mode value or it
    /// disappears.
    var onLightCanvas: Color {
        Color(UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
    }

    /// The reverse of `init(hex:)` — a `"#RRGGBB"` string, for APIs (like Mapbox's
    /// runtime style setters) that want a hex string rather than a `Color`. Lets a
    /// call site reuse a `Hue` token instead of duplicating its hex as a literal.
    var hexString: String {
        let c = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  intent: .defaultIntent, options: nil) ?? UIColor(self).cgColor
        let comps = c.components ?? [0, 0, 0, 1]
        let r = Int((comps[0] * 255).rounded()), g = Int((comps[1] * 255).rounded()), b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension UIColor {
    /// The `Color(hex:)` ramp, one level down, so the dynamic provider above can
    /// build its two ends without bouncing through SwiftUI.
    fileprivate nonisolated convenience init(bp hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Block Party palette. One namespace so call sites read `Hue.paper`, `Hue.ink`, etc.
///
/// Every token carries both appearances. The dark column is measured, not guessed:
/// `ink` on `paper` is 16.3:1, `inkSecondary` on `surface` 6.0:1, and the accent
/// 5.0:1 — the light column's plum is only 2.7:1 on a dark page, which is why the
/// accent is the one token whose dark value moves in the opposite direction.
///
/// `nonisolated` (the module defaults to MainActor): a palette is not main-actor
/// state, and the pure token tables that build on it — `YourDayRailPalette`,
/// `CategoryGradient` — are themselves `nonisolated`. See the MainActor-default
/// gotcha in CLAUDE.md.
nonisolated enum Hue {
    // primary text, buttons, FABs, active states, pins
    static let ink           = Color(light: 0x111111, dark: 0xF2F1EC)
    // app background (warm white → warm near-black, same warmth)
    static let paper         = Color(light: 0xFAFAF7, dark: 0x141412)
    // cards — a step ABOVE the page in both modes, so a card is still an object
    static let surface       = Color(light: 0xFFFFFF, dark: 0x1D1D1A)
    // secondary text, captions, inactive
    static let inkSecondary  = Color(light: 0x6E6E6E, dark: 0x9C9A93)
    // borders, dividers
    static let hairline      = Color(light: 0xE7E7E4, dark: 0x33332E)
    // inert fills, placeholders, skeletons
    static let fill          = Color(light: 0xF1F1EF, dark: 0x23231F)

    /// A border that has to be SEEN rather than merely felt — a dashed edge, a
    /// stronger rule. One step darker than `hairline`; it was #D8D6CE written out
    /// twice (the day sheet's checkbox and the rail's suggested card) before it was
    /// a token, which is exactly the drift `BlockPartyColor` exists to prevent.
    static let edge          = Color(light: 0xD8D6CE, dark: 0x45443D)

    /// The outline of an interactive control that is currently EMPTY — an unchecked
    /// box. WCAG 1.4.11 asks 3:1 of any non-text control boundary, and the old
    /// #D8D6CE measured 1.46:1 on a white card, so an unchecked box read as an
    /// absence rather than as something to press. This warm grey measures 3.46:1 on
    /// white and 4.89:1 on the dark card, so one value serves both appearances.
    static let control       = Color(hex: 0x8C8A82)

    /// The one brand accent — meaning-scoped ONLY (live events, active filters,
    /// selected/saved state, primary CTAs), never decoration, body copy, or a
    /// background wash. Plum/berry: distinct from the retired coral ramp AND from the
    /// basemap's sage parks / sky water, so it never reads as terrain. On the map
    /// CANVAS the accent means "live" (routed via `MarkerRole`); in sheet/chrome it
    /// marks the active/selected/primary control. Not the retired coral 0xFF6B57.
    /// See DECISIONS.md.
    ///
    /// The dark value is the SAME plum lightened (hue 325° → 329°), not a different
    /// colour: #8E3B6B on a #141412 page is 2.67:1, which is under the 3:1 an
    /// indicator needs, and #C06A96 is 5.04:1.
    static let accent        = Color(light: 0x8E3B6B, dark: 0xC06A96)
}
