//
//  FeedModuleStates.swift
//  Block Party — loading faces and error copy for the lower Today feed modules.
//
//  The shared shapes live in `FeedStateViews` (`FeedUnavailableCard`,
//  `FeedSkeletonSection`, `FeedRetryButton`) and are used verbatim here, so For
//  You, the spotlight, trivia and the sign-off fail and load like the almanac,
//  Your Day and Town Notes above them. What is module-specific — and what this
//  file owns — is the SHAPE each skeleton stands in for, and the one sentence
//  that names what didn't load.
//
//  Three rules:
//  1. A skeleton is the shape of its content. Same paddings, radii and block
//     heights, so the real card lands in place instead of shoving the column.
//     A heading that is already known renders for real; only the unknown parts
//     are placeholders.
//  2. An error is calm and in the house voice: what didn't load, and one action.
//     No error codes, no red.
//  3. `phase == .empty` renders nothing at all. A module with nothing to say says
//     nothing; it does not draw a card explaining its own absence.
//

import SwiftUI

/// Titles for the shared error card. Sentence case, past tense, naming the thing
/// the reader was waiting for — never the layer that failed.
nonisolated enum FeedLowerStateCopy {
    static let forYouUnavailable = "Your picks didn't load."
    static let spotlightUnavailable = "This week's spotlight didn't load."
    static let triviaUnavailable = "Today's trivia didn't load."
}

/// Matches `SpotlightCard`: eyebrow, title, two blurb lines, the 16:9 venue photo
/// and the map button, all at the card's own 18pt paddings.
struct SpotlightCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                SkeletonLine(widthFraction: 0.46, height: 11)
                SkeletonLine(widthFraction: 0.60, height: 22)
                // Three ragged blurb lines: the live blurbs are one sentence and
                // wrap to three at this width, so two would drop the card ~22pt
                // when the real text lands.
                SkeletonLine(widthFraction: 1.0, height: 14)
                SkeletonLine(widthFraction: 0.96, height: 14)
                SkeletonLine(widthFraction: 0.44, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            SkeletonBlock(cornerRadius: 0)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

            SkeletonBlock(cornerRadius: Radius.button)
                .frame(height: 42)
                .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// Matches `TriviaCard`: the kicker (known chrome, so it is real), the prompt, and
/// the four 52pt answer rows.
struct TriviaCardSkeleton: View {
    var body: some View {
        FeedSkeletonSection(spacing: 7) {
            Text("St. Joe trivia")
                .font(.monoMedium(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Hue.inkSecondary)
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                // Two prompt lines: a St. Joe question wraps at this width, and a
                // single line would let the four rows jump 28pt on swap-in.
                VStack(alignment: .leading, spacing: 9) {
                    SkeletonLine(widthFraction: 0.92, height: 24)
                    SkeletonLine(widthFraction: 0.52, height: 24)
                }

                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: Radius.button)
                            .frame(height: 52)
                    }
                }
            }
        }
        .blockPartyCard(padding: 18)
    }
}

/// Matches `CaughtUpFooter`: one centred line inside the same 38pt breathing room,
/// so the edition's ending does not jump into place.
struct SignOffSkeleton: View {
    var body: some View {
        SkeletonBlock(cornerRadius: 8)
            .frame(width: 214, height: 17)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 38)
            .shimmering()
            .accessibilityHidden(true)
    }
}
