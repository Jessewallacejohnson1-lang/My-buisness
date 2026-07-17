//
//  Motion.swift
//  Hygge — the ONE motion vocabulary for the app's SwiftUI animations.
//
//  Named springs live here and nowhere else — no inline magic spring values
//  scattered in views (map premium-feel spec §1 / acceptance §12.1). Every callsite
//  routes through one of these tokens so timing is consistent and spec-traceable,
//  and a feel tweak happens in one place.
//
//  Match the token to the MASS of what's moving (emil-design-eng: physics-credible):
//  a small chip is `snappy`, a place card is `card`, a marker pop is `select`, a
//  colour/opacity fade is `smooth`, a finger-tracked drag is `interactive`, and the
//  large detented bottom sheet is `sheet` (heavier — a big surface shouldn't feel as
//  loose as a small card, so it keeps its own slightly slower/stiffer spring).
//
//  NOT here on purpose: perpetual live-pulse loops (PulseRing, StatusDot) — those are
//  bespoke `.repeatForever` loops, not discrete state changes, and each is already
//  Reduce-Motion gated. And Mapbox camera moves (ViewportAnimation) / style-expression
//  interpolators live in the map layer, not this SwiftUI enum.
//

import SwiftUI

enum Motion {
    /// Default UI state changes, toggles, chips. ≈ .spring(duration:0.25, bounce:0.15).
    static let snappy: Animation = .spring(duration: 0.25, bounce: 0.15)

    /// Place-card / sheet content, marker→card open & close.
    static let card: Animation = .spring(response: 0.28, dampingFraction: 0.78)

    /// Marker selection pop (the 1.0→1.25 bump + shadow lift).
    static let select: Animation = .spring(response: 0.32, dampingFraction: 0.72)

    /// Opacity / colour fades, non-bouncy moves (critically damped, no overshoot).
    static let smooth: Animation = .smooth(duration: 0.35)

    /// Anything finger-tracking (drag / pan) that needs momentum smoothing.
    static let interactive: Animation = .interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.25)

    /// The large, detented bottom sheet (MapSheet). Heavier than `card` on purpose —
    /// a full-width sheet settling should read as more mass than a small card.
    static let sheet: Animation = .spring(response: 0.42, dampingFraction: 0.86)
}

// MARK: - Staggered content reveal (sheet cards)
//
// Card/sheet content animates in with a subtle cascade — opacity 0→1 + an 8pt upward
// settle, ~0.03s per row, capped so a longer list doesn't feel slow (spec §5). Apply
// to a FIXED, small set of rows (a detail card's blocks), never a long scrolling list.
// Reduce Motion drops straight to the final state.

private struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(Motion.smooth.delay(min(Double(index) * 0.03, 0.24))) { shown = true }
            }
    }
}

extension View {
    /// Reveal this row as part of a capped cascade — see `StaggeredAppear`.
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}
