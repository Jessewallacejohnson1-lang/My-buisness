//
//  RoadsTileProvider.swift
//  Block Party — the roads Utility Row tile. Fetches active town_status notices
//  and subscribes to live changes (its own RealtimeClient on town_status). Roads
//  notices EXPAND inline on tap (headline + detail + updated time) — no sheet.
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
        guard let newest = notices.first else {
            return UtilityTileValue(content: UtilityTileContent(symbol: "road.lanes", primary: "All clear"))
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
