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

    // MARK: Admin gate — email allowlist, case-insensitive

    func testAdminGate() {
        XCTAssertTrue(Admin.isAdmin("jessewallacejohnson1@icloud.com"))
        XCTAssertTrue(Admin.isAdmin("JesseWallaceJohnson1@iCloud.com"))
        XCTAssertFalse(Admin.isAdmin("someone@example.com"))
        XCTAssertFalse(Admin.isAdmin(nil))
        XCTAssertFalse(Admin.isAdmin(""))
    }
}
