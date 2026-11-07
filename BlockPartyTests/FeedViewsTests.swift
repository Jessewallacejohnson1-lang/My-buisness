//
//  FeedViewsTests.swift
//  The Town feed's views and opens on their way to the server (`FeedViews`, ticket 20): one batch
//  at most every 30 seconds, a failed one kept for the next. What counts as a view is
//  `TownFeed`'s, tested in TownFeedEventsTests.
//

import XCTest
@testable import BlockParty

/// Keeps every batch it's sent, and fails when told to.
@MainActor
final class FeedSender {
    var batches: [[FeedAction]] = []
    var error: Error?
    func send(_ batch: [FeedAction]) async throws {
        if let error { throw error }
        batches.append(batch)
    }
}

@MainActor
final class FeedViewsTests: XCTestCase {

    /// Noon on 2026-10-07, the Town's time.
    private let now = Town.midnight("2026-10-07")!.addingTimeInterval(12 * 3600)

    func testOneBatchEvery30SecondsAndAtOnceWhenTheAppLeaves() async {
        let sender = FeedSender()
        let views = FeedViews(send: sender.send)
        views.opened("a")
        await views.send(at: now)
        XCTAssertEqual(sender.batches, [[FeedAction(itemID: "a", kind: .open)]], "the first goes at once")

        views.opened("b")
        await views.send(at: now.addingTimeInterval(29))
        XCTAssertEqual(sender.batches.count, 1, "nothing before 30 s")
        await views.send(at: now.addingTimeInterval(30))
        XCTAssertEqual(sender.batches.count, 2)

        views.opened("c")
        await views.send(at: now.addingTimeInterval(31), always: true)
        XCTAssertEqual(sender.batches.last, [FeedAction(itemID: "c", kind: .open)], "leaving sends now")
    }

    /// No network or no account: the batch waits for the next. A refused one is dropped.
    func testAFailedBatchJoinsTheNextAndARefusedOneIsDropped() async {
        let sender = FeedSender()
        let views = FeedViews(send: sender.send)
        sender.error = URLError(.notConnectedToInternet)
        views.opened("a")
        await views.send(at: now)
        sender.error = SupabaseError(message: "no session", status: 401)
        views.opened("b")
        await views.send(at: now.addingTimeInterval(30))
        sender.error = nil
        views.opened("c")
        await views.send(at: now.addingTimeInterval(60))
        XCTAssertEqual(sender.batches.last?.map(\.itemID), ["a", "b", "c"])

        sender.error = SupabaseError(message: "bad row", status: 400)
        views.opened("d")
        await views.send(at: now.addingTimeInterval(90))
        sender.error = nil
        views.opened("e")
        await views.send(at: now.addingTimeInterval(120))
        XCTAssertEqual(sender.batches.last?.map(\.itemID), ["e"], "a refused batch would fail every one after it")
    }

    func testANewAccountDropsTheLastOnesWaitingViews() async {
        let sender = FeedSender()
        let views = FeedViews(send: sender.send)
        views.opened("a")
        views.reset()
        await views.send(at: now, always: true)
        XCTAssertEqual(sender.batches, [])
    }
}
