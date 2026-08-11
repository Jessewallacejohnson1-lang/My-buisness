//
//  TimeAxisTests.swift
//  BlockPartyTests
//
//  TimeAxis.x(for:) against known pairs, the midnight crossing, both
//  solstices' label ladders, and the degenerate-window fallback.
//

import XCTest
@testable import BlockParty

final class TimeAxisTests: XCTestCase {
    private let width: CGFloat = 400
    private let sunrise = townDate(2026, 8, 11, 6, 13)
    private let sunset = townDate(2026, 8, 11, 21, 2)

    // MARK: Windows

    func testDayWindowRunsExactSunriseToSunset() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), sunrise: sunrise, sunset: sunset, width: width)
        XCTAssertEqual(axis.kind, .day)
        XCTAssertEqual(axis.start, sunrise)
        XCTAssertEqual(axis.end, sunset)
        XCTAssertFalse(axis.usedFallbackWindow)
    }

    func testNightWindowRunsSunsetToNextSunrise() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 22, 45), sunrise: sunrise, sunset: sunset, width: width)
        XCTAssertEqual(axis.kind, .night)
        XCTAssertEqual(axis.start, sunset)
        XCTAssertEqual(axis.end, sunrise.addingTimeInterval(24 * 3600))
    }

    func testPreDawnNightWindowStartsAtYesterdaysSunset() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 4, 30), sunrise: sunrise, sunset: sunset, width: width)
        XCTAssertEqual(axis.kind, .night)
        XCTAssertEqual(axis.start, sunset.addingTimeInterval(-24 * 3600))
        XCTAssertEqual(axis.end, sunrise)
    }

    // MARK: x(for:)

    func testXMapsKnownPairs() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), sunrise: sunrise, sunset: sunset, width: width)
        XCTAssertEqual(axis.x(for: sunrise), 0)
        XCTAssertEqual(axis.x(for: sunset), width)
        let solarMid = townDate(2026, 8, 11, 13, 37).addingTimeInterval(30)
        XCTAssertEqual(axis.x(for: solarMid)!, width / 2, accuracy: 0.01)
        XCTAssertNil(axis.x(for: sunrise.addingTimeInterval(-60)), "before the window")
        XCTAssertNil(axis.x(for: sunset.addingTimeInterval(60)), "after the window")
    }

    func testMidnightCrossingMapsTomorrowsSmallHours() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 23, 50), sunrise: sunrise, sunset: sunset, width: width)
        let midnight = townDate(2026, 8, 12, 0, 0)
        XCTAssertEqual(axis.midnight, midnight)
        let half12 = axis.x(for: townDate(2026, 8, 12, 0, 30))
        let two = axis.x(for: townDate(2026, 8, 12, 2, 0))
        XCTAssertNotNil(half12)
        XCTAssertNotNil(two)
        XCTAssertGreaterThan(two!, half12!)
        XCTAssertGreaterThan(half12!, axis.x(for: midnight)!)
    }

    func testDayWindowHasNoMidnight() {
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), sunrise: sunrise, sunset: sunset, width: width)
        XCTAssertNil(axis.midnight)
    }

    // MARK: Label ladder at the solstices

    func testSummerSolsticeUsesThreeHourLadder() {
        // 05:26 → 21:03, ~15 h 37 m. 1h grid = 16 hours, 2h = 8 — both over 7.
        let rise = townDate(2026, 6, 20, 5, 26)
        let set = townDate(2026, 6, 20, 21, 3)
        let axis = TimeAxis(now: townDate(2026, 6, 20, 13, 0), sunrise: rise, sunset: set, width: width)
        XCTAssertFalse(axis.usedFallbackWindow)
        XCTAssertEqual(axis.labelInterval, 3)
        let labels = axis.ticks().filter(\.isLabeled).map(\.label)
        // 21:00 sits 1.3 pt from the trailing edge and is dropped.
        XCTAssertEqual(labels, ["6a", "9a", "12p", "3p", "6p"])
    }

    func testWinterSolsticeUsesTwoHourLadder() {
        // 07:48 → 16:34, ~8 h 46 m. 1h grid = 9 hours — over 7.
        let rise = townDate(2026, 12, 21, 7, 48)
        let set = townDate(2026, 12, 21, 16, 34)
        let axis = TimeAxis(now: townDate(2026, 12, 21, 12, 0), sunrise: rise, sunset: set, width: width)
        XCTAssertFalse(axis.usedFallbackWindow)
        XCTAssertEqual(axis.labelInterval, 2)
        let labels = axis.ticks().filter(\.isLabeled).map(\.label)
        // 8:00 sits 9.1 pt from the leading edge and is dropped.
        XCTAssertEqual(labels, ["10a", "12p", "2p", "4p"])
    }

    func testEveryHourGetsATickEvenWhenUnlabeled() {
        let rise = townDate(2026, 6, 20, 5, 26)
        let set = townDate(2026, 6, 20, 21, 3)
        let axis = TimeAxis(now: townDate(2026, 6, 20, 13, 0), sunrise: rise, sunset: set, width: width)
        XCTAssertEqual(axis.ticks().count, 16, "every clean clock hour inside the window")
    }

    // MARK: Degenerate windows

    func testAbsurdlyLongWindowFallsBackToFixedSixToSix() {
        let rise = townDate(2026, 8, 11, 0, 10)
        let set = townDate(2026, 8, 11, 23, 50)
        let axis = TimeAxis(now: townDate(2026, 8, 11, 13, 0), sunrise: rise, sunset: set, width: width)
        XCTAssertTrue(axis.usedFallbackWindow)
        XCTAssertEqual(axis.start, townDate(2026, 8, 11, 6, 0))
        XCTAssertEqual(axis.end, townDate(2026, 8, 11, 18, 0))
    }

    func testAbsurdlyShortWindowFallsBackToFixedSixToSix() {
        let rise = townDate(2026, 8, 11, 10, 0)
        let set = townDate(2026, 8, 11, 13, 0)
        let axis = TimeAxis(now: townDate(2026, 8, 11, 12, 0), sunrise: rise, sunset: set, width: width)
        XCTAssertTrue(axis.usedFallbackWindow)
        XCTAssertEqual(axis.start, townDate(2026, 8, 11, 6, 0))
        XCTAssertEqual(axis.end, townDate(2026, 8, 11, 18, 0))
    }

    func testDegenerateFallbackAtNightUsesSixToSixNightWindow() {
        let rise = townDate(2026, 8, 11, 0, 10)
        let set = townDate(2026, 8, 11, 23, 50)
        let axis = TimeAxis(now: townDate(2026, 8, 11, 22, 0), sunrise: rise, sunset: set, width: width)
        XCTAssertTrue(axis.usedFallbackWindow)
        XCTAssertEqual(axis.kind, .night)
        XCTAssertEqual(axis.start, townDate(2026, 8, 11, 18, 0))
        XCTAssertEqual(axis.end, townDate(2026, 8, 12, 6, 0))
    }

    // MARK: Label formatting

    func testHourLabelFormat() {
        XCTAssertEqual(TimeAxis.hourLabel(hour: 0), "12a")
        XCTAssertEqual(TimeAxis.hourLabel(hour: 8), "8a")
        XCTAssertEqual(TimeAxis.hourLabel(hour: 12), "12p")
        XCTAssertEqual(TimeAxis.hourLabel(hour: 21), "9p")
    }
}
