//
//  GameAllPlaysTests.swift
//  A basketball game's page lists its newest 5 scoring plays, and every one after "Show all" (BP app game-card 34).
//

import XCTest
@testable import BlockParty

final class GameAllPlaysTests: XCTestCase {
    private func game(_ sport: String, plays count: Int) throws -> Game {
        let plays = (1...max(count, 1)).prefix(count).map {
            #"{"id":"\#($0)","text":"5 Clara Goodman LAYUP GOOD (\#($0 * 2) Pt)","period":"Q1","clock":"9:00","side":0,"score":[\#($0 * 2),0]}"#
        }.joined(separator: ",")
        let json = #"{"sport":"\#(sport)","teams":[{"name":"Saint Benedict"},{"name":"Simpson"}],"plays":[\#(plays)]}"#
        return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
    }

    func testBasketballListsItsNewestFiveAndEveryPlayAfterShowAll() throws {
        let game = try game("Basketball", plays: 61)
        XCTAssertTrue(game.foldsPlays)
        XCTAssertEqual(game.listedPlays(all: false).map(\.id), ["61", "60", "59", "58", "57"])
        XCTAssertEqual(game.listedPlays(all: true).count, 61)
        XCTAssertEqual(game.listedPlays(all: true).first?.id, "61", "newest first")
        XCTAssertEqual(game.listedPlays(all: true).last?.id, "1")
    }

    func testFiveOrFewerHaveNothingToShow() throws {
        let game = try game("Girls Basketball", plays: 5)
        XCTAssertFalse(game.foldsPlays, "no Show all row for a list that is already whole")
        XCTAssertEqual(game.listedPlays(all: false).count, 5)
        XCTAssertFalse(try self.game("Basketball", plays: 0).foldsPlays)
    }

    func testOtherSportsListEveryPlayWithNoRow() throws {
        let game = try game("Football", plays: 9)
        XCTAssertFalse(game.foldsPlays)
        XCTAssertEqual(game.listedPlays(all: false).map(\.id), (1...9).reversed().map(String.init))
    }
}
