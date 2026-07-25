//
//  BPFinaleScreen.swift
//  S20 — the finale.
//
//  The line is keyed to S08's `town_level`, so the last thing the flow says reflects the
//  answer the user gave eight screens earlier. That callback is the point of the screen —
//  getting the mapping wrong is a silent failure that still looks fine.
//
//  NO CONFETTI. The spec caps the celebration at "mark + a subtle bpOrange/bpTeal confetti
//  burst" and says explicitly: *propose at the gate before adding*. That proposal hasn't
//  happened, so this ships as mark + line only. Adding the burst later is additive.
//

import SwiftUI

struct BPFinaleScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 0) {
                BPBubble(content: BPCopy.plain(Self.line(forLevel: answers.townLevel)),
                         tail: .bottom(0.5))
                BPMark(side: BPLayout.talkingMarkSide)
                    .padding(.top, BPLayout.talkingBubbleGap)
            }
            .padding(.horizontal, BP.Metric.pageMargin)

            Spacer()

            BPButton(title: "Join the party", action: onFinish)
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.bottom, BPLayout.buttonBottomGap)
        }
        .background(BP.paper.ignoresSafeArea())
    }

    /// Level 1 → new in town · 2–4 → neutral · 5 → mayor.
    ///
    /// A nil level (only reachable if S08 were somehow skipped) falls to the neutral
    /// line rather than crashing or greeting a stranger as the mayor.
    static func line(forLevel level: Int?) -> String {
        switch level {
        case 1:  return "New in town? Perfect. We'll show you around."
        case 5:  return "Alright, mayor — your town's waiting."
        default: return "St. Joe's waiting — let's go."
        }
    }
}
