//
//  TimeAxisTests.swift
//  BlockPartyTests
//
//  The fixed 7a–10p window: known x pairs, the clamped mapping that pins
//  out-of-window marks to the edges, the two-hour tick grid with exactly
//  four labels, and wall-clock edges on DST-change days.
//

import XCTest
@testable import BlockParty

final class TimeAxisTests: XCTestCase {
    private let width: CGFloat = 400

    // MARK: The fixed window

    func testAxisIsSevenToTenAtEveryHourOfTheDay() {
        for hour in [0, 5, 9, 13, 21, 23] {
            let axis = TimeAxis(now: townDate(2026, 8, 11, hour, 0), width: width)
            XCTAssertEqual(axis.start, townDate(2026, 8, 11, 7, 0), "hour \(hour)")
            XCTAssertEqual(axis.end, townDate(2026, 8, 11, 22, 0), "hour \(hour)")
        }
    }

    // MARK: x(for:)

    func testXMapsKnownPairs() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), width: width)
        XCTAssertEqual(axis.x(for: townDate(2026, 8, 11, 7, 0)), 0)
        XCTAssertEqual(axis.x(for: townDate(2026, 8, 11, 22, 0)), width)
        XCTAssertEqual(
            axis.x(for: townDate(2026, 8, 11, 14, 30))!, width / 2, accuracy: 0.01)
        XCTAssertNil(axis.x(for: townDate(2026, 8, 11, 6, 59)), "before the window")
        XCTAssertNil(axis.x(for: townDate(2026, 8, 11, 22, 1)), "after the window")
    }

    func testClampedMappingPinsOutOfWindowMomentsToTheEdges() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 5, 45), width: width)
        XCTAssertEqual(axis.clampedFraction(for: townDate(2026, 8, 11, 5, 45)), 0)
        XCTAssertEqual(axis.clampedFraction(for: townDate(2026, 8, 11, 23, 30)), 1)
        XCTAssertEqual(axis.clampedX(for: townDate(2026, 8, 11, 23, 30)), width)
        XCTAssertEqual(
            axis.clampedFraction(for: townDate(2026, 8, 11, 14, 30)), 0.5,
            accuracy: 0.001)
    }

    // MARK: Ticks and labels — exactly four labels, all day

    func testTicksEveryTwoHoursWithLabelsOnTheFourHourGrid() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), width: width)
        let ticks = axis.ticks()
        XCTAssertEqual(ticks.count, 7, "8a 10a 12p 2p 4p 6p 8p")
        XCTAssertEqual(
            ticks.filter(\.isLabeled).map(\.label), ["8a", "12p", "4p", "8p"])
    }

    func testTicksNeverMoveAcrossTheDay() {
        let morning = TimeAxis(now: townDate(2026, 8, 11, 8, 0), width: width)
        let night = TimeAxis(now: townDate(2026, 8, 11, 23, 30), width: width)
        XCTAssertEqual(morning.ticks(), night.ticks())
        XCTAssertEqual(morning.pointsPerHour, night.pointsPerHour)
    }

    // MARK: DST — edges are wall-clock, spans are honest

    func testDSTChangeDaysKeepWallClockEdges() {
        // Both 2026 transitions happen at 2 AM — before the 7a edge — so the
        // span stays 15 real hours. The guarantee under test is the
        // wall-clock edge: a byAdding implementation would land the spring-
        // forward start at 8 AM; bySettingHour keeps it at 7.
        for day in [townDate(2026, 3, 8, 12, 0), townDate(2026, 11, 1, 12, 0)] {
            let axis = TimeAxis(now: day, width: width)
            XCTAssertEqual(Town.calendar.component(.hour, from: axis.start), 7)
            XCTAssertEqual(Town.calendar.component(.hour, from: axis.end), 22)
            XCTAssertEqual(axis.end.timeIntervalSince(axis.start), 15 * 3600)
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
