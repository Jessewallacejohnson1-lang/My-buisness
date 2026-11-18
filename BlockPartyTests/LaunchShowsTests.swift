//
//  LaunchShowsTests.swift
//  Block Party — the day's first cold start plays the whole launch (Jesse, 2026-11-17; two since
//  2026-11-08), the rest the BlockParty. wordmark and its fade (Jesse, 2026-11-14), counted on the
//  phone as "yyyy-m-d n".
//

import XCTest
@testable import BlockParty

final class LaunchShowsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 8, hour: 12))!
    }

    /// Nothing kept, or another day's count: the first open's show, and today's count starts at 1.
    func testADayStartsWithTheFirstOpen() {
        let fresh = LaunchShows.next(now: today, calendar: calendar, record: nil)
        XCTAssertEqual(fresh.kind, .first)
        XCTAssertEqual(fresh.record, "2026-11-8 1")
        let yesterday = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-7 5")
        XCTAssertEqual(yesterday.kind, .first)
        XCTAssertEqual(yesterday.record, "2026-11-8 1")
    }

    /// Only the first start of the day writes BlockParty.; the second and after play Bp!.
    func testOneFirstOpenThenLaterOpens() {
        XCTAssertEqual(LaunchShows.firstOpensADay, 1)
        let second = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 1")
        XCTAssertEqual(second.kind, .later)
        XCTAssertEqual(second.record, "2026-11-8 2")
        XCTAssertEqual(LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 40").kind, .later)
    }

    /// A record that isn't ours reads as none.
    func testAStrangeRecordStartsOver() {
        let odd = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 lots")
        XCTAssertEqual(odd.kind, .first)
        XCTAssertEqual(odd.record, "2026-11-8 1")
    }

    /// Counting on the phone: three starts in a row read the kept record and move it on.
    func testCountsOnThePhone() {
        let suite = "LaunchShowsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LaunchShows.kind(now: today, defaults: defaults), .first)
        XCTAssertEqual(LaunchShows.kind(now: today, defaults: defaults), .later)
        XCTAssertEqual(LaunchShows.kind(now: today, defaults: defaults), .later)
        XCTAssertEqual(defaults.string(forKey: LaunchShows.key)?.hasSuffix(" 3"), true)
    }
}
