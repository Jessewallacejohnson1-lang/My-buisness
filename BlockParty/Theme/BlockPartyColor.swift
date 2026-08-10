//
//  BlockPartyColor.swift
//  Block Party — design tokens (colors)
//
//  Monochrome ink-on-paper system (July 2026): one warm page ground, white cards,
//  charcoal ink, and a compact neutral ramp with no accent colour.
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

/// Block Party palette. One namespace so call sites read `Hue.paper`, `Hue.ink`, etc.
enum Hue {
    static let ink           = Color(hex: 0x111111)  // primary text, buttons, FABs, active states, pins
    static let paper         = Color(hex: 0xFAFAF7)  // app background (warm white)
    static let surface       = Color(hex: 0xFFFFFF)  // cards
    static let inkSecondary  = Color(hex: 0x6E6E6E)  // secondary text, captions, inactive
    static let hairline      = Color(hex: 0xE7E7E4)  // borders, dividers
    static let fill          = Color(hex: 0xF1F1EF)  // inert fills, placeholders, skeletons

    /// The one brand accent — meaning-scoped ONLY (live events, active filters,
    /// selected/saved state, primary CTAs), never decoration, body copy, or a
    /// background wash. Plum/berry: distinct from the retired coral ramp AND from the
    /// basemap's sage parks / sky water, so it never reads as terrain. On the map
    /// CANVAS the accent means "live" (routed via `MarkerRole`); in sheet/chrome it
    /// marks the active/selected/primary control. Not the retired coral 0xFF6B57.
    /// See DECISIONS.md.
    static let accent        = Color(hex: 0x8E3B6B)  // plum / berry
}
