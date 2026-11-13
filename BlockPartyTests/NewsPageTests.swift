//
//  NewsPageTests.swift
//  BlockPartyTests — a News's post's own words for its News page (BP app docs/plans/town-feed, ticket 65): the cards
//  on screen ask for them in one read, an answer is kept, a failed read is asked again, and the page says where the
//  post was made.
//

import XCTest
@testable import BlockParty

@MainActor
final class NewsPageTests: XCTestCase {

    private func news(_ id: String, post: String = "https://www.facebook.com/flourandflowerbakery/posts/pfbid0") -> TownNews {
        TownNews(id: id, place: "Flour & Flower Bakery", words: "Maple danish, pear scone.", post: URL(string: post)!,
                 leavesAt: .distantFuture, title: "New Fall Pastries and Pies")
    }

    /// Waits for the store's read to finish, a second at most.
    private func settle(_ store: NewsPostWords) async {
        for _ in 0..<100 where store.reading { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testCardsAskingTogetherAreOneRead() async {
        var asked: [[String]] = []
        let store = NewsPostWords { ids in
            asked.append(ids)
            return ["a": NewsCaption(text: "PASTRIES\n-Morning bun", placeID: "p1")]
        }
        store.gather = .milliseconds(1)
        store.want("a")
        store.want("b")
        store.want("a")
        await settle(store)
        XCTAssertEqual(asked, [["a", "b"]], "the cards on screen go in one read, each once")
        XCTAssertEqual(store.words["a"], NewsCaption(text: "PASTRIES\n-Morning bun", placeID: "p1"))
        XCTAssertNil(store.words["b"])
        XCTAssertTrue(store.none.contains("b"), "a News with no words of its own is known, so its card opens the post")
        store.want("a")
        store.want("b")
        await settle(store)
        XCTAssertEqual(asked.count, 1, "an answer is kept: neither is asked again")
    }

    func testAFailedReadIsAskedAgain() async {
        var calls = 0
        let store = NewsPostWords { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return ["a": NewsCaption(text: "Open late Friday", placeID: nil)]
        }
        store.gather = .milliseconds(1)
        store.want("a")
        await settle(store)
        XCTAssertNil(store.words["a"])
        XCTAssertFalse(store.none.contains("a"), "a failure isn't kept as no words")
        store.want("a")
        await settle(store)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(store.words["a"]?.text, "Open late Friday")
    }

    func testATapBeforeItsReadWaitsForTheWords() async {
        let store = NewsPostWords { ids in ids.contains("a") ? ["a": NewsCaption(text: "Open late Friday", placeID: nil)] : [:] }
        store.gather = .milliseconds(1)
        let got = await store.caption("a")
        XCTAssertEqual(got?.text, "Open late Friday", "a card tapped before its read landed still opens its page")
        let clock = ContinuousClock.now
        let missing = await store.caption("b")
        XCTAssertNil(missing, "a News with no words of its own opens its post")
        XCTAssertLessThan(ContinuousClock.now - clock, .milliseconds(900), "it doesn't wait out the second once the read says none")
    }

    func testTheLineSaysWhereThePostWasMade() {
        XCTAssertEqual(news("1").via, "Facebook")
        XCTAssertEqual(news("2", post: "https://www.instagram.com/p/DfqTiPZmKHW/").via, "Instagram")
        XCTAssertEqual(news("3", post: "https://m.facebook.com/x/posts/1").via, "Facebook")
        XCTAssertNil(news("4", post: "https://stjosephmn.gov/news/1").via, "a website story has no post page")
    }
}
