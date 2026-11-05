//
//  FeedCardFacepile.swift
//  Block Party — max-three neighbor avatars and the overflow badge.
//
//  The current-user slot and its spring-in went with the card's "+" RSVP control on
//  2026-09-19 (Jesse): with nothing on the card to join from, there was no moment for
//  your own face to pop into the pile.
//

import SwiftUI

struct FeedCardFacepile: View {
    let neighborAvatars: [URL]
    let goingCount: Int
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: -8) {
            ForEach(slots) { slot in
                avatar(for: slot)
                    .zIndex(Double(slot.order))
            }

            if overflowCount > 0 {
                overflowBadge
                    .zIndex(20)
            }
        }
        .accessibilityHidden(true)
    }

    private var slots: [Slot] {
        let visibleCount = min(3, max(0, goingCount))
        guard visibleCount > 0 else { return [] }

        var result: [Slot] = []
        for (index, url) in neighborAvatars.enumerated()
        where result.count < visibleCount {
            result.append(Slot(id: .neighbor(index), order: result.count, url: url))
        }

        while result.count < visibleCount {
            let index = result.count
            result.append(Slot(id: .placeholder(index), order: index, url: nil))
        }

        return result
    }

    private var overflowCount: Int {
        max(0, goingCount - slots.count)
    }

    private var overflowBadge: some View {
        Text("+\(overflowCount)")
            .font(.sansSemibold(9))
            .monospacedDigit()
            .foregroundStyle(Hue.ink)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.35, dampingFraction: 0.6),
                value: overflowCount
            )
            .frame(width: 24, height: 24)
            .background(Hue.fill, in: Circle())
            .overlay(Circle().strokeBorder(Hue.paper, lineWidth: 1.5))
    }

    private func avatar(for slot: Slot) -> some View {
        Avatar(slot.url, size: 24)
            .overlay(Circle().strokeBorder(Hue.paper, lineWidth: 1.5))
    }

}

private extension FeedCardFacepile {
    struct Slot: Identifiable {
        enum ID: Hashable {
            case neighbor(Int)
            case placeholder(Int)
        }

        let id: ID
        let order: Int
        let url: URL?
    }
}

/// The neighbour's friends Going (town-feed 28), as Facebook's event card leads its count with
/// a friend's face: 24pt circles overlapping by 8pt like the pile above, each friend's photo or
/// Instagram's blank picture. The line beside them says who; the faces are hidden
/// from VoiceOver.
struct FriendFaces: View {
    let friends: [FeedFriend]
    /// The ring that parts the faces: the page under them (the poster's dark on event-card 03).
    var ring: Color = Hue.paper
    /// Each face, and how far the next one tucks under it; the You Agenda's title makes room
    /// by them (you-tab 07).
    static let side: CGFloat = 24
    static let overlap: CGFloat = 8

    var body: some View {
        HStack(spacing: -Self.overlap) {
            ForEach(Array(friends.prefix(3).enumerated()), id: \.offset) { index, friend in
                Avatar(friend.photo, size: Self.side)
                    .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }
}
