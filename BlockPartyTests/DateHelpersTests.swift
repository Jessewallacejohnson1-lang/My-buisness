//
//  DateHelpersTests.swift
//  BlockPartyTests — the first, highest-value test slice: the pure, brand-critical date
//  logic CLAUDE.md repeatedly calls out (timezone dates + live-glow). These are the
//  functions most prone to silent drift and, being pure, are trivially testable.
//

import XCTest
@testable import BlockParty

final class DateHelpersTests: XCTestCase {

    // MARK: minutesOf — free-text display time → minutes from midnight

    func testMinutesOfNamedTimes() {
        XCTAssertEqual(DateHelpers.minutesOf("noon"), 12 * 60)
        XCTAssertEqual(DateHelpers.minutesOf("Noon"), 12 * 60)
        XCTAssertEqual(DateHelpers.minutesOf("midnight"), 0)
        XCTAssertEqual(DateHelpers.minutesOf("Midnight"), 0)   // regression: was mis-parsed as noon
    }

    func testMinutesOfClockTimes() {
        XCTAssertEqual(DateHelpers.minutesOf("7am"), 7 * 60)
        XCTAssertEqual(DateHelpers.minutesOf("7:30 pm"), 19 * 60 + 30)
        XCTAssertEqual(DateHelpers.minutesOf("12pm"), 12 * 60)   // noon
        XCTAssertEqual(DateHelpers.minutesOf("12am"), 0)         // midnight
        XCTAssertEqual(DateHelpers.minutesOf("10 AM"), 10 * 60)
    }

    func testMinutesOfUnparseableIsEndOfDay() {
        XCTAssertEqual(DateHelpers.minutesOf(nil), 24 * 60)
        XCTAssertEqual(DateHelpers.minutesOf(""), 24 * 60)
        XCTAssertEqual(DateHelpers.minutesOf("TBD"), 24 * 60)
        XCTAssertEqual(DateHelpers.minutesOf("Sunset"), 24 * 60)
    }

    // MARK: isLiveNow — start ≤ now ≤ start+120, untimed never live

    func testIsLiveNowWindow() {
        // 10:00 AM event = 600 minutes.
        XCTAssertTrue(DateHelpers.isLiveNow("10:00 am", now: 600))   // exactly at start
        XCTAssertTrue(DateHelpers.isLiveNow("10:00 am", now: 660))   // mid-window
        XCTAssertTrue(DateHelpers.isLiveNow("10:00 am", now: 720))   // start + 120, still live
        XCTAssertFalse(DateHelpers.isLiveNow("10:00 am", now: 599))  // one minute before start
        XCTAssertFalse(DateHelpers.isLiveNow("10:00 am", now: 721))  // one minute past the window
    }

    func testIsLiveNowUntimedOrUnparseable() {
        XCTAssertFalse(DateHelpers.isLiveNow(nil, now: 600))
        XCTAssertFalse(DateHelpers.isLiveNow("all day", now: 600))   // unparseable → not live
    }

    // MARK: daysBetween — local whole-day difference

    func testDaysBetween() {
        XCTAssertEqual(DateHelpers.daysBetween("2026-07-10", "2026-07-17"), 7)
        XCTAssertEqual(DateHelpers.daysBetween("2026-07-17", "2026-07-10"), -7)
        XCTAssertEqual(DateHelpers.daysBetween("2026-07-10", "2026-07-10"), 0)
        XCTAssertNil(DateHelpers.daysBetween("bad", "2026-07-10"))
    }

    // MARK: Admin gate — email allowlist, case-insensitive

    func testAdminGate() {
        XCTAssertTrue(Admin.isAdmin("jessewallacejohnson1@icloud.com"))
        XCTAssertTrue(Admin.isAdmin("JesseWallaceJohnson1@iCloud.com"))
        XCTAssertFalse(Admin.isAdmin("someone@example.com"))
        XCTAssertFalse(Admin.isAdmin(nil))
        XCTAssertFalse(Admin.isAdmin(""))
    }
}
