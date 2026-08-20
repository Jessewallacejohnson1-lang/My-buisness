//
//  TimeAxisTests.swift
//  BlockPartyTests
//
//  The whole-day tape: fixed 12-hours-across-the-card density, strip-local
//  x, the centering offset that pins any moment under the marker, full-day
//  ticks labeled on the four-hour grid, and wall-clock ticks with honest
//  spans on DST-change days.
//

import XCTest
@testable import BlockParty

final class TimeAxisTests: XCTestCase {
    private let width: CGFloat = 360  // 12 h window → 30 pt/hour

    // MARK: The day

    func testTapeCoversTheWholeTownDayAtEveryHour() {
        for hour in [0, 5, 9, 13, 21, 23] {
            let axis = TimeAxis(now: townDate(2026, 8, 11, hour, 0), width: width)
            XCTAssertEqual(axis.dayStart, townDate(2026, 8, 11, 0, 0), "hour \(hour)")
            XCTAssertEqual(axis.dayEnd, townDate(2026, 8, 12, 0, 0), "hour \(hour)")
        }
    }

    // MARK: Density and mapping

    func testDensityIsTwelveVisibleHours() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), width: width)
        XCTAssertEqual(axis.pointsPerHour, 30)
        XCTAssertEqual(axis.x(for: townDate(2026, 8, 11, 0, 0)), 0)
        XCTAssertEqual(axis.x(for: townDate(2026, 8, 11, 12, 0)), width, accuracy: 0.01)
        XCTAssertEqual(axis.x(for: townDate(2026, 8, 12, 0, 0)), 2 * width, accuracy: 0.01)
    }

    func testStripOffsetCentersAnyMomentUnderTheMarker() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), width: width)
        for date in [
            townDate(2026, 8, 11, 0, 0),
            townDate(2026, 8, 11, 9, 30),
            townDate(2026, 8, 11, 14, 7),
            townDate(2026, 8, 12, 0, 0),
        ] {
            let offset = axis.stripOffset(centering: date)
            XCTAssertEqual(
                offset + axis.x(for: date), width / 2, accuracy: 0.001,
                "\(date) must land exactly under the centered marker")
        }
    }

    func testRestingCreepMovesTheStripLeftHalfAPointPerMinute() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), width: width)
        let atOne = axis.stripOffset(centering: townDate(2026, 8, 11, 13, 0))
        let atTwo = axis.stripOffset(centering: townDate(2026, 8, 11, 13, 1))
        XCTAssertEqual(atOne - atTwo, 0.5, accuracy: 0.001)
    }

    // MARK: Ticks and labels

    func testTicksEveryTwoHoursLabeledOnTheFourHourGrid() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), width: width)
        let ticks = axis.ticks()
        XCTAssertEqual(ticks.count, 13, "12a 2a … 10p plus the closing 12a")
        XCTAssertEqual(
            ticks.filter(\.isLabeled).map(\.label),
            ["12a", "4a", "8a", "12p", "4p", "8p", "12a"])
        XCTAssertEqual(ticks.first?.x, 0)
        XCTAssertEqual(ticks.last!.x, 2 * width, accuracy: 0.01)
    }

    func testTicksNeverMoveAcrossTheDay() {
        let morning = TimeAxis(now: townDate(2026, 8, 11, 8, 0), width: width)
        let night = TimeAxis(now: townDate(2026, 8, 11, 23, 30), width: width)
        XCTAssertEqual(morning.ticks(), night.ticks())
        XCTAssertEqual(morning.pointsPerHour, night.pointsPerHour)
    }

    // MARK: DST — ticks are wall-clock, spans are honest

    func testDSTChangeDaysKeepWallClockTicksAndHonestSpans() {
        // Spring forward (2026-03-08, 2 AM skipped): the town day is 23
        // real hours, and a wall-clock 8 AM sits 7 real hours from
        // midnight — a byAdding implementation would land it at 8.
        let spring = TimeAxis(now: townDate(2026, 3, 8, 12, 0), width: width)
        XCTAssertEqual(spring.dayEnd.timeIntervalSince(spring.dayStart), 23 * 3600)
        let springEight = spring.ticks().first { $0.label == "8a" }
        XCTAssertNotNil(springEight)
        XCTAssertEqual(springEight!.x, 7 * spring.pointsPerHour, accuracy: 0.01)

        // Fall back (2026-11-01, 1 AM repeats): 25 real hours, and every
        // tick still lands on a wall-clock hour.
        let fall = TimeAxis(now: townDate(2026, 11, 1, 12, 0), width: width)
        XCTAssertEqual(fall.dayEnd.timeIntervalSince(fall.dayStart), 25 * 3600)
        for tick in fall.ticks() {
            XCTAssertEqual(
                Town.calendar.component(.minute, from: tick.date), 0,
                "\(tick.date) is not a wall-clock hour")
        }
    }

    // MARK: Label formatting

    func testHourLabelFormat() {
        XCTAssertEqual(TimeAxis.hourLabel(hour: 0), "12a")
        XCTAssertEqual(TimeAxis.hourLabel(hour: 8), "8a")
        XCTAssertEqual(TimeAxis.hourLabel(hour: 12), "12p")
        XCTAssertEqual(TimeAxis.hourLabel(hour: 21), "9p")
    }
}
