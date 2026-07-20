//
//  BlockPartyLogoBadge.swift
//  Block Party — the brand mark
//
//  The wordmark set in Jost SemiBold, white on a crisp ink
//  rectangle (square corners — a printed stamp, not a button). This is the ONE
//  place the logo face is used; every other surface is the system font.
//
//  Mirrors the RN twin's <BlockPartyLogoBadge /> so both apps read identically.
//

import SwiftUI

struct BlockPartyLogoBadge: View {
    var body: some View {
        Text("Block Party")
            .font(.logo(15))                 // Jost SemiBold
            .foregroundStyle(.white)
            .kerning(0.2)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Hue.ink)          // a crisp rectangle, no radius
            // A light lift so the mark holds over the map / photos without reading heavy.
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Block Party")
    }
}

// The shared placement: pinned to the top-right safe-area corner so the mark lands
// in the same spot on every screen. It's a decorative stamp, so it never
// intercepts touches — the header controls it sits beside stay tappable.
private struct BrandBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            BlockPartyLogoBadge()
                .padding(.top, 8)
                .padding(.trailing, 16)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Pin the Block Party brand mark to the top-right safe-area corner of this screen.
    func brandBadge() -> some View { modifier(BrandBadgeModifier()) }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        VStack(spacing: 24) {
            BlockPartyLogoBadge()
            BlockPartyLogoBadge().scaleEffect(2)
        }
    }
}
