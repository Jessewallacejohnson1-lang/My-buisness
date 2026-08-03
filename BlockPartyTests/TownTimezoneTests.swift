//
//  TownTimezoneTests.swift
//  BlockPartyTests — the Utility Row's town-fixed clock. The St. Cloud library and
//  the St. Joseph garbage route live in America/Chicago no matter where the phone
//  is, so the providers must NOT fall back to the DEVICE timezone.
//
//  Every other provider test injects a Chicago calendar explicitly, which is exactly
//  how the `calendar: Calendar = .current` defaults survived. These tests deliberately
//  call the providers with NO calendar argument, under a forced foreign ambient zone,
//  so the default itself is what's under test.
//
//  Reference weekdays (2026): Jan 15 = Thu, Jan 16 = Fri, Jan 22 = Thu.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownTimezoneTests: XCTestCase {

    // MARK: Fixtures

    /// Builds the test instants unambiguously — an explicit wall-clock in Chicago,
    /// independent of whatever ambient zone the test has forced.
    private func chicagoCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 1
        return c
    }

    private func chicagoInstant(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return chicagoCalendar().date(from: comps)!
    }

    /// The device calendar re-pointed at a foreign zone — the *only* difference from
    /// `Calendar.current` is the timezone, so a differing answer isolates the bug.
    private func deviceCalendar(zone identifier: String) -> Calendar {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: identifier)!
        return c
    }

    // MARK: Garbage

    func testGarbagePickupUsesTownTimezoneNotDeviceTimezone() {
        // Arrange — a traveling user, phone on Pacific time.
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!

        // Fri Jan 16 2026 00:30 Central == Thu Jan 15 2026 22:30 Pacific.
        // Thursday IS the St. Joseph pickup day, so Central says "Jan 22, six days
        // out, trash-only week" while Pacific says "today, recycling week".
        let instant = chicagoInstant(2026, 1, 16, 0, 30)
        let pacific = deviceCalendar(zone: "America/Los_Angeles")

        // Act
        let deviceDefault = GarbageSchedule.nextPickup(after: instant)
        let town = GarbageSchedule.nextPickup(after: instant, calendar: Town.calendar)
        let explicitPacific = GarbageSchedule.nextPickup(after: instant, calendar: pacific)

        // Assert — the no-calendar default must answer in town time…
        XCTAssertEqual(deviceDefault, town)
        // …and the instant genuinely discriminates, so the check above has teeth.
        XCTAssertNotEqual(town, explicitPacific)
    }

    // MARK: Library

    func testLibraryStatusUsesTownTimezoneNotDeviceTimezone() {
        // Arrange — a traveling user, phone on Central European time.
        //
        // Pacific cannot discriminate this one: it is only 2h behind Central, so the
        // day flips exclusively between 00:00–02:00 Central, when the library is shut
        // in BOTH zones and both resolve to the same "opens 9 AM" answer. A zone AHEAD
        // of Central flips the day during open hours, which is where the two disagree.
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!

        // Thu Jan 15 2026 18:00 Central == Fri Jan 16 2026 01:00 Berlin.
        // Central: Thursday evening, open until 8 PM. Berlin: Friday small hours, shut.
        let instant = chicagoInstant(2026, 1, 15, 18)
        let berlin = deviceCalendar(zone: "Europe/Berlin")

        // Act
        let deviceDefault = LibraryHours.status(at: instant)
        let town = LibraryHours.status(at: instant, calendar: Town.calendar)
        let explicitBerlin = LibraryHours.status(at: instant, calendar: berlin)

        // Assert
        XCTAssertEqual(town, .open(closesAt: 20 * 60, weekday: 5))   // Thu, closes 8 PM
        XCTAssertEqual(deviceDefault, town)
        XCTAssertNotEqual(town, explicitBerlin)
    }

    // MARK: Display formatting

    /// The shared instant for the formatter tests: Thu Jan 15 2026 23:30 Central,
    /// which is already Fri Jan 16 2026 06:30 in Berlin. A formatter that leaks the
    /// device zone gets BOTH the day and the hour wrong, so one instant covers all
    /// three functions.
    private func lateThursdayNightCentral() -> Date { chicagoInstant(2026, 1, 15, 23, 30) }

    func testMediumDateRendersTownDateNotDeviceDate() {
        // Arrange — a traveling user, phone on Central European time.
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!

        let instant = lateThursdayNightCentral()

        // Act / Assert — "EEE, MMM d" on the town's clock.
        XCTAssertEqual(UtilityFormat.mediumDate(instant), "Thu, Jan 15")
        // …and the instant genuinely discriminates, so the check above has teeth.
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.day, from: instant), 16)
    }

    func testWeekdayNameRendersTownWeekdayNotDeviceWeekday() {
        // Arrange
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!

        let instant = lateThursdayNightCentral()

        // Act / Assert — GarbageTileProvider renders pickup.date through this, so a
        // Thursday-Central pickup must never print as "Friday".
        XCTAssertEqual(UtilityFormat.weekdayName(instant), "Thursday")
        XCTAssertEqual(UtilityFormat.weekdayName(instant, short: true), "Thu")
        // Berlin says Friday (weekday 6) — the assert above has teeth.
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.weekday, from: instant), 6)
    }

    func testShortTimeRendersTownTimeNotDeviceTime() {
        // Arrange
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!

        let instant = lateThursdayNightCentral()

        // Act / Assert — "h:mm a" on the town's clock (minutes non-zero ⇒ h:mm).
        XCTAssertEqual(UtilityFormat.shortTime(instant), "11:30 PM")
        // Berlin reads 6 AM — the assert above has teeth.
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.hour, from: instant), 6)
    }

    // MARK: Town.calendar shape

    func testTownCalendarPreservesLocaleFirstWeekday() {
        // Arrange / Act — no ambient override: this is about how Town.calendar is derived.
        let town = Town.calendar

        // Assert — derived from Calendar.current with ONLY the zone replaced. The
        // holiday-shift math compares by week-offset so it stays correct for any
        // firstWeekday (see the 2028 Thanksgiving regression test); overriding
        // firstWeekday or locale here would silently change the user's week.
        XCTAssertEqual(town.firstWeekday, Calendar.current.firstWeekday)
        XCTAssertEqual(town.timeZone.identifier, "America/Chicago")
        XCTAssertEqual(Town.timeZone.identifier, "America/Chicago")
    }
}
