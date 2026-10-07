//
//  TownFeedEventsTests.swift
//  The Town feed's real events (ADR-021): who a found event is from, when an event
//  starts showing, and what a signed-out neighbour is offered.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownFeedEventsTests: XCTestCase {

    /// Noon on 2026-10-07, the Town's time.
    private let now = YourDayLogic.townDay("2026-10-07")!.addingTimeInterval(12 * 3600)

    private func event(_ id: String, on date: String, at time: String? = "6 PM",
                       club: String? = nil, source: String? = "City of St. Joseph",
                       showsFrom: String? = nil, going: Int = 0) -> UpcomingEvent {
        UpcomingEvent(id: id, title: "Event \(id)", eventDate: date, startTime: time, location: nil,
                      goingCount: going, createdAt: "2026-10-06T16:08:20+00:00",
                      clubName: club, sourceName: source, showsFrom: showsFrom)
    }

    private func cards(_ events: [UpcomingEvent], signedIn: Bool = true) -> [FeedCardItem] {
        DailyFeedItem.town(events, now: now, signedIn: signedIn).compactMap {
            if case .event(let item, _) = $0 { return item }
            return nil
        }
    }

    func testAFoundEventIsHostedByItsSourceAndAClubEventByItsClub() {
        let hosts = cards([event("a", on: "2026-10-12"),
                           event("b", on: "2026-10-13", club: "Lions Club", source: nil)]).map(\.hostName)
        XCTAssertEqual(hosts, ["City of St. Joseph", "Lions Club"])
    }

    /// Two weeks ahead unless the event says otherwise, so a council that meets every
    /// other Monday shows its next meeting, not the rest of the season.
    func testAnEventShowsFromTwoWeeksAheadOrItsOwnDay() {
        let shown = cards([
            event("in-two-weeks", on: "2026-10-21"),
            event("in-three-weeks", on: "2026-10-28"),
            event("big-and-early", on: "2026-11-20", showsFrom: "2026-10-01"),
            event("not-yet", on: "2026-11-20", showsFrom: "2026-10-30"),
        ]).map(\.id)
        XCTAssertEqual(shown, ["in-two-weeks", "big-and-early"])
    }

    func testSoonestFirst() {
        let order = cards([
            event("evening", on: "2026-10-12", at: "6 PM"),
            event("morning", on: "2026-10-12", at: "11 AM"),
            event("earlier-day", on: "2026-10-10", at: "7 PM"),
        ]).map(\.id)
        XCTAssertEqual(order, ["earlier-day", "morning", "evening"])
    }

    /// Signed out, RSVPs can't be read, so no "Nobody's going yet", and can't be
    /// written, so no Join (Jesse, 2026-10-07).
    func testSignedOutGetsNoGoingLineAndNoJoin() {
        let out = cards([event("a", on: "2026-10-12", going: 3)], signedIn: false)[0]
        XCTAssertEqual(out.goingSummary, "")
        XCTAssertFalse(out.canJoin)

        let signedIn = cards([event("a", on: "2026-10-12", going: 3)])[0]
        XCTAssertEqual(signedIn.goingSummary, "3 going")
        XCTAssertTrue(signedIn.canJoin)
    }

    func testAnAllDayEventStaysUntilItsDayIsOver() {
        let ranked = DailyRanker.rank(DailyFeedItem.town([event("fare", on: "2026-10-07", at: nil)],
                                                         now: now, signedIn: true), now: now)
        XCTAssertEqual(ranked.map(\.id), ["event:fare"])
    }
}
