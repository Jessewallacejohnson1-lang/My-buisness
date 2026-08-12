//
//  SolarSkyTests.swift
//  BlockPartyTests
//
//  Solar phase boundaries at the eight spec timestamps, elevation shape,
//  sunX anchoring, and the nil-sun-times fallback.
//

import XCTest
@testable import BlockParty

final class SolarSkyTests: XCTestCase {
    // Mock sun times from the spec: 2026-08-11, sunrise 06:13, sunset 21:02 (town time).
    private let sunrise = townDate(2026, 8, 11, 6, 13)
    private let sunset = townDate(2026, 8, 11, 21, 2)

    private func sky(at hour: Int, _ minute: Int, day: Int = 11) -> SolarSky {
        SolarSky(now: townDate(2026, 8, day, hour, minute), sunrise: sunrise, sunset: sunset)
    }

    func testPhaseAtTheEightSpecTimestamps() {
        // Boundaries: dawn 05:33–07:03, day 07:03–19:42, dusk 19:42–21:42.
        XCTAssertEqual(sky(at: 4, 30).phase, .night)
        XCTAssertEqual(sky(at: 6, 5).phase, .dawn)
        XCTAssertEqual(sky(at: 7, 15).phase, .day)
        XCTAssertEqual(sky(at: 10, 0).phase, .day)
        XCTAssertEqual(sky(at: 13, 0).phase, .day)
        XCTAssertEqual(sky(at: 18, 30).phase, .day)
        XCTAssertEqual(sky(at: 20, 25).phase, .dusk)
        XCTAssertEqual(sky(at: 22, 45).phase, .night)
    }

    func testPhaseBoundariesAreExact() {
        XCTAssertEqual(sky(at: 5, 32).phase, .night)
        XCTAssertEqual(sky(at: 5, 33).phase, .dawn)
        XCTAssertEqual(sky(at: 7, 2).phase, .dawn)
        XCTAssertEqual(sky(at: 7, 3).phase, .day)
        XCTAssertEqual(sky(at: 19, 41).phase, .day)
        XCTAssertEqual(sky(at: 19, 42).phase, .dusk)
        XCTAssertEqual(sky(at: 21, 41).phase, .dusk)
        XCTAssertEqual(sky(at: 21, 42).phase, .night)
    }

    func testSolarElevationShape() {
        XCTAssertEqual(SolarSky(now: sunrise, sunrise: sunrise, sunset: sunset).solarElevation, 0, accuracy: 0.001)
        XCTAssertEqual(SolarSky(now: sunset, sunrise: sunrise, sunset: sunset).solarElevation, 0, accuracy: 0.001)
        // Solar midpoint 13:37:30 peaks at 1.
        let midday = townDate(2026, 8, 11, 13, 37).addingTimeInterval(30)
        XCTAssertEqual(SolarSky(now: midday, sunrise: sunrise, sunset: sunset).solarElevation, 1, accuracy: 0.0001)
        // 10:00 AM: progress 227/889 → sin(π·0.2553) ≈ 0.719.
        XCTAssertEqual(sky(at: 10, 0).solarElevation, 0.719, accuracy: 0.005)
        // Clamped to 0 at night.
        XCTAssertEqual(sky(at: 4, 30).solarElevation, 0)
        XCTAssertEqual(sky(at: 22, 45).solarElevation, 0)
    }

    func testDayProgressRunsSunriseToSunset() {
        XCTAssertEqual(SolarSky(now: sunrise, sunrise: sunrise, sunset: sunset).dayProgress, 0, accuracy: 0.001)
        XCTAssertEqual(SolarSky(now: sunset, sunrise: sunrise, sunset: sunset).dayProgress, 1, accuracy: 0.001)
        XCTAssertLessThan(sky(at: 4, 30).dayProgress, 0)
        XCTAssertGreaterThan(sky(at: 22, 45).dayProgress, 1)
    }

    func testPhaseBlendIsContinuousAcrossBoundaries() {
        // Just before a boundary blend → 1, just after → 0.
        let pairs: [(Date, Date)] = [
            (townDate(2026, 8, 11, 5, 33).addingTimeInterval(-1), townDate(2026, 8, 11, 5, 33).addingTimeInterval(1)),
            (townDate(2026, 8, 11, 7, 3).addingTimeInterval(-1), townDate(2026, 8, 11, 7, 3).addingTimeInterval(1)),
            (townDate(2026, 8, 11, 19, 42).addingTimeInterval(-1), townDate(2026, 8, 11, 19, 42).addingTimeInterval(1)),
            (townDate(2026, 8, 11, 21, 42).addingTimeInterval(-1), townDate(2026, 8, 11, 21, 42).addingTimeInterval(1)),
        ]
        for (before, after) in pairs {
            let skyBefore = SolarSky(now: before, sunrise: sunrise, sunset: sunset)
            let skyAfter = SolarSky(now: after, sunrise: sunrise, sunset: sunset)
            XCTAssertGreaterThan(skyBefore.phaseBlend, 0.999, "blend should approach 1 before a boundary")
            XCTAssertLessThan(skyAfter.phaseBlend, 0.001, "blend should restart at 0 after a boundary")
            XCTAssertNotEqual(skyBefore.phase, skyAfter.phase)
        }
    }

    func testSunXTracksTheSunByDay() {
        XCTAssertEqual(sky(at: 13, 0).sunX, 407.0 / 889.0, accuracy: 0.001)
        XCTAssertEqual(SolarSky(now: sunrise, sunrise: sunrise, sunset: sunset).sunX, 0, accuracy: 0.001)
    }

    func testSunXAnchorsToNearestSolarEventAtNight() {
        // 22:45 — 103 min past sunset, 448 min to sunrise: anchor at sunset end.
        XCTAssertEqual(sky(at: 22, 45).sunX, 0)
        // 04:30 — 448 min past (yesterday's) sunset, 103 min to sunrise: anchor at sunrise end.
        XCTAssertEqual(sky(at: 4, 30).sunX, 1)
    }

    func testIsSunUpFlipsExactlyAtSunriseAndSunset() {
        XCTAssertFalse(SolarSky(now: sunrise.addingTimeInterval(-1), sunrise: sunrise, sunset: sunset).isSunUp)
        XCTAssertTrue(SolarSky(now: sunrise, sunrise: sunrise, sunset: sunset).isSunUp)
        XCTAssertTrue(SolarSky(now: sunset.addingTimeInterval(-1), sunrise: sunrise, sunset: sunset).isSunUp)
        XCTAssertFalse(SolarSky(now: sunset, sunrise: sunrise, sunset: sunset).isSunUp)
    }

    func testNilSunTimesFallBackToSixThirtyAndEightThirty() {
        let sky = SolarSky(now: townDate(2026, 8, 11, 12, 0), sunrise: nil, sunset: nil)
        XCTAssertTrue(sky.usedFallbackSunTimes)
        XCTAssertEqual(sky.sunrise, townDate(2026, 8, 11, 6, 30))
        XCTAssertEqual(sky.sunset, townDate(2026, 8, 11, 20, 30))
    }

    func testRebaseKeepsTheSkyTruthfulAcrossMidnight() {
        // The card stays mounted past midnight with yesterday's solar
        // times. Without re-dating, 10 AM reads as a permanent night
        // window; with it, the morning is a morning.
        let staleNow = townDate(2026, 8, 12, 10, 0)
        let rebasedRise = SolarSky.rebase(sunrise, ontoDayOf: staleNow)
        let rebasedSet = SolarSky.rebase(sunset, ontoDayOf: staleNow)
        XCTAssertEqual(rebasedRise, townDate(2026, 8, 12, 6, 13))
        XCTAssertEqual(rebasedSet, townDate(2026, 8, 12, 21, 2))

        let stale = SolarSky(now: staleNow, sunrise: sunrise, sunset: sunset)
        XCTAssertEqual(stale.phase, .night, "the failure mode the rebase exists for")
        let rebased = SolarSky(now: staleNow, sunrise: rebasedRise, sunset: rebasedSet)
        XCTAssertEqual(rebased.phase, .day)

        // Same-day rebasing is the identity, so applying it uniformly is safe.
        XCTAssertEqual(SolarSky.rebase(sunrise, ontoDayOf: townDate(2026, 8, 11, 13, 0)), sunrise)
        XCTAssertNil(SolarSky.rebase(nil, ontoDayOf: staleNow))
    }
}

/// Builds a Date from components in the town's timezone.
extension SolarSkyTests {
    /// The moon disc's height: the sun's sin arc run over the night.
    func testNightElevationArcsOverTheNightAndIsZeroByDay() {
        let sunrise = townDate(2026, 8, 11, 6, 13)
        let sunset = townDate(2026, 8, 11, 21, 2)
        func sky(_ date: Date) -> SolarSky {
            SolarSky(now: date, sunrise: sunrise, sunset: sunset)
        }

        XCTAssertEqual(sky(townDate(2026, 8, 11, 13, 0)).nightElevation, 0, "sun up")
        // Rising after sunset, peaking mid-night, descending toward sunrise.
        let early = sky(townDate(2026, 8, 11, 21, 30)).nightElevation
        let mid = sky(townDate(2026, 8, 12, 1, 38)).nightElevation
        let fourAM = sky(townDate(2026, 8, 11, 4, 0)).nightElevation
        let predawn = sky(townDate(2026, 8, 11, 5, 45)).nightElevation
        XCTAssertGreaterThan(early, 0)
        XCTAssertGreaterThan(mid, early)
        XCTAssertEqual(mid, 1, accuracy: 0.01, "solar-midnight peak")
        XCTAssertGreaterThan(fourAM, predawn, "the moon descends toward sunrise")
        XCTAssertGreaterThan(predawn, 0, "still up until the sun takes over")
    }
}

func townDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return Town.calendar.date(from: components)!
}
