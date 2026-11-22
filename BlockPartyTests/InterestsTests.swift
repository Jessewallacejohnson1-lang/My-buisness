//
//  InterestsTests.swift
//  The 25 interests (BP app onboarding 20 and 21), the old-to-new map, and the 12 rows and circles that pick
//  them (onboarding 48).
//

import UIKit
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

    func testTheTwelveRowsSaveOnlyRealInterests() {
        XCTAssertEqual(Interests.rows.map(\.label),
                       ["Schools", "Sports", "Campus life", "Families & kids", "Faith & church", "Arts & music", "Food",
                        "Shopping", "Fun & games", "Outdoors", "Health & fitness", "City updates"])
        let real = Set(Interests.all.map(\.id))
        for id in Interests.picks.flatMap(\.ids) { XCTAssertTrue(real.contains(id), id) }
        // Nothing saves what another saves.
        let ids = Interests.picks.flatMap(\.ids)
        XCTAssertEqual(ids.count, Set(ids).count)
        // Schools saves nothing: it leads Follow 3 with schools (onboarding 48).
        for id in ["high_school", "middle_school", "networking"] { XCTAssertFalse(ids.contains(id), id) }
    }

    func testEachCirclePicksItsWholeRow() {
        XCTAssertEqual(Interests.circles.map(\.label), Interests.rows.map(\.label))
        let circle = { (label: String) in Interests.circles.first { $0.label == label }! }
        XCTAssertEqual(circle("Schools").ids, [])
        XCTAssertEqual(circle("Sports").ids, ["watch_sports"])
        XCTAssertEqual(circle("Campus life").ids, ["campus", "college"])
        XCTAssertEqual(circle("Arts & music").ids, ["live_music", "art_theater", "crafts", "books", "talks"])
        XCTAssertEqual(circle("Food").ids, ["coffee", "dining"])
        XCTAssertEqual(circle("Shopping").ids, ["markets"])
        XCTAssertEqual(circle("Fun & games").ids, ["games", "festivals", "bars"])
        XCTAssertEqual(circle("City updates").ids, ["town_meetings", "volunteering"])
        // One tap picks the whole group and counts once; another takes it all off.
        let picked = Interests.toggled(circle("Food"), in: ["faith"])
        XCTAssertEqual(picked, ["faith", "coffee", "dining"])
        XCTAssertEqual(Interests.circlesPicked(picked), 2)
        XCTAssertEqual(Interests.toggled(circle("Food"), in: picked), ["faith"])
        // A chip picked in Edit Profile shows its circle on.
        XCTAssertEqual(Interests.circlesPicked(["bars"]), 1)
        XCTAssertEqual(Interests.circlesPicked([]), 0)
    }

    func testEveryCircleHasItsPhoto() {
        XCTAssertEqual(Interests.photo(Interests.circles[3]), "interest-families-kids.jpg")
        for circle in Interests.circles {
            XCTAssertNotNil(UIImage(named: Interests.photo(circle)), circle.label)
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

    func testFollowingTheCollegePicksCampusLife() {
        XCTAssertEqual(Interests.withCollege(["coffee"]), ["coffee", "campus", "college"])
        XCTAssertEqual(Interests.withCollege(["coffee", "campus", "college"]), ["coffee", "campus", "college"])
        XCTAssertEqual(Interests.withCollege(["campus", "coffee"]), ["campus", "coffee", "college"])
        XCTAssertEqual(Interests.count(["campus", "college"]), 1, "Campus life shows them since onboarding 48")
    }

    func testPicksNoLongerOnTheRowsGo() {
        XCTAssertEqual(Interests.onRows(["watch_sports", "coffee", "high_school", "networking", "campus", "college"]),
                       ["watch_sports", "coffee", "campus", "college"])
    }
}
