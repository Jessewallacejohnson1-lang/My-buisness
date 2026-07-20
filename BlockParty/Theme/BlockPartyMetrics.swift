//
//  BlockPartyMetrics.swift
//  Block Party — design tokens (radii, elevation, card style)
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
    func blockPartyCard(radius: CGFloat = Radius.lg, padding: CGFloat? = 16) -> some View {
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
    func blockPartyHairline(radius: CGFloat = Radius.md) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
    }

    // MARK: Map shadows (soft, diffuse — no hard dark edges)

    /// Floating chrome button: y=2, blur=8, 10% opacity (spec §8 — one clean elevation).
    func mapFloatShadow(pressed: Bool = false) -> some View {
        self.shadow(
            color: .black.opacity(pressed ? 0.14 : 0.10),
            radius: pressed ? 10 : 8,
            x: 0, y: 2
        )
    }

    /// Map marker elevation — a TIGHTER, closer shadow than a floating button, and it
    /// lifts on selection (spec §8): awake = 0.12 / blur 4 / y 1 → selected = 0.20 /
    /// blur 10 / y 3. The y-shift (1→3) is what reads as "the pin rose toward you".
    func mapMarkerShadow(selected: Bool = false) -> some View {
        self.shadow(
            color: .black.opacity(selected ? 0.20 : 0.12),
            radius: selected ? 10 : 4,
            x: 0, y: selected ? 3 : 1
        )
    }

    /// Bottom sheet: y=−2 (upward), blur=16, 8% opacity.
    func mapSheetShadow() -> some View {
        self.shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -2)
    }
}
