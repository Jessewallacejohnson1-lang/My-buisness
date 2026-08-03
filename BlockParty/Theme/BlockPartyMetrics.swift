//
//  BlockPartyMetrics.swift
//  Block Party — design tokens (radii, elevation, card style)
//

import SwiftUI

/// Canonical corner radius scale.
enum Radius {
    static let button: CGFloat = 12
    static let tile: CGFloat = 16
    static let card: CGFloat = 20

    /// The Calendar-bento family — the Insights bento boxes and the Today utility
    /// tiles, which are the same object at two sizes. Deliberately OUTSIDE the
    /// 12/16/20 scale: a bento is a large gradient slab, not a white card, and 20
    /// reads boxy at that footprint while 24 starts to look like a pill.
    ///
    /// It exists as a token because the two surfaces MUST stay equal. They were
    /// two separate literals carrying "deliberate match" comments, and a comment
    /// cannot fail a build when one of them moves.
    static let bento: CGFloat = 22
}

/// The single elevation in the system — one soft, neutral lift. Everything else
/// stays flat, leaning on fill + the hairline border instead.
struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// A white card: surface fill, hairline border, card radius, the one soft shadow.
    func blockPartyCard(radius: CGFloat = Radius.card, padding: CGFloat? = 16) -> some View {
        self
            .padding(padding ?? 0)
            .background(Hue.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: 1)
            )
            .modifier(CardShadow())
    }

    /// Hairline-bordered surface with no shadow (chips, inputs, flat tiles).
    func blockPartyHairline(radius: CGFloat = Radius.button) -> some View {
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
