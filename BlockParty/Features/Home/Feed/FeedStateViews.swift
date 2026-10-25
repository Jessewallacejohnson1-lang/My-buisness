//
//  FeedStateViews.swift
//  Block Party — the ONE shape of "loading" and "didn't load" in the Today feed.
//
//  Your Day and Town Notes each fetched on their own, so before this file
//  each had invented its own failure card: different background, different radius,
//  different button, different sentence. Three ways to say the same thing on one
//  screen reads as three unfinished features. They now share this.
//
//  Rules encoded here:
//   • A section HEADING is chrome, not data. It is known before the fetch, so the
//     skeleton renders the real heading and only stands in for what is unknown.
//     That is also what stops the heading from jumping when content swaps in.
//   • An error is calm: house voice, sentence case, no code, no red, one verb.
//   • The button says what happens when it is tapped.
//

import SwiftUI

/// The words. Shared so the feed's states cannot drift apart a sentence at a time.
nonisolated enum FeedStateCopy {
    /// The same second line everywhere. It names the likeliest cause and the fix,
    /// and nothing else — a neighbour telling you the wifi dropped.
    static let retryMessage = "Check your connection and try again."

    /// A label that matches what tapping it does: it runs the load again.
    static let retryAction = "Try again"

    /// Working words; Jesse writes the final ones.
    static let townEventsUnavailable = "Events didn’t load."
    /// The Town feed's pill when a read fails over a kept list: the map sheet's words
    /// (Jesse, 2026-10-09).
    static let offline = "You’re offline."
}

/// Title + explanation + retry, with no surface of its own. Used directly when the
/// state already sits inside a card.
struct FeedUnavailableBody: View {
    let title: String
    var message: String = FeedStateCopy.retryMessage
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            FeedRetryButton(action: retry)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Ink-filled, `Radius.button` — a rounded square, never a pill. Every visual is
/// inside the label so `FeedCardPressStyle` scales the whole control, not just its
/// text sitting inside a stationary background.
struct FeedRetryButton: View {
    var title: String = FeedStateCopy.retryAction
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.surface)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(
                    Hue.ink,
                    in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                )
        }
        .buttonStyle(FeedCardPressStyle())
    }
}

/// A section heading rendered for real above a set of skeleton shapes. The heading
/// is known before the fetch resolves, so standing in for it would be a lie that
/// also costs a layout jump on swap-in. Only the placeholder shapes shimmer, and
/// only they are hidden from VoiceOver — the heading is real content.
struct FeedSkeletonSection<Heading: View, Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var heading: () -> Heading
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            heading()

            content()
                .shimmering()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
