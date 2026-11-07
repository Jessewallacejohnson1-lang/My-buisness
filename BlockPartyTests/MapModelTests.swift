//
//  MapModelTests.swift
//  BlockPartyTests — when the map reads (`MapModel`, BP app codebase-health 31): a live score
//  moves nothing and a final reads the Town feed again; each event's spot is read once and a
//  failed read is asked again at the next change; only today's cards go on the map, and
//  midnight rolls the day over and reads again.
//

import CoreLocation
import XCTest
@testable import BlockParty

@MainActor
final class MapModelTests: XCTestCase {

    private let spot = CLLocationCoordinate2D(latitude: 45.5644264, longitude: -94.320549)
    /// The map's clock: 2026-11-07 at 6 PM in the Town, unless a test moves it.
    private lazy var clock = Town.midnight("2026-11-07")!.addingTimeInterval(18 * 3600)
    /// Every spot read, by the ids it asked for. The first `failing` reads throw.
    private var spotReads: [[String]] = []
    private var failing = 0
    private lazy var model = MapModel(readSpots: { [unowned self] ids in
        self.spotReads.append(ids)
        if self.failing > 0 { self.failing -= 1; throw URLError(.notConnectedToInternet) }
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, self.spot) })
    }, now: { [unowned self] in self.clock })

    /// The Town feed, counting its reads.
    private var cards: [FeedCardItem] = []
    private var feedReads = 0
    private lazy var feed = TownFeed(read: { [unowned self] in
        self.feedReads += 1
        return self.cards.map { TownFeedEntry(card: $0, leavesAt: .distantFuture) }
    })
    /// The app's one `club_events` connection, faked: `changed` hands the map a change.
    private let live = LiveGames(listen: { _ in })

    private func card(_ id: String, on day: String = "2026-11-07") -> FeedCardItem {
        var card = FeedCardItem(id: id, title: id, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isSaved: false, isJoined: false)
        card.eventDate = day
        return card
    }

    /// Today's game as a realtime row carries it: its live score, and its final once in.
    private func game(live: String, final: [Int]? = nil) -> RealtimeClient.Change.Row {
        RealtimeClient.Change.Row(id: "game", eventDate: "2026-11-07", startTime: "19:00:00", status: "approved",
                                  kind: "event", title: "SJU vs Gustavus", location: "Clemens Stadium",
                                  finalScore: final, liveScore: Data(live.utf8))
    }

    /// The map opens on a Town feed already read, as it does from the Town bar, so its own read
    /// at start can't stand in for the one a test waits for.
    private func open() async {
        await feed.refresh()
        model.start(auth: AuthStore(), feed: feed, live: live)
    }

    /// Waits until `done` holds, up to 10 s: the map's reads run in their own tasks.
    private func until(_ done: () -> Bool) async {
        let end = Date().addingTimeInterval(10)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// A live score coming in moves nothing on the map; a final does, since the game's bubble goes.
    func testAScoreReadsNothingAndAFinalReadsAgain() async {
        cards = [card("game")]
        await open()
        defer { model.stop() }
        let reads = feedReads
        live.changed(RealtimeClient.Change(kind: .update, new: game(live: "14-7"), old: game(live: "7-7")))
        try? await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(feedReads, reads, "a score alone reads nothing")
        live.changed(RealtimeClient.Change(kind: .update, new: game(live: "21-10", final: [21, 10]),
                                           old: game(live: "14-7")))
        await until { self.feedReads > reads }
        XCTAssertEqual(feedReads, reads + 1, "a final reads the Town feed again")
    }

    /// An event's spot is read the first time its card shows. A failed read turns on the map's
    /// try-again pill and is asked again at the next change; a spot found is never read again.
    func testEachSpotIsReadOnceAndAFailedReadIsAskedAgain() async {
        failing = 1
        model.show([card("bingo")])
        await until { self.model.spotsFailed }
        XCTAssertTrue(model.spotsFailed, "the pill offers to try again")
        XCTAssertTrue(model.today.spots.isEmpty)

        model.show([card("bingo")])
        await until { !self.model.today.spots.isEmpty }
        XCTAssertFalse(model.spotsFailed)
        XCTAssertEqual(spotReads, [["bingo"], ["bingo"]], "asked again at the next change")

        model.show([card("bingo"), card("raffle")])
        await until { self.model.today.spots.count == 2 }
        XCTAssertEqual(spotReads, [["bingo"], ["bingo"], ["raffle"]], "only the new card's spot is read")
    }

    /// Only cards dated today go on the map, and only their spots are read.
    func testACardDatedTomorrowStaysOff() async {
        model.show([card("bingo"), card("parade", on: "2026-11-08")])
        XCTAssertEqual(model.today.events.map(\.id), ["bingo"])
        await until { !self.model.today.spots.isEmpty }
        XCTAssertEqual(spotReads, [["bingo"]], "tomorrow's spot isn't read")
    }

    /// Midnight rolls the map over to the new day and reads the Town feed again, with no one
    /// touching it: tomorrow's card goes on.
    func testMidnightRollsTheDayOverAndReadsAgain() async {
        cards = [card("bingo"), card("parade", on: "2026-11-08")]
        clock = Town.midnight("2026-11-08")!.addingTimeInterval(-0.1)
        await open()
        defer { model.stop() }
        XCTAssertEqual(model.today.events.map(\.id), ["bingo"])
        let reads = feedReads
        clock = Town.midnight("2026-11-08")!.addingTimeInterval(2)
        await until { self.model.today.events.map(\.id) == ["parade"] }
        XCTAssertEqual(model.today.events.map(\.id), ["parade"], "the new day's card is on")
        XCTAssertEqual(feedReads, reads + 1, "midnight reads the Town feed again")

        // The changes it follows roll over too: a new event on the new day reads again.
        let rolled = feedReads
        live.changed(RealtimeClient.Change(kind: .insert, new: RealtimeClient.Change.Row(
            id: "new", eventDate: "2026-11-08", startTime: nil, status: "approved", kind: "event",
            title: nil, location: nil), old: nil))
        await until { self.feedReads > rolled }
        XCTAssertEqual(feedReads, rolled + 1, "a new event on the new day reads again")
    }
}
