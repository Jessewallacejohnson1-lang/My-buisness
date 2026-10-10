//
//  TownFeedCache.swift
//  Block Party — the Town feed's offline copy.
//
//  The last list `get_town_feed` sent, kept on disk so a relaunch shows it at once,
//  even with no signal (BP app docs/plans/town-feed, ticket 11). Raw bytes, as
//  `BriefingCache` keeps them, read back through the same decoding as a live read:
//  a copy from before the function's columns changed just misses, never blocks.
//
//  One file per account, because the list holds that person's Going. Saving one
//  removes any other, so a second person on the phone never sees the first's.
//
//  Application Support, not Caches: the system may evict Caches under pressure.
//

import Foundation

enum TownFeedCache {
    private static let prefix = "town-feed-"

    private static var folder: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    private static func file(for userId: String?) -> URL? {
        folder?.appendingPathComponent(prefix + (userId ?? "signed-out") + ".json")
    }

    /// The last list saved for this account, or nil when there is none.
    static func load(for userId: String?) -> Data? {
        file(for: userId).flatMap { try? Data(contentsOf: $0) }
    }

    static func save(_ raw: Data, for userId: String?) {
        guard let folder, let file = file(for: userId) else { return }
        do {
            try raw.write(to: file, options: .atomic)
        } catch {
            // A failed write costs the offline copy, nothing else.
            Log.network("town feed cache write failed: \(error.localizedDescription)")
        }
        let saved = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for other in saved where other.lastPathComponent.hasPrefix(prefix)
            && other.lastPathComponent != file.lastPathComponent {
            try? FileManager.default.removeItem(at: other)
        }
    }
}
