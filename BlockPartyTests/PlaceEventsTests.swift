//
//  PlaceEventsTests.swift
//  BlockPartyTests — a place's Events on its business page (BP app place-pages 05): which of the calendar's are the
//  place's, the list by day (profile-left 05), the months its arrows reach, and the day picked first and on an arrow.
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

    private func event(_ id: String, _ date: String, _ time: String = "6:30 PM", title: String? = nil) -> DailyEvent {
        YouCalendar.event(from: UpcomingEvent(id: id, title: title ?? id, eventDate: date, startTime: time,
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

    /// The list (profile-left 05) at 7 PM on Monday the 16th: tomorrow's bingo leads under "Tomorrow / Tuesday", then the
    /// 28th's two under "Nov 28 / Saturday", then January's; the 3rd and the 13th are over.
    func testTheListByDay() {
        let now = town("2026-11-16 19:00")
        let days = PlaceEvents.days(PlaceEvents.rows(PlaceEvents.events(calendar, ids: sals), now: now))
        XCTAssertEqual(days.map { $0.rows.map(\.event.id) }, [["bingo-17"], ["market-28", "band-28"], ["feed-jan"]])
        XCTAssertEqual(days.map { PlaceEvents.title($0.day, now: now).day }, ["Tomorrow", "Nov 28", "Jan 8"])
        XCTAssertEqual(days.map { PlaceEvents.title($0.day, now: now).weekday }, ["Tuesday", "Saturday", "Friday"])
        XCTAssertEqual(PlaceEvents.title(day("2026-11-16"), now: now).day, "Today")
        XCTAssertEqual(PlaceEvents.title(day("2026-11-16"), now: now).weekday, "Monday")
    }

    /// An Event leaves the list once it's over, not when it starts: at 7 PM the 6:30 PM bingo is still on.
    func testAnEventThatsOverLeaves() {
        let events = PlaceEvents.events(calendar, ids: sals)
        XCTAssertEqual(PlaceEvents.rows(events, now: town("2026-11-17 19:00")).first?.event.id, "bingo-17")
        XCTAssertEqual(PlaceEvents.rows(events, now: town("2026-11-17 20:31")).first?.event.id, "market-28")
        XCTAssertTrue(PlaceEvents.rows(events, now: day("2027-02-01")).isEmpty)
        XCTAssertTrue(PlaceEvents.rows(PlaceEvents.events(calendar, ids: []), now: today).isEmpty)
    }

    /// Ten rows, then See all: twelve Events show their first ten, a day cut short keeping the ones that fit; ten
    /// or fewer have no See all.
    func testTenThenSeeAll() {
        // Two a day from the 17th: the 22nd's second one is the 11th row.
        let twelve = (0..<12).map { event("e\($0)", "2026-11-\(17 + $0 / 2)", $0 % 2 == 0 ? "1 PM" : "7 PM") }
        let rows = PlaceEvents.rows(twelve, now: today)
        XCTAssertTrue(PlaceEvents.seeAll(rows))
        let first = PlaceEvents.days(rows, limit: PlaceEvents.shown)
        XCTAssertEqual(first.flatMap(\.rows).map(\.event.id), (0..<10).map { "e\($0)" })
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(PlaceEvents.days(rows).flatMap(\.rows).count, 12)
        XCTAssertFalse(PlaceEvents.seeAll(Array(rows.prefix(10))))

        XCTAssertEqual(PlaceEvents.days(rows, limit: 3).map { $0.rows.map(\.event.id) }, [["e0", "e1"], ["e2"]])
    }

    /// A repeat (profile-left 06) is the same title, letter case aside, at the same start time: at 7 PM on the 16th
    /// that day's 8:30 Mass is over, so Mass shows once on the 17th with the 18th, 19th and 20th ("mass") as its more
    /// dates; the 5 PM Mass is its own row, and Bingo between them keeps its place.
    func testARepeatShowsOnceAtItsNextDate() {
        let church = [event("m16", "2026-11-16", "8:30 AM", title: "Mass"), event("m17", "2026-11-17", "8:30 AM", title: "Mass"),
                      event("bingo", "2026-11-17", "7 PM", title: "Bingo"), event("m18", "2026-11-18", "8:30 AM", title: "Mass"),
                      event("m19", "2026-11-19", "8:30 AM", title: "Mass"), event("m20", "2026-11-20", "8:30 AM", title: "mass"),
                      event("vigil", "2026-11-21", "5 PM", title: "Mass")]
        let rows = PlaceEvents.rows(church, now: town("2026-11-16 19:00"))
        XCTAssertEqual(rows.map(\.event.id), ["m17", "bingo", "vigil"])
        XCTAssertEqual(rows.map { $0.more.map(\.id) }, [["m18", "m19", "m20"], [], []])
        XCTAssertEqual(PlaceEvents.days(rows).map { $0.rows.map(\.event.id) }, [["m17", "bingo"], ["vigil"]])
        XCTAssertEqual(rows.map { PlaceEvents.moreDates($0.more.count) }, ["+3 more dates", nil, nil])
        XCTAssertEqual(PlaceEvents.moreDates(1), "+1 more date")
        // Once the 17th's is over, Mass shows on the 18th, after that evening's Bingo, with two more.
        let later = PlaceEvents.rows(church, now: town("2026-11-17 12:00"))
        XCTAssertEqual(later.map(\.event.id), ["bingo", "m18", "vigil"])
        XCTAssertEqual(later[1].more.map(\.id), ["m19", "m20"])
    }

    /// The ten rows before See all are counted after the fold: thirty daily Masses and nine others are ten rows;
    /// one more Event makes eleven, and See all.
    func testTenCountedAfterTheFold() {
        let masses = (0..<30).map { offset in
            let date = PlaceEvents.calendar.date(byAdding: .day, value: offset, to: day("2026-11-17"))!
            return event("m\(offset)", Town.day(date), "8:30 AM", title: "Mass")
        }
        let others = (0..<9).map { event("e\($0)", "2026-11-\(17 + $0)", "7 PM") }
        let all = masses + others
        let rows = PlaceEvents.rows(PlaceEvents.events(all, ids: Set(all.map(\.id))), now: today)
        XCTAssertEqual(rows.count, 10)
        XCTAssertEqual(rows.first?.more.count, 29)
        XCTAssertFalse(PlaceEvents.seeAll(rows))
        let eleven = all + [event("e9", "2026-11-30")]
        XCTAssertTrue(PlaceEvents.seeAll(PlaceEvents.rows(PlaceEvents.events(eleven, ids: Set(eleven.map(\.id))), now: today)))
    }

    /// The price tag: "Free", "No cover" or one dollar amount, ten letters at most; anything else, none.
    func testThePriceTag() {
        for (price, tag) in [("Free", "Free"), ("free", "Free"), ("No cover", "No cover"), ("$50", "$50"),
                             ("$5 cover", "$5 cover"), ("$2 tickets", "$2 tickets"), (" $49 ", "$49")] {
            XCTAssertEqual(PlaceEvents.priceTag(price), tag, price)
        }
        for price in [nil, "", "Free admission", "$40 a person", "$49 in advance, $60 at the door", "$10-$15",
                      "Free will offering", "Donations appreciated", "$35, down from $54.99", "Tickets $5"] {
            XCTAssertNil(PlaceEvents.priceTag(price), price ?? "nil")
        }
    }

    /// The place is said only when it isn't this one: its name, a room in it, "St." for "Saint", "&" for "and" and
    /// letter case all count as here.
    func testThePlaceSaidOnlyWhenElsewhere() {
        XCTAssertNil(PlaceEvents.elsewhere("Bad Habit Brewing", place: "Bad Habit Brewing"))
        XCTAssertNil(PlaceEvents.elsewhere("Bad Habit Brewing, Brewer’s Lounge", place: "Bad Habit Brewing"))
        XCTAssertNil(PlaceEvents.elsewhere("Church of St. Joseph", place: "Church of Saint Joseph"))
        XCTAssertNil(PlaceEvents.elsewhere("sal's bar and grill", place: "Sal's Bar & Grill"))
        XCTAssertNil(PlaceEvents.elsewhere(nil, place: "Bad Habit Brewing"))
        XCTAssertNil(PlaceEvents.elsewhere(" ", place: "Bad Habit Brewing"))
        XCTAssertEqual(PlaceEvents.elsewhere("Lake Sarah Park", place: "Bad Habit Brewing"), "Lake Sarah Park")
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
