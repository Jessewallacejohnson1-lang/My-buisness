//
//  HyggeColor.swift
//  Hygge — design tokens (colors)
//
//  Unified coral + white system (July 2026): coral is the primary accent on white
//  surfaces across every screen — the old warm-linen surfaces + green buttons are
//  retired. Mirrors the map's white+coral look and the RN twin's coral accent.
//

import SwiftUI
import UIKit

extension Color {
    /// Build a Color from a 0xRRGGBB hex literal.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
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

/// Hygge palette. One namespace so call sites read `Hue.paper`, `Hue.ink`, etc.
enum Hue {
    // Surfaces — white + subtle gray (unified with the map system; Strava-clean)
    static let paper    = Color(hex: 0xFFFFFF)  // default surface — pure white cards
    static let paper100 = Color(hex: 0xF6F7F8)  // raised tint
    static let paper200 = Color(hex: 0xEFF1F3)  // muted surface
    static let paper300 = Color(hex: 0xE5E7EB)  // de-emphasized / dividers
    static let canvas   = Color(hex: 0xF6F7F8)  // app page background — white cards lift off it

    // Text — charcoal ink ramp (WCAG-verified on paper)
    static let ink  = Color(hex: 0x2a2a28)  // primary (AAA)
    static let ink2 = Color(hex: 0x5e5d56)  // secondary (AA body)
    static let ink3 = Color(hex: 0x828077)  // tertiary / placeholder

    // moss → coral now: primary action / completed / positive. Key names kept to avoid
    // churning ~30 call sites — the whole app's primary accent is coral (see `accent`).
    static let moss400 = Color(hex: 0xFF8A79)  // light coral
    static let moss500 = Color(hex: 0xE5503C)  // pressed / deep
    static let moss700 = Color(hex: 0xFF6B57)  // coral — primary button
    static let moss800 = Color(hex: 0xC7452F)  // deepest pressed

    // sky → brand / focus rings
    static let sky400 = Color(hex: 0xa6b1b6)
    static let sky500 = Color(hex: 0x87959c)
    static let sky600 = Color(hex: 0x6b7b84)  // brand
    static let sky700 = Color(hex: 0x55636b)
    static let sky800 = Color(hex: 0x3e4d54)

    // honey → warmth (use sparingly)
    static let honey500 = Color(hex: 0xEDAE1C)  // brighter sun-gold — the Almanac sun glyph
    static let honey600 = Color(hex: 0xb07d2b)
    static let honey700 = Color(hex: 0x8a5f1c)

    // clay → warning / error only
    static let clay700 = Color(hex: 0xb0573a)
    static let clay800 = Color(hex: 0x8c4329)

    // Hairline border — border-black/[0.07]
    static let hairline = Color.black.opacity(0.07)

    // MARK: Coral accent system (Strava-clean, warm coral on white)
    // Coral is THE primary accent across the whole app — live indicators, primary
    // buttons, active/selected states, tappable elements. Neutrals: surface/gray/mapInk.
    static let accent        = Color(hex: 0xFF6B57)  // warm coral — live + tappable
    static let accentPressed = Color(hex: 0xE5503C)  // button pressed state
    static let accentSoft    = Color(hex: 0xFFF0EC)  // soft tint

    static let surface  = Color(hex: 0xFFFFFF)  // pure white floating elements
    static let bgSubtle = Color(hex: 0xF6F7F8)  // subtle background

    static let gray      = Color(hex: 0x6B7280)  // secondary text
    static let grayLight = Color(hex: 0x9CA3AF)  // captions

    static let mapInk      = Color(hex: 0x1A1D21)  // primary text + icons on map
    static let mapHairline = Color(hex: 0xE5E7EB)  // borders / grabber pill
}
