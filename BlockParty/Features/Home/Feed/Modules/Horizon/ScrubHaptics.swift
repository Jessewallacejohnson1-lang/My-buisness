//
//  ScrubHaptics.swift
//  BlockParty
//
//  The scrub interaction's Taptic voice, Phase 1: the pickup pop, the
//  rigid day-bound thud, the exit settle. Generators are held once and
//  kept warm (Haptics.swift's house rule), everything is silent in Low
//  Power Mode, and a hard 60 ms floor between any two fires means a fast
//  fling can never machine-gun. The Phase 2 crossing detector
//  (hour/event/sunrise/sunset) lands on top of this file.
//

import UIKit

@MainActor
enum ScrubHaptics {
    /// Spec budget: minimum spacing between ANY two haptics.
    static let minimumSpacing: TimeInterval = 0.06

    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static var lastFired: Date = .distantPast

    private static var enabled: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Warm every generator at touch-down so the pickup pop at +0.25 s
    /// fires with zero latency (spec: prepare() all generators at pickup).
    static func prepareAll() {
        guard enabled else { return }
        medium.prepare()
        rigid.prepare()
        light.prepare()
    }

    /// Pickup: one medium pop at 0.8.
    static func pickup() { fire(medium, intensity: 0.8) }

    /// Day bound: one rigid thud at 1.0 per rubber-band contact (the
    /// once-per-contact rule lives in ScrubSession.hasThuddedThisContact).
    static func boundThud() { fire(rigid, intensity: 1.0) }

    /// Exit settle: light at 0.4 as the strip glides home.
    static func settle() { fire(light, intensity: 0.4) }

    private static func fire(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard enabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFired) >= minimumSpacing else { return }
        lastFired = now
        generator.impactOccurred(intensity: intensity)
        generator.prepare()  // keep warm for the next fire
    }
}
