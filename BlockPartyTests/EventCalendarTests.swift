//
//  EventCalendarTests.swift
//  BlockPartyTests — Search's Event calendar (BP app five-tabs 10): a year one month at a time, how a month lays
//  out under its weekdays, the day order, the day card's arrows, which day a month lands on, and the model
//  keeping its list through a failed read.
//

import XCTest
@testable import BlockParty

@MainActor
final class EventCalendarTests: XCTestCase {
    /// A Town wall-clock moment, "2026-11-13 12:00".
    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func day(_ text: String) -> Date { town("\(text) 00:00") }

    private func row(_ id: String, _ date: String, _ time: String?, title: String? = nil) -> UpcomingEvent {
        UpcomingEvent(id: id, title: title ?? id, eventDate: date, startTime: time, location: "Klinefelter Park",
                      goingCount: 0, createdAt: "")
    }

    // MARK: The months

    /// This month and the 11 after it, each its 1st at Town midnight, across the new year.
    func testAYearFromThisMonth() {
        let months = EventCalendar.months(now: town("2026-11-13 12:00"))
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first.map(Town.day), "2026-11-01")
        XCTAssertEqual(months.map(Town.day)[2], "2027-01-01")
        XCTAssertEqual(months.last.map(Town.day), "2027-10-01")
        // Late on the last night of a month is still that month in the Town.
        XCTAssertEqual(EventCalendar.months(now: town("2026-11-30 23:59")).first.map(Town.day), "2026-11-01")
    }

    /// The 1st sits under its weekday, weeks from Sunday: Nov 1 2026 is a Sunday, Jan 1 2027 a Friday.
    func testAMonthSitsUnderItsWeekdays() {
        let november = EventCalendar.grid(day("2026-11-01"))
        XCTAssertEqual(november.count, 30)
        XCTAssertEqual(november.first.flatMap { $0 }.map(Town.day), "2026-11-01")
        let january = EventCalendar.grid(day("2027-01-01"))
        XCTAssertEqual(january.prefix(5).filter { $0 == nil }.count, 5)
        XCTAssertEqual(january[5].map(Town.day), "2027-01-01")
        XCTAssertEqual(january.compactMap { $0 }.count, 31)
        // February 2027 has 28 days, the day the clocks change in March is one day.
        XCTAssertEqual(EventCalendar.grid(day("2027-02-01")).compactMap { $0 }.count, 28)
        XCTAssertEqual(EventCalendar.grid(day("2027-03-01")).compactMap { $0 }.map(Town.day)[13], "2027-03-14")
        XCTAssertEqual(EventCalendar.days(EventCalendar.months(now: town("2026-11-13 12:00"))).count, 365)
    }

    // MARK: The days

    /// By day, a day's timed Events soonest first, then its untimed ones, then by title.
    func testADaysEventsInOrder() {
        let events = EventCalendar.ordered([
            row("supper", "2026-11-14", "5 PM"), row("fair", "2026-11-14", nil),
            row("bingo", "2026-11-13", "7 PM"), row("coffee", "2026-11-14", "8 AM"),
            row("auction", "2026-11-14", "5 PM"),
        ].compactMap(YouCalendar.event(from:)))
        XCTAssertEqual(events.map(\.id), ["bingo", "coffee", "auction", "supper", "fair"])
    }

    /// The day card's arrows go to the day before or after with Events, and stop at the ends.
    func testTheArrowsStepToDaysWithEvents() {
        let planned = ["2026-11-14", "2026-11-19", "2026-12-04"].map(day)
        XCTAssertEqual(EventCalendar.step(day("2026-11-14"), by: 1, planned: planned), day("2026-11-19"))
        XCTAssertEqual(EventCalendar.step(day("2026-11-15"), by: 1, planned: planned), day("2026-11-19"))
        XCTAssertEqual(EventCalendar.step(day("2026-11-19"), by: -1, planned: planned), day("2026-11-14"))
        XCTAssertNil(EventCalendar.step(day("2026-11-14"), by: -1, planned: planned))
        XCTAssertNil(EventCalendar.step(day("2026-12-04"), by: 1, planned: planned))
    }

    /// A month at rest keeps the picked day when it's in it, else today, else its first day with Events, else its 1st.
    func testAMonthLandsOnOneOfItsDays() {
        let today = day("2026-11-13")
        let planned = ["2026-11-19", "2026-12-04", "2027-01-15"].map(day)
        func land(_ month: String, picked: String) -> String {
            Town.day(EventCalendar.settle(day(month), picked: day(picked), today: today, planned: planned))
        }
        XCTAssertEqual(land("2026-11-01", picked: "2026-11-19"), "2026-11-19")
        XCTAssertEqual(land("2026-11-01", picked: "2026-12-04"), "2026-11-13")
        XCTAssertEqual(land("2026-12-01", picked: "2026-11-19"), "2026-12-04")
        XCTAssertEqual(land("2027-03-01", picked: "2027-01-15"), "2027-03-01")
    }

    /// Only the page on screen and the two beside it draw their photos (a year at once kept the month waiting).
    func testOnlyNearPagesDrawInFull() {
        let pages = ["2026-11-13", "2026-11-14", "2026-11-19", "2026-12-04"].map(day)
        XCTAssertTrue(EventCalendar.near(day("2026-11-14"), day("2026-11-13"), in: pages))
        XCTAssertTrue(EventCalendar.near(day("2026-11-13"), day("2026-11-13"), in: pages))
        XCTAssertFalse(EventCalendar.near(day("2026-11-19"), day("2026-11-13"), in: pages))
        XCTAssertFalse(EventCalendar.near(day("2026-11-20"), day("2026-11-13"), in: pages))
    }

    /// What VoiceOver reads on a day, in Search's own words.
    func testSpokenDays() {
        XCTAssertEqual(EventCalendar.spoken(day("2026-11-13"), events: 3, today: true), "Today, Friday, November 13, 3 Events")
        XCTAssertEqual(EventCalendar.spoken(day("2026-11-14"), events: 1, today: false), "Saturday, November 14, 1 Event")
        XCTAssertEqual(EventCalendar.spoken(day("2026-11-15"), events: 0, today: false), "Sunday, November 15, nothing on")
        XCTAssertEqual(EventCalendar.spoken(day("2026-11-15"), events: nil, today: false), "Sunday, November 15")
    }

    /// The pill sits right after All, opens on Events when typed into, and the calendar's read decodes as cards.
    func testThePillAndItsRead() throws {
        XCTAssertEqual(SearchChip.allCases.prefix(2), [.all, .calendar])
        XCTAssertEqual(SearchChip.calendar.title, "Event calendar")
        XCTAssertEqual(SearchChip.calendar.resultKinds, [.event])
        let data = Data(#"[{"card": {"id": "a", "title": "Bingo night", "event_date": "2026-11-17", "start_time": "7 PM", "going_count": 2, "created_at": ""}}, {"card": null}]"#.utf8)
        let rows = try CommunityAPI.myGoingRows(from: data)
        XCTAssertEqual(rows.map(\.title), ["Bingo night"])
    }
}
