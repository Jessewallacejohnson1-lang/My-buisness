//
//  HorizonPaletteTests.swift
//  BlockPartyTests
//
//  The ground/sky luminance separation sweep, the text contrast sweep, sky
//  ramp continuity across phase boundaries, and adjustedForSky for the teal
//  category in all four phases.
//

import XCTest
@testable import BlockParty

final class HorizonPaletteTests: XCTestCase {
    private let sunrise = townDate(2026, 8, 11, 6, 13)
    private let sunset = townDate(2026, 8, 11, 21, 2)

    private func sky(at date: Date) -> SolarSky {
        SolarSky(now: date, sunrise: sunrise, sunset: sunset)
    }

    // MARK: Sky ramp behavior

    func testSkyIsContinuousAcrossEveryPhaseBoundary() {
        let boundaries = [
            townDate(2026, 8, 11, 5, 33),   // night → dawn
            townDate(2026, 8, 11, 7, 3),    // dawn → day
            townDate(2026, 8, 11, 19, 42),  // day → dusk
            townDate(2026, 8, 11, 21, 42),  // dusk → night
        ]
        for boundary in boundaries {
            let before = HorizonPalette.skyStops(for: sky(at: boundary.addingTimeInterval(-1)))
            let after = HorizonPalette.skyStops(for: sky(at: boundary.addingTimeInterval(1)))
            for (a, b) in zip(before, after) {
                XCTAssertEqual(a.location, b.location, accuracy: 0.001)
                XCTAssertEqual(a.color.r, b.color.r, accuracy: 0.005)
                XCTAssertEqual(a.color.g, b.color.g, accuracy: 0.005)
                XCTAssertEqual(a.color.b, b.color.b, accuracy: 0.005)
            }
        }
    }

    func testSkyIsPureAtPhaseMidpoints() {
        // Day runs 07:03 → 19:42; midpoint 13:22:30 should be the day ramp untouched.
        let midDay = townDate(2026, 8, 11, 13, 22).addingTimeInterval(30)
        let stops = HorizonPalette.skyStops(for: sky(at: midDay))
        for (computed, reference) in zip(stops, HorizonPalette.dayRamp) {
            XCTAssertEqual(computed.color.r, reference.color.r, accuracy: 0.002)
            XCTAssertEqual(computed.color.g, reference.color.g, accuracy: 0.002)
            XCTAssertEqual(computed.color.b, reference.color.b, accuracy: 0.002)
        }
    }

    // MARK: Seam guarantee — sampled every minute of a simulated 24 hours

    func testGroundAndSkyNeverConvergeAtTheSeam() {
        var worstDelta = Double.infinity
        var worstRatio = Double.infinity
        var failures: [String] = []
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            let moment = dayStart.addingTimeInterval(Double(minute) * 60)
            let s = sky(at: moment)
            let sep = HorizonPalette.seamSeparation(sky: s)
            worstDelta = min(worstDelta, sep.deltaL)
            worstRatio = min(worstRatio, sep.ratio)
            if !HorizonPalette.seamHolds(sky: s) {
                failures.append("minute \(minute): ΔL \(sep.deltaL), ratio \(sep.ratio)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "seam failures: \(failures.prefix(5))")
    }

    // MARK: Polarity — the ground never lingers at mid-luminance

    func testGroundFillNeverSitsInTheMidLuminanceBand() {
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            let moment = dayStart.addingTimeInterval(Double(minute) * 60)
            let lum = HorizonPalette.groundStyle(for: sky(at: moment)).fill.luminance
            XCTAssertFalse(
                (0.35...0.65).contains(lum),
                "ground fill at minute \(minute) sits at mid-luminance \(lum)"
            )
        }
        // The model flips as a step at elevation 0; the view renders it with a
        // 2.5 s ease, so the on-screen fill crosses the 35–65% band in well
        // under 90 s (≈0.9 s). The step is asserted here:
        XCTAssertFalse(HorizonPalette.groundStyle(for: sky(at: sunset.addingTimeInterval(-1))).isDark)
        XCTAssertTrue(HorizonPalette.groundStyle(for: sky(at: sunset.addingTimeInterval(1))).isDark)
        XCTAssertTrue(HorizonPalette.groundStyle(for: sky(at: sunrise.addingTimeInterval(-1))).isDark)
        XCTAssertFalse(HorizonPalette.groundStyle(for: sky(at: sunrise.addingTimeInterval(1))).isDark)
    }

    // MARK: Text contrast — sampled at 5-minute intervals across a day

    func testTextClearsFourPointFiveToOneAtEverySample() {
        var worst = Double.infinity
        var worstAt = ""
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 5) {
            let moment = dayStart.addingTimeInterval(Double(minute) * 60)
            let ground = HorizonPalette.groundStyle(for: sky(at: moment))
            for (name, text) in [("primary", ground.textPrimary), ("secondary", ground.textSecondary)] {
                let ratio = text.contrastRatio(with: ground.fill)
                if ratio < worst {
                    worst = ratio
                    worstAt = "\(name) at minute \(minute)"
                }
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) text at minute \(minute): \(ratio)")
            }
        }
        // Keep the measured worst case visible in test logs for the report.
        print("HorizonPalette worst text contrast: \(worst) (\(worstAt))")
    }

    // MARK: Now marker — ≥3:1 against the sky in every phase

    func testNowMarkerClearsThreeToOneAtEveryMinute() {
        var worst = Double.infinity
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            let s = sky(at: dayStart.addingTimeInterval(Double(minute) * 60))
            let marker = HorizonPalette.nowMarker(for: s)
            let bottom = HorizonPalette.skyStops(for: s)[3].color
            let ratio = marker.color.contrastRatio(with: bottom)
            worst = min(worst, ratio)
            XCTAssertGreaterThanOrEqual(ratio, 3.0, "now marker at minute \(minute): \(ratio)")
        }
        print("HorizonPalette worst now-marker contrast: \(worst)")
    }

    func testNowMarkerPolarityAtTheSpecsTwoAnchors() {
        // Noon: ink line, paper halo. Night: paper line, ink halo.
        let noon = HorizonPalette.nowMarker(for: sky(at: townDate(2026, 8, 11, 13, 0)))
        XCTAssertEqual(noon.color, HorizonRGB(hex: 0x111111))
        XCTAssertEqual(noon.halo, HorizonRGB(hex: 0xFAFAF7))
        let night = HorizonPalette.nowMarker(for: sky(at: townDate(2026, 8, 11, 23, 30)))
        XCTAssertEqual(night.color, HorizonRGB(hex: 0xFAFAF7))
        XCTAssertEqual(night.halo, HorizonRGB(hex: 0x111111))
    }

    // MARK: adjustedForSky — the teal category in all four phases

    func testAdjustedForSkyLiftsTealPerPhase() {
        let teal = HorizonRGB(hex: 0x2E9E86)  // CategoryGradient.outdoorsTrails top, light
        let base = teal.hsl

        let day = teal.adjustedForSky(.day)
        XCTAssertEqual(day, teal, "day is untouched")

        for phase in [SkyPhase.dawn, .dusk] {
            let adjusted = teal.adjustedForSky(phase).hsl
            XCTAssertEqual(adjusted.l, base.l + 0.18, accuracy: 0.01)
            XCTAssertEqual(adjusted.s, base.s - 0.10, accuracy: 0.01)
        }

        let night = teal.adjustedForSky(.night).hsl
        XCTAssertEqual(night.l, base.l + 0.32, accuracy: 0.01)
        XCTAssertEqual(night.s, base.s - 0.15, accuracy: 0.01)

        // Warm hues go the other way at dawn/dusk — darker against the
        // bloom, not lighter into it (screenshot-loop finding).
        let orange = HorizonRGB(hex: 0xE67633)  // eventsFestivals top, light
        let duskOrange = orange.adjustedForSky(.dusk).hsl
        XCTAssertEqual(duskOrange.l, orange.hsl.l - 0.12, accuracy: 0.01)
        XCTAssertGreaterThan(
            orange.adjustedForSky(.night).hsl.l, orange.hsl.l,
            "night still lifts warm hues — the night sky is uniformly dark"
        )

        // The point of the adjustment: adjusted teal must separate from the
        // sky's bottom stop where raw teal collapses.
        let nightSkyBottom = HorizonPalette.nightRamp[2].color
        XCTAssertGreaterThanOrEqual(
            teal.adjustedForSky(.night).contrastRatio(with: nightSkyBottom), 3.0,
            "night-adjusted teal must stand off the night sky"
        )
    }

    // MARK: Horizon line

    func testHorizonLineIsBottomStopAtLoweredLuminance() {
        let stops = HorizonPalette.skyStops(for: sky(at: townDate(2026, 8, 11, 13, 0)))
        let line = HorizonPalette.horizonLine(skyStops: stops)
        // 40% — softened for the continuous-scene redesign, still visible.
        XCTAssertEqual(line.opacity, 0.40)
        let bottom = stops.last!.color
        XCTAssertEqual(line.color.luminance, bottom.luminance * 0.55, accuracy: 0.01)
    }

    // MARK: Sky depth — the fade must be unmissable in every phase

    func testDaySkyTopToHorizonLuminanceRangeIsDeepEnough() {
        for ramp in [
            HorizonPalette.dayRamp, HorizonPalette.dawnRamp, HorizonPalette.duskRamp,
        ] {
            let range = abs(ramp[0].color.luminance - ramp[3].color.luminance)
            XCTAssertGreaterThanOrEqual(range, 0.25, "near-flat sky ramp")
        }
        // Night is dark end to end; a ratio is the honest depth measure there.
        let night = HorizonPalette.nightRamp
        XCTAssertGreaterThanOrEqual(
            night[3].color.contrastRatio(with: night[0].color), 1.6
        )
    }

    // MARK: Ground derivation — a tint of the sky, not a foreign panel

    func testGroundFillStaysInTheSkysColorFamily() {
        // Same hue family: the derived fill's hue must sit within 0.1 of the
        // sky bottom stop's hue (wrapping), for a saturated stop.
        let duskBottom = HorizonPalette.duskRamp[3].color
        let fill = HorizonPalette.groundFill(fromSkyBottom: duskBottom, isDark: false)
        var delta = abs(fill.hsl.h - duskBottom.hsl.h)
        delta = min(delta, 1 - delta)
        XCTAssertLessThan(delta, 0.1)
    }

    // MARK: Bloom

    func testBloomOpacityScalesInverselyWithElevation() {
        let lowSun = sky(at: townDate(2026, 8, 11, 6, 30))
        let highSun = sky(at: townDate(2026, 8, 11, 13, 37))
        XCTAssertGreaterThan(
            HorizonPalette.bloom(for: lowSun).coreOpacity,
            HorizonPalette.bloom(for: highSun).coreOpacity
        )
        // Floored at 0.55: the glow must stay visible at arm's length at noon.
        XCTAssertEqual(HorizonPalette.bloom(for: highSun).coreOpacity, 0.55, accuracy: 0.01)
    }

    func testNightBloomGoesCoolNotAbsent() {
        let night = HorizonPalette.bloom(for: sky(at: townDate(2026, 8, 11, 23, 30)))
        XCTAssertEqual(night.core, HorizonRGB(hex: 0x7B7ABF))
        XCTAssertEqual(night.coreOpacity, 0.65)
        // Cool, not warm: the blue channel dominates the core.
        XCTAssertGreaterThan(night.core.b, night.core.r)
        // And visibly brighter than the night sky's bottom stop, or the card
        // reads as a flat rectangle (the failure the spec warns against).
        let nightSkyBottom = HorizonPalette.nightRamp[2].color
        XCTAssertGreaterThan(night.core.luminance - nightSkyBottom.luminance, 0.05)
    }
}
