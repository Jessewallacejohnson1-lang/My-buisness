//
//  BriefingCache.swift
//  Block Party — the Today tab's offline copy.
//
//  Cache-first: the last payload is written to disk and rendered instantly on
//  launch, then refreshed in the background. The morning bad-wifi case is the
//  whole point — a briefing you have already downloaded must still open.
//
//  Stores the server's raw bytes rather than a re-encoding, so what is replayed
//  offline is byte-for-byte what the RPC returned.
//
//  Application Support, not Caches: the system may evict Caches under pressure,
//  which would silently break the offline guarantee.
//

import Foundation

// MainActor-isolated, like the rest of the module: it reads the shared
// `SupabaseCoding.decoder` and logs through `Log`, both of which are. The payload
// is a few KB read once per launch, so keeping it here costs nothing worth the
// duplicate decoder configuration that going nonisolated would require.
enum BriefingCache {
    private static let fileName = "briefing-cache.json"

    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    /// The last payload written, or nil if there is none or it no longer decodes
    /// (a contract change ships a new shape; a stale cache must never crash the
    /// tab — it just misses).
    static func load() -> BriefingPayload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? SupabaseCoding.decoder.decode(BriefingPayload.self, from: data)
    }

    static func save(_ raw: Data) {
        guard let url = fileURL else { return }
        do {
            try raw.write(to: url, options: .atomic)
        } catch {
            // A cache write failure costs the offline copy, nothing else.
            Log.network("briefing cache write failed: \(error.localizedDescription)")
        }
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
