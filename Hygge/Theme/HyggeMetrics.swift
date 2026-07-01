//
//  HyggeMetrics.swift
//  Hygge — design tokens (radii, elevation, card style)
//

import SwiftUI

/// Corner radius scale, named by px value so class and code never drift.
enum Radius {
    static let sm: CGFloat = 8   // small chips / insets
    static let md: CGFloat = 12  // inputs, buttons (control default)
    static let lg: CGFloat = 16  // cards (card default)
    static let xl: CGFloat = 20  // full-bleed sheets / hero
}

/// The single elevation in the system — one soft, warm lift. Everything else
/// stays flat, leaning on fill + the hairline border instead.
struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color(hex: 0x2a241c, alpha: 0.10), radius: 11, x: 0, y: 6)
    }
}

extension View {
    /// A linen card: paper fill, hairline border, lg radius, the one soft shadow.
    func hyggeCard(radius: CGFloat = Radius.lg, padding: CGFloat? = 16) -> some View {
        self
            .padding(padding ?? 0)
            .background(Hue.paper)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: 1)
            )
            .modifier(CardShadow())
    }

    /// Hairline-bordered surface with no shadow (chips, inputs, flat tiles).
    func hyggeHairline(radius: CGFloat = Radius.md) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
    }
}
