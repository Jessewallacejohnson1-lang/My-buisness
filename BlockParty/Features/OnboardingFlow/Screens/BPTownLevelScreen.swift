//
//  BPTownLevelScreen.swift
//  S08 — question 2, single-select on an ascending 1→5 scale.
//
//  Persists `profile.town_level` (1…5), which later drives S20's closing line and the
//  feed defaults (1–2 discovery-heavy, 4–5 posting nudges).
//
//  The chips hold `BPLevelBars` rather than a lucide glyph: this is a SCALE, so the
//  filled-bar count is the meaning. No icon set ships five graded variants of one glyph,
//  and drawing it keeps the ramp exact.
//
//  The level is stored as the Int, not the row index, so the two can never drift apart.
//

import SwiftUI

struct BPTownLevelScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    static let options: [(level: Int, label: String)] = [
        (1, "Just moved here"),
        (2, "I know a few spots"),
        (3, "I know my way around"),
        (4, "Pretty plugged in"),
        (5, "I'm basically the mayor"),
    ]

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: BPCopy.plain("How well do you know St. Joe?"),
            canContinue: answers.townLevel != nil,
            onBack: onBack,
            onContinue: onContinue
        ) {
            ForEach(Self.options, id: \.level) { opt in
                BPRow(label: opt.label,
                      icon: .level(opt.level),
                      selected: answers.townLevel == opt.level) {
                    answers.townLevel = opt.level
                }
            }
        }
    }
}
