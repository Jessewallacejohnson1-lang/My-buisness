//
//  InterestsTests.swift
//  The 25 interests (BP app onboarding 20 and 21), the old-to-new map, and the 9 rows that pick them
//  (onboarding 28).
//

import XCTest
@testable import BlockParty

final class InterestsTests: XCTestCase {

    func testTwentyFiveInterestsStay() {
        XCTAssertEqual(Interests.all.count, 25)
        XCTAssertEqual(Set(Interests.all.map(\.id)).count, 25)
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

    func testTheNineRowsSaveOnlyRealInterests() {
        XCTAssertEqual(Interests.rows.map(\.label),
                       ["Schools", "Families & kids", "Faith & church", "Arts & music", "Food & drink", "Fun",
                        "Outdoors", "Health & fitness", "Town life"])
        let real = Set(Interests.all.map(\.id))
        for id in Interests.picks.flatMap(\.ids) + Interests.collegeIds { XCTAssertTrue(real.contains(id), id) }
        // Nothing saves what another saves.
        let ids = Interests.picks.flatMap(\.ids)
        XCTAssertEqual(ids.count, Set(ids).count)
        // Schools saves nothing: only what you follow lifts (Jesse, 2026-11-04).
        for id in ["watch_sports", "high_school", "middle_school", "networking", "campus", "college"] {
            XCTAssertFalse(ids.contains(id), id)
        }
    }

    func testAPickThatSavesTwoCountsOnceAndComesOffWhole() {
        let books = Interests.picks.first { $0.label == "Books & talks" }!
        let picked = Interests.toggled(books, in: ["coffee"])
        XCTAssertEqual(picked, ["coffee", "books", "talks"])
        XCTAssertEqual(Interests.count(picked), 2, "things picked, not interests saved")
        XCTAssertEqual(Interests.names(picked), ["Books & talks", "Coffee shops"], "top to bottom")
        XCTAssertEqual(Interests.toggled(books, in: picked), ["coffee"])
        // An older pick of one half shows on, and one tap takes it off.
        XCTAssertTrue(books.isOn(in: ["talks"]))
        XCTAssertEqual(Interests.toggled(books, in: ["talks"]), [])
    }

    func testTheCollegesInterestsFollowItsFollows() {
        XCTAssertEqual(Interests.withCollege(["coffee"], following: true), ["coffee", "campus", "college"])
        XCTAssertEqual(Interests.withCollege(["coffee", "campus", "college"], following: true), ["coffee", "campus", "college"])
        XCTAssertEqual(Interests.withCollege(["campus", "coffee", "college"], following: false), ["coffee"])
        XCTAssertEqual(Interests.count(["campus", "college"]), 0, "a follow is what's counted, never these")
    }

    func testPicksNoLongerOnTheRowsGo() {
        XCTAssertEqual(Interests.onRows(["watch_sports", "coffee", "high_school", "networking", "campus", "college"]),
                       ["coffee", "campus", "college"])
    }
}
