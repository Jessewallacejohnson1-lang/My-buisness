//
//  ScrubHapticsTests.swift
//  BlockPartyTests
//
//  The crossing detector (arrival counts, departure doesn't, event
//  outranks sun outranks hour) and the pure 60 ms budget — including the
//  synthetic-fling guarantee that no two admitted fires ever sit closer
//  than the floor, and that the sunrise/sunset double-soft's +60 ms
//  second tap passes it exactly.
//

import XCTest
@testable import BlockParty

final class ScrubHapticsTests: XCTestCase {
    private let sunrise = townDate(2026, 8, 11, 6, 13)
    private let sunset = townDate(2026, 8, 11, 21, 2)

    private func detect(from: Date, to: Date, events: [Date] = []) -> ScrubCrossing? {
        ScrubCrossingDetector.detect(
            from: from, to: to, events: events, sunrise: sunrise, sunset: sunset)
    }

    // MARK: Crossing detection

    func testHourBoundaryDetectsInBothDirections() {
        let before = townDate(2026, 8, 11, 14, 58)
        let after = townDate(2026, 8, 11, 15, 2)
        XCTAssertEqual(detect(from: before, to: after), .hour)
        XCTAssertEqual(detect(from: after, to: before), .hour)
        // No boundary inside the span → silence.
        XCTAssertNil(
            detect(from: townDate(2026, 8, 11, 14, 10), to: townDate(2026, 8, 11, 14, 50)))
        XCTAssertNil(detect(from: before, to: before))
    }

    func testArrivalOnAnEventCountsDepartureDoesNot() {
        let event = townDate(2026, 8, 11, 15, 30)
        // Landing exactly on it (the magnet's ease does this) ticks…
        XCTAssertEqual(
            detect(from: townDate(2026, 8, 11, 15, 25), to: event, events: [event]),
            .event)
        // …passing over it ticks…
        XCTAssertEqual(
            detect(
                from: townDate(2026, 8, 11, 15, 25),
                to: townDate(2026, 8, 11, 15, 35), events: [event]),
            .event)
        // …but dragging OFF it must not re-tick.
        XCTAssertNil(
            detect(from: event, to: townDate(2026, 8, 11, 15, 30, 30), events: [event]))
    }

    func testEventOutranksSunOutranksHour() {
        // One fast frame across 21:00 (hour), 21:02 (sunset) and an event:
        // the event's voice wins (the 60 ms floor silences the rest).
        let event = townDate(2026, 8, 11, 21, 5)
        let from = townDate(2026, 8, 11, 20, 55)
        let to = townDate(2026, 8, 11, 21, 10)
        XCTAssertEqual(detect(from: from, to: to, events: [event]), .event)
        // Without the event, the sun dot outranks the hour line.
        XCTAssertEqual(detect(from: from, to: to), .sun)
        // Sunrise is a sun crossing too.
        XCTAssertEqual(
            detect(from: townDate(2026, 8, 11, 6, 10), to: townDate(2026, 8, 11, 6, 20)),
            .sun)
    }

    // MARK: The 60 ms budget

    func testBudgetAdmitsExactlyAtTheFloorAndRefusesUnderIt() {
        var budget = HapticBudget(minimumSpacing: 0.06)
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        XCTAssertTrue(budget.admit(at: t0))
        // 59 ms later: refused.
        XCTAssertFalse(budget.admit(at: t0.addingTimeInterval(0.059)))
        // Exactly 60 ms after the ADMITTED fire: passes — this is the
        // sunrise/sunset double-soft's second tap.
        XCTAssertTrue(budget.admit(at: t0.addingTimeInterval(0.06)))
    }

    func testSyntheticFlingNeverFiresTwoWithinTheFloor() {
        // A 120 Hz fling asking on every frame: whatever is asked, no two
        // ADMITTED fires may sit closer than 60 ms.
        var budget = HapticBudget(minimumSpacing: 0.06)
        var admitted: [TimeInterval] = []
        for frame in 0..<240 {
            let t = Date(timeIntervalSinceReferenceDate: Double(frame) * (1.0 / 120.0))
            if budget.admit(at: t) {
                admitted.append(t.timeIntervalSinceReferenceDate)
            }
        }
        XCTAssertGreaterThan(admitted.count, 1, "the fling must still tick sometimes")
        for (a, b) in zip(admitted, admitted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 0.06 - 1e-12, "machine-gun: \(b - a)s apart")
        }
    }
}

private func townDate(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int
) -> Date {
    townDate(year, month, day, hour, minute).addingTimeInterval(Double(second))
}
