//
//  BPQuestionScaffold.swift
//  Block Party — the shared skeleton behind every question screen.
//
//  S05/S06, S08, S09/S10, S12, S17/S18 and S19 are all the same layout: top bar, a
//  small mark with a bubble beside it, a scrollable answer area, and a bottom-pinned
//  primary button that starts disabled. Building that once means the bubble and bar can
//  never drift a few points between screens — which is exactly the kind of difference
//  the reference-frame diff would catch late and expensively.
//
//  The answer area SCROLLS (S09 has seven rows), and the button block is pinned outside
//  the scroll view so it never travels. Rows use `BPRow`, whose press feedback rides
//  `ButtonStyle.isPressed` precisely so it composes with this scroll view rather than
//  fighting it.
//

import SwiftUI

struct BPQuestionScaffold<Answers: View>: View {
    let step: BPStep
    /// The bubble's line. Swap it to make the mascot "react" (S10, S18, S20).
    let prompt: AttributedString
    /// Bottom button title — "Continue" everywhere except S12's "I'm in".
    var buttonTitle: String = "Continue"
    /// Disabled until the question is answered, exactly as the reference does.
    let canContinue: Bool
    let onBack: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let answers: () -> Answers

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
                .padding(.top, 8)

            // Measured off S05: mascot x 28.3–110pt, bubble x 123.3–345pt. So the mark
            // sits in from the page margin, the gap is ~13pt, and the bubble is
            // content-sized rather than running to the right margin.
            HStack(alignment: .top, spacing: BPLayout.markBubbleGap) {
                BPMark(side: BPLayout.questionMarkSide)
                BPBubble(content: prompt, tail: .leading(0.43))
                Spacer(minLength: 0)
            }
            .padding(.leading, BPLayout.markLeadingInset)
            .padding(.trailing, BP.Metric.pageMargin)
            .padding(.top, BPLayout.bubbleTopGap)

            ScrollView {
                VStack(spacing: BP.Metric.rowGap) {
                    answers()
                }
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.top, BPLayout.answersTopGap)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            BPButton(title: buttonTitle, enabled: canContinue, action: onContinue)
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.bottom, BPLayout.buttonBottomGap)
                .padding(.top, 8)
        }
        .background(BP.paper.ignoresSafeArea())
    }
}

/// Screen-level spacing shared across the flow.
///
/// Split out from `BP.Metric` (which holds *component* internals) so a screen-layout
/// tweak never risks disturbing a component whose geometry is already verified 1:1.
enum BPLayout {
    /// The small mark beside a question's bubble. The reference mascot measures
    /// 81.7 x 101.7pt there; ours is square, so a 74pt side carries similar mass
    /// without towering over the bubble.
    static let questionMarkSide: CGFloat = 74
    /// The mark on the talking screens, where it sits under a centred bubble.
    /// Reference mascot is ~110pt wide on S03.
    static let talkingMarkSide: CGFloat = 100
    /// Mark's inset from the screen edge on a question screen (measured 28.3pt, less a
    /// little because the reference figure carries a soft shadow we don't have).
    static let markLeadingInset: CGFloat = 24
    /// Mark → bubble. Measured 13.3pt on S05.
    static let markBubbleGap: CGFloat = 13
    /// Top bar → bubble. Lands the bubble's top edge near the measured 141.7pt.
    static let bubbleTopGap: CGFloat = 30
    /// Bubble → first answer row.
    static let answersTopGap: CGFloat = 26
    /// Bottom button → the bottom safe-area edge.
    static let buttonBottomGap: CGFloat = 12
    /// Talking screens: bubble's bottom border → mark's top. Measured ~20pt on S03.
    static let talkingBubbleGap: CGFloat = 20
}
