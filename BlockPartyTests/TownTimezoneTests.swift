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
}
