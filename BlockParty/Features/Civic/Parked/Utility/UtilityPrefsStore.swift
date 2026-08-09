//
//  UtilityPrefsStore.swift
//  Block Party — the Utility Row's preference store: a UserDefaults mirror for
//  instant offline render, hydrated from Supabase (user_utility_prefs) once
//  available. Unknown tile ids in stored prefs are dropped (forward compat).
//
//  The Supabase leg is behind ONE seam (`UtilityPrefsSyncing`) and is optional:
//  `init(api: nil)` is a local-mirror-only store that never touches the network.
//

import Foundation
import Combine

/// The store's ONLY door to the network. Extracted so a test (or a preview) can
/// build a store with no door at all — see `UtilityPrefsStore.init(api:…)`.
/// Signatures mirror `UtilityPrefsAPI` exactly; `@MainActor` is explicit rather
/// than inherited from the module default so the test target (which does not set
/// `SWIFT_DEFAULT_ACTOR_ISOLATION`) can conform to it without surprises.
@MainActor
protocol UtilityPrefsSyncing {
    func getMine() async throws -> UtilityPrefsRow?
    func upsert(tiles: [String], settings: [String: TileSettings]) async throws
}

/// The real, Supabase-backed door. Declared here (same module, so not a
/// retroactive conformance) to keep `UtilityPrefsAPI` a plain transport type.
extension UtilityPrefsAPI: UtilityPrefsSyncing {}

@MainActor
final class UtilityPrefsStore: ObservableObject {
    /// Enabled tiles, in order.
    @Published private(set) var tiles: [UtilityTileID]
    /// Per-tile settings, keyed by tile id.
    @Published private(set) var settings: [UtilityTileID: TileSettings]
    /// True once the user has saved at least once (drives Phase-3 first-run UI).
    @Published private(set) var hasSavedOnce: Bool

    /// The remote, or `nil` for a LOCAL-MIRROR-ONLY store: `hydrate()` pulls
    /// nothing and `pushToServer()` writes nothing. Tests use `nil` so a suite run
    /// can never POST fixtures to the signed-in user's real `user_utility_prefs` row.
    private let api: (any UtilityPrefsSyncing)?
    /// Ids this app version can render — anything else in stored prefs is ignored.
    private let knownIDs: Set<UtilityTileID>
    /// The mirror's backing store. Injectable so a test can run over a throwaway
    /// suite — and construct a SECOND store over the same suite to simulate a
    /// relaunch reading genuinely written bytes.
    private let defaults: UserDefaults

    private static let tilesKey = "utility.tiles"
    private static let settingsKey = "utility.settings"
    private static let savedKey = "utility.hasSavedOnce"
    private static let pendingKey = "utility.pendingSync"   // an offline save awaiting upsert

    /// The app's store: syncs with Supabase. `api` is resolved in the (MainActor)
    /// init body, never as a default argument — see the CLAUDE.md
    /// MainActor-default-arg gotcha. (`UserDefaults.standard` is nonisolated, so
    /// it is safe as a default.)
    convenience init(knownIDs: Set<UtilityTileID> = Set(UtilityTileID.defaults),
                     defaults: UserDefaults = .standard) {
        self.init(api: UtilityPrefsAPI(auth: .shared), knownIDs: knownIDs, defaults: defaults)
    }

    /// Explicit-remote init. `api: nil` means local-mirror-only — no network at
    /// all. `api` has NO default here on purpose: "which remote?" must be a
    /// decision, so a caller can never fall into a live POST by omission.
    init(api: (any UtilityPrefsSyncing)?,
         knownIDs: Set<UtilityTileID> = Set(UtilityTileID.defaults),
         defaults: UserDefaults = .standard) {
        self.api = api
        self.knownIDs = knownIDs
        self.defaults = defaults

        // Instant: read the UserDefaults mirror (or fall back to defaults) so the
        // row renders immediately, offline, on the very first frame.
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
        // Local-mirror-only: nothing to pull, and nothing owed (see pushToServer).
        guard let api else {
            setPending(false)
            return
        }
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
        // No remote: the UserDefaults mirror IS the source of truth. `pendingSync`
        // means "the server is behind the mirror" — with no server there is nobody
        // to be behind, so the honest value is false. (Setting it here rather than
        // skipping it in `save` keeps the rule in ONE place, and also clears a flag
        // inherited from a mirror a syncing build left dirty.)
        guard let api else {
            setPending(false)
            return
        }
        let idStrings = tiles.map(\.rawValue)
        let settingStrings = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        do {
            try await api.upsert(tiles: idStrings, settings: settingStrings)
            setPending(false)
        } catch {
            // Stays pending; retried on the next hydrate / launch.
        }
    }

    private var isPending: Bool { defaults.bool(forKey: Self.pendingKey) }
    private func setPending(_ value: Bool) { defaults.set(value, forKey: Self.pendingKey) }

    /// Update one tile's settings (e.g. garbage weekday) and persist.
    func updateSettings(_ id: UtilityTileID, _ value: TileSettings) async {
        var next = settings
        next[id] = value
        await save(tiles: tiles, settings: next)
    }

    // MARK: - Private

    private func mirror() {
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
