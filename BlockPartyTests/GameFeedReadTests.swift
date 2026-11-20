//
//  GameFeedReadTests.swift
//  BlockPartyTests
//
//  A live game read from the Town feed (BP app backlog 37). PostgREST's reader (`Supabase.decode`) turns
//  `clock_s`, `period_n` and `period_s` into `clockS`, `periodN` and `periodS`; a live update's plain reader
//  leaves them. A game reads them either way, so the soccer minute and the basketball and hockey bars show
//  from the feed's first read, not only after the first live update.
//

import XCTest
@testable import BlockParty

final class GameFeedReadTests: XCTestCase {
    /// One live game, read as a live update reads it and as the Town feed reads it: inside its row, through
    /// `Supabase.decode`.
    private func both(_ live: String, sport: String) throws -> (update: Game, feed: Game) {
        let game = #"{"sport":"\#(sport)","teams":[{"name":"Saint John's"},{"name":"Augsburg"}],"live":\#(live)}"#
        let update = try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(game.utf8)).value)
        let row = #"""
        {"id":"g1","title":"\#(sport)","event_date":"2026-11-20","start_time":"7 PM","going_count":0,
         "created_at":"2026-11-01T16:00:00+00:00","game":\#(game)}
        """#
        let feed = try XCTUnwrap(try Supabase.decode(Data(row.utf8), as: UpcomingEvent.self).game)
        return (update, feed)
    }

    private let basketball = #"""
    {"score":[34,29],"period":"Q2","clock":"2:30","clock_s":150,"complete":false,"at":"2026-11-07T20:30:00Z",
     "period_n":2,"regulation":4,"period_s":600}
    """#

    func testSoccersMinuteReadsFromTheFeed() throws {
        let (update, feed) = try both(#"""
        {"score":[1,0],"period":"1st half","clock":"23'","clock_s":1330,"complete":false,"at":"2026-11-03T20:30:00Z"}
        """#, sport: "Soccer")
        let live = try XCTUnwrap(feed.live)
        XCTAssertEqual(live.seconds, 1330)
        XCTAssertEqual(live.minute(at: try XCTUnwrap(live.at)), 23, "the minute ring from the first read")
        XCTAssertEqual(feed.live, update.live, "the feed reads what a live update reads")
    }

    func testBasketballsBarReadsFromTheFeed() throws {
        let (update, feed) = try both(basketball, sport: "Basketball")
        XCTAssertEqual(feed.live?.barFill, [1, 0.75, 0, 0], "Q2 with 2:30 left")
        XCTAssertEqual(feed.live, update.live)
    }

    /// Hockey's period number reads from the feed, so a power play ends at 2:00 there too; a clock at 0 (a period
    /// just over, as the server sends it) is 0, not none.
    func testHockeysPeriodAndAClockAtZeroReadFromTheFeed() throws {
        let (update, feed) = try both(#"""
        {"score":[2,1],"period":"P1","clock":"13:20","clock_s":800,"complete":false,"at":"2026-11-06T20:30:00Z",
         "period_n":1,"ice":{"saves":[[],[]],"power":[{"side":0,"start":true,"at":100}]}}
        """#, sport: "Hockey")
        XCTAssertEqual(feed.live?.periodNumber, 1)
        XCTAssertNil(feed.live?.powerPlay, "a penalty from 5:00 ago has run out")
        XCTAssertEqual(feed.live, update.live)
        let (endUpdate, endFeed) = try both(#"""
        {"score":[2,1],"period":"P1","clock":"0:00","clock_s":0,"complete":false,"at":"2026-11-06T20:45:00Z",
         "period_n":1,"ice":{"saves":[[],[]],"power":[]}}
        """#, sport: "Hockey")
        XCTAssertEqual(endFeed.live?.seconds, 0)
        XCTAssertEqual(endFeed.live, endUpdate.live)
    }

    /// The feed reads again after a live update with the same time: the feed's game wins the tie
    /// (`LiveGames.newer`), and it keeps the bar.
    func testAFeedRefreshAfterALiveUpdateKeepsTheBar() throws {
        let (update, feed) = try both(basketball, sport: "Basketball")
        XCTAssertEqual(LiveGames.newer(update, feed)?.live?.barFill, [1, 0.75, 0, 0])
    }
}
