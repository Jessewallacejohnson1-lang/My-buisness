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

    /// A large slab's corner: Daily's Spotlight card (Jesse, 2026-09-30).
    /// Deliberately OUTSIDE the 12/16/20 scale: 20 reads boxy at that footprint while
    /// 24 starts to look like a pill.
    static let bento: CGFloat = 22

    /// Search, measured from its References (mockup v7, 2026-10-02): iOS's search field
    /// and the round result avatars' squares (10), Photoroom's logo squares (11), and
    /// Airbnb's photo cards (13).
    static let searchField: CGFloat = 10
    static let logoTile: CGFloat = 11
    static let photoCard: CGFloat = 13
    /// New in St. Joseph's yellow New tag, from the five-tabs mock's round 2 (BP app five-tabs 04).
    static let newTag: CGFloat = 7

    /// The Town's Event of the day poster: DICE's card corner (the approved Round 3 page, BP app
    /// event-card 03), tighter than a Town card's 20, as a printed poster's is.
    static let poster: CGFloat = 10
}

/// The single elevation in the system — one soft, neutral lift. Everything else
/// stays flat, leaning on fill + the hairline border instead.
struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// Hairline-bordered surface with no shadow (chips, inputs, flat tiles).
    func blockPartyHairline(radius: CGFloat = Radius.button) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
    }

    // MARK: The Daily Spotlight (Jesse: the one card that pops out)

    /// The Spotlight card's own crisp edge, under the low sun's shadow (`DailyPage`).
    func spotlightEdge() -> some View {
        shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1.5)
    }

    // MARK: The Meetup pill (`MeetupPillStyle`)

    /// The pill's two shadows (Figma "Meetup depth"): black 30%, 1.5 pt down, 3 pt blur where
    /// it touches the page, and black 22%, 8 pt down, 24 pt blur that lifts it. Pressed they
    /// pull in, to 1 pt / 2 pt and 3 pt / 10 pt at 16%. Each falls from its own copy of the
    /// capsule, so the wide one doesn't blur the tight one too. Figma's blur is twice
    /// SwiftUI's radius.
    /// `strength`: the light buttons (Town's grey X, the yellow share) cast a lighter shadow (event-card 06).
    func meetupPillDepth(pressed: Bool, strength: Double = 1) -> some View {
        background {
            ZStack {
                Capsule().shadow(color: .black.opacity(0.30 * strength), radius: pressed ? 1 : 1.5, x: 0, y: pressed ? 1 : 1.5)
                Capsule().shadow(color: .black.opacity((pressed ? 0.16 : 0.22) * strength), radius: pressed ? 5 : 12,
                                 x: 0, y: pressed ? 3 : 8)
            }
        }
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
}
