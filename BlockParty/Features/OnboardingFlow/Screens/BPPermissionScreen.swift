//
//  BPPermissionScreen.swift
//  S14 (notifications) and S15 (location) — the permission pre-prompt choreography.
//
//  The whole point of the pattern: the user sees a GREYED MOCK of the system alert, with
//  an arrow pointing at the affirmative button, BEFORE anything real happens. Then the
//  big primary button fires the real request, so the system sheet is never a surprise and
//  the user has already been told which button to press.
//
//  Rules this screen holds to:
//   • The mock is inert — `allowsHitTesting(false)`, one accessibility element describing
//     it as a preview. It must never become a real alert: a modal dialog blocks the
//     automation channel the verification loop screenshots through.
//   • The flow ADVANCES REGARDLESS of what the user picks in the system sheet. A denied
//     permission is a valid answer, not a dead end, and must never re-block the flow.
//   • The request fires at most once per screen. Tapping the primary twice (a fast double
//     tap, or a tap while the system sheet is animating in) must not queue two requests.
//

import SwiftUI

struct BPPermissionScreen: View {
    let step: BPStep
    let prompt: AttributedString
    let dialogTitle: String
    let dialogMessage: String
    let dialogAllow: String
    let primaryTitle: String
    /// S15 offers a quiet "Not now"; S14 has no opt-out button (the system sheet is the
    /// only place to decline), matching the reference.
    var quietTitle: String?
    /// Fires the real system request. Returns when the user has answered.
    let request: () async -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: BPLayout.markBubbleGap) {
                BPMark(side: BPLayout.questionMarkSide)
                BPBubble(content: prompt, tail: .leading(0.43))
                Spacer(minLength: 0)
            }
            .padding(.leading, BPLayout.markLeadingInset)
            .padding(.trailing, BP.Metric.pageMargin)
            .padding(.top, BPLayout.bubbleTopGap)

            Spacer()

            BPMockDialog(title: dialogTitle,
                         message: dialogMessage,
                         allowTitle: dialogAllow)
                // Room below the card for the nudge arrow, which overhangs its frame.
                .padding(.bottom, 48)

            Spacer()

            VStack(spacing: 4) {
                BPButton(title: primaryTitle, enabled: !isRequesting) {
                    Task { await fire() }
                }
                if let quietTitle {
                    BPButton(title: quietTitle, variant: .quiet) { onContinue() }
                }
            }
            .padding(.horizontal, BP.Metric.pageMargin)
            .padding(.bottom, BPLayout.buttonBottomGap)
        }
        .background(BP.paper.ignoresSafeArea())
    }

    private func fire() async {
        guard !isRequesting else { return }
        isRequesting = true
        await request()
        // Advance whatever the answer was — see the file header.
        isRequesting = false
        onContinue()
    }
}
