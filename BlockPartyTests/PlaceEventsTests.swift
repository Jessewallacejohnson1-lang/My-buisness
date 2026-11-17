//
//  PlaceEventsTests.swift
//  BlockPartyTests — a place's Events on its business page (BP app place-pages 05): which of the calendar's are the
//  place's, the row's count and words, the months its arrows reach, and the day picked first and on an arrow.
//

import XCTest
@testable import BlockParty

@MainActor
final class PlaceEventsTests: XCTestCase {
    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func day(_ text: String) -> Date { town("\(text) 00:00") }

    private func event(_ id: String, _ date: String, _ time: String = "6:30 PM") -> DailyEvent {
        YouCalendar.event(from: UpcomingEvent(id: id, title: id, eventDate: date, startTime: time,
                                              location: "Sal's Bar & Grill", goingCount: 0, createdAt: ""))!
    }

    /// Sal's in November 2026, with another place's Event on its own day, read on Monday the 16th.
    private var calendar: [DailyEvent] {
        [event("bingo-3", "2026-11-03"), event("raffle-13", "2026-11-13", "5 PM"), event("other", "2026-11-17"),
         event("bingo-17", "2026-11-17"), event("market-28", "2026-11-28", "10 AM"), event("band-28", "2026-11-28", "7 PM"),
         event("feed-jan", "2027-01-08", "5 PM")]
    }

    private let sals: Set<String> = ["bingo-3", "raffle-13", "bingo-17", "market-28", "band-28", "feed-jan"]
    private var today: Date { day("2026-11-16") }

    /// Only the place's Events, in the calendar's order, past ones of this month kept for the faded days.
    func testOnlyThePlacesEvents() {
        let events = PlaceEvents.events(calendar.reversed(), ids: sals)
        XCTAssertEqual(events.map(\.id), ["bingo-3", "raffle-13", "bingo-17", "market-28", "band-28", "feed-jan"])
    }

    /// The row counts today and later only; with none it isn't drawn (count 0).
    func testTheRowCountsWhatsComingUp() {
        let events = PlaceEvents.events(calendar, ids: sals)
        XCTAssertEqual(PlaceEvents.coming(events, today: today), 4)
        XCTAssertEqual(PlaceEvents.coming(events, today: day("2027-02-01")), 0)
        XCTAssertEqual(PlaceEvents.coming(PlaceEvents.events(calendar, ids: []), today: today), 0)
        XCTAssertEqual(PlaceEvents.words(4).count + PlaceEvents.words(4).rest, "4 Events coming up")
        XCTAssertEqual(PlaceEvents.words(1).count + PlaceEvents.words(1).rest, "1 Event coming up")
    }

    /// The arrows reach only months with an Event, from this month on: December, with none, is skipped.
    func testTheMonthsSkipEmptyOnes() {
        let months = PlaceEvents.months(PlaceEvents.events(calendar, ids: sals), today: today)
        XCTAssertEqual(months.map(Town.day), ["2026-11-01", "2027-01-01"])
    }

    /// The next Event's day is picked first; an arrow lands on that month's first day with an Event from today on.
    func testTheDayPicked() {
        let events = PlaceEvents.events(calendar, ids: sals)
        XCTAssertEqual(PlaceEvents.next(events, today: today).map(Town.day), "2026-11-17")
        XCTAssertEqual(PlaceEvents.next(events, today: day("2026-11-17")).map(Town.day), "2026-11-17")
        XCTAssertEqual(PlaceEvents.landing(day("2027-01-01"), events: events, today: today).map(Town.day), "2027-01-08")
        XCTAssertEqual(PlaceEvents.landing(day("2026-11-01"), events: events, today: today).map(Town.day), "2026-11-17")
    }
}
