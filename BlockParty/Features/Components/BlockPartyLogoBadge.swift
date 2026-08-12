//
//  BlockPartyLogoBadge.swift
//  Block Party — the brand mark
//
//  The exact app mark beside the product name, set on a crisp ink rectangle
//  (square corners — a printed stamp, not a button).
//
//  Mirrors the RN twin's <BlockPartyLogoBadge /> so both apps read identically.
//

import SwiftUI

struct BlockPartyLogoBadge: View {
    var body: some View {
        HStack(spacing: 7) {
            BlockPartyMark(side: 24)
            Text("Block Party")
                .font(.logo(15))
                .foregroundStyle(.white)
                .kerning(0.2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
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
