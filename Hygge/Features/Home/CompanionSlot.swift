//
//  CompanionSlot.swift
//  Hygge — reserved hook for a future companion character.
//
//  The Today-tab remake deliberately ships with NO mascot/companion illustration
//  (the user dislikes the current AI-artwork style — see the design spec §3 /
//  the plan's "No mascot ships" global constraint). This view exists purely so a
//  future illustrated character can drop into AlmanacHeader (or elsewhere)
//  without re-plumbing the call site: swap the body for real content later, no
//  signature change needed. Renders nothing today.
//

import SwiftUI

struct CompanionSlot: View {
    var body: some View {
        EmptyView()
    }
}
