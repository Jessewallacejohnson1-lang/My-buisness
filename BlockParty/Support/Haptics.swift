//
//  Haptics.swift
//  Block Party — tiny wrapper over UIFeedbackGenerator (the expo-haptics analogue).
//
//  House rule mirrors motion: feedback confirms a real interaction, never decorates.
//
//  Premium-feel spec §10: generators are instantiated ONCE and held (a fresh
//  generator per call means a cold Taptic engine and a missed/late tap), `prepare()`
//  keeps the engine warm for the next fire, and everything is a silent no-op under
//  Low Power Mode. The four entry points (light / selection / success / error) are
//  unchanged, so the ~40 existing call sites don't move; only the engine underneath
//  them changed. (The module runs under MainActor default isolation, so the held,
//  non-Sendable generators are main-actor state — all call sites are already on main.)
//

import UIKit

enum Haptics {
    // Held once — not re-allocated per call. A warm generator fires with no latency.
    private static let impact    = UIImpactFeedbackGenerator(style: .light)
    private static let selector  = UISelectionFeedbackGenerator()
    private static let notifier  = UINotificationFeedbackGenerator()

    /// Skip all feedback in Low Power Mode (spec §10) — silent, never a partial buzz.
    private static var enabled: Bool { !ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// Warm the Taptic engine just before a likely interaction (touch-down / onAppear),
    /// so the first real fire has zero latency.
    static func prepare() {
        guard enabled else { return }
        impact.prepare(); selector.prepare(); notifier.prepare()
    }

    /// A light tap — selecting a pin / small confirmations.
    static func light() {
        guard enabled else { return }
        impact.impactOccurred()
        impact.prepare()          // keep warm for the next tap
    }

    /// A crisp selection tick — moving between segmented choices / sheet detents / filters.
    static func selection() {
        guard enabled else { return }
        selector.selectionChanged()
        selector.prepare()
    }

    /// A success notification — a completed post / a place saved.
    static func success() {
        guard enabled else { return }
        notifier.notificationOccurred(.success)
        notifier.prepare()
    }

    /// A gentle error notification — an action that couldn't complete.
    static func error() {
        guard enabled else { return }
        notifier.notificationOccurred(.error)
        notifier.prepare()
    }
}
