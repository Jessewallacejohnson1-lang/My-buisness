//
//  SchoolEventsTests.swift
//  BlockPartyTests — a school's page (BP app school-search 05): its events card's Yesterday, Today and
//  Upcoming, and the top folding into the bar on scroll.
//

import XCTest
@testable import BlockParty

final class SchoolEventsTests: XCTestCase {
    /// Wednesday 2026-11-11, 3 PM in St. Joseph.
    private let now = Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!

    private func event(_ id: String, _ date: String, _ time: String? = "4 PM") -> SchoolEvent {
        SchoolEvent(id: id, title: "Event \(id)", day: Town.midnight(date)!, time: time, location: nil, symbol: "basketball")
    }

    func testTheCardOpensOnTodayWhenTodayHasAnEvent() {
        let events = [event("a", "2026-11-11"), event("b", "2026-11-12")]
        XCTAssertEqual(SchoolEvents.opening(events, now: now), .today)
    }

    func testTheCardOpensOnUpcomingWhenTodayHasNone() {
        XCTAssertEqual(SchoolEvents.opening([event("a", "2026-11-10"), event("b", "2026-11-12")], now: now), .upcoming)
        XCTAssertEqual(SchoolEvents.opening([], now: now), .upcoming)
    }

    /// The server sorts a time as words ("10 AM" before "9 AM"): the card sorts by the clock, one it can't read last
    /// on its day, two at one time in the server's order (the activities').
    func testTheSchoolsEventsSoonestFirst() {
        let events = [event("game", "2026-11-12", "4 PM"), event("banquet", "2026-11-12", nil),
                      event("late", "2026-11-12", "10 AM"), event("meet", "2026-11-12", "9 AM"),
                      event("bowl", "2026-11-12", "4 PM"), event("next", "2026-11-16", "8 AM")]
        XCTAssertEqual(SchoolEvents.sorted(events).map(\.id), ["meet", "late", "game", "bowl", "banquet", "next"])
    }

    func testEachSegmentShowsItsOwnDaysUnderTheirDate() {
        let events = [event("last", "2026-11-10"), event("now", "2026-11-11"), event("a", "2026-11-12"),
                      event("b", "2026-11-12", "5 PM"), event("c", "2026-11-16")]
        func shown(_ day: SchoolDay) -> [String] {
            SchoolEvents.days(events, on: day, now: now).map { "\(Town.day($0.day)): " + $0.events.map(\.id).joined(separator: ",") }
        }
        XCTAssertEqual(shown(.yesterday), ["2026-11-10: last"])
        XCTAssertEqual(shown(.today), ["2026-11-11: now"])
        XCTAssertEqual(shown(.upcoming), ["2026-11-12: a,b", "2026-11-16: c"])
    }

    func testTheTopFoldsIntoTheBarOverNinetyPoints() {
        XCTAssertEqual(SchoolFold.progress(-40), 0, "a pull down leaves it open")
        XCTAssertEqual(SchoolFold.progress(0), 0)
        XCTAssertEqual(SchoolFold.progress(45), 0.5)
        XCTAssertEqual(SchoolFold.progress(90), 1)
        XCTAssertEqual(SchoolFold.progress(400), 1)
        XCTAssertEqual(SchoolFold.topScale(1), 0.75)
    }

    func testTheBarsTitleComesInOverTheFoldsLastStretch() {
        XCTAssertEqual(SchoolFold.titleOpacity(0.5), 0)
        XCTAssertEqual(SchoolFold.titleOpacity(0.7), 0)
        XCTAssertEqual(SchoolFold.titleOpacity(0.85), 0.5, accuracy: 0.001)
        XCTAssertEqual(SchoolFold.titleOpacity(1), 1)
    }

    func testTheBarsGlassIsTheSchoolsColourBrightened() {
        XCTAssertEqual(TeamPage.brighter(0x1B2859, by: 2), 0x3650B2, "Kennedy's navy, the mock's glass")
        XCTAssertEqual(TeamPage.brighter(0xA0A0A0, by: 2), 0xFFFFFF, "no channel past full")
    }

    /// Upcoming shows every coming event the reads found: no ticket asks for a cap (the run's review).
    func testUpcomingShowsEveryComingEvent() {
        let events = (12...18).map { event("d\($0)", "2026-11-\($0)") }
        let shown = SchoolEvents.days(events, on: .upcoming, now: now).flatMap(\.events).map(\.id)
        XCTAssertEqual(shown, ["d12", "d13", "d14", "d15", "d16", "d17", "d18"])
    }

    /// Before "See all" the card shows its first five events, their days' headings kept (Jesse, 2026-11-12: "i agree
    /// to all", the next 5 with See all); a day cut in the middle keeps only the events that fit.
    func testBeforeSeeAllTheCardShowsTheFirstFiveEvents() {
        let events = [event("a", "2026-11-12"), event("b", "2026-11-12"), event("c", "2026-11-13"),
                      event("d", "2026-11-14"), event("e", "2026-11-14"), event("f", "2026-11-14"), event("g", "2026-11-15")]
        let days = SchoolEvents.days(events, on: .upcoming, now: now)
        let first = SchoolEvents.first(SchoolEvents.shown, of: days)
        XCTAssertEqual(first.flatMap(\.events).map(\.id), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(first.count, 3, "the 14th keeps its heading over the two that fit")
        XCTAssertEqual(SchoolEvents.first(SchoolEvents.shown, of: Array(days.prefix(2))).flatMap(\.events).count, 3,
                       "fewer than five: all of them, and no See all")
    }

    /// The card's days turn at the Town's midnight, whatever the phone's zone: tomorrow's game is Upcoming at
    /// 11:59 PM and Today a minute past midnight, so a card left open overnight moves it.
    func testTheDaysTurnAtTheTownsMidnight() {
        let game = [event("game", "2026-11-12")]
        let beforeMidnight = Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23, minute: 59))!
        let afterMidnight = beforeMidnight.addingTimeInterval(120)
        XCTAssertEqual(SchoolEvents.days(game, on: .upcoming, now: beforeMidnight).count, 1)
        XCTAssertEqual(SchoolEvents.days(game, on: .today, now: afterMidnight).count, 1)
        XCTAssertEqual(SchoolEvents.opening(game, now: afterMidnight), .today)
    }

    /// A title keeps its words but not the middle-school tag the mock leaves off: the school's page is its level.
    func testATitleDropsTheMiddleSchoolTag() {
        XCTAssertEqual(SchoolEvents.title("Girls Basketball vs Stride Academy · MS"), "Girls Basketball vs Stride Academy")
        XCTAssertEqual(SchoolEvents.title("Apollo Volleyball vs Brainerd · JV"), "Apollo Volleyball vs Brainerd · JV")
        XCTAssertEqual(SchoolEvents.title("MS Art Night"), "MS Art Night")
    }
}
