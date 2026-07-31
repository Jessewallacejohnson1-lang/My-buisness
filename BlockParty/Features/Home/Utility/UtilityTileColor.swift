//
//  UtilityTileColor.swift
//  Block Party — the Utility Row COLOR SYSTEM: one file of named gradient tokens.
//  A future tile adds its own token here (hex pair [top, bottom]) — nothing else.
//
//  These are FULL-COLOUR tiles: a deliberate, user-approved departure from the
//  app's monochrome chrome. Every gradient here is darkened so its LIGHTER stop
//  passes WCAG 4.5:1 against white text (verified — see the ratios below and
//  scripts/contrast.py). Pure data (hex ints); the tile view maps to Color.
//

import Foundation

enum UtilityTileGradient {
    // Static per-tile tokens [top, bottom]. Contrast ratio = worst-case (lighter)
    // stop on white; all ≥ 4.5:1.
    static let weather:   [UInt32] = [0x3677AF, 0x20528F]   // blue      · 4.76:1 (static fallback)
    static let garbage:   [UInt32] = [0x1F8438, 0x115A24]   // green     · 4.76:1
    static let roads:     [UInt32] = [0xA46404, 0x7B3900]   // amber     · 4.77:1
    static let library:   [UInt32] = [0xA14BCD, 0x712B9B]   // purple    · 4.77:1
    static let customize: [UInt32] = [0x727276, 0x47474B]   // neutral   · 4.79:1

    /// The live weather tile derives its gradient from the current WeatherState,
    /// darkened so white text stays legible (the raw WeatherState.gradient palettes
    /// are light sky backgrounds and fail 4.5:1). nil → static blue fallback.
    static func weather(for state: WeatherState?) -> [UInt32] {
        switch state {
        case .clearDay:   return [0x375D7A, 0x637581]   // 4.78:1
        case .clearNight: return [0x1B2A4A, 0x33415E]   // 10.20:1 (already dark)
        case .cloudy:     return [0x505962, 0x6E7379]   // 4.78:1
        case .rain:       return [0x46515C, 0x68747E]   // 4.79:1
        case .snow:       return [0x565C61, 0x6F7376]   // 4.78:1
        case .storm:      return [0x2C2E3A, 0x4A4E63]   // 8.20:1 (already dark)
        case nil:         return weather
        }
    }
}

/// WCAG contrast helper — used to VERIFY the tokens above (Phase 4 report / a
/// DEBUG self-check). White text ⇒ the lighter stop is the worst case.
enum UtilityContrast {
    /// Relative luminance of an sRGB hex colour (0…1).
    nonisolated static func luminance(_ hex: UInt32) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(Double((hex >> 16) & 0xFF) / 255)
        let g = lin(Double((hex >> 8) & 0xFF) / 255)
        let b = lin(Double(hex & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Contrast ratio of white text on the given colour.
    nonisolated static func ratioOnWhite(_ hex: UInt32) -> Double {
        1.05 / (luminance(hex) + 0.05)
    }

    /// Worst-case (lighter-stop) white-text ratio for a gradient; ≥ 4.5 required.
    nonisolated static func worstRatioOnWhite(_ gradient: [UInt32]) -> Double {
        gradient.map(ratioOnWhite).min() ?? 0
    }
}
