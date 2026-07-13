//
//  TimeWashOverlay.swift
//  Hygge — the atmospheric glow above the basemap. Low opacity (≤0.16) so pins
//  stay crisp; the palette (below the pins) carries most of the time feel. Night
//  is a near-uniform veil; golden/dawn/dusk are directional (light from a corner).
//

import SwiftUI

struct TimeWashOverlay: View {
    let atmosphere: TownAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let w = BasemapPalette.make(for: atmosphere).wash
        let c = Color(.sRGB, red: w.r, green: w.g, blue: w.b, opacity: w.a)
        let faint = Color(.sRGB, red: w.r, green: w.g, blue: w.b, opacity: w.a * 0.15)
        let uniform = atmosphere.phase == .night
        Rectangle()
            .fill(
                LinearGradient(
                    colors: uniform ? [c, c] : [c, faint],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: atmosphere.phase)
    }
}
