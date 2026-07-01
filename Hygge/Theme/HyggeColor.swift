//
//  HyggeColor.swift
//  Hygge — design tokens (colors)
//
//  Ported verbatim from the Expo app's src/theme.ts + tailwind.config.js.
//  Warm linen surfaces, charcoal ink, accents with one job each.
//  Keep these in sync with the React Native source of truth.
//

import SwiftUI

extension Color {
    /// Build a Color from a 0xRRGGBB hex literal.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Hygge palette. One namespace so call sites read `Hue.paper`, `Hue.ink`, etc.
enum Hue {
    // Surfaces — warm linen first
    static let paper    = Color(hex: 0xfbfaf5)  // default surface
    static let paper100 = Color(hex: 0xf5f1e8)  // raised tint
    static let paper200 = Color(hex: 0xeae4d4)  // muted surface
    static let paper300 = Color(hex: 0xe1dbc9)  // de-emphasized
    static let canvas   = Color(hex: 0xf1f0ec)  // app page background

    // Text — charcoal ink ramp (WCAG-verified on paper)
    static let ink  = Color(hex: 0x2a2a28)  // primary (AAA)
    static let ink2 = Color(hex: 0x5e5d56)  // secondary (AA body)
    static let ink3 = Color(hex: 0x828077)  // tertiary / placeholder

    // moss → positive / primary action / completed
    static let moss400 = Color(hex: 0x4f7053)
    static let moss500 = Color(hex: 0x3c5a40)
    static let moss700 = Color(hex: 0x2d4530)  // primary button
    static let moss800 = Color(hex: 0x1f3022)

    // sky → brand / focus rings
    static let sky400 = Color(hex: 0xa6b1b6)
    static let sky500 = Color(hex: 0x87959c)
    static let sky600 = Color(hex: 0x6b7b84)  // brand
    static let sky700 = Color(hex: 0x55636b)
    static let sky800 = Color(hex: 0x3e4d54)

    // honey → warmth (use sparingly)
    static let honey600 = Color(hex: 0xb07d2b)
    static let honey700 = Color(hex: 0x8a5f1c)

    // clay → warning / error only
    static let clay700 = Color(hex: 0xb0573a)
    static let clay800 = Color(hex: 0x8c4329)

    // Hairline border — border-black/[0.07]
    static let hairline = Color.black.opacity(0.07)
}
