//
//  LibraryHoursTests.swift
//  BlockPartyTests — open/closed math for the library Utility Row tile against the
//  static hours table. Deterministic via a fixed calendar + `now`.
//
//  Reference weekdays (2026): Jul 12 = Sun, Jul 13 = Mon, Jul 14 = Tue, Jul 15 = Wed.
//

import XCTest
@testable import BlockParty

@MainActor
final class LibraryHoursTests: XCTestCase {

    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 1
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return cal().date(from: comps)!
    }

    func testOpenMidday() {
        // Wed Jul 15 2026, 2:00 PM → open, closes 8 PM (1200 min).
        let s = LibraryHours.status(at: date(2026, 7, 15, 14), calendar: cal())
        XCTAssertEqual(s, .open(closesAt: 20 * 60, weekday: 4))
    }

    func testClosedAfterHoursOpensNextDay() {
        // Wed Jul 15 2026, 9:00 PM → closed, next opening Thu(5) 10 AM.
        let s = LibraryHours.status(at: date(2026, 7, 15, 21), calendar: cal())
        XCTAssertEqual(s, .closed(opensAt: 10 * 60, weekday: 5))
    }

    func testClosedBeforeOpeningSameDay() {
        // Wed Jul 15 2026, 9:00 AM → closed, opens today(4) at 10 AM.
        let s = LibraryHours.status(at: date(2026, 7, 15, 9), calendar: cal())
        XCTAssertEqual(s, .closed(opensAt: 10 * 60, weekday: 4))
    }

    func testSundayClosedOpensMonday() {
        // Sun Jul 12 2026, noon → closed all day, opens Mon(2) 10 AM.
        let s = LibraryHours.status(at: date(2026, 7, 12, 12), calendar: cal())
        XCTAssertEqual(s, .closed(opensAt: 10 * 60, weekday: 2))
    }

    func testClosesAtTableUpperBound() {
        // Sat Jul 11 2026, 2 PM → open, closes 5 PM (Sat closes earlier).
        let s = LibraryHours.status(at: date(2026, 7, 11, 14), calendar: cal())
        XCTAssertEqual(s, .open(closesAt: 17 * 60, weekday: 7))
    }
}
