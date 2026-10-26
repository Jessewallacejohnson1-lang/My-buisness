//
//  TownTimezoneTests.swift
//  BlockPartyTests — the town-fixed clock. The town lives in America/Chicago no
//  matter where the phone is. Its garbage, library and date-format tests went with
//  the parked utility row on 2026-10-25 (docs/archive/GUTTING-LEDGER.md).
//

import XCTest
@testable import BlockParty

@MainActor
final class TownTimezoneTests: XCTestCase {

    // MARK: Town.calendar shape

    func testTownCalendarPreservesLocaleFirstWeekday() {
        // Arrange / Act — no ambient override: this is about how Town.calendar is derived.
        let town = Town.calendar

        // Assert — derived from Calendar.current with ONLY the zone replaced.
        // Overriding firstWeekday or locale here would silently change the user's week.
        XCTAssertEqual(town.firstWeekday, Calendar.current.firstWeekday)
        XCTAssertEqual(town.timeZone.identifier, "America/Chicago")
        XCTAssertEqual(Town.timeZone.identifier, "America/Chicago")
    }

    // MARK: Town helpers

    func testGregorianIsTheTownsZone() {
        XCTAssertEqual(Town.gregorian.timeZone.identifier, "America/Chicago")
        XCTAssertEqual(Town.gregorian.identifier, .gregorian)
    }

    func testMidnightAndDayRoundTrip() throws {
        let day = try XCTUnwrap(Town.midnight("2026-10-25"))
        XCTAssertEqual(Town.day(day), "2026-10-25")
        XCTAssertEqual(Town.gregorian.component(.hour, from: day), 0)
        XCTAssertNil(Town.midnight("Oct 25"))
    }

    func testDaysCountsTownDaysAcrossTheClockChange() throws {
        // Clocks go back on Sunday, Nov 1 2026: that day is 25 hours long.
        let saturday = try XCTUnwrap(Town.midnight("2026-10-31")).addingTimeInterval(23 * 3600)
        let monday = try XCTUnwrap(Town.midnight("2026-11-02")).addingTimeInterval(3600)
        XCTAssertEqual(Town.days(from: saturday, to: monday), 2)
        XCTAssertEqual(Town.days(from: monday, to: saturday), -2)
        XCTAssertEqual(Town.days(from: saturday, to: saturday.addingTimeInterval(1800)), 1, "past midnight is tomorrow")
    }

    func testClockReadsLikeThePrintedCard() throws {
        let day = try XCTUnwrap(Town.midnight("2026-10-25"))
        XCTAssertEqual(Town.clock(day.addingTimeInterval(19 * 3600)), "7 PM")
        XCTAssertEqual(Town.clock(day.addingTimeInterval(19.5 * 3600)), "7:30 PM")
        XCTAssertEqual(Town.clock(day.addingTimeInterval(12 * 3600)), "Noon")
        XCTAssertEqual(Town.clock(day), "Midnight")
        XCTAssertEqual(Town.clock(minutes: 9 * 60 + 5), "9:05 AM")
    }

    func testFormatIsEnglishInTheTownsTime() throws {
        // 11:30 PM Saturday in St. Joseph is already Sunday in UTC.
        let late = try XCTUnwrap(Town.midnight("2026-10-24")).addingTimeInterval(23.5 * 3600)
        XCTAssertEqual(Town.format(late, "EEEE"), "Saturday")
        XCTAssertEqual(Town.format(late, "EEEMMMd"), "Sat, Oct 24")
        XCTAssertEqual(Town.format(late, "EEE"), "Sat", "a second call reads the kept formatter")
    }
}
