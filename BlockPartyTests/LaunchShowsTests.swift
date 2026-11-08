//
//  LaunchShowsTests.swift
//  Block Party — the day's first two cold starts play the whole launch, the rest its short cut
//  (Jesse, 2026-11-08), counted on the phone as "yyyy-m-d n".
//

import XCTest
@testable import BlockParty

final class LaunchShowsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 8, hour: 12))!
    }

    /// Nothing kept, or another day's count: the full show, and today's count starts at 1.
    func testADayStartsWithTheFullShow() {
        let fresh = LaunchShows.next(now: today, calendar: calendar, record: nil)
        XCTAssertEqual(fresh.kind, .full)
        XCTAssertEqual(fresh.record, "2026-11-8 1")
        let yesterday = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-7 5")
        XCTAssertEqual(yesterday.kind, .full)
        XCTAssertEqual(yesterday.record, "2026-11-8 1")
    }

    /// The second start of the day is still the full show; the third and after are the short cut.
    func testTwoFullShowsThenTheShortCut() {
        XCTAssertEqual(LaunchShows.fullShowsADay, 2)
        let second = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 1")
        XCTAssertEqual(second.kind, .full)
        XCTAssertEqual(second.record, "2026-11-8 2")
        let third = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 2")
        XCTAssertEqual(third.kind, .short)
        XCTAssertEqual(third.record, "2026-11-8 3")
        XCTAssertEqual(LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 40").kind, .short)
    }

    /// A record that isn't ours reads as none.
    func testAStrangeRecordStartsOver() {
        let odd = LaunchShows.next(now: today, calendar: calendar, record: "2026-11-8 lots")
        XCTAssertEqual(odd.kind, .full)
        XCTAssertEqual(odd.record, "2026-11-8 1")
    }

    /// Counting on the phone: three starts in a row read the kept record and move it on.
    func testCountsOnThePhone() {
        let suite = "LaunchShowsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LaunchShows.kind(now: today, defaults: defaults), .full)
        XCTAssertEqual(LaunchShows.kind(now: today, defaults: defaults), .full)
        XCTAssertEqual(LaunchShows.kind(now: today, defaults: defaults), .short)
        XCTAssertEqual(defaults.string(forKey: LaunchShows.key)?.hasSuffix(" 3"), true)
    }
}
