//
//  ShareLook.swift
//  Block Party — the share card's colours (BP app share-sheet 01).
//

import SwiftUI

/// The share card's two looks, measured off Hypelist's card (BP app `references/share-sheet/SPEC.md`, "Why it looks
/// clean"; Jesse, 2026-11-19: "easy on eyes not the harsh yellow"): the picture's own hue greyed down to 30% saturation
/// and 31% brightness, a touch greyer and lighter at the top; and a pale tint of the same hue. A picture with no
/// colourful hue, or none at all, takes soft charcoal and a pale warm grey.
nonisolated struct ShareLook: Equatable, Sendable {
    let top: UInt32
    let mid: UInt32
    let foot: UInt32
    /// White words, name and edge light on it; else ink.
    let dark: Bool

    /// Under this saturation a picture's colour counts as grey (`EventLook.grey` is 0).
    static let greyBelow = 0.08
    /// Where the middle colour sits down the card.
    static let midAt = 0.45

    static let charcoal = ShareLook(top: 0x4C4A48, mid: 0x383634, foot: 0x2D2C2B, dark: true)
    static let paleGrey = ShareLook(top: 0xF8F6F2, mid: 0xF0EDE8, foot: 0xE9E5DE, dark: false)

    /// The first look: the picture's hue, as quiet as Hypelist's dusty maroon.
    static func colour(_ rgb: UInt32?) -> ShareLook {
        guard let hue = hue(rgb) else { return charcoal }
        return ShareLook(top: hsv(hue, 0.19, 0.36), mid: hsv(hue, 0.30, 0.31), foot: hsv(hue, 0.30, 0.27), dark: true)
    }

    /// The second look: a pale tint of the same hue, ink on it.
    static func pale(_ rgb: UInt32?) -> ShareLook {
        guard let hue = hue(rgb) else { return paleGrey }
        return ShareLook(top: hsv(hue, 0.05, 0.97), mid: hsv(hue, 0.08, 0.945), foot: hsv(hue, 0.11, 0.92), dark: false)
    }

    var stops: [Gradient.Stop] {
        [.init(color: Color(hex: top), location: 0), .init(color: Color(hex: mid), location: Self.midAt),
         .init(color: Color(hex: foot), location: 1)]
    }

    /// The colour's hue (0 to 1), or nil for none and for a grey.
    static func hue(_ rgb: UInt32?) -> Double? {
        guard let rgb else { return nil }
        let (h, s, _) = hsv(of: rgb)
        return s < greyBelow ? nil : h
    }

    /// Hue (0 to 1), saturation and brightness, as Python's colorsys gives them (the mock's rule).
    static func hsv(of rgb: UInt32) -> (Double, Double, Double) {
        let r = Double(rgb >> 16 & 0xFF) / 255, g = Double(rgb >> 8 & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), d = high - low
        guard high > 0, d > 0 else { return (0, 0, high) }
        let h = high == r ? (g - b) / d + (g < b ? 6 : 0) : high == g ? (b - r) / d + 2 : (r - g) / d + 4
        return (h / 6, d / high, high)
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> UInt32 {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
        func channel(_ c: Double) -> UInt32 { UInt32((c * 255).rounded()) }
        return channel(r) << 16 | channel(g) << 8 | channel(b)
    }
}
