//
//  GamePlayersTests.swift
//  A basketball game's player lines (BP app game-card 35): read from `club_events.player_stats`, kept through a realtime
//  update that has none, shown only with both teams, and spoken as one line a player.
//

import XCTest
@testable import BlockParty

@MainActor
final class GamePlayersTests: XCTestCase {
    /// `club_events.player_stats` as `private.sidearm_box` writes it: Saint Ben's then Simpson, `pts` points for the first.
    private func stats(_ pts: Int = 12) -> String {
        let line = { (uni: String, name: String, pts: Int) in
            #"{"uni":"\#(uni)","name":"\#(name)","pos":"G","pts":\#(pts),"reb":1,"ast":1,"fg":"4-14","tp":"3-12"}"#
        }
        let total = #"{"pts":54,"reb":34,"ast":15,"fg":"18-58","tp":"7-29"}"#
        return #"[{"rows":[\#(line("5", "C. Goodman", pts)),\#(line("4", "A. Sadlovsky", 7))],"total":\#(total)},"#
            + #"{"rows":[\#(line("44", "T. Hansen", 16))],"total":\#(total)}]"#
    }

    private func game(_ more: String = "") throws -> Game {
        let json = #"{"sport":"Basketball","teams":[{"name":"Saint Benedict"},{"name":"Simpson"}]"# + more + "}"
        return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
    }

    func testTheRowReadsAsBothTeamsInOrder() throws {
        let boxes = try XCTUnwrap(Game.Box.pair(from: Data(stats().utf8)))
        XCTAssertEqual(boxes.map { $0.rows.first?.name }, ["C. Goodman", "T. Hansen"])
        XCTAssertEqual(boxes[0].rows.first?.fg, "4-14")
        XCTAssertEqual(boxes[0].total.pts, 54)
        XCTAssertNil(boxes[0].total.name)
    }

    func testOneTeamOrNoPlayersShowsNothing() {
        let one = #"[{"rows":[],"total":{"pts":0,"reb":0,"ast":0,"fg":"0-0","tp":"0-0"}},"# +
            #"{"rows":[{"pts":2,"reb":0,"ast":0,"fg":"1-1","tp":"0-0"}],"total":{"pts":2,"reb":0,"ast":0,"fg":"1-1","tp":"0-0"}}]"#
        XCTAssertNil(Game.Box.pair(from: Data(one.utf8)), "a team with no players")
        XCTAssertNil(Game.Box.pair(from: Data("[]".utf8)))
        XCTAssertNil(Game.Box.pair(from: Data("null".utf8)))
    }

    func testTheFeedsGameHasNoneAndTheSampleHasThem() throws {
        XCTAssertNil(try game().players)
        XCTAssertEqual(try game(#","players":"# + stats()).players?.count, 2)
    }

    func testARealtimeUpdateBringsNewerLinesAndOneWithoutKeepsThem() throws {
        let live = LiveGames(listen: { _ in })
        var event = UpcomingEvent(id: "b1", title: "CSB Basketball vs Simpson", eventDate: "2026-11-14", startTime: "3:00 PM",
                                  location: "Claire Lynch Hall", goingCount: 0, createdAt: "")
        event.game = try game()
        let card = FeedCardItem(event)
        let now = Date()
        live.hold("page:test", [card], at: now)
        func change(_ stats: String?) -> RealtimeClient.Change {
            let row = RealtimeClient.Change.Row(id: "b1", eventDate: "2026-11-14", startTime: "15:00:00", status: nil, kind: nil,
                                                title: nil, location: nil, liveScore: nil, playerStats: stats.map { Data($0.utf8) })
            return RealtimeClient.Change(kind: .update, new: row, old: row.withoutScores)
        }
        live.changed(change(stats(12)), at: now)
        XCTAssertEqual(live.game(card)?.players?.first?.rows.first?.pts, 12)
        live.changed(change(stats(14)), at: now)
        XCTAssertEqual(live.game(card)?.players?.first?.rows.first?.pts, 14)
        live.changed(change(nil), at: now)
        XCTAssertEqual(live.game(card)?.players?.first?.rows.first?.pts, 14, "a score-only update keeps the lines")
    }

    func testVoiceOverReadsEachRowAsOneLine() {
        let line = Game.Box.Line(uni: "1", name: "L. Arnold", pos: "G", pts: 5, reb: 1, ast: 6, fg: "1-1", tp: "1-1")
        XCTAssertEqual(GamePlayers.spoken(line),
                       "L. Arnold, guard, 5 points, 1 rebound, 6 assists, 1 of 1 field goals, 1 of 1 threes")
        let total = Game.Box.Line(pts: 54, reb: 34, ast: 15, fg: "18-58", tp: "7-29")
        XCTAssertEqual(GamePlayers.spoken(total, team: true),
                       "Team, 54 points, 34 rebounds, 15 assists, 18 of 58 field goals, 7 of 29 threes")
    }
}
