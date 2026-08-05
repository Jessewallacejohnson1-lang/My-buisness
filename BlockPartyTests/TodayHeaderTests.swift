//
//  TodayHeaderTests.swift
//  BlockPartyTests — the Today tab's compact fixed header bar.
//
//  The 34pt wordmark + date line that used to scroll away with the content
//  (`Masthead`) becomes a fixed 44pt bar — block glyph leading, town name centered,
//  the existing menu button trailing — and today's date moves into the almanac card
//  as a small uppercase eyebrow.
//
//  Two things in that rework are pure logic and therefore testable, and both have a
//  history of going wrong elsewhere in this app:
//
//  1. The eyebrow is a DATE, so it must read `Town`'s clock (America/Chicago), not
//     the device's — the same trap `TownTimezoneTests` locks down for the Utility
//     Row formatters. The old `Masthead.dateLine` used a bare `DateFormatter` with
//     no timezone and no locale pin, so it printed the phone's day in the phone's
//     language. The replacement must not.
//  2. The bar cross-fades in a bottom hairline once content scrolls past 8pt. The
//     interesting input is the NEGATIVE one: a rubber-banded overscroll (pull to
//     refresh) must not flash a hairline on the way down.
//
//  Reference weekdays (2026): Aug 1 = Sat, Jan 15 = Thu, Jan 16 = Fri, Nov 3 = Tue.
//

import XCTest
@testable import BlockParty

@MainActor
final class TodayHeaderTests: XCTestCase {

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

    // MARK: - Eyebrow formatting

    func testEyebrowIsUppercaseWeekdayAndDate() {
        // Arrange — Sat Aug 1 2026, mid-morning Central so no zone within ±9h can
        // slide the day. The shape is "EEEE, MMMM d" uppercased.
        let instant = chicagoInstant(2026, 8, 1, 9)

        // Act
        let eyebrow = TodayHeader.eyebrow(for: instant)

        // Assert — exact string: the comma, the full weekday, the full month.
        XCTAssertEqual(eyebrow, "SATURDAY, AUGUST 1")
    }

    func testEyebrowUsesTownTimeNotDeviceTime() {
        // Arrange — a traveling user, phone on Central European time.
        //
        // A zone AHEAD of Central is what discriminates: at 23:30 Central the Berlin
        // phone has already rolled over to the next calendar day, so a formatter that
        // leaks the device zone prints tomorrow's date on today's almanac card.
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!

        // Thu Jan 15 2026 23:30 Central == Fri Jan 16 2026 06:30 Berlin.
        let instant = chicagoInstant(2026, 1, 15, 23, 30)

        // Act
        let eyebrow = TodayHeader.eyebrow(for: instant)

        // Assert — the town's Thursday, not Berlin's Friday.
        XCTAssertEqual(eyebrow, "THURSDAY, JANUARY 15")
        // …and the instant genuinely discriminates, so the check above has teeth:
        // a Berlin calendar really does report day 16 / weekday 6 (Friday).
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.day, from: instant), 16)
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.weekday, from: instant), 6)
    }

    func testEyebrowHasNoLeadingZeroOnTheDay() {
        // Arrange — Tue Nov 3 2026, a single-digit day in a different month than the
        // shape test, so "d" (not "dd") is what's actually pinned.
        let instant = chicagoInstant(2026, 11, 3, 7, 5)

        // Act
        let eyebrow = TodayHeader.eyebrow(for: instant)

        // Assert
        XCTAssertEqual(eyebrow, "TUESDAY, NOVEMBER 3")
        XCTAssertFalse(eyebrow.contains("NOVEMBER 03"), "The day must not be zero-padded")
    }

    // MARK: - Hairline threshold

    func testHairlineHiddenAtRest() {
        // Arrange / Act — the feed sitting at the top, untouched.
        let shows = TodayHeader.showsHairline(contentOffsetY: 0)

        // Assert — a bar over unscrolled content is a bar with nothing beneath it.
        XCTAssertFalse(shows)
    }

    func testHairlineHiddenExactlyAtThreshold() {
        // Arrange / Act — exactly at the 8pt trigger.
        let shows = TodayHeader.showsHairline(contentOffsetY: TodayHeader.scrollThreshold)

        // Assert — strictly GREATER than, so the boundary itself is still hidden.
        XCTAssertFalse(shows, "The threshold is exclusive: > 8, not >= 8")
    }

    func testHairlineShownPastThreshold() {
        // Arrange / Act — a hair past the trigger, and deep into the feed.
        let justPast = TodayHeader.showsHairline(contentOffsetY: 8.5)
        let farDown = TodayHeader.showsHairline(contentOffsetY: 200)

        // Assert
        XCTAssertTrue(justPast)
        XCTAssertTrue(farDown)
    }

    func testHairlineHiddenWhenRubberBandedPastTop() {
        // Arrange / Act — an overscroll bounce (pull to refresh) drives the offset
        // NEGATIVE. Comparing |offset| instead of offset would flash a hairline
        // partway down every pull.
        let bounce = TodayHeader.showsHairline(contentOffsetY: -60)
        let smallBounce = TodayHeader.showsHairline(contentOffsetY: -8.5)

        // Assert
        XCTAssertFalse(bounce, "A rubber-banded overscroll must not raise the hairline")
        XCTAssertFalse(smallBounce)
    }

    // MARK: - Geometry constants

    func testBarGeometryConstants() {
        // Arrange / Act / Assert — a guard so a later tweak to the bar is deliberate
        // rather than an accidental drift back toward the old scrolling masthead.
        XCTAssertEqual(TodayHeader.contentHeight, 44)
        XCTAssertEqual(TodayHeader.maxHeight, 52)
        XCTAssertEqual(TodayHeader.scrollThreshold, 8)

        // The bar never grows past its ceiling — the relationship, not just the numbers.
        XCTAssertGreaterThan(TodayHeader.maxHeight, TodayHeader.contentHeight)
    }
}
