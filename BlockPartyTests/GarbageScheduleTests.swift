//
//  GarbageScheduleTests.swift
//  BlockPartyTests — pure date math for the garbage Utility Row tile: the next
//  pickup (weekday), every-other-week recycling parity, and the holiday +1 shift.
//  All deterministic via an injected fixed calendar + `now`.
//

import XCTest
@testable import BlockParty

final class GarbageScheduleTests: XCTestCase {

    /// Fixed calendar: gregorian, St. Joe timezone, Sunday-first — matches how the
    /// provider reads the user's local calendar, but pinned for reproducibility.
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 1   // Sunday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h
        return cal().date(from: comps)!
    }

    // MARK: daysFromToday → the "Tonight / Tomorrow / weekday" mapping input

    func testPickupTomorrowFromDayBefore() {
        // Mon Jul 13 2026, pickup Tuesday(3) → Jul 14, one day out.
        let p = GarbageSchedule.nextPickup(after: date(2026, 7, 13), pickupWeekday: 3, calendar: cal())
        XCTAssertEqual(p.daysFromToday, 1)
        XCTAssertEqual(cal().component(.weekday, from: p.date), 3)   // Tuesday
    }

    func testPickupTonightWhenTodayIsPickupDay() {
        // Tue Jul 14 2026 morning, pickup Tuesday(3) → today.
        let p = GarbageSchedule.nextPickup(after: date(2026, 7, 14, 8), pickupWeekday: 3, calendar: cal())
        XCTAssertEqual(p.daysFromToday, 0)
    }

    // MARK: recycling parity — anchored to Jul 14 2026 (a recycling week)

    func testAnchorWeekIsRecyclingMatchesRealCalendar() {
        // Thu Jan 15 2026 is a "Blue Week" recycling Thursday (Republic Services 2026 calendar).
        let p = GarbageSchedule.nextPickup(after: date(2026, 1, 12), pickupWeekday: 5, calendar: cal())
        XCTAssertEqual(cal().component(.day, from: p.date), 15)
        XCTAssertTrue(p.isRecyclingWeek)
    }

    func testNextWeekIsTrashOnly() {
        // Thu Jan 22 2026 is the off week → trash only (white on the real calendar).
        let p = GarbageSchedule.nextPickup(after: date(2026, 1, 19), pickupWeekday: 5, calendar: cal())
        XCTAssertEqual(cal().component(.day, from: p.date), 22)
        XCTAssertFalse(p.isRecyclingWeek)
    }

    func testParityAlternatesWeekly() {
        // Jan 15 recycling · Jan 22 trash · Jan 29 recycling — matches the 2026 calendar.
        let a = GarbageSchedule.nextPickup(after: date(2026, 1, 12), pickupWeekday: 5, calendar: cal())
        let b = GarbageSchedule.nextPickup(after: date(2026, 1, 19), pickupWeekday: 5, calendar: cal())
        let c = GarbageSchedule.nextPickup(after: date(2026, 1, 26), pickupWeekday: 5, calendar: cal())
        XCTAssertTrue(a.isRecyclingWeek)
        XCTAssertFalse(b.isRecyclingWeek)
        XCTAssertTrue(c.isRecyclingWeek)
    }

    // MARK: holiday shift — a holiday on/before the pickup day delays pickup +1

    func testHolidayDelaysPickupByOneDay() {
        // Christmas (Dec 25 2026) is in observedHolidays. Set the pickup weekday to
        // Christmas's own weekday and `now` to the start of that week: the holiday
        // falls ON the pickup day, so pickup shifts to the next day.
        let c = cal()
        let christmas = date(2026, 12, 25)
        let xmasWeekday = c.component(.weekday, from: christmas)
        let weekStart = c.dateInterval(of: .weekOfYear, for: christmas)!.start

        let p = GarbageSchedule.nextPickup(after: weekStart, pickupWeekday: xmasWeekday, calendar: c)
        // Shifted to the day after Christmas.
        XCTAssertEqual(c.component(.day, from: p.date), 26)
        XCTAssertEqual(c.component(.month, from: p.date), 12)
    }

    func testFloatingHolidayShiftsInAFutureYear() {
        // Thanksgiving is the 4th Thursday of Nov — computed per year, not hardcoded.
        // In 2028 that's Thu Nov 23; a Friday(6) pickup that week shifts to Sat Nov 25.
        let c = cal()
        let p = GarbageSchedule.nextPickup(after: date(2028, 11, 20), pickupWeekday: 6, calendar: c)
        XCTAssertEqual(c.component(.month, from: p.date), 11)
        XCTAssertEqual(c.component(.day, from: p.date), 25)
    }

    func testNoHolidayNoShift() {
        // A plain week: pickup weekday is returned unshifted.
        let c = cal()
        let p = GarbageSchedule.nextPickup(after: date(2026, 7, 13), pickupWeekday: 3, calendar: c)
        XCTAssertEqual(c.component(.weekday, from: p.date), 3)   // still Tuesday, no shift
    }
}
