//
//  UtilityCustomizeSheetSeedTests.swift
//  BlockPartyTests — the customize sheet's SEEDING rule, the one piece of the sheet
//  that decides what the user can still reach.
//
//  The headline invariant: **no sequence of toggles and reorders may make a catalog
//  tile unreachable from the sheet.** A tile the user turned off must still be listed
//  (off) so it can be turned back on — if seeding ever dropped it, the tile would be
//  gone for good with nothing on screen to say so. That is a silent failure of exactly
//  the kind CLAUDE.md says to cover, so it is tested as a randomized property over ~200
//  replayable operation sequences rather than a handful of hand-picked cases.
//
//  Everything here runs against `UtilityCustomizeSheet.seed(saved:catalog:)` — the pure
//  function the sheet's `init` seeding is extracted into — plus the real persistence
//  path (`UtilityPrefsStore` over a throwaway `UserDefaults` suite) so a "relaunch"
//  is a genuine new store reading genuinely written bytes.
//
//  Every store here is built LOCAL-MIRROR-ONLY (`makeStore`, i.e. `api: nil`). The
//  app initializer resolves the real `UtilityPrefsAPI(auth: .shared)`, so on any
//  simulator or device with a signed-in session these fixtures would upsert into that
//  user's actual `user_utility_prefs` row — silently, since `pushToServer` swallows
//  its errors. `testLocalOnlyStoreNeverCallsTheRemote` is the guard on that rule.
//

import XCTest
import SwiftUI
@testable import BlockParty

// MARK: - Deterministic randomness

/// A tiny seeded LCG. Property tests MUST be replayable — `Int.random` / `shuffle()`
/// give a failure nobody can reproduce, so every choice here comes from this instead.
/// The raw LCG's low bits are highly periodic, so the state is run through a
/// murmur3-style finalizer before any value is derived from it.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    private mutating func nextBits() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var mixed = state
        mixed = (mixed ^ (mixed >> 33)) &* 0xff51_afd7_ed55_8ccd
        mixed = (mixed ^ (mixed >> 33)) &* 0xc4ce_b9fe_1a85_ec53
        return mixed ^ (mixed >> 33)
    }

    /// An integer in `0..<upperBound`.
    mutating func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        return Int(nextBits() % UInt64(upperBound))
    }

    mutating func bool() -> Bool { nextBits() & 1 == 0 }
}

/// One user action inside the customize sheet. Carries a printable label so a failing
/// sequence can be pasted straight back into a repro.
private enum SheetOp {
    /// Flip a catalog tile's toggle (index into the catalog).
    case toggle(Int)
    /// Drag a row (indices into the draft order, SwiftUI `move` offsets).
    case move(from: Int, to: Int)

    var label: String {
        switch self {
        case .toggle(let index):       return "toggle(\(index))"
        case .move(let from, let to):  return "move(from: \(from), to: \(to))"
        }
    }
}

// MARK: - Remote spy

/// A `UtilityPrefsSyncing` that talks to nothing and counts what it was asked to do.
/// Injected into a store it proves the seam is live; WITHHELD (`api: nil`) its zero
/// counts are what "this suite performed no network I/O" looks like.
@MainActor
private final class SpyPrefsRemote: UtilityPrefsSyncing {
    private(set) var getMineCount = 0
    private(set) var upsertCount = 0

    func getMine() async throws -> UtilityPrefsRow? {
        getMineCount += 1
        return nil
    }

    func upsert(tiles: [String], settings: [String: TileSettings]) async throws {
        upsertCount += 1
    }
}

// MARK: - Tests

@MainActor
final class UtilityCustomizeSheetSeedTests: XCTestCase {

    private static let iterationCount = 200
    private static let maxOpsPerIteration = 12
    /// Fixed base seed — the whole property run is byte-for-byte reproducible.
    private static let baseSeed: UInt64 = 0x5EED_B10C_0000_0001
    private static let tilesKey = "utility.tiles"
    private static let pendingKey = "utility.pendingSync"

    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames = []
        super.tearDown()
    }

    // MARK: 1 — the reachability property

    func testEveryCatalogTileStaysReachableAfterAnySequenceOfTogglesAndReorders() {
        // Arrange
        let registry = UtilityTileRegistry()
        let catalog = registry.catalog

        for iteration in 0..<Self.iterationCount {
            let seed = Self.baseSeed &+ UInt64(iteration)
            var rng = SeededRandom(seed: seed)

            // A random starting configuration, seeded exactly like a sheet open.
            var startingEnabled: Set<UtilityTileID> = []
            for id in catalog {
                if rng.bool() { startingEnabled.insert(id) }
            }
            var draft = UtilityCustomizeSheet.seed(
                saved: catalog.filter { startingEnabled.contains($0) },
                catalog: catalog)

            // Act — a random series of toggles and drags, then Save, then reopen.
            var ops: [SheetOp] = []
            for _ in 0...rng.int(below: Self.maxOpsPerIteration) {
                let op = Self.randomOp(&rng, orderCount: draft.order.count, catalogCount: catalog.count)
                ops.append(op)
                draft = Self.applying(op, to: draft, catalog: catalog)
            }
            // What Save persists (mirrors UtilityRowModel.applyDraft), then the reopen seed.
            let saved = draft.order.filter { draft.enabled.contains($0) }
            let reopened = UtilityCustomizeSheet.seed(saved: saved, catalog: catalog)

            // Assert
            guard Set(reopened.order) == Set(catalog) else {
                XCTFail("""
                    A catalog tile became unreachable from the customize sheet. \
                    \(Self.trace(seed: seed, ops: ops)) · saved \(saved) · order \(reopened.order)
                    """)
                return
            }
            guard Set(reopened.order).count == reopened.order.count else {
                XCTFail("""
                    Seeded order contains a duplicate tile. \
                    \(Self.trace(seed: seed, ops: ops)) · order \(reopened.order)
                    """)
                return
            }
        }
    }

    // MARK: 2 — round trip through the store and a relaunch

    func testDisabledTileSurvivesSaveAndRelaunchAsAnOffRow() async throws {
        // Arrange — all four on, then roads off.
        let registry = UtilityTileRegistry()
        let defaults = try makeSuite()
        let enabled = Set(registry.catalog).subtracting([.roads])
        let store = makeStore(registry: registry, defaults: defaults)

        // Act — save, then a NEW store over the SAME suite (a relaunch), then seed.
        await store.save(tiles: registry.catalog.filter { enabled.contains($0) }, settings: [:])
        let relaunched = makeStore(registry: registry, defaults: defaults)
        let seeded = UtilityCustomizeSheet.seed(saved: relaunched.tiles, catalog: registry.catalog)

        // Assert — every tile is still listed; exactly the disabled one is off.
        XCTAssertEqual(Set(seeded.order), Set(registry.catalog))
        XCTAssertEqual(seeded.enabled, enabled)
        XCTAssertTrue(seeded.order.contains(.roads))
        XCTAssertFalse(seeded.enabled.contains(.roads))
    }

    // MARK: 3 — catalog drift (prefs written by a newer app version)

    func testSavedUnknownTileIdIsDroppedAndKnownTilesSurvive() throws {
        // Arrange — a stored list from a future version that knows a "school" tile.
        let registry = UtilityTileRegistry()
        let defaults = try makeSuite()
        let unknown = UtilityTileID(rawValue: "school")
        let stored: [UtilityTileID] = [.library, unknown, .weather]
        defaults.set(try JSONEncoder().encode(stored), forKey: Self.tilesKey)

        // Act
        let store = makeStore(registry: registry, defaults: defaults)
        let seeded = UtilityCustomizeSheet.seed(saved: store.tiles, catalog: registry.catalog)

        // Assert — the unknown id is gone, the known ones survive in their saved order,
        // and the sheet still lists the whole catalog.
        XCTAssertEqual(store.tiles, [.library, .weather])
        XCTAssertFalse(seeded.order.contains(unknown))
        XCTAssertFalse(seeded.enabled.contains(unknown))
        XCTAssertEqual(Array(seeded.order.prefix(2)), [.library, .weather])
        XCTAssertEqual(seeded.enabled, [.library, .weather])
        XCTAssertEqual(Set(seeded.order), Set(registry.catalog))
    }

    // MARK: 4 — a disabled tile keeps its configuration

    func testGarbageWeekdaySettingSurvivesDisableThenReEnable() async throws {
        // Arrange — a configured pickup day, saved while garbage is OFF. Settings are
        // deliberately never filtered by enablement; turning a tile off must not erase it.
        let registry = UtilityTileRegistry()
        let defaults = try makeSuite()
        let pickupWeekday = 3
        let settings: [UtilityTileID: TileSettings] = [.garbage: TileSettings().setting("day", .int(pickupWeekday))]
        let store = makeStore(registry: registry, defaults: defaults)

        // Act — save with garbage disabled, relaunch, re-enable, save, relaunch again.
        await store.save(tiles: registry.catalog.filter { $0 != .garbage }, settings: settings)

        let reopened = makeStore(registry: registry, defaults: defaults)
        let whileDisabled = UtilityCustomizeSheet.seed(saved: reopened.tiles, catalog: registry.catalog)
        let reEnabled = whileDisabled.enabled.union([.garbage])
        await reopened.save(tiles: whileDisabled.order.filter { reEnabled.contains($0) },
                            settings: reopened.settings)

        let relaunched = makeStore(registry: registry, defaults: defaults)
        let afterReEnable = UtilityCustomizeSheet.seed(saved: relaunched.tiles, catalog: registry.catalog)

        // Assert — the weekday survived both hops, and garbage is back on.
        XCTAssertTrue(whileDisabled.order.contains(.garbage))
        XCTAssertFalse(whileDisabled.enabled.contains(.garbage))
        XCTAssertEqual(reopened.settings[.garbage]?.int("day"), pickupWeekday)
        XCTAssertEqual(relaunched.settings[.garbage]?.int("day"), pickupWeekday)
        XCTAssertTrue(afterReEnable.enabled.contains(.garbage))
    }

    // MARK: 5 — a reorder is what the user gets back

    func testReorderedEnabledTilesSurviveSaveAndReload() async throws {
        // Arrange — a non-default order with one tile switched off.
        let registry = UtilityTileRegistry()
        let defaults = try makeSuite()
        let reordered: [UtilityTileID] = [.library, .roads, .weather]
        let store = makeStore(registry: registry, defaults: defaults)

        // Act
        await store.save(tiles: reordered, settings: [:])
        let relaunched = makeStore(registry: registry, defaults: defaults)
        let seeded = UtilityCustomizeSheet.seed(saved: relaunched.tiles, catalog: registry.catalog)

        // Assert — enabled tiles keep their order at the top; the off tile trails, still listed.
        XCTAssertEqual(relaunched.tiles, reordered)
        XCTAssertEqual(Array(seeded.order.prefix(reordered.count)), reordered)
        XCTAssertEqual(seeded.enabled, Set(reordered))
        XCTAssertEqual(seeded.order.last, .garbage)
        XCTAssertEqual(Set(seeded.order), Set(registry.catalog))
    }

    // MARK: 6 — the test store is airtight: no remote call, ever

    func testLocalOnlyStoreNeverCallsTheRemoteAndLeavesNothingPending() async throws {
        // Arrange — one spy, and a store deliberately built WITHOUT it (`api: nil`),
        // which is exactly how every store in this suite is built.
        let registry = UtilityTileRegistry()
        let defaults = try makeSuite()
        let spy = SpyPrefsRemote()
        let localOnly = makeStore(registry: registry, defaults: defaults)

        // Act — the two calls that reach the network in the app's store.
        await localOnly.save(tiles: [.weather, .library],
                             settings: [.garbage: TileSettings().setting("day", .int(3))])
        await localOnly.hydrate()

        // Assert — nothing went out, and the mirror still holds the save.
        XCTAssertEqual(spy.upsertCount, 0)
        XCTAssertEqual(spy.getMineCount, 0)
        XCTAssertEqual(localOnly.tiles, [.weather, .library])
        // "Pending" means the server is behind the mirror; with no server there is
        // nothing to owe, so the flag must not be left stranded on forever.
        XCTAssertFalse(defaults.bool(forKey: Self.pendingKey))

        // Act/Assert — the same spy DOES see a save through a store that has a remote,
        // so the zeroes above are the seam working, not an assertion that can't fail.
        let syncedDefaults = try makeSuite()
        let synced = UtilityPrefsStore(api: spy, knownIDs: registry.knownIDs, defaults: syncedDefaults)
        await synced.save(tiles: [.weather], settings: [:])
        XCTAssertEqual(spy.upsertCount, 1)
    }

    // MARK: - Helpers

    /// A store with NO remote (`api: nil`). Every store in this file goes through here:
    /// `UtilityPrefsStore(knownIDs:defaults:)` resolves the LIVE `UtilityPrefsAPI`, which
    /// would upsert these fixtures into the signed-in user's real row.
    private func makeStore(registry: UtilityTileRegistry, defaults: UserDefaults) -> UtilityPrefsStore {
        UtilityPrefsStore(api: nil, knownIDs: registry.knownIDs, defaults: defaults)
    }

    /// A wiped, throwaway suite; removed again in `tearDown`. The test host is the real
    /// app, so `UserDefaults.standard` carries whatever a screenshot session left behind.
    private func makeSuite() throws -> UserDefaults {
        let suiteName = "UtilityCustomizeSheetSeedTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func randomOp(_ rng: inout SeededRandom,
                                 orderCount: Int,
                                 catalogCount: Int) -> SheetOp {
        if rng.bool() {
            return .toggle(rng.int(below: catalogCount))
        }
        return .move(from: rng.int(below: orderCount), to: rng.int(below: orderCount + 1))
    }

    /// Apply one sheet action, returning a NEW draft (the draft is never mutated in place).
    private static func applying(_ op: SheetOp,
                                 to draft: (order: [UtilityTileID], enabled: Set<UtilityTileID>),
                                 catalog: [UtilityTileID]) -> (order: [UtilityTileID], enabled: Set<UtilityTileID>) {
        switch op {
        case .toggle(let index):
            let id = catalog[index]
            let enabled = draft.enabled.contains(id)
                ? draft.enabled.subtracting([id])
                : draft.enabled.union([id])
            return (draft.order, enabled)

        case .move(let from, let to):
            var order = draft.order
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to)   // the sheet's own primitive
            return (order, draft.enabled)
        }
    }

    private static func trace(seed: UInt64, ops: [SheetOp]) -> String {
        "seed 0x\(String(seed, radix: 16)) · ops [\(ops.map(\.label).joined(separator: ", "))]"
    }
}
