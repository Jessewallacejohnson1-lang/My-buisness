//
//  TownFixturesTests.swift
//  BlockPartyTests — `-town-live` and `-town-now` samples start an hour ago, but stay on today
//  from midnight to 1 AM (BP app agent-guardrails 10).
//

import XCTest
@testable import BlockParty

final class TownFixturesTests: XCTestCase {
    private func townTime(_ hour: Int, _ minute: Int) -> Date {
        Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: hour, minute: minute))!
    }

    func testJustAfterMidnightItStartsAtMidnightToday() {
        let now = townTime(0, 20)
        let start = TownFixtures.startedAnHourAgo(now: now)
        XCTAssertEqual(TownFixtures.townClock("h:mm a", start), "12:00 AM")
        XCTAssertEqual(TownFixtures.townClock("yyyy-MM-dd", start), "2026-11-16")
    }

    func testInTheAfternoonItStartsAnHourAgo() {
        let start = TownFixtures.startedAnHourAgo(now: townTime(15, 0))
        XCTAssertEqual(TownFixtures.townClock("h:mm a", start), "2:00 PM")
        XCTAssertEqual(TownFixtures.townClock("yyyy-MM-dd", start), "2026-11-16")
    }
}
