//
//  BPConnectionScreen.swift
//  S05 / S06 — question 1, single-select. One screen, two states.
//
//  The progress bar debuts here. Continue starts disabled and turns orange on the first
//  pick — the S05→S06 difference.
//
//  The header row ("For events, clubs & town news" + chevron) is DECORATIVE ONLY, as the
//  spec says: in the reference it looks like a collapsible section header but does not
//  collapse anything. It is marked `.accessibilityHidden` and carries no tap target, so
//  VoiceOver never offers a control that does nothing.
//
//  Answer identifiers are stable snake_case strings, not row indices — they land in a
//  database column, and reordering the rows later must not silently rewrite what an
//  existing user answered.
//

import SwiftUI

struct BPConnectionScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    /// (id, glyph, label) — id is what persists as `profile.connection`.
    static let options: [(id: String, glyph: BPGlyph, label: String)] = [
        ("live_here",   .house,         "I live here"),
        ("moving_here", .truck,         "I'm moving here"),
        ("student",     .graduationCap, "I'm a student (CSB/SJU)"),
        ("live_nearby", .mapPin,        "I live nearby"),
        ("visiting",    .car,           "Just visiting"),
    ]

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: BPCopy.plain("What's your connection to St. Joe?"),
            canContinue: answers.connection != nil,
            onBack: onBack,
            onContinue: onContinue
        ) {
            header

            ForEach(Self.options, id: \.id) { opt in
                BPRow(label: opt.label,
                      icon: .glyph(opt.glyph),
                      selected: answers.connection == opt.id) {
                    answers.connection = opt.id
                }
            }
        }
    }

    /// Decorative section header — matches the reference's chevron affordance without
    /// pretending to be interactive.
    private var header: some View {
        HStack(spacing: 6) {
            Text("For events, clubs & town news")
                .font(.sansBold(17))
                .foregroundStyle(BP.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BP.gray)
        }
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
}
