//
//  BPTalkingScreen.swift
//  S03, S04 (and later S11) — the talking screens.
//
//  Back arrow, NO progress bar (it debuts on S05). The bubble sits at the top with its
//  tail pointing DOWN at the mark below it — the opposite arrangement to the question
//  screens, where the mark is beside the bubble.
//
//  The bubble types on. `.id(line)` inside `BPBubble` restarts the type-on when the line
//  changes, so re-entering the step from a back-navigation retypes rather than showing a
//  finished line — matching the reference, where every arrival types.
//

import SwiftUI

struct BPTalkingScreen: View {
    let line: AttributedString
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
                .padding(.top, 8)

            Spacer()

            // Measured off S03: the bubble is content-sized (180.7 x 54pt), CENTRED on
            // the screen, with its tail at its own centre pointing down at the mark
            // below. Both are centred, so the tail lands on the mark.
            VStack(spacing: 0) {
                BPBubble(content: line, tail: .bottom(0.5))

                BPMark(side: BPLayout.talkingMarkSide)
                    .padding(.top, BPLayout.talkingBubbleGap)
            }
            .padding(.horizontal, BP.Metric.pageMargin)

            Spacer()

            BPButton(title: "Continue", action: onContinue)
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.bottom, BPLayout.buttonBottomGap)
        }
        .background(BP.paper.ignoresSafeArea())
    }
}
