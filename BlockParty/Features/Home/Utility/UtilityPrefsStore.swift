//
//  UtilityPrefsStore.swift
//  Block Party — the Utility Row's preference store: a UserDefaults mirror for
//  instant offline render, hydrated from Supabase (user_utility_prefs) once
//  available. Unknown tile ids in stored prefs are dropped (forward compat).
//

import Foundation
import Combine

@MainActor
final class UtilityPrefsStore: ObservableObject {
    /// Enabled tiles, in order.
    @Published private(set) var tiles: [UtilityTileID]
    /// Per-tile settings, keyed by tile id.
    @Published private(set) var settings: [UtilityTileID: TileSettings]
    /// True once the user has saved at least once (drives Phase-3 first-run UI).
    @Published private(set) var hasSavedOnce: Bool

    private let api: UtilityPrefsAPI
    /// Ids this app version can render — anything else in stored prefs is ignored.
    private let knownIDs: Set<UtilityTileID>

    private static let tilesKey = "utility.tiles"
    private static let settingsKey = "utility.settings"
    private static let savedKey = "utility.hasSavedOnce"
    private static let pendingKey = "utility.pendingSync"   // an offline save awaiting upsert

    init(api: UtilityPrefsAPI? = nil,
         knownIDs: Set<UtilityTileID> = Set(UtilityTileID.defaults)) {
        // Resolve the MainActor default in the (MainActor) init body, never as a
        // default argument — see the CLAUDE.md MainActor-default-arg gotcha.
        self.api = api ?? UtilityPrefsAPI(auth: .shared)
        self.knownIDs = knownIDs

        // Instant: read the UserDefaults mirror (or fall back to defaults) so the
        // row renders immediately, offline, on the very first frame.
        let defaults = UserDefaults.standard
        self.hasSavedOnce = defaults.bool(forKey: Self.savedKey)

        if let raw = defaults.data(forKey: Self.tilesKey),
           let stored = try? JSONDecoder().decode([UtilityTileID].self, from: raw) {
            self.tiles = Self.sanitize(stored, known: knownIDs)
        } else {
            self.tiles = UtilityTileID.defaults
        }

        if let raw = defaults.data(forKey: Self.settingsKey),
           let stored = try? JSONDecoder().decode([String: TileSettings].self, from: raw) {
            self.settings = Self.mapSettings(stored)
        } else {
            self.settings = [:]
        }
    }

    /// Pull the server row and reconcile (call once per session after sign-in).
    /// A missing row or a network failure leaves the mirrored state untouched.
    func hydrate() async {
        // If a local save never reached the server (offline), the mirror is NEWER
        // than the server row — push it instead of letting a stale row overwrite
        // the un-synced edit (data loss).
        if isPending {
            await pushToServer()
            return
        }
        guard let row = try? await api.getMine() else { return }
        tiles = Self.sanitize(row.tiles.map { UtilityTileID(rawValue: $0) }, known: knownIDs)
        settings = Self.mapSettings(row.settings)
        hasSavedOnce = true          // a server row means they've configured before
        mirror()
    }

    /// Persist a new configuration: UserDefaults immediately (so the row updates
    /// and survives relaunch offline), then push to Supabase.
    func save(tiles newTiles: [UtilityTileID], settings newSettings: [UtilityTileID: TileSettings]) async {
        tiles = newTiles
        settings = newSettings
        hasSavedOnce = true
        setPending(true)   // dirty until the server confirms — protects an offline edit
        mirror()
        await pushToServer()
    }

    /// Upsert local prefs to Supabase; clears the pending flag on success, leaves
    /// it set (retried on the next hydrate) on failure.
    private func pushToServer() async {
        let idStrings = tiles.map(\.rawValue)
        let settingStrings = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        do {
            try await api.upsert(tiles: idStrings, settings: settingStrings)
            setPending(false)
        } catch {
            // Stays pending; retried on the next hydrate / launch.
        }
    }

    private var isPending: Bool { UserDefaults.standard.bool(forKey: Self.pendingKey) }
    private func setPending(_ value: Bool) { UserDefaults.standard.set(value, forKey: Self.pendingKey) }

    /// Update one tile's settings (e.g. garbage weekday) and persist.
    func updateSettings(_ id: UtilityTileID, _ value: TileSettings) async {
        var next = settings
        next[id] = value
        await save(tiles: tiles, settings: next)
    }

    // MARK: - Private

    private func mirror() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(tiles) { defaults.set(data, forKey: Self.tilesKey) }
        let settingStrings = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(settingStrings) { defaults.set(data, forKey: Self.settingsKey) }
        defaults.set(hasSavedOnce, forKey: Self.savedKey)
    }

    /// Drop unknown ids (forward compat) and de-dup while preserving order.
    /// `nonisolated` so it's unit-testable without the MainActor store.
    nonisolated static func sanitize(_ ids: [UtilityTileID], known: Set<UtilityTileID>) -> [UtilityTileID] {
        var seen = Set<UtilityTileID>()
        return ids.filter { known.contains($0) && seen.insert($0).inserted }
    }

    nonisolated static func mapSettings(_ raw: [String: TileSettings]) -> [UtilityTileID: TileSettings] {
        Dictionary(uniqueKeysWithValues: raw.map { (UtilityTileID(rawValue: $0.key), $0.value) })
    }
}
