//
//  BPMotivationsScreen.swift
//  S09 / S10 — question 3, MULTI-select. One screen, two states.
//
//  Seven rows, each with a trailing check badge that springs in. On the FIRST selection
//  the bubble reacts — "That's what we're here for." — and stays reacted while any row
//  is chosen. Deselecting everything returns the original prompt, so the reaction always
//  tells the truth about the current state rather than latching on forever.
//
//  Seven 56pt rows plus 12pt gaps is 464pt of content, which overflows the answer area,
//  so this is the screen that proves the scaffold's ScrollView. `BPRow`'s press feedback
//  rides `ButtonStyle.isPressed` precisely so it composes with that scroll rather than
//  out-competing the pan (the documented feed-scroll bug in this codebase).
//

import SwiftUI

struct BPMotivationsScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    static let options: [(id: String, glyph: BPGlyph, label: String)] = [
        ("find_things",  .partyPopper,  "Find things to do"),
        ("meet_people",  .users,        "Meet new people"),
        ("stay_in_loop", .newspaper,    "Stay in the loop"),
        ("kids",         .baby,         "Get my kids involved"),
        ("settle_in",    .truck,        "Get settled after moving"),
        ("promote",      .megaphone,    "Promote my club or business"),
        ("other",        .ellipsis,     "Other"),
    ]

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: prompt,
            canContinue: !answers.motivations.isEmpty,
            onBack: onBack,
            onContinue: onContinue
        ) {
            ForEach(Self.options, id: \.id) { opt in
                BPRow(label: opt.label,
                      icon: .glyph(opt.glyph),
                      selected: answers.motivations.contains(opt.id),
                      showsCheck: true) {
                    toggle(opt.id)
                }
            }
        }
    }

    private var prompt: AttributedString {
        answers.motivations.isEmpty
            ? BPCopy.plain("What brings you to Block Party?")
            : BPCopy.plain("That's what we're here for.")
    }

    private func toggle(_ id: String) {
        withAnimation(BP.Motion.bubbleSwap) {
            if answers.motivations.contains(id) {
                answers.motivations.remove(id)
            } else {
                answers.motivations.insert(id)
            }
        }
    }
}
