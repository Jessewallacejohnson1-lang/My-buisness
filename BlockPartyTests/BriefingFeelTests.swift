//
//  BriefingFeelTests.swift
//  Block Party — what the feel pass can actually assert.
//
//  SwiftUI's `Animation` is opaque: a spring's response and damping have no
//  runtime accessors, so "the poll pops on Motion.select" is NOT testable and is
//  verified by screen recording instead (same limitation UtilityRowMotionTests
//  documents). What IS testable: that the motion tokens the spec names exist, the
//  numeric timings, and the once-per-day rule behind the caught-up celebration.
//

import XCTest
@testable import BlockParty

final class BriefingFeelTests: XCTestCase {

    private var suite: UserDefaults!
    private let suiteName = "briefing.feel.tests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        suite = nil
        super.tearDown()
    }

    // MARK: - Once per day, not once per launch

    func testFirstArrivalOnADayCelebrates() {
        XCTAssertTrue(CaughtUpMemory.shouldCelebrate("2026-08-05", store: suite))
    }

    func testSecondArrivalOnTheSameDayDoesNot() {
        CaughtUpMemory.remember("2026-08-05", store: suite)
        XCTAssertFalse(CaughtUpMemory.shouldCelebrate("2026-08-05", store: suite),
                       "reaching the bottom again the same day must stay quiet")
    }

    func testANewBriefingDayCelebratesAgain() {
        CaughtUpMemory.remember("2026-08-05", store: suite)
        XCTAssertTrue(CaughtUpMemory.shouldCelebrate("2026-08-06", store: suite),
                      "a new briefing earns a new draw-on")
    }

    /// The footer renders before a payload exists, so an empty date must not burn
    /// the day's celebration.
    func testAnEmptyDateNeverCelebratesAndNeverStamps() {
        XCTAssertFalse(CaughtUpMemory.shouldCelebrate("", store: suite))
        CaughtUpMemory.remember("", store: suite)
        XCTAssertNil(suite.string(forKey: CaughtUpMemory.key))
    }

    /// The key is new on purpose: `hygge.*` and `utility.*` are frozen, and reusing
    /// one signs people out or drops their tile preferences.
    func testTheMemoryKeyIsNamespacedToBriefing() {
        XCTAssertTrue(CaughtUpMemory.key.hasPrefix("briefing."))
    }

    // MARK: - Timings the spec names

    func testPollFillDurationMatchesTheSpec() {
        XCTAssertEqual(DailyTouchCard.fillDuration, 0.30, accuracy: 0.0001)
    }

    /// Token identity, not token values — see the file comment.
    @MainActor
    func testTheMotionTokensTheBriefingUsesExist() {
        _ = Motion.select
        _ = Motion.tilePress
        _ = Motion.smooth
    }

    /// The briefing continues the Today entrance rather than introducing a second,
    /// near-identical one. If these drift, the modules and the almanac card stop
    /// moving together.
    func testTheBriefingReusesTheTodayEntranceTiming() {
        XCTAssertEqual(RevealTiming.stagger, 0.05, accuracy: 0.0001)
        XCTAssertEqual(RevealTiming.rise, 22, accuracy: 0.0001)
        XCTAssertEqual(RevealTiming.duration, 0.48, accuracy: 0.0001)
    }

    // MARK: - Module order

    func testModuleOrderIsTheBriefingRunningOrder() {
        XCTAssertEqual(BriefingModuleID.order,
                       [.almanac, .utility, .happeningSoon, .dailyTouch, .spotlight, .caughtUp])
    }

    func testAnUnknownModuleIdDecodesRatherThanFailing() {
        let id: BriefingModuleID = "someV2Module"
        XCTAssertEqual(id.rawValue, "someV2Module")
        XCTAssertFalse(BriefingModuleID.order.contains(id))
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
