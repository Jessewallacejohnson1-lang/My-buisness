//
//  BPStatementScreen.swift
//  S13 (and reusable) — a bubble that states something, with no question under it.
//
//  Same top-left mark + bubble arrangement as a question screen, but the answer area is
//  empty and Continue is always live. Built on `BPQuestionScaffold` rather than as its
//  own layout so the bar, mark and bubble land in exactly the same place they do on the
//  questions either side of it — a few points of drift between adjacent screens is very
//  visible when you page through the flow.
//

import SwiftUI

struct BPStatementScreen: View {
    let line: AttributedString
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void
    var buttonTitle: String = "Continue"

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: line,
            buttonTitle: buttonTitle,
            canContinue: true,
            onBack: onBack,
            onContinue: onContinue
        ) {
            EmptyView()
        }
    }
}

/// S13's copy, with the highlighted span in the primary colour.
///
/// ⚠️ VERIFIED FALSE — DO NOT SHIP AS-IS (checked against the live project 2026-07-25).
///
/// The spec's `TODO(Jesse)` asked whether "30+" holds. It does not:
///   • approved events WITH a date:  9, across 2 months  → 4.5 / month
///   • approved events total:        14
///   • upcoming (today onward):      3
///   • clubs: 0 · places: 91 (venues) · board_items: 62 (bulletin, not happenings)
///
/// "30+ a month" overstates reality by ~7x, which collides head-on with the repo rule
/// "Real data only — never seeded or inflated counts" — the same rule that sent S07 to
/// its fallback line.
///
/// Left unchanged because this is user-facing brand voice and §4 says copy is verbatim;
/// the number is Jesse's to pick. Recommended replacement drops the count entirely and
/// keeps the emphasis mechanic:
///     "That's **every St. Joe happening** — all in one place."
enum BPHappenings {
    /// Not supported by real data — see the warning above before shipping.
    static let claim = 30

    static var line: AttributedString {
        BPCopy.emphasised("That's ",
                          "\(claim)+ St. Joe happenings",
                          " a month — all in one place.",
                          tint: BP.orange)
    }
}
