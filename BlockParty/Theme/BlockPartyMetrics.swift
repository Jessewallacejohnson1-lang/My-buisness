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

    /// Search, measured from its References (mockup v7, 2026-10-02): iOS's search field
    /// and the round result avatars' squares (10), Photoroom's logo squares (11), and
    /// Airbnb's photo cards (13).
    static let searchField: CGFloat = 10
    static let logoTile: CGFloat = 11
    static let photoCard: CGFloat = 13
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

    // MARK: The Daily Spotlight (Jesse: the one card that pops out)

    /// The Spotlight card's own crisp edge, under the low sun's shadow (`DailyPage`).
    func spotlightEdge() -> some View {
        shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1.5)
    }

    /// The Spotlight's round photo, pressed: it rises toward the finger and casts its
    /// own shadow on the card. At rest the low sun's shadow covers it, as in the depth
    /// mockup Jesse picked (2026-10-01).
    func portraitLift(pressed: Bool) -> some View {
        shadow(color: .black.opacity(pressed ? 0.30 : 0), radius: 16, x: 0, y: 18)
    }

    // MARK: The Meetup pill (`MeetupPillStyle`)

    /// The pill's two shadows (Figma "Meetup depth"): black 30%, 1.5 pt down, 3 pt blur where
    /// it touches the page, and black 22%, 8 pt down, 24 pt blur that lifts it. Pressed they
    /// pull in, to 1 pt / 2 pt and 3 pt / 10 pt at 16%. Each falls from its own copy of the
    /// capsule, so the wide one doesn't blur the tight one too. Figma's blur is twice
    /// SwiftUI's radius.
    func meetupPillDepth(pressed: Bool) -> some View {
        background {
            ZStack {
                Capsule().shadow(color: .black.opacity(0.30), radius: pressed ? 1 : 1.5, x: 0, y: pressed ? 1 : 1.5)
                Capsule().shadow(color: .black.opacity(pressed ? 0.16 : 0.22), radius: pressed ? 5 : 12,
                                 x: 0, y: pressed ? 3 : 8)
            }
        }
    }

    /// The Event page's white RSVP bar (Figma "Meetup depth"): black 10%, 2 pt down, 6 pt blur,
    /// and black 8%, 10 pt down, 30 pt blur, each from its own copy of the capsule.
    func meetupBarDepth() -> some View {
        background {
            ZStack {
                Capsule().shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 2)
                Capsule().shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 10)
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
