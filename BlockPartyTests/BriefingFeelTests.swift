//
//  BriefingFeelTests.swift
//  Block Party — what the feel pass can actually assert.
//
//  SwiftUI's `Animation` is opaque: a spring's response and damping have no
//  runtime accessors, so "the poll pops on Motion.select" is NOT testable and is
//  verified by screen recording instead (same limitation UtilityRowMotionTests
//  documents). What IS testable: that the motion tokens the spec names exist and
//  the numeric timings.
//
//  The caught-up celebration and the poll-fill timing left with the Today
//  strip-down (`CaughtUpFooter`, `DailyTouchCard`); their tests went with them.
//

import XCTest
@testable import BlockParty

final class BriefingFeelTests: XCTestCase {

    // MARK: - Timings the spec names

    /// Token identity, not token values — see the file comment.
    @MainActor
    func testTheMotionTokensTheBriefingUsesExist() {
        _ = Motion.select
        _ = Motion.tilePress
        _ = Motion.smooth
    }

    /// The briefing continues the Today entrance rather than introducing a second,
    /// near-identical one. If these drift, the modules stop
    /// moving together.
    func testTheBriefingReusesTheTodayEntranceTiming() {
        XCTAssertEqual(RevealTiming.stagger, 0.05, accuracy: 0.0001)
        XCTAssertEqual(RevealTiming.rise, 22, accuracy: 0.0001)
        XCTAssertEqual(RevealTiming.duration, 0.48, accuracy: 0.0001)
    }

    // MARK: - Module order

    /// The Today surface was stripped back to chrome: the registry ships EMPTY and
    /// the feed renders nothing. This is the guard that an accidental re-add gets
    /// noticed — and the line to update, deliberately, when modules come back.
    @MainActor
    func testTheRegistryShipsWithNoModules() {
        XCTAssertTrue(FeedRegistry().modules.isEmpty,
                      "Today renders nothing until a module is registered again")
    }

    /// The registry still answers a lookup rather than trapping — the property that
    /// let an id from a newer build decode and be skipped.
    @MainActor
    func testAnUnknownModuleIdDecodesRatherThanFailing() {
        let id: FeedModuleID = "someV2Module"
        let module = FeedRegistry().module(for: id)
        XCTAssertEqual(id.rawValue, "someV2Module")
        XCTAssertNil(module)
    }

    // MARK: - Date label

    func testBriefingDateParsesInTownTime() throws {
        let date = try XCTUnwrap(BriefingDate.parse("2026-08-05"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Town.timeZone
        XCTAssertEqual(cal.component(.day, from: date), 5)
        XCTAssertEqual(cal.component(.month, from: date), 8)
    }

    func testBriefingDateRejectsMalformedInput() {
        XCTAssertNil(BriefingDate.parse("not-a-date"))
        XCTAssertNil(BriefingDate.parse(""))
        XCTAssertNil(BriefingDate.eyebrow(for: "2026-13"))
    }
}
