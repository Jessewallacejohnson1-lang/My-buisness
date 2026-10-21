//
//  TownFeedCache.swift
//  Block Party — the Town feed's offline copy.
//
//  The last list `get_town_feed` sent, kept on disk so a relaunch shows it at once,
//  even with no signal (BP app docs/plans/town-feed, ticket 11). Raw bytes, as
//  `BriefingCache` keeps them, read back through the same decoding as a live read:
//  a copy from before the function's columns changed just misses, never blocks.
//
//  The Event of the day's picks that top the feed are kept beside it, so the poster lands with
//  the list rather than pushing it down a moment later (BP app event-card 03).
//
//  It holds the person's Going, so signing out clears it, as it does the briefing's.
//  One file rather than one per account: the first read can run before the session
//  is restored, and would look for the wrong account's file.
//
//  Application Support, not Caches: the system may evict Caches under pressure.
//

import Foundation

enum TownFeedCache {
    /// The feed's list, or the Event of the day's picks (`get_event_of_the_day`).
    enum Kind: String, CaseIterable {
        case feed = "town-feed.json"
        case eventOfTheDay = "event-of-the-day.json"
    }

    private static func file(_ kind: Kind) -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent(kind.rawValue)
    }

    /// The last list saved, or nil when there is none.
    static func load(_ kind: Kind = .feed) -> Data? {
        file(kind).flatMap { try? Data(contentsOf: $0) }
    }

    static func save(_ raw: Data, _ kind: Kind = .feed) {
        guard let file = file(kind) else { return }
        do {
            try raw.write(to: file, options: .atomic)
        } catch {
            // A failed write costs the offline copy, nothing else.
            Log.network("town feed cache write failed: \(error.localizedDescription)")
        }
    }

    static func clear() {
        for kind in Kind.allCases {
            guard let file = file(kind) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
