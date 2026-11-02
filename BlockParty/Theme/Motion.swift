//
//  Motion.swift
//  Block Party — the ONE motion vocabulary for the app's SwiftUI animations.
//
//  Named springs live here, so timing stays consistent and a feel tweak happens in
//  one place.
//
//  Match the token to the MASS of what's moving (emil-design-eng: physics-credible):
//  a small chip is `snappy`, a small card is `card`, a pick or bump is `select`, a
//  colour/opacity fade is `smooth`, and a big surface is `sheet` (heavier — it
//  shouldn't feel as loose as a small card). `bentoExpand` grows something in place.
//
//  NOT here on purpose: Mapbox camera moves (ViewportAnimation) live in the map.
//

import SwiftUI

enum Motion {
    /// Default UI state changes, toggles, chips. ≈ .spring(duration:0.25, bounce:0.15).
    static let snappy: Animation = .spring(duration: 0.25, bounce: 0.15)

    /// A small card settling back (the hello pill after a drag, a like burst).
    static let card: Animation = .spring(response: 0.28, dampingFraction: 0.78)

    /// A pick or a bump: Daily's topic, You's day, a team's star.
    static let select: Animation = .spring(response: 0.32, dampingFraction: 0.72)

    /// Opacity / colour fades, non-bouncy moves (critically damped, no overshoot).
    static let smooth: Animation = .smooth(duration: 0.35)

    /// A big surface moving (the hello drop, the feed's hide and undo). Heavier than
    /// `card` on purpose — a full-width surface should read as more mass than a small card.
    static let sheet: Animation = .spring(response: 0.42, dampingFraction: 0.86)

    /// Something expanding/collapsing in place (the hello drop). Slower and calmer
    /// than `card`: it GROWS where it stands rather than arriving from somewhere, so
    /// it should settle rather than pop.
    static let bentoExpand: Animation = .spring(response: 0.44, dampingFraction: 0.82)
}
