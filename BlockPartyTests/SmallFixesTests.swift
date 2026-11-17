//
//  SmallFixesTests.swift
//  BlockPartyTests — BP app backlog 20: a News share leads with its headline, and Search keeps a
//  name whole when a cut would leave it hanging.
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
        XCTAssertEqual(SearchModel.shown("Bad Habit Brewing Company"), "Bad Habit Brewing")
        XCTAssertEqual(SearchModel.shown("Bello Cucina | Italian Restaurant"), "Bello Cucina")
    }
}
