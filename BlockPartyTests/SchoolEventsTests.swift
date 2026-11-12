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
        SchoolEvent(id: id, title: "Event \(id)", date: date, time: time, location: nil, symbol: "basketball")
    }

    func testTheCardOpensOnTodayWhenTodayHasAnEvent() {
        let events = [event("a", "2026-11-11"), event("b", "2026-11-12")]
        XCTAssertEqual(SchoolEvents.opening(events, now: now), .today)
    }

    func testTheCardOpensOnUpcomingWhenTodayHasNone() {
        XCTAssertEqual(SchoolEvents.opening([event("a", "2026-11-10"), event("b", "2026-11-12")], now: now), .upcoming)
        XCTAssertEqual(SchoolEvents.opening([], now: now), .upcoming)
    }

    func testEveryActivitysEventsBecomeOneListSoonestFirst() {
        let basketball = [event("game", "2026-11-12", "4 PM"), event("shared", "2026-11-16", "4:15 PM")]
        let knowledgeBowl = [event("meet", "2026-11-12", "9 AM"), event("shared", "2026-11-16", "4:15 PM"),
                             event("banquet", "2026-11-12", nil)]
        XCTAssertEqual(SchoolEvents.merged([basketball, knowledgeBowl]).map(\.id), ["meet", "game", "banquet", "shared"])
    }

    func testEachSegmentShowsItsOwnDaysUnderTheirDate() {
        let events = [event("last", "2026-11-10"), event("now", "2026-11-11"), event("a", "2026-11-12"),
                      event("b", "2026-11-12", "5 PM"), event("c", "2026-11-16")]
        func shown(_ day: SchoolDay) -> [String] {
            SchoolEvents.days(events, on: day, now: now).map { "\($0.date): " + $0.events.map(\.id).joined(separator: ",") }
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

    func testUpcomingShowsTheNextFiveAsTheMockDoes() {
        let events = (12...18).map { event("d\($0)", "2026-11-\($0)") }
        let shown = SchoolEvents.days(events, on: .upcoming, now: now).flatMap(\.events).map(\.id)
        XCTAssertEqual(shown, ["d12", "d13", "d14", "d15", "d16"])
    }
}
