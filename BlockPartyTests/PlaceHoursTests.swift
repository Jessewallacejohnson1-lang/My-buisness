//
//  PlaceHoursTests.swift
//  BlockPartyTests — a business page's hours row: open, closes soon, closed till, past midnight,
//  and the week list. Fixed Town clock and dates.
//
//  Reference weekdays (2026): Oct 24 = Sat, Oct 25 = Sun, Oct 26 = Mon, Oct 27 = Tue.
//

import XCTest
@testable import BlockParty

final class PlaceHoursTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    /// Monday closed, Tue–Thu 4–10 PM, Fri–Sat noon–1 AM, Sunday noon–8 PM.
    private let brewery = try! JSONDecoder().decode(PlaceHours.self, from: Data("""
    {"sun": [["12:00","20:00"]], "mon": [], "tue": [["16:00","22:00"]], "wed": [["16:00","22:00"]],
     "thu": [["16:00","22:00"]], "fri": [["12:00","01:00"]], "sat": [["12:00","01:00"]]}
    """.utf8))

    private func words(_ date: Date, _ hours: PlaceHours? = nil) -> String? {
        (hours ?? brewery).status(at: date, calendar: cal).map(PlaceHours.words)
    }

    func testOpenSaysWhenItCloses() {
        XCTAssertEqual(words(at(25, 14)), "Open till 8 PM")
    }

    func testLastHalfHourClosesSoon() {
        XCTAssertEqual(words(at(25, 19, 30)), "Closes soon · 8 PM")
        XCTAssertEqual(words(at(25, 19, 29)), "Open till 8 PM")
    }

    func testPastMidnightStillOpenFromYesterday() {
        // Sunday 12:40 AM, inside Saturday's noon–1 AM.
        XCTAssertEqual(words(at(25, 0, 40)), "Closes soon · 1 AM")
        XCTAssertEqual(words(at(24, 23)), "Open till 1 AM")
    }

    func testClosedLaterTodaySaysOnlyTheTime() {
        XCTAssertEqual(words(at(25, 9)), "Closed till 12 PM")
    }

    func testClosedDayNamesTheDay() {
        // Sunday 9 PM: Monday is closed, so Tuesday 4 PM.
        XCTAssertEqual(words(at(25, 21)), "Closed till Tue 4 PM")
        XCTAssertEqual(words(at(26, 13)), "Closed till Tue 4 PM")
    }

    func testClosedOvernightTillMorningSaysOnlyTheTime() {
        let shop = PlaceHours(days: Array(repeating: [9 * 60 ..< 17 * 60], count: 7))
        XCTAssertEqual(words(at(25, 18), shop), "Closed till 9 AM")
        XCTAssertEqual(words(at(25, 17), shop), "Closed till 9 AM")
    }

    func testAlwaysOpenAndNeverOpen() {
        XCTAssertEqual(words(at(25, 3), PlaceHours(days: Array(repeating: [0 ..< 1440], count: 7))), "Open 24 hours")
        XCTAssertNil(words(at(25, 3), PlaceHours(days: Array(repeating: [], count: 7))))
    }

    func testBadTimesAreDropped() throws {
        let hours = try JSONDecoder().decode(PlaceHours.self, from: Data(#"{"mon": [["9am","17:00"]], "tue": [["09:30","17:00"]]}"#.utf8))
        XCTAssertEqual(hours.days[1], [])
        XCTAssertEqual(hours.days[2], [570 ..< 1020])
    }

    func testWeekStartsTodayInWords() {
        let week = brewery.week(from: at(24, 12), calendar: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week[0].day, "Saturday")
        XCTAssertTrue(week[0].today)
        XCTAssertEqual(week[0].hours, "12 PM – 1 AM")
        XCTAssertEqual(week[1].hours, "12 – 8 PM")
        XCTAssertEqual(week[2].hours, "Closed")
        XCTAssertEqual(PlaceHours.line([570 ..< 1020]), "9:30 AM – 5 PM")
    }
}
