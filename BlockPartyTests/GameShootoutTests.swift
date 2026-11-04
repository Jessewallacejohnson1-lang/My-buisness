//
//  GameShootoutTests.swift
//  A tied game settled on penalty kicks says who won (BP app game-card 15): Saint Ben's 1-1 Macalester, 5-4 on kicks.
//

import XCTest
@testable import BlockParty

final class GameShootoutTests: XCTestCase {
    private func game(final: [Int]?, shootout: String?) -> Game {
        let finalJSON = final.map { "[\($0[0]), \($0[1])]" } ?? "null"
        let shootoutJSON = shootout.map { ", \"shootout\": \($0)" } ?? ""
        let json = """
        {"sport": "Soccer", "occasion": null, "final": \(finalJSON),
         "live": {"score": [1, 1], "period": "OT", "complete": true\(shootoutJSON)},
         "teams": [{"name": "Saint Benedict", "short": "Saint Ben's"}, {"name": "Macalester", "short": "Macalester"}]}
        """
        return try! JSONDecoder().decode(Game.self, from: Data(json.utf8))
    }

    private let kicks = #"{"score": [5, 4], "who": "CSB"}"#

    func testATieWonOnPenaltiesHasAWinnerAndSaysSo() throws {
        let game = game(final: [1, 1], shootout: kicks)
        XCTAssertEqual(game.winner, 0)
        XCTAssertEqual(game.shootout?.wins, "CSB wins 5–4")
        XCTAssertEqual(game.spoken, "Soccer, Saint Ben's 1, Macalester 1, final, Saint Ben's wins 5 to 4 on penalties")
    }

    func testTheAwayTeamCanWinThem() throws {
        let game = game(final: [2, 2], shootout: #"{"score": [3, 4], "who": "MAC"}"#)
        XCTAssertEqual(game.winner, 1)
        XCTAssertEqual(game.shootout?.wins, "MAC wins 4–3", "the winner's count first")
        XCTAssertEqual(game.spoken, "Soccer, Saint Ben's 2, Macalester 2, final, Macalester wins 4 to 3 on penalties")
    }

    func testATieWithNoKicksStaysATie() throws {
        for read in [nil, "null"] {
            let game = game(final: [1, 1], shootout: read)
            XCTAssertNil(game.winner)
            XCTAssertNil(game.shootout)
            XCTAssertEqual(game.spoken, "Soccer, Saint Ben's 1, Macalester 1, final")
        }
    }

    func testKicksThatDoNotReadStayATieAndNeverCostTheScore() throws {
        for read in [#"{"score": [4, 4], "who": "CSB"}"#, #"{"score": [5], "who": "CSB"}"#, #"{"score": [5, -1], "who": "CSB"}"#,
                     #"{"score": [5, 4], "who": ""}"#, #"{"score": [5, 4]}"#, #""5-4""#] {
            let game = game(final: [1, 1], shootout: read)
            XCTAssertEqual(game.final, [1, 1], read)
            XCTAssertNil(game.shootout, read)
            XCTAssertNil(game.winner, read)
        }
    }

    func testKicksMeanNothingWithoutATiedFinal() throws {
        XCTAssertNil(game(final: nil, shootout: kicks).shootout, "before the final")
        let decided = game(final: [2, 1], shootout: #"{"score": [4, 5], "who": "MAC"}"#)
        XCTAssertNil(decided.shootout, "a final with a winner already")
        XCTAssertEqual(decided.winner, 0)
    }

    func testARealtimeUpdateBringsTheKicksWithTheFinal() throws {
        let before = game(final: nil, shootout: nil)
        let live = try JSONDecoder().decode(Game.Live.self, from: Data(#"""
        {"score": [1, 1], "period": "OT", "complete": true, "shootout": {"score": [5, 4], "who": "CSB"}}
        """#.utf8))
        let after = before.with(final: [1, 1], live: live)
        XCTAssertEqual(after.winner, 0)
        XCTAssertNil(after.live, "the live score goes at the final")
        XCTAssertEqual(after.shootout?.wins, "CSB wins 5–4", "the kicks stay")
    }
}
