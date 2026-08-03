//
//  RoadsTileProvider.swift
//  Block Party — the roads Utility Row tile. Fetches active town_status notices
//  and subscribes to live changes (its own RealtimeClient on town_status). Roads
//  notices EXPAND inline on tap (headline + detail + updated time) — no sheet.
//  The notices → tile mapping lives in the pure `value(for:)`; `fetch` is that plus
//  the network. Zero notices produces the muted (de-emphasised) variant.
//

import Foundation

@MainActor
final class RoadsTileProvider: UtilityTileProvider {
    let id: UtilityTileID = .roads
    let refreshPolicy: UtilityRefreshPolicy = .live(staleAfter: 24 * 60 * 60)

    private let auth: AuthStore
    private let api: TownStatusAPI

    init(auth: AuthStore? = nil) {
        // Resolve the MainActor default in the (MainActor) init body — see the
        // CLAUDE.md MainActor-default-arg gotcha.
        let resolved = auth ?? .shared
        self.auth = resolved
        self.api = TownStatusAPI(auth: resolved)
    }

    func fetch(settings: TileSettings) async throws -> UtilityTileValue {
        let notices = try await api.activeNotices(kind: "roads")
        return Self.value(for: notices)
    }

    /// The whole notices → tile mapping, pure: everything `fetch` does apart from
    /// the network call, so it's testable without AuthStore, TownStatusAPI, or a
    /// backend. `notices` arrives newest-first (`activeNotices` orders it) and is
    /// read in that order — index 0 is the newest.
    ///
    /// Zero active notices is the nothing-to-see state. It still reads "All clear",
    /// but the tile is `isMuted`: a de-emphasised gradient, no warning triangle,
    /// nothing to expand. Nothing is wrong, so the tile must not look like it is.
    ///
    /// MainActor-isolated (not `nonisolated`) because it builds `UtilityTileContent`,
    /// whose init is MainActor under the module's default isolation — the row and the
    /// tests are both MainActor, so nothing needs it from another context.
    static func value(for notices: [TownStatusNotice]) -> UtilityTileValue {
        guard let newest = notices.first else {
            let calm = UtilityTileContent(symbol: "road.lanes",
                                          primary: "All clear",
                                          isMuted: true)
            return UtilityTileValue(content: calm)
        }
        let primary = notices.count == 1 ? "1 notice" : "\(notices.count) notices"
        let expanded = notices.prefix(3).map { notice in
            UtilityDetailRow(symbol: "exclamationmark.triangle.fill",
                             label: notice.headline,
                             value: UtilityFormat.relative(notice.updatedAt))
        }
        let content = UtilityTileContent(symbol: "road.lanes",
                                         primary: primary,
                                         secondary: newest.headline,   // truncated by the tile's lineLimit
                                         badge: .warning,
                                         expanded: Array(expanded))
        // updatedAt = newest notice → drives the ">24h → Updated Nd ago" stale note.
        return UtilityTileValue(content: content, updatedAt: newest.updatedAt)
    }

    func subscribe(settings: TileSettings, onChange: @escaping () -> Void) -> UtilitySubscription? {
        // Own RealtimeClient instance (one table per client). Any town_status change
        // → re-fetch; RLS + the query filter keep it to this town's roads notices.
        let client = RealtimeClient(table: "town_status") { [weak auth] in
            try? await auth?.validAccessToken()
        }
        client.onAnyChange = onChange
        client.start()
        return UtilitySubscription { client.stop() }
    }
}
