//
//  CalendarFoldTests.swift
//  BlockPartyTests — You's Calendar folding to one week (BP app docs/plans/you-tab, ticket 14):
//  which week the folded row shows, how far a pull opens it, where a let-go settles, and the
//  height and roll the fold draws.
//

import XCTest
@testable import BlockParty

@MainActor
final class CalendarFoldTests: XCTestCase {
    private let pitch = YouMetric.day + YouMetric.rowGap

    func testTheFoldedRowIsThePickedDaysWeek() {
        XCTAssertEqual(CalendarFold.row(of: 0), 0)
        XCTAssertEqual(CalendarFold.row(of: 6), 0)
        XCTAssertEqual(CalendarFold.row(of: 7), 1)
        XCTAssertEqual(CalendarFold.row(of: 20), 2)
        // A day off the three weeks (a page from before midnight) keeps the first week.
        XCTAssertEqual(CalendarFold.row(of: nil), 0)
    }

    func testFoldedShowsOneRowAndOpenShowsThree() {
        XCTAssertEqual(CalendarFold.height(openness: 0), YouMetric.day, accuracy: 0.01)
        XCTAssertEqual(CalendarFold.height(openness: 1), YouMetric.day + 2 * pitch, accuracy: 0.01)
        // Folded saves the two 60 pt rows the ticket names.
        XCTAssertEqual(CalendarFold.travel, 120, accuracy: 0.01)
    }

    func testFoldedRollsThePickedWeekToTheTopAndOpenPutsItBack() {
        XCTAssertEqual(CalendarFold.offset(openness: 0, row: 2), -2 * pitch, accuracy: 0.01)
        XCTAssertEqual(CalendarFold.offset(openness: 1, row: 2), 0, accuracy: 0.01)
        XCTAssertEqual(CalendarFold.offset(openness: 0.5, row: 1), -pitch / 2, accuracy: 0.01)
        XCTAssertEqual(CalendarFold.offset(openness: 0, row: 0), 0, accuracy: 0.01)
    }

    func testAPullFollowsTheFingerBothWaysAndStopsAtTheEnds() {
        XCTAssertEqual(CalendarFold.openness(from: 0, pulled: 60), 0.5, accuracy: 0.001)
        XCTAssertEqual(CalendarFold.openness(from: 1, pulled: -30), 0.75, accuracy: 0.001)
        XCTAssertEqual(CalendarFold.openness(from: 0.4, pulled: 12), 0.5, accuracy: 0.001)
        XCTAssertEqual(CalendarFold.openness(from: 0, pulled: -40), 0)
        XCTAssertEqual(CalendarFold.openness(from: 1, pulled: 300), 1)
    }

    func testALetGoSettlesOnTheNearerEndOfWhereTheFlickWouldCarryIt() {
        XCTAssertTrue(CalendarFold.settlesOpen(from: 0, flung: 61))
        XCTAssertFalse(CalendarFold.settlesOpen(from: 0, flung: 59))
        XCTAssertFalse(CalendarFold.settlesOpen(from: 1, flung: -61))
        // Caught halfway and flicked back up: it folds.
        XCTAssertFalse(CalendarFold.settlesOpen(from: 0.6, flung: -40))
        XCTAssertTrue(CalendarFold.settlesOpen(from: 0.6, flung: 0))
    }
}
