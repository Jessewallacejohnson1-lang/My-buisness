//
//  CardTime.swift
//  Block Party — when, on every Town card: plain words just under the title, as Instagram's feed puts its
//  time under the caption, with no chip and no pill (BP app inside-cards 25 and 26; Jesse, 2026-11-07,
//  "i agree with all" to the page that drew it). The photo's top keeps only its credit and the host's logo.
//

import SwiftUI

/// The time's one look on the photo card, the poster, the white card, News and the game card: BP Body
/// SemiBold 14, white over a picture (under the title's shadow, which the caller's words carry), the small
/// line's grey on white, BP yellow on the poster. On now, "Now" behind Apple's green dot cross-fades in at
/// the start minute, as the chip did. At accessibility sizes it may take a second line: never cut off.
struct CardTime: View {
    let text: String
    var spoken: String? = nil
    /// On right now: "Now" behind the green dot, in place of `text`.
    var now = false
    let color: Color
    /// Lines at the default text sizes, one more at accessibility sizes: the game card's day over its time is 2.
    var lines = 1

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A ZStack, not a Group: a Group hands the transition to each line, and the one coming in never
        // sees `now` change, so it would cut.
        ZStack(alignment: .leading) {
            if now {
                words("Now", spoken: "Happening now", dot: Hue.now).transition(.opacity)
            } else {
                words(text, spoken: spoken ?? text, dot: nil).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: now)
    }

    private func words(_ text: String, spoken: String, dot: Color?) -> some View {
        HStack(spacing: PhotoChip.dotGap) {
            if let dot {
                Circle().fill(dot).frame(width: PhotoChip.dotSide, height: PhotoChip.dotSide)
            }
            Text(text)
                .font(.sansSemibold(14))
                .foregroundStyle(color)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? lines + 1 : lines)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
