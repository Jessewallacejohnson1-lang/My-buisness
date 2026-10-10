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
          "created_at":"2026-10-06T16:08:20.123+00:00","going_count":2,
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

    /// The clock moves only once the read is done. The feed's leave timer is keyed on
    /// `nextLeave`, which the clock decides: moved first, it cancelled the timer's own
    /// read, so a series' next date never came in.
    func testTheClockMovesOnlyOnceTheReadIsDone() async {
        final class Probe { var town: TownFeed?; var clockDuringRead: Date? }
        let probe = Probe()
        let town = TownFeed {
            probe.clockDuringRead = probe.town?.clock
            return [TownFeed.entry(self.row("a"), signedIn: true)]
        }
        probe.town = town
        let before = town.clock
        await town.reload(at: now)
        XCTAssertEqual(probe.clockDuringRead, before)
        XCTAssertEqual(town.clock, now)
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
        XCTAssertTrue(town.failed, "a failed refresh over a list says it's offline")
        XCTAssertEqual(town.cards.map(\.id), ["a"])
    }

    // MARK: When the order changes (ticket 11)

    private func entries(_ ids: [String], going: Int = 0) -> [TownFeedEntry] {
        ids.map { TownFeed.entry(row($0, going: going), signedIn: true) }
    }

    /// A feed whose reads answer in turn.
    private func feed(answers: [[TownFeedEntry]], kept: [TownFeedEntry]? = nil) -> TownFeed {
        var answers = answers
        return TownFeed(read: { answers.removeFirst() }, kept: { kept })
    }

    /// Back within 30 minutes, the order on screen stays: cards update in place, a
    /// card that went drops out, and a new one waits for the next fresh order.
    func testBackSoonKeepsTheOrderOnScreen() async {
        let town = feed(answers: [entries(["a", "b", "c"]),
                                  entries(["new", "c", "a"], going: 5)])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.atTop = false
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(29 * 60))
        await town.refresh(at: now.addingTimeInterval(29 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "c"])
        XCTAssertEqual(town.cards.map(\.goingCount), [5, 5])
    }

    /// Back after 30 minutes or more, still at the top: the fresh order.
    func testBackAfterHalfAnHourAtTheTopTakesTheFreshOrder() async {
        let town = feed(answers: [entries(["a", "b"]), entries(["new", "b", "a"])])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(30 * 60))
        await town.refresh(at: now.addingTimeInterval(30 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["new", "b", "a"])
    }

    /// Already scrolling when the fresh order lands: it waits for the next pull, so
    /// nothing moves under the finger.
    func testAFreshOrderWaitsForAPullOnceTheScreenHasScrolled() async {
        let town = feed(answers: [entries(["a", "b"]), entries(["new", "b", "a"]),
                                  entries(["new", "b", "a"])])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(60 * 60))
        town.atTop = false
        await town.refresh(at: now.addingTimeInterval(60 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "b"])

        await town.reload(at: now.addingTimeInterval(60 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["new", "b", "a"])
    }

    /// A launch shows the list kept on the phone at once, before its read answers,
    /// then the fresh order (a launch counts as long away).
    func testALaunchShowsTheKeptListAtOnceThenTheFreshOrder() async {
        final class Probe { var town: TownFeed?; var shownDuringRead: [String]? }
        let probe = Probe()
        let town = TownFeed(read: {
            probe.shownDuringRead = probe.town?.cards.map(\.id)
            return self.entries(["new", "a"])
        }, kept: { self.entries(["a"]) })
        probe.town = town
        town.cameBack(at: now)
        await town.refresh(at: now)
        XCTAssertEqual(probe.shownDuringRead, ["a"])
        XCTAssertEqual(town.cards.map(\.id), ["new", "a"])
    }

    /// Offline at launch: the kept list stays and the feed says it's offline. A kept
    /// list with nothing still on shows the skeleton, not an empty feed.
    func testOfflineAtLaunchKeepsTheKeptList() async {
        let offline = TownFeed(read: { throw Offline() }, kept: { self.entries(["a"]) })
        await offline.refresh(at: now)
        XCTAssertEqual(offline.cards.map(\.id), ["a"])
        XCTAssertTrue(offline.failed)

        let gone = [TownFeed.entry(row("old", leavesIn: -1), signedIn: true)]
        let stale = TownFeed(read: { throw Offline() }, kept: { gone })
        await stale.refresh(at: now)
        XCTAssertNil(stale.entries)
    }

    /// Back within 30 minutes it lands on the card it left; after, from the top.
    func testComingBackLandsOnTheCardItLeftUnlessLongAway() {
        let town = feed(answers: [])
        town.cameBack(at: now)
        town.topCardID = "c"
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(town.topCardID, "c")

        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(45 * 60))
        XCTAssertNil(town.topCardID)
    }

    /// One kept list per account, since it holds that person's Going: saving one
    /// removes another's.
    func testTheKeptListBelongsToOneAccount() {
        TownFeedCache.save(Data("[1]".utf8), for: "test-person-1")
        XCTAssertEqual(TownFeedCache.load(for: "test-person-1"), Data("[1]".utf8))
        XCTAssertNil(TownFeedCache.load(for: "test-person-2"))

        TownFeedCache.save(Data("[2]".utf8), for: "test-person-2")
        XCTAssertNil(TownFeedCache.load(for: "test-person-1"))
        XCTAssertEqual(TownFeedCache.load(for: "test-person-2"), Data("[2]".utf8))
    }
}
