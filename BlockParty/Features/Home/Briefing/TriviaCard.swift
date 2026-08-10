//
//  TriviaCard.swift
//  Block Party — immediate, monochrome reveal for today's St. Joe question.
//

import SwiftUI

struct TriviaCard: View {
    let question: TriviaQuestion
    var onAnswer: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(kicker)
                    .font(.monoMedium(10))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Hue.inkSecondary)

                Text(question.prompt)
                    .font(.displaySemi(21))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(option, at: index)
                }
            }

            if let reveal = TriviaReveal.make(for: question) {
                revealSummary(reveal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
    }

    private var kicker: String {
        question.id.hasPrefix("debug-")
            ? "Debug fixture · St. Joe trivia"
            : "St. Joe trivia"
    }

    @ViewBuilder
    private func optionRow(_ option: String, at index: Int) -> some View {
        let visualState = TriviaAnswerVisualState.resolve(
            optionIndex: index,
            question: question
        )

        if !question.hasAnswered, let onAnswer {
            Button {
                Haptics.light()
                onAnswer(index)
            } label: {
                TriviaAnswerRow(option: option, visualState: visualState)
            }
            .buttonStyle(FeedCardPressStyle())
            .accessibilityLabel("Answer \(option)")
        } else {
            TriviaAnswerRow(option: option, visualState: visualState)
        }
    }

    /// The reveal is immediate and calm — no animation, no transition. It is not
    /// one of the two moments in this app allowed to perform.
    private func revealSummary(_ reveal: TriviaReveal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(reveal.answerLine)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let townLine = reveal.townLine {
                Text(townLine)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let streakLine = reveal.streakLine {
                Text(streakLine)
                    .font(.mono(11))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TriviaAnswerRow: View {
    let option: String
    let visualState: TriviaAnswerVisualState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: visualState.symbolName)
                .font(.system(size: 17, weight: symbolWeight))
                .foregroundStyle(foregroundColor)
                .accessibilityHidden(true)

            Text(option)
                .font(textFont)
                .foregroundStyle(foregroundColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 14)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundColor: Color {
        switch visualState.foregroundRole {
        case .ink: Hue.ink
        case .inkSecondary: Hue.inkSecondary
        }
    }

    private var backgroundColor: Color {
        switch visualState {
        case .selectedCorrect, .correctAnswer: Hue.surface
        case .unanswered, .selectedIncorrect, .notSelected: Hue.fill
        }
    }

    private var borderColor: Color {
        switch visualState {
        case .selectedCorrect, .selectedIncorrect, .correctAnswer: Hue.ink
        case .unanswered, .notSelected: Hue.hairline
        }
    }

    private var borderWidth: CGFloat {
        switch visualState {
        case .selectedCorrect, .selectedIncorrect, .correctAnswer: 2
        case .unanswered, .notSelected: 1
        }
    }

    private var symbolWeight: Font.Weight {
        switch visualState {
        case .selectedCorrect, .selectedIncorrect, .correctAnswer: .bold
        case .unanswered, .notSelected: .medium
        }
    }

    private var textFont: Font {
        switch visualState {
        case .selectedCorrect, .selectedIncorrect, .correctAnswer: .sansSemibold(15)
        case .unanswered, .notSelected: .sansMedium(15)
        }
    }

    private var isSelected: Bool {
        visualState == .selectedCorrect || visualState == .selectedIncorrect
    }

    private var accessibilityLabel: String {
        switch visualState {
        case .unanswered:
            option
        case .selectedCorrect:
            "\(option), correct answer, your answer"
        case .selectedIncorrect:
            "\(option), incorrect, your answer"
        case .correctAnswer:
            "\(option), correct answer"
        case .notSelected:
            option
        }
    }
}
