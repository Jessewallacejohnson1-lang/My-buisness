//
//  UtilityPrefsCodecTests.swift
//  BlockPartyTests — persistence + forward-compat for the Utility Row prefs:
//  tile-id / settings JSON round-trips, the "drop unknown ids" rule the spec
//  requires, and the shared PostgREST decoder (snake_case + dates + nulls).
//

import XCTest
@testable import BlockParty

@MainActor
final class UtilityPrefsCodecTests: XCTestCase {

    // MARK: UtilityTileID — codes as a plain string; accepts unknown ids

    func testTileIDCodesAsPlainStringArray() throws {
        let ids: [UtilityTileID] = [.weather, .garbage]
        let data = try JSONEncoder().encode(ids)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["weather","garbage"]"#)
        let back = try JSONDecoder().decode([UtilityTileID].self, from: data)
        XCTAssertEqual(back, ids)
    }

    func testTileIDDecodesUnknownId() throws {
        let data = Data(#"["school"]"#.utf8)
        let back = try JSONDecoder().decode([UtilityTileID].self, from: data)
        XCTAssertEqual(back, [UtilityTileID(rawValue: "school")])   // forward compat: no crash
    }

    // MARK: TileSettings + JSONValue round-trips

    func testTileSettingsRoundTrip() throws {
        let settings = TileSettings(["day": .int(3)])
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"day":3}"#)
        let back = try JSONDecoder().decode(TileSettings.self, from: data)
        XCTAssertEqual(back.int("day"), 3)
    }

    func testJSONValueRoundTripMixed() throws {
        let value = JSONValue.object([
            "s": .string("hi"),
            "n": .int(7),
            "d": .double(1.5),
            "b": .bool(true),
            "arr": .array([.int(1), .int(2)]),
        ])
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(back, value)
    }

    func testJSONValueDistinguishesBoolFromInt() throws {
        // JSON `true` must decode as .bool, not .int(1).
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("true".utf8)), .bool(true))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("3".utf8)), .int(3))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("3.5".utf8)), .double(3.5))
    }

    // MARK: Forward compat — sanitize drops unknown ids, de-dups, keeps order

    func testSanitizeDropsUnknownAndDedups() {
        let known = Set(UtilityTileID.defaults)
        let input: [UtilityTileID] = [.weather, "school", .garbage, .weather]
        XCTAssertEqual(UtilityPrefsStore.sanitize(input, known: known), [.weather, .garbage])
    }

    func testSanitizePreservesOrder() {
        let known = Set(UtilityTileID.defaults)
        XCTAssertEqual(UtilityPrefsStore.sanitize([.library, .weather], known: known), [.library, .weather])
    }

    func testMapSettingsKeysBecomeTileIDs() {
        let mapped = UtilityPrefsStore.mapSettings(["garbage": TileSettings(["day": .int(3)])])
        XCTAssertEqual(mapped[.garbage]?.int("day"), 3)
    }

    // MARK: Shared PostgREST decoder — snake_case, dates (fractional + plain), nulls

    func testDecodePrefsRowSnakeCaseAndFractionalDate() throws {
        let json = Data(#"""
        {"user_id":"abc-123","tiles":["weather","garbage"],"settings":{"garbage":{"day":3}},"updated_at":"2026-07-24T12:00:00.123456+00:00"}
        """#.utf8)
        let row = try SupabaseCoding.decoder.decode(UtilityPrefsRow.self, from: json)
        XCTAssertEqual(row.userId, "abc-123")
        XCTAssertEqual(row.tiles, ["weather", "garbage"])
        XCTAssertEqual(row.settings["garbage"]?.int("day"), 3)
    }

    func testDecodeTownStatusPlainDateAndNulls() throws {
        let json = Data(#"""
        {"id":"1","town":"st-joseph-mn","kind":"roads","status":"advisory","headline":"Lane closure","detail":null,"link":null,"active":true,"updated_at":"2026-07-24T12:00:00+00:00"}
        """#.utf8)
        let notice = try SupabaseCoding.decoder.decode(TownStatusNotice.self, from: json)
        XCTAssertEqual(notice.kind, "roads")
        XCTAssertEqual(notice.headline, "Lane closure")
        XCTAssertNil(notice.detail)
        XCTAssertTrue(notice.active)
    }
}
