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

    /// From the photo's top left corner.
    static let inset: CGFloat = 10
    private static let height: CGFloat = 30
    private static let padding: CGFloat = 15

    var body: some View {
        Text(text)
            .font(.sansMedium(14))
            .foregroundStyle(Hue.ink)
            .lineLimit(1)
            .padding(.horizontal, Self.padding)
            .frame(minHeight: Self.height)
            .background(Capsule().fill(Hue.surface))
            .accessibilityLabel(spoken ?? text)
    }
}
