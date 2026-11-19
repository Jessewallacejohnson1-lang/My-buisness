//
//  SmallFixesTests.swift
//  BlockPartyTests — BP app backlog 20: a News share leads with its headline, Search keeps a
//  name whole when a cut would leave it hanging, and says what a place is in plain words.
//

import XCTest
@testable import BlockParty

@MainActor
final class SmallFixesTests: XCTestCase {
    private func news(words: String, title: String?) -> TownNews {
        TownNews(id: "n", place: "City of St. Joseph", words: words, post: URL(string: "https://x/n")!,
                 leavesAt: .distantFuture, title: title)
    }

    func testShareLeadsWithTheHeadline() {
        let text = TownNewsCard.shareText(news(words: "Thursday, Nov 26", title: "City offices closed for Thanksgiving"))
        XCTAssertEqual(text, "City of St. Joseph: City offices closed for Thanksgiving Thursday, Nov 26 https://x/n")
    }

    func testShareWithNoTitleSaysTheWordsOnce() {
        XCTAssertEqual(TownNewsCard.shareText(news(words: "Leaf pickup starts Monday.", title: nil)),
                       "City of St. Joseph: Leaf pickup starts Monday. https://x/n")
    }

    func testShownKeepsAnAmpersandName() {
        XCTAssertEqual(SearchModel.shown("Hudson & Company"), "Hudson & Company")
        XCTAssertEqual(SearchModel.shown("Smith and Company"), "Smith and Company")
        XCTAssertEqual(SearchModel.shown("Hansen & Company Woodworks"), "Hansen & Company Woodworks")
        XCTAssertEqual(SearchModel.shown("Bad Habit Brewing Company"), "Bad Habit Brewing")
        XCTAssertEqual(SearchModel.shown("Bello Cucina | Italian Restaurant"), "Bello Cucina")
    }

    /// Search's kinds in a neighbour's words, not Google's (backlog 20); a catch-all says nothing.
    func testKindsInPlainWords() {
        XCTAssertEqual(SearchModel.label("personal_or_beauty_service"), "Beauty & wellness",
                       "a hair studio and a nutrition shop share it")
        XCTAssertEqual(SearchModel.label("wellness_service"), "Wellness")
        XCTAssertEqual(SearchModel.label("hardware_home_and_garden_store"), "Hardware store")
        XCTAssertEqual(SearchModel.label("b2b_office_and_professional_service"), "Business services")
        XCTAssertNil(SearchModel.label("point_of_interest"))
        XCTAssertNil(SearchModel.label(""))
        XCTAssertEqual(SearchModel.label("print_shop"), "Print shop", "a type new since reads as itself")
    }
}
