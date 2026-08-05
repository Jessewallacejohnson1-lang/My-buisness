//
//  CaughtUpFooter.swift
//  Block Party — the quiet end of a daily briefing.
//

import SwiftUI

struct CaughtUpFooter: View {
    let caughtUp: BriefingCaughtUp
    let briefingDateLabel: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Hue.ink)
                .frame(width: 40, height: 40)
                .background(Hue.fill)
                .clipShape(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(briefingDateLabel)
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .monospacedDigit()

            Text(caughtUp.label)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Caught up. \(briefingDateLabel). \(caughtUp.label)")
    }
}
