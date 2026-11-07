//
//  DateHelpersTests.swift
//  BlockPartyTests — the first, highest-value test slice: the pure, brand-critical date
//  logic CLAUDE.md repeatedly calls out (timezone dates + live-glow). These are the
//  functions most prone to silent drift and, being pure, are trivially testable.
//

import XCTest
@testable import BlockParty

final class DateHelpersTests: XCTestCase {

    // MARK: daysBetween — local whole-day difference

    func testDaysBetween() {
        XCTAssertEqual(DateHelpers.daysBetween("2026-07-10", "2026-07-17"), 7)
        XCTAssertEqual(DateHelpers.daysBetween("2026-07-17", "2026-07-10"), -7)
        XCTAssertEqual(DateHelpers.daysBetween("2026-07-10", "2026-07-10"), 0)
        XCTAssertNil(DateHelpers.daysBetween("bad", "2026-07-10"))
    }

    // MARK: timestamp — every shape of Postgres timestamptz the server sends

    /// 2026-10-24 18:21:32 UTC.
    private let saturdayAfternoon = Date(timeIntervalSince1970: 1_792_866_092)

    func testTimestampReadsEveryServerShape() throws {
        let micro = try XCTUnwrap(DateHelpers.timestamp("2026-10-24T18:21:32.123456+00:00"))
        XCTAssertEqual(micro.timeIntervalSince1970, saturdayAfternoon.timeIntervalSince1970 + 0.123, accuracy: 0.001)
        let milli = try XCTUnwrap(DateHelpers.timestamp("2026-10-24T18:21:32.5Z"))
        XCTAssertEqual(milli.timeIntervalSince1970, saturdayAfternoon.timeIntervalSince1970 + 0.5, accuracy: 0.001)
        XCTAssertEqual(DateHelpers.timestamp("2026-10-24T18:21:32+00:00"), saturdayAfternoon)
        XCTAssertEqual(DateHelpers.timestamp("2026-10-24T18:21:32Z"), saturdayAfternoon)
        XCTAssertEqual(DateHelpers.timestamp("2026-10-24T13:21:32-05:00"), saturdayAfternoon, "Central daylight time")
        XCTAssertEqual(DateHelpers.timestamp("  2026-10-24T18:21:32Z\n"), saturdayAfternoon)
    }

    func testTimestampGarbageIsNilNotAWrongDate() {
        XCTAssertNil(DateHelpers.timestamp(nil))
        XCTAssertNil(DateHelpers.timestamp(""))
        XCTAssertNil(DateHelpers.timestamp("   "))
        XCTAssertNil(DateHelpers.timestamp("garbage"))
        XCTAssertNil(DateHelpers.timestamp("tomorrow at 7"))
        XCTAssertNil(DateHelpers.timestamp("2026-10-24"), "a plain date is not a timestamp")
    }

    func testTimestampStringIsWhatTheServerIsSent() {
        XCTAssertEqual(DateHelpers.timestampString(saturdayAfternoon), "2026-10-24T18:21:32Z")
        XCTAssertEqual(DateHelpers.timestampString(saturdayAfternoon.addingTimeInterval(0.75)), "2026-10-24T18:21:32Z",
                       "whole seconds, as the app always sent")
        XCTAssertEqual(DateHelpers.timestamp(DateHelpers.timestampString(saturdayAfternoon)), saturdayAfternoon)
    }

    /// One shared reader, many threads at once: every one reads the same instant.
    func testTimestampIsSafeFromAnyThread() {
        let shapes = ["2026-10-24T18:21:32Z", "2026-10-24T18:21:32+00:00", "2026-10-24T18:21:32.000+00:00"]
        let lock = NSLock()
        var read: [Date?] = []
        DispatchQueue.concurrentPerform(iterations: 300) { i in
            let date = DateHelpers.timestamp(shapes[i % shapes.count])
            _ = DateHelpers.timestampString(Date(timeIntervalSince1970: Double(i)))
            lock.lock(); read.append(date); lock.unlock()
        }
        XCTAssertEqual(read.count, 300)
        XCTAssertTrue(read.allSatisfy { $0 == saturdayAfternoon })
    }

    // MARK: townDay — a Postgres date is the Town's day

    func testTownDayIsTownMidnight() throws {
        let day = try XCTUnwrap(DateHelpers.townDay("2026-10-31"))
        XCTAssertEqual(day, Date(timeIntervalSince1970: 1_793_422_800), "00:00 CDT is 05:00 UTC")
        XCTAssertEqual(Town.day(day), "2026-10-31")
        XCTAssertEqual(Town.midnight("2026-10-31"), day, "Town.midnight reads through the same owner")
    }

    /// Around midnight Central the UTC date is already tomorrow; the Town's day is not.
    func testTownDayAroundCentralMidnight() throws {
        let midnight = try XCTUnwrap(DateHelpers.townDay("2026-10-31"))
        XCTAssertEqual(Town.day(midnight.addingTimeInterval(-1)), "2026-10-30")
        XCTAssertEqual(Town.day(midnight), "2026-10-31")
        let lateSaturday = try XCTUnwrap(DateHelpers.timestamp("2026-11-01T04:30:00Z"))
        XCTAssertEqual(Town.day(lateSaturday), "2026-10-31", "11:30 PM Central, Saturday, though UTC says Sunday")
    }

    /// Sunday Nov 1, 2026 is the US fall-back day: 1:00–2:00 AM Central happens twice.
    func testHalloweenWeekFallBack() throws {
        let daylight = try XCTUnwrap(DateHelpers.timestamp("2026-11-01T01:30:00-05:00"))
        let standard = try XCTUnwrap(DateHelpers.timestamp("2026-11-01T01:30:00-06:00"))
        XCTAssertEqual(daylight, Date(timeIntervalSince1970: 1_793_514_600))
        XCTAssertEqual(standard, Date(timeIntervalSince1970: 1_793_518_200))
        XCTAssertEqual(standard.timeIntervalSince(daylight), 3600, "the same 1:30 AM, an hour apart")
        for moment in [daylight, standard] {
            XCTAssertEqual(Town.day(moment), "2026-11-01")
            XCTAssertEqual(Town.gregorian.component(.hour, from: moment), 1)
            XCTAssertEqual(Town.gregorian.component(.minute, from: moment), 30)
        }

        let sunday = try XCTUnwrap(DateHelpers.townDay("2026-11-01"))
        let monday = try XCTUnwrap(DateHelpers.townDay("2026-11-02"))
        XCTAssertEqual(sunday, Date(timeIntervalSince1970: 1_793_509_200), "00:00 CDT")
        XCTAssertEqual(monday, Date(timeIntervalSince1970: 1_793_599_200), "00:00 CST")
        XCTAssertEqual(monday.timeIntervalSince(sunday), 25 * 3600, "fall-back Sunday is 25 hours long")
        XCTAssertEqual(Town.day(sunday.addingTimeInterval(24 * 3600)), "2026-11-01", "11 PM Sunday is still Sunday")
        XCTAssertEqual(Town.days(from: sunday, to: monday), 1)
    }

    func testTownDayGarbageIsNilNotAWrongDay() {
        XCTAssertNil(DateHelpers.townDay(nil))
        XCTAssertNil(DateHelpers.townDay(""))
        XCTAssertNil(DateHelpers.townDay("garbage"))
        XCTAssertNil(DateHelpers.townDay("Oct 31"))
        XCTAssertNil(DateHelpers.townDay("2026-02-30"), "not rolled over to March 2")
        XCTAssertNil(DateHelpers.townDay("2026-13-01"))
        XCTAssertNil(DateHelpers.townDay("2026-10-31T00:00:00Z"), "a timestamp is not a plain date")
        XCTAssertNil(DateHelpers.townDay("26-10-31"))
        XCTAssertNil(DateHelpers.townDay("2026-10--31"))
    }

    // MARK: Town.calendar — built once

    func testTownCalendarIsStoredWithTheTownsZone() {
        XCTAssertEqual(Town.calendar, Town.calendar)
        XCTAssertEqual(Town.calendar.timeZone, Town.timeZone)
    }
}
