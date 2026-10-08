//
//  TownFeedEventsTests.swift
//  The Town feed (`TownFeed`): what `get_town_feed` sends becomes cards in its order,
//  the list survives a failed read, and a card goes when its time is up. What is in
//  the feed, when, and in what order are the function's, tested in
//  supabase/tests/town_feed.test.mjs.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownFeedEventsTests: XCTestCase {

    /// Noon on 2026-10-07, the Town's time.
    private let now = YourDayLogic.townDay("2026-10-07")!.addingTimeInterval(12 * 3600)

    private struct Offline: Error {}

    private func row(_ id: String, leavesIn hours: Double = 24, club: String? = nil,
                     source: String? = "City of St. Joseph", going: Int = 0,
                     recurrence: String? = nil) -> TownFeedRow {
        let event = UpcomingEvent(id: id, title: "Event \(id)", eventDate: "2026-10-12",
                                  startTime: "6 PM", location: nil, goingCount: going,
                                  createdAt: "2026-10-06T16:08:20+00:00", clubName: club,
                                  sourceName: source)
        return TownFeedRow(event: event, recurrence: recurrence,
                           leavesAt: now.addingTimeInterval(hours * 3600))
    }

    private func feed(_ rows: [TownFeedRow], signedIn: Bool = true) -> TownFeed {
        TownFeed { rows.map { TownFeed.entry($0, signedIn: signedIn) } }
    }

    /// The columns `get_town_feed` returns, as PostgREST sends them. A renamed column
    /// on either side fails here rather than emptying the feed.
    func testTheFunctionsRowsBecomeEventsWithTheirRepeatAndLeavingTime() throws {
        let json = """
        [{"id":"e1","title":"City Council Meeting","event_date":"2026-10-19","start_time":"6 PM",
          "location":"City Hall","image_url":null,"category":null,"club_name":null,
          "source_name":"City of St. Joseph","end_at":"2026-10-20T04:59:00+00:00","all_day":false,
          "shows_from":null,"created_at":"2026-10-06T16:08:20.123+00:00","going_count":2,
          "rsvpd":true,"recurrence":"Every 1st & 3rd Monday",
          "leaves_at":"2026-10-20T04:59:00+00:00"}]
        """
        let rows = try CommunityAPI.townFeedRows(from: Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].recurrence, "Every 1st & 3rd Monday")
        XCTAssertEqual(rows[0].leavesAt, DateHelpers.timestamp("2026-10-20T04:59:00Z"))
        XCTAssertEqual(rows[0].event.endAt, rows[0].leavesAt)
        XCTAssertEqual(rows[0].event.goingCount, 2)
        XCTAssertTrue(rows[0].event.rsvpd)

        let card = TownFeed.entry(rows[0], signedIn: true).card
        XCTAssertEqual(card.recurrence, "Every 1st & 3rd Monday")
        XCTAssertEqual(card.hostName, "City of St. Joseph")
    }

    func testAFoundEventIsHostedByItsSourceAndAClubEventByItsClub() async {
        let town = feed([row("a"), row("b", club: "Lions Club", source: nil)])
        await town.reload(at: now)
        XCTAssertEqual(town.cards.map(\.hostName), ["City of St. Joseph", "Lions Club"])
    }

    /// The database's order, untouched: the app never re-sorts.
    func testCardsKeepTheFunctionsOrder() async {
        let town = feed([row("later", leavesIn: 2), row("sooner", leavesIn: 48), row("going", leavesIn: 1)])
        await town.reload(at: now)
        XCTAssertEqual(town.cards.map(\.id), ["later", "sooner", "going"])
    }

    /// Signed out, RSVPs can't be read, so no "Nobody's going yet", and can't be
    /// written, so no Join (Jesse, 2026-10-07).
    func testSignedOutGetsNoJoin() async {
        let signedOut = feed([row("a", going: 3)], signedIn: false)
        await signedOut.reload(at: now)
        XCTAssertFalse(signedOut.cards[0].canJoin)

        let signedIn = feed([row("a", going: 3)])
        await signedIn.reload(at: now)
        XCTAssertEqual(signedIn.cards[0].goingSummary, "3 going")
        XCTAssertTrue(signedIn.cards[0].canJoin)
    }

    /// A card goes once its time is up, and the feed knows when to read again.
    func testACardLeavesWhenItsTimeIsUp() async {
        let town = feed([row("short", leavesIn: 1), row("long", leavesIn: 5)])
        await town.reload(at: now)
        XCTAssertEqual(town.cards.map(\.id), ["short", "long"])
        XCTAssertEqual(town.nextLeave, now.addingTimeInterval(3600))

        await town.reload(at: now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(town.cards.map(\.id), ["long"])
        XCTAssertEqual(town.nextLeave, now.addingTimeInterval(5 * 3600))
    }

    /// Skeleton until the first answer; a failed first read shows the retry; a failed
    /// refresh keeps the list already showing.
    func testAFailedReadKeepsTheListAlreadyShowing() async {
        var answers: [Result<[TownFeedEntry], Error>] = [
            .failure(Offline()),
            .success([TownFeed.entry(row("a"), signedIn: true)]),
            .failure(Offline()),
        ]
        let town = TownFeed { try answers.removeFirst().get() }
        XCTAssertNil(town.entries)

        await town.reload(at: now)
        XCTAssertTrue(town.failed)
        XCTAssertNil(town.entries)

        await town.reload(at: now)
        XCTAssertFalse(town.failed)
        XCTAssertEqual(town.cards.map(\.id), ["a"])

        await town.reload(at: now)
        XCTAssertFalse(town.failed)
        XCTAssertEqual(town.cards.map(\.id), ["a"])
    }
}
