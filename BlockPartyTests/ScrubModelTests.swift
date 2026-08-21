//
//  ScrubModelTests.swift
//  BlockPartyTests
//
//  The scrub state machine's pure math: drag → time (drag left = later,
//  1:1 through the tape's density), the 0.35 rubber band past either
//  midnight, the once-per-contact bound flag's trigger, the ±8 minute
//  event magnet, and the release-target rules.
//

import XCTest
@testable import BlockParty

final class ScrubModelTests: XCTestCase {
    // 360 pt card / 12 visible hours = 30 pt per hour.
    private let pph: CGFloat = 30
    private let noon = townDate(2026, 8, 11, 12, 0)

    private func model() -> ScrubModel {
        ScrubModel(now: noon, pointsPerHour: pph)
    }

    // MARK: Bounds come from the town day

    func testBoundsAreTheTownDay() {
        let m = model()
        XCTAssertEqual(m.dayStart, townDate(2026, 8, 11, 0, 0))
        XCTAssertEqual(m.dayEnd, townDate(2026, 8, 12, 0, 0))
    }

    // MARK: Drag → time

    func testDragLeftMovesTimeLater() {
        XCTAssertEqual(
            model().rawTime(from: noon, dragTranslation: -30),
            townDate(2026, 8, 11, 13, 0))
    }

    func testDragRightMovesTimeEarlier() {
        XCTAssertEqual(
            model().rawTime(from: noon, dragTranslation: 60),
            townDate(2026, 8, 11, 10, 0))
    }

    func testDragMapsOneToOneThroughPointsPerHour() {
        // Half a point is a minute at this density — real precision.
        XCTAssertEqual(
            model().rawTime(from: noon, dragTranslation: -0.5).timeIntervalSince(noon),
            60, accuracy: 0.001)
    }

    func testZeroPointsPerHourGoesNowhere() {
        // The card before first layout: width 0 must not divide by zero.
        let dead = ScrubModel(now: noon, pointsPerHour: 0)
        XCTAssertEqual(dead.rawTime(from: noon, dragTranslation: -100), noon)
    }

    // MARK: Bounds + rubber band

    func testInsideBoundsDisplayIsIdentity() {
        let m = model()
        let t = townDate(2026, 8, 11, 18, 30)
        XCTAssertFalse(m.isBeyondBounds(t))
        XCTAssertEqual(m.displayTime(forRaw: t), t)
    }

    func testRubberBandResistsBeyondBothBounds() {
        let m = model()
        // One raw hour past the day's end shows as 21 resisted minutes.
        let past = townDate(2026, 8, 12, 1, 0)
        XCTAssertTrue(m.isBeyondBounds(past))
        XCTAssertEqual(
            m.displayTime(forRaw: past),
            m.dayEnd.addingTimeInterval(3600 * 0.35))
        // Symmetric before it starts.
        let before = townDate(2026, 8, 10, 23, 0)
        XCTAssertTrue(m.isBeyondBounds(before))
        XCTAssertEqual(
            m.displayTime(forRaw: before),
            m.dayStart.addingTimeInterval(-3600 * 0.35))
    }

    // MARK: The ±8 minute event magnet

    func testMagnetSnapsWithinEightMinutesEitherSide() {
        let event = townDate(2026, 8, 11, 15, 0)
        XCTAssertEqual(
            ScrubModel.magnetTarget(
                near: townDate(2026, 8, 11, 14, 53), eventTimes: [event]),
            event)
        XCTAssertEqual(
            ScrubModel.magnetTarget(
                near: townDate(2026, 8, 11, 15, 8), eventTimes: [event]),
            event)
    }

    func testMagnetIgnoresBeyondEightMinutesAndEmptyDays() {
        let event = townDate(2026, 8, 11, 15, 0)
        XCTAssertNil(
            ScrubModel.magnetTarget(
                near: townDate(2026, 8, 11, 14, 51), eventTimes: [event]))
        XCTAssertNil(ScrubModel.magnetTarget(near: noon, eventTimes: []))
    }

    func testMagnetPicksTheNearestOfTwo() {
        let near = townDate(2026, 8, 11, 15, 5)
        let far = townDate(2026, 8, 11, 15, 12)
        XCTAssertEqual(
            ScrubModel.magnetTarget(
                near: townDate(2026, 8, 11, 15, 6), eventTimes: [far, near]),
            near)
    }

    // MARK: Release

    func testReleaseSnapsOverscrollBackToTheBound() {
        let m = model()
        let overshoot = m.dayEnd.addingTimeInterval(30 * 60)
        XCTAssertEqual(m.releaseTarget(for: overshoot, eventTimes: []), m.dayEnd)
        let undershoot = m.dayStart.addingTimeInterval(-10 * 60)
        XCTAssertEqual(m.releaseTarget(for: undershoot, eventTimes: []), m.dayStart)
    }

    func testReleaseStaysPutInsideTheDayAwayFromEvents() {
        // Nil = no settling animation — scrub persists exactly where the
        // finger left it.
        XCTAssertNil(
            model().releaseTarget(
                for: townDate(2026, 8, 11, 16, 20),
                eventTimes: [townDate(2026, 8, 11, 18, 0)]))
    }

    func testReleasePrefersTheMagnetOverStayingPut() {
        let m = model()
        let event = townDate(2026, 8, 11, 17, 0)
        XCTAssertEqual(
            m.releaseTarget(for: townDate(2026, 8, 11, 17, 6), eventTimes: [event]),
            event)
    }
}
