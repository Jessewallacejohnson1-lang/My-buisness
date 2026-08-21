//
//  ScrubHaptics.swift
//  BlockParty
//
//  The scrub interaction's Taptic voice: pickup pop, the crossing table
//  (hour ·light 0.55 / event ·medium 0.9 / sunrise·sunset ·soft ×2 60 ms
//  apart at 0.7 / day-bound ·rigid 1.0), and the exit settle. Generators
//  are held once and kept warm (Haptics.swift's house rule), everything
//  is silent in Low Power Mode, and the pure `HapticBudget` enforces the
//  spec's hard 60 ms floor between ANY two fires — a fast fling can never
//  machine-gun. The detector and budget are nonisolated pure so
//  ScrubHapticsTests can fling synthetically.
//

import UIKit

/// One haptic-worthy boundary between two scrub positions, highest
/// priority first: landing on an event outranks the sun dots, which
/// outrank a plain hour line (with the 60 ms floor, only the first fire
/// in a fast frame survives — so the ranking decides which one that is).
nonisolated enum ScrubCrossing: Equatable {
    case event, sun, hour
}

nonisolated enum ScrubCrossingDetector {
    /// The single crossing to voice for a move `from → to`, or nil.
    /// Arriving exactly ON a boundary counts; departing from one does not
    /// (sitting on a magnetized event and dragging away must not re-tick).
    static func detect(
        from: Date,
        to: Date,
        events: [Date],
        sunrise: Date,
        sunset: Date,
        calendar: Calendar = Town.calendar
    ) -> ScrubCrossing? {
        guard from != to else { return nil }
        let lo = min(from, to)
        let hi = max(from, to)
        func crossed(_ boundary: Date) -> Bool {
            (lo < boundary && boundary < hi) || boundary == to
        }
        if events.contains(where: crossed) { return .event }
        if crossed(sunrise) || crossed(sunset) { return .sun }
        let fromHour = calendar.dateInterval(of: .hour, for: from)?.start
        let toHour = calendar.dateInterval(of: .hour, for: to)?.start
        if fromHour != toHour { return .hour }
        return nil
    }
}

/// The spec's spacing budget, pure and clock-injected: at most one fire
/// per `minimumSpacing`, whatever asks.
nonisolated struct HapticBudget {
    let minimumSpacing: TimeInterval
    private(set) var lastFired: Date = .distantPast

    mutating func admit(at now: Date) -> Bool {
        guard now.timeIntervalSince(lastFired) >= minimumSpacing else { return false }
        lastFired = now
        return true
    }
}

@MainActor
enum ScrubHaptics {
    /// Spec budget: minimum spacing between ANY two haptics.
    static let minimumSpacing: TimeInterval = 0.06

    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static var budget = HapticBudget(minimumSpacing: minimumSpacing)

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
        soft.prepare()
    }

    /// Pickup: one medium pop at 0.8.
    static func pickup() { fire(medium, intensity: 0.8) }

    /// Day bound: one rigid thud at 1.0 per rubber-band contact (the
    /// once-per-contact rule lives in ScrubSession.hasThuddedThisContact).
    static func boundThud() { fire(rigid, intensity: 1.0) }

    /// Exit settle: light at 0.4 as the strip glides home.
    static func settle() { fire(light, intensity: 0.4) }

    /// Crossing an hour line: light at 0.55.
    static func hourTick() { fire(light, intensity: 0.55) }

    /// Landing on / passing an event: medium at 0.9.
    static func eventTick() { fire(medium, intensity: 0.9) }

    /// Crossing a sunrise/sunset dot: soft ×2, 60 ms apart, at 0.7. The
    /// second tap rides the budget's own floor — exactly at the limit, so
    /// it lands unless something else fired in between (budget rules all).
    static func sunTick() {
        fire(soft, intensity: 0.7)
        Task {
            try? await Task.sleep(for: .milliseconds(Int(minimumSpacing * 1000)))
            fire(soft, intensity: 0.7)
        }
    }

    /// One voiced crossing, table-routed.
    static func crossing(_ crossing: ScrubCrossing) {
        switch crossing {
        case .event: eventTick()
        case .sun: sunTick()
        case .hour: hourTick()
        }
    }

    private static func fire(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard enabled, budget.admit(at: Date()) else { return }
        generator.impactOccurred(intensity: intensity)
        generator.prepare()  // keep warm for the next fire
    }
}
