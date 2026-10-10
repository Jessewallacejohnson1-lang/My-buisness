//
//  TownFeedCache.swift
//  Block Party — the Town feed's offline copy.
//
//  The last list `get_town_feed` sent, kept on disk so a relaunch shows it at once,
//  even with no signal (BP app docs/plans/town-feed, ticket 11). Raw bytes, as
//  `BriefingCache` keeps them, read back through the same decoding as a live read:
//  a copy from before the function's columns changed just misses, never blocks.
//
//  It holds the person's Going, so signing out clears it, as it does the briefing's.
//  One file rather than one per account: the first read can run before the session
//  is restored, and would look for the wrong account's file.
//
//  Application Support, not Caches: the system may evict Caches under pressure.
//

import Foundation

enum TownFeedCache {
    private static var file: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("town-feed.json")
    }

    /// The last list saved, or nil when there is none.
    static func load() -> Data? {
        file.flatMap { try? Data(contentsOf: $0) }
    }

    static func save(_ raw: Data) {
        guard let file else { return }
        do {
            try raw.write(to: file, options: .atomic)
        } catch {
            // A failed write costs the offline copy, nothing else.
            Log.network("town feed cache write failed: \(error.localizedDescription)")
        }
    }

    static func clear() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
