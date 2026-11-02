//
//  LiveGamesTests.swift
//  BlockPartyTests — Live games (BP app codebase-health-2 08): when the app listens for scores, and
//  which score a card and an Event page show, driven through a fake change stream.
//

import XCTest
@testable import BlockParty

@MainActor
final class LiveGamesTests: XCTestCase {
    /// The fake stream: every on and off the keeper asked for.
    private var calls: [Bool] = []
    private lazy var live = LiveGames(listen: { [unowned self] in self.calls.append($0) })

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    /// 2026-11-03 at `hour`:`minute` in the Town.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour, minute: minute))!
    }

    /// SJU vs Gustavus, with `more` after its teams (a live score, a final).
    private func game(_ more: String = "") throws -> Game {
        let json = #"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Gustavus"}]"# + more + "}"
        return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
    }

    /// `club_events.live_score` at `minute` past 7 PM, as a realtime row carries it.
    private func liveScore(_ score: [Int], _ minute: Int) -> String {
        #"{"score":[\#(score[0]),\#(score[1])],"period":"Q1","clock":"9:18","complete":false,"at":"2026-11-04T01:\#(String(format: "%02d", minute)):00Z"}"#
    }

    /// The game's Event card, starting at 7 PM on 2026-11-03.
    private func card(_ game: Game?, id: String = "g1") -> FeedCardItem {
        var event = UpcomingEvent(id: id, title: "SJU vs Gustavus", eventDate: "2026-11-03", startTime: "7:00 PM",
                                  location: "Clemens Stadium", goingCount: 0, createdAt: "")
        event.game = game
        return FeedCardItem(event)
    }

    /// A realtime UPDATE of the game's row: its scores, as the connection hands them on.
    private func change(_ id: String = "g1", final: [Int]? = nil, live: String? = nil,
                        plays: String? = nil) -> RealtimeClient.Change {
        let row = RealtimeClient.Change.Row(id: id, eventDate: "2026-11-03", startTime: "19:00:00", status: nil,
                                            kind: nil, title: nil, location: nil, finalScore: final,
                                            liveScore: live.map { Data($0.utf8) }, scoringPlays: plays.map { Data($0.utf8) })
        return RealtimeClient.Change(kind: .update, new: row, old: row.withoutScores)
    }

    func testAGameNotStartedDoesNotListenAndOneOnByItsHoursDoes() throws {
        live.hold("town", [card(try game())], at: at(18))
        XCTAssertEqual(calls, [], "an hour before kickoff, nothing")
        live.hold("town", [card(try game())], at: at(19, 5))
        XCTAssertEqual(calls, [true], "on by its hours")
        live.hold("town", [card(try game())], at: at(19, 10))
        XCTAssertEqual(calls, [true], "held again, still one connection")
    }

    func testAScoreAlreadyComingListensWhateverTheHours() throws {
        live.hold("town", [card(try game(#","live":"# + liveScore([7, 0], 18)))], at: at(12))
        XCTAssertTrue(live.listening)
    }

    func testAFinalStopsIt() throws {
        live.hold("town", [card(try game())], at: at(19, 30))
        live.changed(change(final: [21, 10]), at: at(21, 40))
        XCTAssertEqual(calls, [true, false])
        XCTAssertEqual(live.game(card(try game()))?.final, [21, 10])
        live.hold("town", [card(try game())], at: at(21, 45))
        XCTAssertEqual(calls, [true, false], "a read without the final can't start it again")
    }

    func testLettingGoOfTheLastScreenStopsIt() throws {
        live.hold("town", [card(try game())], at: at(19, 30))
        live.hold("page:1", [card(try game())], at: at(19, 31))
        live.hold("town", [], at: at(19, 32))
        XCTAssertEqual(calls, [true], "the page still shows it")
        live.hold("page:1", [], at: at(19, 33))
        XCTAssertEqual(calls, [true, false])
    }

    func testTheBackgroundStopsItAndComingBackStartsItAgain() throws {
        live.hold("page:1", [card(try game())], at: at(19, 30))
        live.away(true, at: at(19, 40))
        live.away(false, at: at(19, 50))
        XCTAssertEqual(calls, [true, false, true])
    }

    /// The Event page opened from You (or the bell, Saved, Daily), on a game no Town feed holds: its
    /// score comes in, the touchdown with it.
    func testAPageOpenedFromYouUpdates() throws {
        let opened = card(try game())
        live.hold("page:you", [opened], at: at(19, 5))
        XCTAssertTrue(live.listening)
        let play = #"[{"id":"1","text":"C. Kern 1 yd TD run (M. Olson kick)","period":"Q1","clock":"9:18","side":0,"score":[7,0]}]"#
        live.changed(change(live: liveScore([7, 0], 18), plays: play), at: at(19, 18))
        XCTAssertEqual(live.game(opened)?.live?.score, [7, 0])
        XCTAssertEqual(live.game(opened)?.plays.map(\.id), ["1"])
    }

    /// From You before ticket 01, the page's Event has no game of its own: it takes the one the Town
    /// feed showed.
    func testAPageWithoutItsGameTakesTheOneTheFeedShowed() throws {
        live.hold("town", [card(try game(#","live":"# + liveScore([7, 0], 18)))], at: at(19, 20))
        live.hold("town", [], at: at(19, 21))
        let fromYou = card(nil)
        XCTAssertEqual(live.game(fromYou)?.live?.score, [7, 0])
        live.hold("page:you", [fromYou], at: at(19, 22))
        XCTAssertTrue(live.listening)
    }

    func testANewerReadReplacesAnOlderScoreAndAnOlderOneNeverCoversANewerOne() throws {
        let opened = card(try game())
        live.hold("page:1", [opened], at: at(19, 5))
        live.changed(change(live: liveScore([7, 0], 18)), at: at(19, 18))
        // A read made before that change, landing after it.
        live.hold("town", [card(try game(#","live":"# + liveScore([0, 0], 2)))], at: at(19, 19))
        XCTAssertEqual(live.game(opened)?.live?.score, [7, 0])
        // A read made after it, back from the background.
        live.hold("town", [card(try game(#","live":"# + liveScore([14, 3], 50)))], at: at(19, 51))
        XCTAssertEqual(live.game(opened)?.live?.score, [14, 3])
        // A change that adds only a scoring play keeps the score's time: it still shows.
        let play = #"[{"id":"9","text":"T. Lund 34 yd field goal","period":"Q2","clock":"0:03","side":1,"score":[14,3]}]"#
        live.changed(change(live: liveScore([14, 3], 50), plays: play), at: at(19, 52))
        XCTAssertEqual(live.game(opened)?.plays.map(\.id), ["9"])
    }

    /// A page opened before kickoff starts listening at kickoff with no one touching the screen, and
    /// checks once more when the game's three hours end.
    func testAPageOpenedBeforeKickoffChecksAgainAtKickoff() throws {
        live.hold("page:1", [card(try game())], at: at(18, 55))
        XCTAssertFalse(live.listening)
        XCTAssertEqual(live.nextCheck(at: at(18, 55)), at(19))
        XCTAssertEqual(live.nextCheck(at: at(19, 5)), at(22), "then when its hours end")
        live.changed(change(live: liveScore([7, 0], 18)), at: at(19, 18))
        XCTAssertNil(live.nextCheck(at: at(19, 18)), "a score coming in keeps it on whatever the clock says")
    }

    /// A fresh read wins a tie: a final corrected, a special night added, while the app is open.
    func testAFreshReadWinsATie() throws {
        let opened = card(try game())
        live.hold("town", [card(try game(#","final":[21,10]"#))], at: at(22))
        live.hold("town", [card(try game(#","final":[21,17]"#))], at: at(22, 5))
        XCTAssertEqual(live.game(opened)?.final, [21, 17])
        live.hold("town", [card(try game(), id: "g2")], at: at(12))
        live.hold("town", [card(try game(#","occasion":"Homecoming""#), id: "g2")], at: at(12, 5))
        XCTAssertEqual(live.games["g2"]?.occasion, "Homecoming")
    }

    func testAChangeToAGameNothingShowedIsDropped() throws {
        live.hold("town", [card(try game())], at: at(19, 5))
        live.changed(change("other", live: liveScore([3, 0], 10)), at: at(19, 10))
        XCTAssertNil(live.games["other"])
    }

    /// The map follows every change on the one connection, a game or not.
    func testTheMapListensWithNothingHeldAndHearsEveryChange() throws {
        var heard: [String?] = []
        live.follow({ heard.append($0.new?.id) }, at: at(9))
        XCTAssertEqual(calls, [true])
        live.changed(change("e7"), at: at(9, 1))
        XCTAssertEqual(heard, ["e7"])
        live.follow(nil, at: at(9, 2))
        XCTAssertEqual(calls, [true, false])
    }

    /// The Town feed's cards carry Live games' score.
    func testTheTownFeedsCardCarriesTheNewestScore() async throws {
        let entry = TownFeedEntry(card: card(try game()), leavesAt: at(22))
        let feed = TownFeed(read: { [entry] }, live: live)
        await feed.reload(at: at(19, 5))
        feed.cameBack(at: at(19, 5))
        XCTAssertTrue(live.listening, "the feed holds its games while it's on screen")
        live.changed(change(live: liveScore([7, 0], 18)), at: at(19, 18))
        XCTAssertEqual(feed.cards.first?.game?.live?.score, [7, 0])
        feed.left(at: at(19, 20))
        XCTAssertFalse(live.listening, "off screen, it lets go")
    }
}
