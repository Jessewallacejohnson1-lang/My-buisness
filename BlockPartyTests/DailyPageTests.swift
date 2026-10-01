//
//  DailyPageTests.swift
//  BlockPartyTests — the Daily tab: its sample Spotlight, the low sun that throws the
//  card's shadow across the yellow, and the tilt.
//

import XCTest
@testable import BlockParty

final class DailyPageTests: XCTestCase {
    #if DEBUG
    /// The sample Spotlight names its photos by bundle resource; a renamed or removed
    /// image would leave a grey hole in the card instead of failing anywhere else.
    func testSampleSpotlightPhotosAreBundled() {
        XCTAssertNotNil(DailySpotlight.sample.portrait)
        XCTAssertEqual(DailySpotlight.sample.photos.count, 2)
    }
    #endif

    /// Morning throws the shadow right, dinner throws it left, both long; midday drops it
    /// short and straight down.
    func testTheSunSwingsTheShadowAcrossTheDay() {
        let sunrise = DailySun.shadow(hour: 6), midday = DailySun.shadow(hour: 13.5)
        let sunset = DailySun.shadow(hour: 21)
        XCTAssertEqual(sunrise.x, 46, accuracy: 0.001)
        XCTAssertEqual(sunset.x, -46, accuracy: 0.001)
        XCTAssertEqual(midday.x, 0, accuracy: 0.001)
        XCTAssertEqual(sunrise.y, 36, accuracy: 0.001)
        XCTAssertEqual(midday.y, 12, accuracy: 0.001)
        XCTAssertGreaterThan(sunrise.blur, midday.blur)
    }

    /// At night the shadow is the midday one, like a streetlight overhead (Jesse, 2026-10-01).
    func testNightKeepsTheMiddayShadow() {
        let midday = DailySun.shadow(hour: 13.5)
        for hour in [0.0, 3, 5.9, 21.1, 23.5] {
            let night = DailySun.shadow(hour: hour)
            XCTAssertEqual(night.x, midday.x, accuracy: 0.001, "hour \(hour)")
            XCTAssertEqual(night.y, midday.y, accuracy: 0.001, "hour \(hour)")
        }
    }

    /// The sun keeps the Town's clock, not the phone's.
    func testTheSunReadsTheTownsHour() {
        // 2026-10-01 12:30 UTC is 7:30 in the morning in St. Joseph (CDT, UTC-5).
        let date = Date(timeIntervalSince1970: 1_790_857_800)
        XCTAssertEqual(DailySun.hour(at: date), 7.5, accuracy: 0.001)
    }

    /// The lean is measured from the way the phone is held, stops at a full lean, and the
    /// rest creeps toward the hand so a new grip reads as level again.
    func testTiltLeansFromTheRestAndTheRestFollows() {
        var rest = (x: 0.0, z: -0.5)
        let lean = DailyTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest)
        XCTAssertEqual(lean.x, 1, accuracy: 0.001, "a lean past the range stops at a full lean")
        XCTAssertEqual(lean.y, -0.5, accuracy: 0.001)
        XCTAssertGreaterThan(rest.x, 0)
        XCTAssertLessThan(rest.x, 0.6)

        for _ in 0..<600 { _ = DailyTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest) }
        let settled = DailyTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest)
        XCTAssertEqual(settled.x, 0, accuracy: 0.01, "held still for 10 s, the grip reads as level")
    }
}
