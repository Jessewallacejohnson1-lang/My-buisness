//
//  HyggeLogoBadge.swift
//  Hygge — the brand mark
//
//  The wordmark set in Atkinson Hyperlegible Bold, white on a crisp coral
//  rectangle (square corners — a printed stamp, not a button). This is the ONE
//  place the logo face is used; every other surface is the system font.
//
//  Mirrors the RN twin's <HyggeLogoBadge /> so both apps read identically.
//

import SwiftUI

struct HyggeLogoBadge: View {
    var body: some View {
        Text("Hygge")
            .font(.logo(15))                 // Atkinson Hyperlegible Bold
            .foregroundStyle(.white)
            .kerning(0.2)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Hue.accent)          // coral #FF6B57 — a crisp rectangle, no radius
            // A light lift so the mark holds over the map / photos without reading heavy.
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Hygge")
    }
}

// The shared placement: pinned to the top-right safe-area corner so the mark lands
// in the same spot on every screen. It's a decorative stamp, so it never
// intercepts touches — the header controls it sits beside stay tappable.
private struct BrandBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            HyggeLogoBadge()
                .padding(.top, 8)
                .padding(.trailing, 16)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Pin the Hygge brand mark to the top-right safe-area corner of this screen.
    func brandBadge() -> some View { modifier(BrandBadgeModifier()) }
}

#Preview {
    ZStack {
        Hue.canvas.ignoresSafeArea()
        VStack(spacing: 24) {
            HyggeLogoBadge()
            HyggeLogoBadge().scaleEffect(2)
        }
    }
}
