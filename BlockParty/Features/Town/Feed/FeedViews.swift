//
//  FeedViews.swift
//  Block Party — the Town feed's views and opens on their way to the server (ticket 20).
//
//  `TownFeed` counts a view (a card half on screen for a second, once per feed load) and the shell
//  an open; both wait here and go up in one batch at most every 30 seconds, and when the app leaves
//  the screen. The server turns views into popularity per view.
//

import Foundation

@MainActor
final class FeedViews {
    /// Views and opens go up at most this often, and when the app leaves the screen.
    nonisolated static let sendEvery: TimeInterval = 30
    /// How long a pull waits for what you just saw to go up, before it reads anyway.
    nonisolated static let sendWait: Duration = .seconds(1)

    /// Views and opens not yet sent; a batch that fails for want of a network or an
    /// account goes back in front.
    private(set) var unsent: [FeedAction] = []
    private var lastSent: Date = .distantPast
    /// Where they go: the live table, or nowhere (tests, sample modes).
    private let sender: ([FeedAction]) async throws -> Void

    init(send: @escaping ([FeedAction]) async throws -> Void) {
        sender = send
    }

    /// A card the feed counted as seen: News goes apart from the rest (`see_news`, town-feed 41).
    func viewed(_ id: String, news: Bool) {
        unsent.append(FeedAction(itemID: id, kind: news ? .news : .view))
    }

    /// An Event page opened from the Town feed.
    func opened(_ id: String) {
        unsent.append(FeedAction(itemID: id, kind: .open))
    }

    /// Sends what is waiting, at most every 30 seconds, or now when the app leaves the
    /// screen. A batch that found no network, no account or a server down goes back in
    /// front of the next; one the server refuses (a bad row) is dropped, or it would
    /// fail every batch after it.
    func send(at now: Date = Date(), always: Bool = false) async {
        guard !unsent.isEmpty, always || now.timeIntervalSince(lastSent) >= Self.sendEvery else { return }
        let batch = unsent
        unsent = []
        lastSent = now
        do {
            try await sender(batch)
        } catch {
            Log.network("TownFeed: \(batch.count) views and opens not sent: \(error)")
            if SupabaseHTTP.noAnswer(error) || Task.isCancelled { unsent = batch + unsent }
        }
    }

    /// A new account: the last one's waiting views and opens are not this one's.
    func reset() {
        unsent = []
    }
}
