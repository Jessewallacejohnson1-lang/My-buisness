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

    private let placeholderInitials = ["A", "M", "S"]

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
        ZStack {
            Circle().fill(Hue.fill)

            if let url = slot.url {
                FeedCardURLPhoto(url: url)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } else {
                Text(placeholderInitials[slot.order % placeholderInitials.count])
                    .font(.sansSemibold(10))
                    .foregroundStyle(Hue.ink)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
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

/// A feed author's profile picture: the poster of a posting, the host of an event.
///
/// Always a circle (Jesse, 2026-09-19). The photo-less case is their initial on an
/// inert fill, matching the facepile's placeholder above — NOT `BlockPartyGlyph`,
/// which is the app icon on a rounded square, and whose wide wordmark lockup loses
/// its ends when clipped into a circle.
struct FeedAuthorAvatar: View {
    let url: URL?
    let name: String
    var side: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(Hue.fill)

            if let url {
                FeedCardURLPhoto(url: url)
                    .frame(width: side, height: side)
            } else {
                Text(initial)
                    .font(.sansSemibold(14))
                    .foregroundStyle(Hue.ink)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }

    private var initial: String {
        name.first.map { String($0).uppercased() } ?? ""
    }
}
