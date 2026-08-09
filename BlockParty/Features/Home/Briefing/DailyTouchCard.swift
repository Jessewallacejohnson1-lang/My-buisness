//
//  DailyTouchCard.swift
//  Block Party — the daily poll or town-history touchpoint.
//

import SwiftUI

struct DailyTouchCard: View {
    let touch: BriefingTouch
    var onVote: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True only for a vote cast in THIS session. A poll that arrives already
    /// answered — reopening the app later in the day — shows its results at rest,
    /// with no fill sweep and no haptic. Celebrating a vote you cast hours ago
    /// would be theatre.
    @State private var justVoted = false

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if let fixture = TriviaDebugFixtures.question() {
            TriviaCard(question: fixture, onAnswer: fixture.hasAnswered ? nil : { _ in })
        } else {
            regularTouch
        }
        #else
        regularTouch
        #endif
    }

    private var regularTouch: some View {
        Group {
            switch touch.kind {
            case .poll:
                pollContent
            case .history:
                historyContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
        .onChange(of: touch.hasVoted) { wasVoted, isVoted in
            guard !wasVoted, isVoted else { return }
            // The tap already fired `.light`. This is the results settling, so it
            // lands after the fill has swept — one beat, not two at once.
            let settle = reduceMotion ? 0 : Self.fillDuration
            Task {
                try? await Task.sleep(for: .seconds(settle))
                Haptics.success()
            }
        }
    }

    /// The bar sweep, and therefore when the results are "settled".
    static let fillDuration: TimeInterval = 0.30

    private var pollContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(touch.prompt)
                .font(.displaySemi(21))
                .foregroundStyle(Hue.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                ForEach(Array(touch.choices.enumerated()), id: \.offset) { index, option in
                    pollRow(option: option, at: index)
                }
            }
        }
    }

    @ViewBuilder
    private func pollRow(option: String, at index: Int) -> some View {
        if touch.hasVoted {
            BriefingPollResultRow(
                option: option,
                share: touch.share(at: index),
                count: touch.count(at: index),
                isMyChoice: touch.myVote == index,
                animatesIn: justVoted && !reduceMotion
            )
        } else if let onVote {
            Button {
                Haptics.light()
                // Set HERE, not from the parent's `.onChange(of: touch.hasVoted)`.
                // That fires in the same update pass that inserts the result row,
                // and SwiftUI guarantees no ordering between a parent onChange and
                // a new child's onAppear — so the sweep could silently not play.
                justVoted = true
                onVote(index)
            } label: {
                unvotedRow(option)
            }
            .buttonStyle(BriefingPollOptionStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Vote for \(option)")
        } else {
            unvotedRow(option)
        }
    }

    private func unvotedRow(_ option: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Hue.ink)
                .accessibilityHidden(true)

            Text(option)
                .font(.sansMedium(15))
                .foregroundStyle(Hue.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 14)
        .background(Hue.fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(touch.prompt)
                .font(.displaySemi(21))
                .foregroundStyle(Hue.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let body = touch.body, !body.isEmpty {
                Text(body)
                    .font(.sans(16))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineSpacing(5)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BriefingPollResultRow: View {
    let option: String
    let share: Double
    let count: Int
    let isMyChoice: Bool
    /// Sweeps the bar and counts the number up. False when the poll was already
    /// answered on arrival, or under Reduce Motion.
    var animatesIn: Bool = false

    /// Drives BOTH the bar width and the percentage, so the number counts up in
    /// lockstep with the fill instead of racing it.
    /// Starts SETTLED. Visibility is never gated on an animation, so a render
    /// path that does not run `onAppear` — ImageRenderer, which ShareCenter uses,
    /// and the first frame generally — still shows the real bar and the real
    /// number rather than an empty bar reading 0%.
    @State private var progress: Double = 1
    @State private var pop: CGFloat = 1

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Hue.fill)

            GeometryReader { proxy in
                Rectangle()
                    .fill(Hue.ink.opacity(0.12))
                    .frame(width: proxy.size.width * CGFloat(clampedShare * progress))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .accessibilityHidden(true)

            HStack(spacing: 12) {
                Image(systemName: isMyChoice ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .accessibilityHidden(true)

                Text(option)
                    .font(isMyChoice ? .sansSemibold(15) : .sansMedium(15))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(percentage)%")
                        .font(.monoMedium(13))
                        .monospacedDigit()
                    Text(voteCountLabel)
                        .font(.mono(11))
                        .monospacedDigit()
                }
                .foregroundStyle(Hue.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .scaleEffect(pop)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isMyChoice ? .isSelected : [])
        .onAppear {
            guard animatesIn else { return }
            // Rewind only when the sweep is actually going to play.
            progress = 0
            withAnimation(.easeOut(duration: DailyTouchCard.fillDuration)) { progress = 1 }
            guard isMyChoice else { return }
            // Only the row you picked acknowledges the tap.
            withAnimation(Motion.select) { pop = 1.02 }
            Task {
                try? await Task.sleep(for: .seconds(0.18))
                withAnimation(Motion.select) { pop = 1 }
            }
        }
    }

    private nonisolated var clampedShare: Double {
        min(max(share, 0), 1)
    }

    /// Counts up with the bar: derived from the animated progress, not the final
    /// share, so the number and the fill arrive together.
    private var percentage: Int {
        Int((clampedShare * progress * 100).rounded())
    }

    private nonisolated var voteCountLabel: String {
        "\(count) \(count == 1 ? "vote" : "votes")"
    }

    /// The settled figure, never the counting-up one — VoiceOver must not announce
    /// a mid-animation value.
    private nonisolated var finalPercentage: Int {
        Int((clampedShare * 100).rounded())
    }

    private nonisolated var accessibilityLabel: String {
        let selection = isMyChoice ? ", your choice" : ""
        return "\(option), \(finalPercentage) percent, \(voteCountLabel)\(selection)"
    }
}

private struct BriefingPollOptionStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.76 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.tilePress,
                value: configuration.isPressed
            )
    }
}
