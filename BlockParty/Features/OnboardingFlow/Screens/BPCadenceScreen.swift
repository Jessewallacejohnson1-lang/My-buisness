//
//  BPCadenceScreen.swift
//  S12 — question 4, single-select. Bold left label, grey right label.
//
//  Two things make this screen different from the other questions:
//   • "A few times a week" is PRE-SELECTED, so Continue is live on arrival.
//   • The button reads "I'm in", not "Continue".
//
//  The rows carry no icon chip — matching the reference, where this is the one question
//  whose rows are label-only. The right-hand words (Casual / Regular / Serious / Intense)
//  are verbatim from the spec.
//
//  This answer sets the REAL notification default, so the id strings are what
//  `notify_cadence` stores; the right-hand label is presentation only.
//

import SwiftUI

struct BPCadenceScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    static let options: [(id: String, label: String, intensity: String)] = [
        ("weekly", "Weekly roundup",        "Casual"),
        ("few",    "A few times a week",    "Regular"),
        ("daily",  "Daily digest",          "Serious"),
        ("instant", "The second it happens", "Intense"),
    ]

    /// The reference arrives with the second option already chosen.
    static let defaultID = "few"

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: BPCopy.plain("How often should we keep you posted?"),
            buttonTitle: "I'm in",
            canContinue: answers.notifyCadence != nil,
            onBack: onBack,
            onContinue: onContinue
        ) {
            ForEach(Self.options, id: \.id) { opt in
                BPRow(label: opt.label,
                      trailingLabel: opt.intensity,
                      selected: answers.notifyCadence == opt.id) {
                    answers.notifyCadence = opt.id
                }
            }
        }
        .onAppear {
            // Pre-select on first arrival only — never overwrite a real choice the user
            // made and then navigated back to.
            if answers.notifyCadence == nil { answers.notifyCadence = Self.defaultID }
        }
    }
}
