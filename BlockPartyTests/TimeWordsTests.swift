//
//  TimeWordsTests.swift
//  BlockPartyTests — the words in a search that say when, and the ones that say nothing (BP app search-helpful 06).
//

import XCTest
@testable import BlockParty

final class TimeWordsTests: XCTestCase {
    /// Tuesday, Nov 3 2026, in the Town's time.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func read(_ words: String, _ now: Date) -> TimeWords.Read {
        TimeWords.read(words, now: now, calendar: Town.gregorian)
    }

    func testTimeWordsPickTheirHours() {
        let now = at(3, 10)
        XCTAssertEqual(read("tonight", now).hours, at(3, 17) ..< at(4, 5))
        XCTAssertEqual(read("tonight", at(4, 1)).hours, at(4, 1) ..< at(4, 5), "after midnight, tonight is still on")
        XCTAssertEqual(read("today", now).hours, now ..< at(4, 0))
        XCTAssertEqual(read("tomorrow", now).hours, at(4, 0) ..< at(5, 0))
        XCTAssertEqual(read("saturday", now).hours, at(7, 0) ..< at(8, 0))
        XCTAssertEqual(read("on Friday night", now), TimeWords.Read(words: "", hours: at(6, 17) ..< at(7, 5), took: true))
        XCTAssertEqual(read("tuesday", now).hours, now ..< at(4, 0), "today's own weekday is today")
        XCTAssertEqual(read("this weekend", now).hours, at(6, 17) ..< at(9, 0), "from Friday 5 PM")
        XCTAssertEqual(read("this weekend", at(7, 12)).hours, at(7, 12) ..< at(9, 0), "on Saturday, from now")
        XCTAssertEqual(read("things to do", now).hours, now ..< at(10, 0))
        XCTAssertEqual(read("things to do tonight", now), TimeWords.Read(words: "", hours: at(3, 17) ..< at(4, 5), took: true))
        XCTAssertEqual(read("things to do this weekend", now).hours, at(6, 17) ..< at(9, 0))
        XCTAssertEqual(read("now", now).hours, now ..< now)
        XCTAssertEqual(read("open now", now), TimeWords.Read(words: "", openNow: true, took: true))
    }

    func testOtherWordsStay() {
        let now = at(3, 10)
        XCTAssertEqual(read("live music tonight", now).words, "live music")
        XCTAssertEqual(read("hockey games this week", now).words, "hockey games")
        XCTAssertEqual(read("pizza near me", now), TimeWords.Read(words: "pizza", took: true))
        XCTAssertFalse(read("Pizza", now).took, "nothing taken: scored once")
        XCTAssertEqual(read("best coffee", now).words, "coffee")
        XCTAssertEqual(read("where to eat", now).words, "eat")
        XCTAssertEqual(read("kid friendly", now).words, "kid")
        XCTAssertEqual(read("hop on", now).words, "hop on", "\"on\" goes only after a weekday")
        XCTAssertEqual(read("Sal's", now).words, "sals")
    }

    func testWhatFitsTheHours() {
        let now = at(3, 10), tonight = at(3, 17) ..< at(4, 5)
        func fits(_ start: Date, _ end: Date, timed: Bool = true, _ hours: Range<Date>) -> Bool {
            TimeWords.fits(start: start, end: end, timed: timed, in: hours, now: now, calendar: Town.gregorian)
        }
        XCTAssertTrue(fits(at(3, 19), at(3, 21), tonight))
        XCTAssertFalse(fits(at(3, 16), at(3, 18), tonight), "an afternoon meet still on at 5 isn't tonight")
        XCTAssertTrue(fits(at(3, 9), at(3, 11), now ..< at(4, 0)), "on now counts for today")
        XCTAssertTrue(fits(at(3, 0), at(4, 0), timed: false, now ..< at(4, 0)), "today's all-day fair")
        XCTAssertFalse(fits(at(3, 0), at(4, 0), timed: false, now ..< now), "an all-day listing isn't on now")
        XCTAssertFalse(fits(at(1, 0), at(20, 0), timed: false, tonight), "a month-long exhibit isn't tonight")
        XCTAssertFalse(fits(at(4, 0), at(5, 0), timed: false, tonight), "tomorrow's all-day fair isn't tonight")
        XCTAssertTrue(fits(at(3, 0), at(4, 0), timed: false, tonight), "today's all-day fair is")
        XCTAssertTrue(fits(at(6, 0), at(9, 0), timed: false, at(7, 0) ..< at(8, 0)), "a weekend festival is Saturday's")
    }
}
