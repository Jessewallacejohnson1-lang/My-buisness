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
/// `TODO(Jesse)`: verify "30+" against the seeded content before ship. The repo's
/// standing rule is real data only — never inflated counts — so if the seed does not
/// actually support 30 a month, this number has to come down or become a live count.
enum BPHappenings {
    static let claim = 30

    static var line: AttributedString {
        BPCopy.emphasised("That's ",
                          "\(claim)+ St. Joe happenings",
                          " a month — all in one place.",
                          tint: BP.orange)
    }
}
