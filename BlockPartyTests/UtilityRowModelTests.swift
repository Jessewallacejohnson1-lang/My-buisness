//
//  UtilityRowModelTests.swift
//  BlockPartyTests — reachability and empty-state behavior for the Utility Row.
//

import XCTest
@testable import BlockParty

@MainActor
final class UtilityRowModelTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames = []
        super.tearDown()
    }

    func testCustomizeTileRemainsVisibleAfterSavingTwoEnabledTiles() throws {
        let model = try makeModel(tiles: [.roads, .library], hasSavedOnce: true)

        XCTAssertTrue(model.showCustomizeTile)
    }

    func testCustomizeTileIsVisibleOnFirstRun() throws {
        let model = try makeModel()

        XCTAssertTrue(model.showCustomizeTile)
    }

    func testCustomizeTileIsVisibleWithNoEnabledTiles() throws {
        let model = try makeModel(tiles: [], hasSavedOnce: true)

        XCTAssertTrue(model.showCustomizeTile)
    }

    private func makeModel(tiles: [UtilityTileID]? = nil,
                           hasSavedOnce: Bool = false) throws -> UtilityRowModel {
        let suiteName = "UtilityRowModelTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        if let tiles {
            defaults.set(try JSONEncoder().encode(tiles), forKey: "utility.tiles")
        }
        defaults.set(hasSavedOnce, forKey: "utility.hasSavedOnce")

        let registry = UtilityTileRegistry()
        let prefs = UtilityPrefsStore(knownIDs: registry.knownIDs, defaults: defaults)
        return UtilityRowModel(registry: registry, prefs: prefs)
    }
}
