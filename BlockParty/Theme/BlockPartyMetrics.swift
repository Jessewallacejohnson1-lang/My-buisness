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

    /// Search, measured from its References (mockup v7, 2026-10-02): iOS's search field
    /// and the round result avatars' squares (10), Photoroom's logo squares (11), and
    /// Airbnb's photo cards (13).
    static let searchField: CGFloat = 10
    static let logoTile: CGFloat = 11
    static let photoCard: CGFloat = 13
    /// New in St. Joseph's yellow New tag, from the five-tabs mock's round 2 (BP app five-tabs 04).
    static let newTag: CGFloat = 7
    /// Adjust's strip of a post's photos: Instagram's small rounded squares (BP app backlog 32, the mock's 8).
    static let adjustThumb: CGFloat = 8

    /// The Town's Event of the day poster: DICE's card corner (the approved Round 3 page, BP app
    /// event-card 03), tighter than a Town card's 20, as a printed poster's is.
    static let poster: CGFloat = 10

    /// The hello pill open into a count's Events, and each row's photo: the approved Figma L2 (BP app hello-drop 10).
    static let helloList: CGFloat = 28
    static let helloRowPhoto: CGFloat = 10

    /// A school page's cards, Apple Sports' league page as the picked mock draws them (BP app
    /// school-search 05, version 2; measured off Apple's own frame they come out nearer 26).
    static let schoolCard: CGFloat = 30
    /// Search's Event calendar, the picked day's card: the Sports mock's card, as the approved mock draws it
    /// (BP app five-tabs 10).
    static let dayCard: CGFloat = 30
    /// The share sheet's story card and the picture card in it, measured off Hypelist's (BP app share-sheet 01,
    /// `references/share-sheet/SPEC.md`).
    static let shareCard: CGFloat = 18
    static let shareFace: CGFloat = 14
    /// Onboarding's Name box and Photo squircle, measured off Clubhouse's (BP app onboarding 55,
    /// `references/profile-clubhouse/SPEC.md`): the box's corner, and a face's iOS smooth corner as a
    /// share of its side (66.6 on the Photo step's 160, whose inside is Clubhouse's 158 at 65.6): every person's picture (backlog 40).
    static let nameBox: CGFloat = 4.8
    /// Follow 3's white search box, Spotify's, measured (BP app onboarding 50, `references/follow-spotify/SPEC.md`).
    static let followSearch: CGFloat = 3.7
    static let faceShare: CGFloat = 0.416
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
