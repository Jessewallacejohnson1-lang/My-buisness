//
//  ComposeFAB.swift
//  Hygge — the shared floating "+" composer for tabs without a masthead
//  (Explore, Calendar). CLAUDE.md's pitch is "a shared calendar anyone can add
//  to" — so every list/calendar surface needs a reachable way to post, not just
//  Home and Map. Coral disc, bottom-right, cleared above the floating tab bar.
//  Renders nothing when no compose action is wired.
//

import SwiftUI

struct ComposeFAB: View {
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button {
                Haptics.light()
                action()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Hue.accent, in: Circle())
                    .shadow(color: Hue.accent.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 96)   // clear the floating tab bar
            .accessibilityLabel("Add to the town")
        }
    }
}
