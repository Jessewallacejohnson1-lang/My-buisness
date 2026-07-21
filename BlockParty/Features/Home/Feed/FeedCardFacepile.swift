//
//  FeedCardFacepile.swift
//  Block Party — max-three neighbor avatars, overflow, and current-user pop.
//

import SwiftUI

struct FeedCardFacepile: View {
    let neighborAvatars: [URL]
    let goingCount: Int
    let includesCurrentUser: Bool
    let reduceMotion: Bool

    private let placeholderInitials = ["A", "M", "S"]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(slots) { slot in
                avatar(for: slot)
                    .zIndex(slot.isCurrentUser ? 10 : Double(slot.order))
                    .transition(
                        slot.isCurrentUser
                            ? currentUserTransition
                            : .identity
                    )
            }

            if overflowCount > 0 {
                overflowBadge
                    .zIndex(20)
            }
        }
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.6),
            value: includesCurrentUser
        )
        .accessibilityHidden(true)
    }

    private var slots: [Slot] {
        let visibleCount = min(3, max(0, goingCount))
        guard visibleCount > 0 else { return [] }

        var result: [Slot] = []
        if includesCurrentUser {
            result.append(
                Slot(id: .currentUser, order: 0, url: nil, isCurrentUser: true)
            )
        }

        for (index, url) in neighborAvatars.enumerated()
        where result.count < visibleCount {
            result.append(
                Slot(
                    id: .neighbor(index),
                    order: result.count,
                    url: url,
                    isCurrentUser: false
                )
            )
        }

        while result.count < visibleCount {
            let index = result.count
            result.append(
                Slot(
                    id: .placeholder(index),
                    order: index,
                    url: nil,
                    isCurrentUser: false
                )
            )
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
            Circle().fill(slot.isCurrentUser ? Hue.ink : Hue.fill)

            if slot.isCurrentUser {
                Text("Y")
                    .font(.sansSemibold(10))
                    .foregroundStyle(.white)
            } else if let url = slot.url {
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

    private var currentUserTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .scale(scale: 0.75, anchor: .center).combined(with: .opacity)
    }
}

private extension FeedCardFacepile {
    struct Slot: Identifiable {
        enum ID: Hashable {
            case currentUser
            case neighbor(Int)
            case placeholder(Int)
        }

        let id: ID
        let order: Int
        let url: URL?
        let isCurrentUser: Bool
    }
}
