//
//  BriefingUnavailableCard.swift
//  Block Party — the briefing could not be reached, and there is nothing cached.
//
//  Only ever shown on a genuinely cold start with no connection. Once a briefing
//  has been downloaded the cached copy renders instead and a failed refresh stays
//  invisible, which is the right trade: a briefing you already have should not
//  disappear because the network did.
//
//  Calm, not alarming — no error code, no red. It says what happened and offers
//  the one useful action.
//

import SwiftUI

struct BriefingUnavailableCard: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's briefing didn't load")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("You're offline, or the town is being quiet. It'll be here when the connection is.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Text("Try again")
                    .font(.sansSemibold(14))
                    .foregroundStyle(Hue.surface)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 20)
                    .background(Hue.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(BriefingRetryPressStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

private struct BriefingRetryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : Motion.tilePress, value: configuration.isPressed)
    }
}
