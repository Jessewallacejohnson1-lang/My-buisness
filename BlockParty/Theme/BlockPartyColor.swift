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
//  THE EXCEPTIONS ARE THE TWO FIXED-LIGHT GROUNDS. Mapbox renders LIGHT
//  cartography in both appearances (`BasemapPalette`), so ink drawn ON the map
//  canvas must stay ink or a pin badge turns white-on-white; and since round 2
//  Phase D the pin card's status wash (`statusTint`) is the same pale coral in
//  both appearances, so its content pins to the light ramp too
//  (`PinDetailSheet.CardInk`). Those call sites resolve their tokens through
//  `onLightCanvas` below rather than following the system. That is scoping, not
//  an opt-out: neither canvas actually changes.
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
    /// Two such grounds exist: the Mapbox basemap (light cartography in both modes)
    /// and the pin-detail status card's fixed pale `statusTint` wash. Ink over
    /// either keeps its light-mode value or it disappears (a dark-mode near-white
    /// `ink` measured ~1.1:1 on the wash — round 2 Phase D).
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

    /// The pin-detail sheet's status-card wash — the ONE token that card's
    /// background routes through, and nothing else. Jesse's call (2026-08-14):
    /// the BP mark's own orange. The mark's lockup samples to #F78067 (mean of
    /// the render's coral pixels, `scripts/brand`-style sweep); at full strength
    /// that overwhelms a card background, so this is that hue mixed to a pale
    /// wash — the Flighty pale-rose treatment in our coral. LIGHT ink ≈17:1 and
    /// light `inkSecondary` ≈4.5:1 on it, so AA holds — but the wash is the same
    /// pale colour in BOTH appearances, so the card's content pins to the light
    /// ramp via `onLightCanvas` (`PinDetailSheet.CardInk`; dark ink measured
    /// ~1.1:1 here). The card's header dot and status word stay ink (plum only
    /// while live). See DECISIONS.md (map polish Q3).
    static let statusTint    = Color(hex: 0xFDECE8)

    /// The like state, and nothing else. A heart that stays ink reads as a shape;
    /// a heart that turns red reads as something you did — which is the whole job of
    /// this control (Jesse, 2026-09-19). Same value in both appearances: it is a
    /// small filled glyph, not text, so it does not need the dark ramp's lift.
    ///
    /// This is the one red in the app. It is state, not chrome: never a border, never
    /// a background, never an error colour.
    static let heart         = Color(hex: 0xFF3040)

    /// **The brand yellow.** The logo's field colour, sampled from the master
    /// (`docs/brand/source-logo-1254.png`): the modal pixel across the field, not an
    /// eyeballed approximation. This is the app's ONE accent (Jesse, 2026-09-18) and
    /// every yellow in the UI derives from it — never a second yellow, never a
    /// call-site hex.
    ///
    /// Re-sampled 2026-09-19 for the wordmark logo: 0xF2B800 (the retired
    /// wave-figure icon's arcs) → 0xFCE804. The rule did not change, the artwork did.
    ///
    /// Accents are small by rule: the Today bar's map disc and the tab bar's Create
    /// disc today, and whatever else Jesse scopes in later. The app's ground stays
    /// white/paper.
    nonisolated static let brandYellowHex: UInt32 = 0xFCE804

    /// The brand yellow at FULL strength, as a solid disc: the tab bar's Create
    /// disc (Jesse, 2026-09-20) and, since 2026-09-24, the Today bar's map disc
    /// too. A centre button that let the glass capsule through would read as a hole
    /// rather than as an object; the reference's centre button is a solid disc, and
    /// this is that disc in our colour. The map disc used to be glass tinted with
    /// the yellow at 68% (`mapWash`, deleted 2026-09-24): a tint is not the brand
    /// yellow, and it went mustard over photos.
    ///
    /// DESIGN.md's "accents are small by rule" still holds and this is the boundary:
    /// two controls, both circular, both 50pt or under. A third is a conversation.
    static let createDisc    = Color(hex: brandYellowHex)

    /// Ink drawn ON `createDisc`, pinned to the LIGHT ramp.
    ///
    /// The disc is the same yellow in both appearances, so it is a fixed canvas in
    /// exactly the sense `Color.onLightCanvas` exists for. Following the system here
    /// would put the dark ramp's near-white `ink` (#F2F1EC) on #FCE804 at **1.11:1**
    /// — the plus would vanish in Dark Mode. The light ink measures **15.0:1** on it.
    ///
    /// The reference draws a WHITE plus on a black disc. White on this yellow is
    /// 1.26:1, so the inversion is forced by the colour swap, not a style choice.
    ///
    /// Written as the hex rather than `ink.onLightCanvas`, which is what the map's
    /// fixed-canvas tokens use: `Hue` is `nonisolated` and `onLightCanvas` is a
    /// MainActor-isolated property, so routing through it here is a warning, and
    /// this file holds the zero-warning bar. `CreateDiscContrastTests` pins the two
    /// together so the restated value cannot drift from `ink`'s light column.
    nonisolated static let onCreateDiscHex: UInt32 = 0x111111
    static let onCreateDisc  = Color(hex: onCreateDiscHex)

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
