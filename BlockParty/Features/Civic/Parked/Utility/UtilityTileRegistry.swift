//
//  UtilityTileRegistry.swift
//  Block Party — the Utility Row's single source of truth. The row UI AND the
//  customize sheet render PURELY from this. Adding a future tile requires exactly:
//  one provider (Phase 1), one entry here, one gradient token (UtilityTileColor) —
//  and ZERO edits to the row or sheet views.
//

import SwiftUI

/// Everything the row + sheet need to render one tile, independent of its data.
struct UtilityTileDescriptor: Identifiable {
    let id: UtilityTileID
    /// Shown as the tile's label and the customize-sheet row title.
    let displayName: String
    /// Fixed label glyph + customize-sheet preview symbol. The live tile prefers
    /// the provider's content symbol (e.g. weather's condition) when present.
    let symbol: String
    /// The static gradient token [top, bottom] hex. A provider's content may
    /// override per-value (weather → live condition); see UtilityTileContent.gradientHex.
    let gradient: [UInt32]
    /// One-line description for the customize sheet.
    let summary: String
    /// The tile's data source (one persistent instance).
    let provider: UtilityTileProvider
    /// Optional inline settings editor for the customize sheet (Phase 3). Given the
    /// current per-tile settings + an apply callback. nil = no settings.
    let settingsEditor: ((TileSettings, @escaping (TileSettings) -> Void) -> AnyView)?
}

@MainActor
final class UtilityTileRegistry {
    /// Full V1 catalog order (also the customize-sheet order).
    let catalog: [UtilityTileID]
    private let byID: [UtilityTileID: UtilityTileDescriptor]

    init() {
        let entries: [UtilityTileDescriptor] = [
            UtilityTileDescriptor(
                id: .weather, displayName: "Weather", symbol: "cloud.sun.fill",
                gradient: UtilityTileGradient.weather,
                summary: "Temperature, feels-like, air quality and rain at a glance.",
                provider: WeatherTileProvider(), settingsEditor: nil),
            UtilityTileDescriptor(
                id: .garbage, displayName: "Garbage", symbol: "trash.fill",
                gradient: UtilityTileGradient.garbage,
                summary: "Your next trash and recycling pickup.",
                provider: GarbageTileProvider(),
                settingsEditor: { settings, apply in
                    AnyView(GarbageWeekdaySetting(settings: settings, apply: apply))
                }),
            UtilityTileDescriptor(
                id: .roads, displayName: "Roads", symbol: "road.lanes",
                gradient: UtilityTileGradient.roads,
                summary: "Town road closures and advisories.",
                provider: RoadsTileProvider(), settingsEditor: nil),
            UtilityTileDescriptor(
                id: .library, displayName: "Library", symbol: "book.fill",
                gradient: UtilityTileGradient.library,
                summary: "Great River Library — St. Cloud (nearest branch) hours.",
                provider: LibraryTileProvider(), settingsEditor: nil),
        ]
        catalog = entries.map(\.id)
        byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    /// Ids this app version knows — used to drop unknown stored prefs (forward compat).
    var knownIDs: Set<UtilityTileID> { Set(catalog) }

    func descriptor(_ id: UtilityTileID) -> UtilityTileDescriptor? { byID[id] }
}
