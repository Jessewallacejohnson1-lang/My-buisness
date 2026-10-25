//
//  InterestsTests.swift
//  The 21 interests (BP app onboarding 20): the old-to-new map, search's everyday words, and
//  "Popular in St. Joseph".
//

import XCTest
@testable import BlockParty

final class InterestsTests: XCTestCase {

    func testTwentyOneInSevenGroups() {
        XCTAssertEqual(Interests.all.count, 21)
        XCTAssertEqual(Interests.sections.map(\.title),
                       ["Outdoors", "Food & drink", "Arts & music", "Fun", "Sports & health", "Community", "Civics"])
        XCTAssertEqual(Set(Interests.all.map(\.id)).count, 21)
    }

    func testOldPicksMapOntoTheNew() {
        XCTAssertEqual(Interests.migrate(["trails_hiking", "parks_gardens", "coffee"]), ["outdoors", "coffee"])
        XCTAssertEqual(Interests.migrate(["art_exhibits", "sports_leagues"]),
                       ["art_theater", "crafts", "watch_sports", "play_sports"])
        XCTAssertEqual(Interests.migrate(["breweries", "farmers_market", "fitness_yoga", "health_wellness"]),
                       ["bars", "markets", "health"])
        // Kept as picked: a new id, and books, which can't bring Talks back after it's taken off.
        XCTAssertEqual(Interests.migrate(["books", "campus"]), ["books", "campus"])
        XCTAssertEqual(Interests.migrate(["gone_forever"]), [])
        // Every old id lands on real ones.
        for (_, ids) in Interests.legacy { XCTAssertEqual(Interests.migrate(ids), ids) }
    }

    func testSearchKnowsEverydayWords() {
        XCTAssertEqual(Interests.search("pickleball").map(\.id), ["play_sports"])
        XCTAssertEqual(Interests.search("church").map(\.id), ["faith"])
        XCTAssertTrue(Interests.search("Trivia").map(\.id).contains("games"))
        XCTAssertTrue(Interests.search("lib").map(\.id).contains("books"))
        XCTAssertTrue(Interests.search("bingo night").map(\.id).contains("games"))
        XCTAssertEqual(Interests.search("zzzz"), [])
        XCTAssertEqual(Interests.search("  ").count, 21)
    }

    func testPopularCountsRealEvents() {
        let events = Array(repeating: ["watch_sports"], count: 5) + Array(repeating: ["faith", "live_music"], count: 4)
            + Array(repeating: ["sports_leagues"], count: 2) + [["coffee"], ["coffee"]]
        // Old ids count as their new ones; under 3 events doesn't make the row.
        XCTAssertEqual(Interests.popular(events), ["watch_sports", "live_music", "faith"])
        XCTAssertEqual(Interests.popular(events, limit: 2), ["watch_sports", "live_music"])
        // Fewer than 3 interests with enough events: no row.
        XCTAssertEqual(Interests.popular(Array(repeating: ["faith"], count: 9)), [])
        XCTAssertEqual(Interests.popular([]), [])
    }
}
