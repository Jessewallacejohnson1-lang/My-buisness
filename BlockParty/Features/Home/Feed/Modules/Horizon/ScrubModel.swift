//
//  ScrubModel.swift
//  BlockParty
//
//  The pure state machine behind scrubbing the "Your day" strip: drag →
//  time mapping (drag left = later, 1:1 through the tape's density), the
//  00:00–24:00 day bounds with 0.35 rubber-band resistance, the ±8 minute
//  event magnet, and where the strip settles when the finger lifts. The
//  view layer only applies what this decides — every number here is
//  assertable in a unit test (ScrubModelTests).
//

import CoreGraphics
import Foundation

/// Which gesture owns the live drag. The pickup sequence (long-press →
/// drag) and the resume drag (immediate, while scrub mode persists after
/// a finger lift) both track the same touches — ownership is what keeps
/// them from double-driving one finger. See HorizonCard's gesture note.
nonisolated enum ScrubDragOwner: Equatable {
    case pickup, resume
}

/// One live scrub, owned as `@State` by YourDayHorizonSection. Nil at
/// rest.
nonisolated struct ScrubSession: Equatable {
    /// The strip time under the centered marker — THE scalar (spec law).
    var scrubTime: Date
    /// scrubTime at the moment the current drag claimed the session.
    var dragBase: Date?
    var dragOwner: ScrubDragOwner?
    /// The rigid day-bound thud fires once per contact with a bound.
    var hasThuddedThisContact = false
    /// True through the exit rewind: the lift/scrim/pill have settled but
    /// scrubTime is still animating home, and it must keep driving the
    /// sky (the time-lapse) with the minute-drift ease still suppressed.
    var isEnding = false
}

nonisolated struct ScrubModel: Equatable {
    /// Spec: rubber-band beyond the day with 0.35 resistance.
    static let rubberBandResistance = 0.35
    /// Spec: magnetic stubs capture within ±8 minutes on release.
    static let magnetWindow: TimeInterval = 8 * 60

    let dayStart: Date
    let dayEnd: Date
    let pointsPerHour: CGFloat

    init(now: Date, pointsPerHour: CGFloat) {
        let interval = YourDayLogic.todayInterval(now: now)
        self.dayStart = interval.start
        self.dayEnd = interval.end
        self.pointsPerHour = pointsPerHour
    }

    /// Drag left = later: the finger drags the STRIP, so the time under
    /// the marker moves opposite the translation, 1:1 with no inertia.
    func rawTime(from base: Date, dragTranslation dx: CGFloat) -> Date {
        guard pointsPerHour > 0 else { return base }
        return base.addingTimeInterval(TimeInterval(-dx / pointsPerHour) * 3600)
    }

    func isBeyondBounds(_ raw: Date) -> Bool {
        raw < dayStart || raw > dayEnd
    }

    /// What the strip shows for a raw drag time: itself inside the day,
    /// 0.35-resisted overshoot beyond either midnight.
    func displayTime(forRaw raw: Date) -> Date {
        if raw < dayStart {
            return dayStart.addingTimeInterval(
                raw.timeIntervalSince(dayStart) * Self.rubberBandResistance)
        }
        if raw > dayEnd {
            return dayEnd.addingTimeInterval(
                raw.timeIntervalSince(dayEnd) * Self.rubberBandResistance)
        }
        return raw
    }

    /// The exact event time within ±8 minutes, nearest first — the
    /// magnetic stubs.
    static func magnetTarget(near time: Date, eventTimes: [Date]) -> Date? {
        eventTimes
            .min { abs($0.timeIntervalSince(time)) < abs($1.timeIntervalSince(time)) }
            .flatMap { abs($0.timeIntervalSince(time)) <= magnetWindow ? $0 : nil }
    }

    /// Where the strip settles on finger lift: a magnet event, else back
    /// inside the day when released overscrolled, else nil — stay put
    /// (scrub mode persists until the tap off the card).
    func releaseTarget(for time: Date, eventTimes: [Date]) -> Date? {
        if let magnet = Self.magnetTarget(near: time, eventTimes: eventTimes) {
            return magnet
        }
        let clamped = min(max(time, dayStart), dayEnd)
        return clamped == time ? nil : clamped
    }
}
