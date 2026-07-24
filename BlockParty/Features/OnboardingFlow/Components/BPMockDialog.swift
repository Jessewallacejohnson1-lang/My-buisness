//
//  BPMockDialog.swift
//  Block Party — the permission pre-prompt mock.
//
//  Signature mechanic #6. Used on S14 (notifications) and S15 (location).
//
//  A greyed-out, NON-INTERACTIVE mock of the real iOS alert, with a small teal arrow
//  nudging toward Allow. The point of the choreography: the user sees what the system
//  is about to ask *before* it asks, so the real prompt is never a surprise — and the
//  real prompt only fires from the big primary button underneath, never from this.
//
//  It is deliberately inert: `allowsHitTesting(false)` plus a single accessibility
//  element describing it as a preview, so VoiceOver never presents fake buttons.
//
//  Triggering a real UIAlert here would also be actively harmful in this codebase —
//  a modal dialog blocks the automation channel the verification loop screenshots
//  through. This never becomes a real alert.
//

import SwiftUI

struct BPMockDialog: View {
    /// e.g. `"Block Party" Would Like to Send You Notifications`
    let title: String
    let message: String
    /// The right-hand affirmative label the arrow points at — "Allow" or
    /// "Allow While Using App".
    let allowTitle: String
    var denyTitle: String = "Don't Allow"

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.sansSemibold(15))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.sans(12))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(BP.gray)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(BP.hairline)
                .frame(height: 1)

            HStack(spacing: 0) {
                Text(denyTitle)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(BP.hairline)
                    .frame(width: 1, height: 42)
                Text(allowTitle)
                    .frame(maxWidth: .infinity)
            }
            .font(.sans(15))
            .foregroundStyle(BP.gray)
            .frame(height: 42)
        }
        .frame(width: 260)
        .background(BP.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BP.hairline, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            // The nudge — sits under the affirmative button, pointing up at it.
            BPNudgeArrow()
                .frame(width: 22, height: 30)
                .offset(x: -44, y: 42)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the system permission alert: \(title). \(allowTitle) is highlighted.")
    }
}

/// A slim upward arrow in the selection accent.
private struct BPNudgeArrow: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w / 2, y: h))
                p.addLine(to: CGPoint(x: w / 2, y: 0))
            }
            .stroke(BP.teal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            Path { p in
                p.move(to: CGPoint(x: w / 2 - w * 0.34, y: h * 0.34))
                p.addLine(to: CGPoint(x: w / 2, y: 0))
                p.addLine(to: CGPoint(x: w / 2 + w * 0.34, y: h * 0.34))
            }
            .stroke(BP.teal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}
