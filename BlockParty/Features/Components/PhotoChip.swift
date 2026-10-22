//
//  PhotoChip.swift
//  Block Party — the white chip on a photo's top left that says when.
//
//  Airbnb's trip card ("In 3 months"), measured for Daily's Event of the day, and since
//  2026-10-19 the Town card's day and time too (BP app docs/plans/event-card, ticket 01).
//

import SwiftUI

struct PhotoChip: View {
    let text: String
    /// What VoiceOver reads, when the chip's words are shorter than the spoken ones.
    var spoken: String? = nil
    /// A dot before the words: "Now" behind Apple's green (`Hue.now`, event-card 04).
    var dot: Color? = nil

    /// From the photo's top left corner.
    static let inset: CGFloat = 10
    static let height: CGFloat = 30
    private static let padding: CGFloat = 15
    /// The game card plan's measures (BP app docs/plans/game-card): an 8 pt dot, 6 pt before the words.
    static let dotSide: CGFloat = 8
    static let dotGap: CGFloat = 6

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Self.dotGap) {
            if let dot {
                Circle().fill(dot).frame(width: Self.dotSide, height: Self.dotSide)
            }
            Text(text)
                .font(.sansMedium(14))
                .foregroundStyle(Hue.ink)
                // A second line at accessibility sizes: the day and time are never cut.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .padding(.horizontal, Self.padding)
        .frame(minHeight: Self.height)
        .background(Capsule().fill(Hue.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
    }
}
