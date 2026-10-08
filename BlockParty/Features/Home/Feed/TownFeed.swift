//
//  TownFeed.swift
//  Block Party — the Town feed: what's in it and in what order.
//
//  The database works both out (`get_town_feed`, the one function iOS and Android call;
//  BP app docs/plans/town-feed, ticket 05), so this never filters or re-sorts by its
//  own rules. It keeps the last good list across tab switches and failed refreshes,
//  lets an event go once its leaves-at passes, and reads again then, because a
//  series' next date only arrives with a fresh read.
//

import Foundation

/// One event in the Town feed: its card, and when it leaves.
struct TownFeedEntry: Identifiable {
    let card: FeedCardItem
    let leavesAt: Date
    var id: String { card.id }
}

@MainActor @Observable
final class TownFeed {
    /// nil until the first read answers, which the feed shows as its skeleton.
    private(set) var entries: [TownFeedEntry]?
    /// The first read failed, so there is nothing to show yet.
    private(set) var failed = false
    /// When the list was last read or checked. Events that have left by then are hidden.
    private(set) var clock = Date()

    private let read: () async throws -> [TownFeedEntry]

    init(read: @escaping () async throws -> [TownFeedEntry]) {
        self.read = read
    }

    /// The live feed, or under DEBUG `-town-samples` the sample events, so design
    /// work has photos under the chrome and never reads the live database.
    convenience init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-town-samples") {
            self.init { DailyFixtures.townEntries() }
            return
        }
        #endif
        self.init(read: Self.live)
    }

    /// The cards still on, in the database's order.
    var cards: [FeedCardItem] {
        (entries ?? []).filter { $0.leavesAt > clock }.map(\.card)
    }

    /// When the next card leaves: the feed reads again then.
    var nextLeave: Date? {
        entries?.lazy.map(\.leavesAt).filter { $0 > self.clock }.min()
    }

    /// Reads the feed as of `now`. A failed read keeps the list already showing, minus
    /// what has left; with no list, the feed shows its retry.
    ///
    /// The clock moves only once the read is done: it decides `nextLeave`, and the
    /// feed's leave timer is keyed on that, so moving it first cancelled the very read
    /// the timer had started.
    func reload(at now: Date = Date()) async {
        if entries == nil { failed = false }
        do {
            entries = try await read()
            failed = false
        } catch {
            // Left mid-read (the tab went away): not a failure; the read runs again
            // when the feed comes back.
            guard !Task.isCancelled else { return }
            Log.network("TownFeed: \(error)")
            if entries == nil { failed = true }
        }
        clock = now
    }

    private static func live() async throws -> [TownFeedEntry] {
        let auth = AuthStore.shared
        return try await CommunityAPI(auth: auth).getTownFeed().map {
            entry($0, signedIn: auth.isSignedIn)
        }
    }

    /// A row as the card a club's event gets. Signed out, an RSVP can be neither read
    /// nor written, so the card offers no Join (`FeedCardItem.canJoin`).
    static func entry(_ row: TownFeedRow, signedIn: Bool) -> TownFeedEntry {
        var card = FeedCardItem(row.event, recurrence: row.recurrence)
        card.canJoin = signedIn
        return TownFeedEntry(card: card, leavesAt: row.leavesAt)
    }
}
