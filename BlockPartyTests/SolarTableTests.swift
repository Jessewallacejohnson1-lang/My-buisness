//
//  SolarTableTests.swift
//  BlockPartyTests
//
//  The scrub's solar LUT: minute-exact parity with SolarSky across all
//  1440 minutes (the table is BUILT from the model, and this sweep is
//  what keeps them from ever drifting apart), inter-minute continuity —
//  including across the dusk→night phase wrap — clamping beyond the day
//  bounds, and the fallback sun-times passthrough.
//

import XCTest
@testable import BlockParty

final class SolarTableTests: XCTestCase {
    private let sunrise = townDate(2026, 8, 11, 6, 13)
    private let sunset = townDate(2026, 8, 11, 21, 2)
    private let noon = townDate(2026, 8, 11, 12, 0)
    private let dayStart = townDate(2026, 8, 11, 0, 0)

    private func table() -> SolarTable {
        SolarTable(day: noon, sunrise: sunrise, sunset: sunset)
    }

    // MARK: Parity — every minute of the day

    func testSampleMatchesSolarSkyAtEveryMinute() {
        let table = table()
        for minute in 0..<(24 * 60) {
            let moment = dayStart.addingTimeInterval(Double(minute) * 60)
            let direct = SolarSky(now: moment, sunrise: sunrise, sunset: sunset)
            let sampled = table.sample(at: moment)
            XCTAssertEqual(sampled.phase, direct.phase, "phase at minute \(minute)")
            XCTAssertEqual(
                sampled.phaseBlend, direct.phaseBlend, accuracy: 1e-9,
                "phaseBlend at minute \(minute)")
            XCTAssertEqual(
                sampled.solarElevation, direct.solarElevation, accuracy: 1e-9,
                "solarElevation at minute \(minute)")
            XCTAssertEqual(
                sampled.dayProgress, direct.dayProgress, accuracy: 1e-9,
                "dayProgress at minute \(minute)")
            XCTAssertEqual(sampled.isSunUp, direct.isSunUp, "isSunUp at minute \(minute)")
            XCTAssertEqual(
                sampled.nightElevation, direct.nightElevation, accuracy: 1e-9,
                "nightElevation at minute \(minute)")
        }
    }

    // MARK: Inter-minute samples — between the neighbors, never a jump

    func testMidMinuteSamplesInterpolateBetweenNeighbors() {
        let table = table()
        // Mid-morning, deep inside the day phase: the lerp is exact
        // because phaseBlend is linear in time there.
        let moment = townDate(2026, 8, 11, 10, 30).addingTimeInterval(30)
        let direct = SolarSky(now: moment, sunrise: sunrise, sunset: sunset)
        let sampled = table.sample(at: moment)
        XCTAssertEqual(sampled.phase, direct.phase)
        XCTAssertEqual(sampled.phaseBlend, direct.phaseBlend, accuracy: 1e-6)
        // Elevation is a sine — the chord sits within a hair of the arc.
        XCTAssertEqual(sampled.solarElevation, direct.solarElevation, accuracy: 1e-5)
    }

    func testSamplingIsContinuousAcrossTheDuskNightWrap() {
        let table = table()
        let duskEnd = sunset.addingTimeInterval(40 * 60)
        var previous = table.sample(at: duskEnd.addingTimeInterval(-120))
        for second in stride(from: -110, through: 120, by: 10) {
            let sky = table.sample(at: duskEnd.addingTimeInterval(Double(second)))
            let before = HorizonPalette.skyStops(for: previous)
            let after = HorizonPalette.skyStops(for: sky)
            for (a, b) in zip(before, after) {
                let jump = max(
                    abs(a.color.r - b.color.r),
                    abs(a.color.g - b.color.g),
                    abs(a.color.b - b.color.b))
                XCTAssertLessThan(jump, 0.01, "sky jump \(jump) at \(second)s from duskEnd")
            }
            previous = sky
        }
    }

    // MARK: Bounds — the rubber band's overshoot clamps, truthfully dated

    func testSamplesBeyondTheDayClampButKeepTheirOwnNow() {
        let table = table()
        let dayEnd = townDate(2026, 8, 12, 0, 0)
        let overshoot = dayEnd.addingTimeInterval(30 * 60)
        let clamped = table.sample(at: overshoot)
        let atEnd = table.sample(at: dayEnd)
        XCTAssertEqual(clamped.phase, atEnd.phase)
        XCTAssertEqual(clamped.phaseBlend, atEnd.phaseBlend, accuracy: 1e-9)
        XCTAssertEqual(clamped.solarElevation, atEnd.solarElevation, accuracy: 1e-9)
        // isSunUp and the pill's readout stay the requested instant's.
        XCTAssertEqual(clamped.now, overshoot)

        let undershoot = table.sample(at: dayStart.addingTimeInterval(-30 * 60))
        XCTAssertEqual(undershoot.phase, table.sample(at: dayStart).phase)
    }

    // MARK: Fallback sun times ride through the reference SolarSky

    func testFallbackSunTimesMatchSolarSkys() {
        let table = SolarTable(day: noon, sunrise: nil, sunset: nil)
        let reference = SolarSky(now: noon, sunrise: nil, sunset: nil)
        XCTAssertTrue(table.usedFallbackSunTimes)
        XCTAssertEqual(table.sunrise, reference.sunrise)
        XCTAssertEqual(table.sunset, reference.sunset)
        let sampled = table.sample(at: noon)
        XCTAssertEqual(sampled.sunrise, reference.sunrise)
        XCTAssertEqual(sampled.phase, reference.phase)
    }
}
