//
//  Haptics.swift
//  Hygge — tiny wrapper over UIFeedbackGenerator (the expo-haptics analogue).
//
//  House rule mirrors motion: feedback confirms a real interaction, never decorates.
//

import UIKit

enum Haptics {
    /// A light tap — for selecting a pin / small confirmations.
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }

    /// A crisp selection tick — for moving between tabs / segmented choices.
    static func selection() {
        let g = UISelectionFeedbackGenerator()
        g.selectionChanged()
    }

    /// A success notification — for a completed post.
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }

    /// A gentle error notification — for an action that couldn't complete.
    static func error() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.error)
    }
}
