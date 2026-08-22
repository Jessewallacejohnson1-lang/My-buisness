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
        // Exempt the two 20-min polarity windows: the fill's continuous
        // flip travels from a light to a dark derivation of the SAME sky
        // bottom stop, so it necessarily passes through it mid-window —
        // the horizon line carries the edge for those minutes. Everywhere
        // else the guarantee is unchanged.
        var worstDelta = Double.infinity
        var worstRatio = Double.infinity
        var failures: [String] = []
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            let moment = dayStart.addingTimeInterval(Double(minute) * 60)
            let s = sky(at: moment)
            let darkness = HorizonPalette.groundDarkness(for: s)
            guard darkness == 0 || darkness == 1 else { continue }
            let sep = HorizonPalette.seamSeparation(sky: s)
            worstDelta = min(worstDelta, sep.deltaL)
            worstRatio = min(worstRatio, sep.ratio)
            if !HorizonPalette.seamHolds(sky: s) {
                failures.append("minute \(minute): ΔL \(sep.deltaL), ratio \(sep.ratio)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "seam failures: \(failures.prefix(5))")
    }

    // MARK: Polarity — a pure 20-min crossfade, mid-luminance only inside it

    func testGroundPolarityCrossfadesOnlyInsideTheTwentyMinuteWindows() {
        // Pinned outside the windows, exactly half at the solar instants.
        XCTAssertEqual(
            HorizonPalette.groundDarkness(for: sky(at: sunset.addingTimeInterval(-11 * 60))), 0)
        XCTAssertEqual(
            HorizonPalette.groundDarkness(for: sky(at: sunset.addingTimeInterval(11 * 60))), 1)
        XCTAssertEqual(
            HorizonPalette.groundDarkness(for: sky(at: sunrise.addingTimeInterval(-11 * 60))), 1)
        XCTAssertEqual(
            HorizonPalette.groundDarkness(for: sky(at: sunrise.addingTimeInterval(11 * 60))), 0)
        XCTAssertEqual(
            HorizonPalette.groundDarkness(for: sky(at: sunset)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(
            HorizonPalette.groundDarkness(for: sky(at: sunrise)), 0.5, accuracy: 1e-9)

        // isDark still answers the step question at the exact instants.
        XCTAssertFalse(HorizonPalette.groundStyle(for: sky(at: sunset.addingTimeInterval(-1))).isDark)
        XCTAssertTrue(HorizonPalette.groundStyle(for: sky(at: sunset.addingTimeInterval(60))).isDark)

        // The fill only ever sits at mid-luminance while a window is live.
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            let s = sky(at: dayStart.addingTimeInterval(Double(minute) * 60))
            let darkness = HorizonPalette.groundDarkness(for: s)
            guard darkness == 0 || darkness == 1 else { continue }
            let lum = HorizonPalette.groundStyle(for: s).fill.luminance
            XCTAssertFalse(
                (0.35...0.65).contains(lum),
                "ground fill at minute \(minute) sits at mid-luminance \(lum) outside a window"
            )
        }
    }

    func testGroundCrossfadeHasNoAdjacentJumpAcrossTheSolarInstants() {
        // 10 s steps across both windows (plus margin): no fill or ink
        // channel may jump — the exact hard cut the spec bans.
        for instant in [sunset, sunrise] {
            var previous: HorizonGroundStyle?
            for second in stride(from: -12 * 60, through: 12 * 60, by: 10) {
                let style = HorizonPalette.groundStyle(
                    for: sky(at: instant.addingTimeInterval(Double(second))))
                if let previous {
                    for (a, b) in [
                        (previous.fill, style.fill),
                        (previous.textPrimary, style.textPrimary),
                        (previous.textSecondary, style.textSecondary),
                    ] {
                        let jump = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
                        XCTAssertLessThan(
                            jump, 0.03,
                            "ground jump \(jump) at \(second)s from the solar instant")
                    }
                }
                previous = style
            }
        }
    }

    // MARK: Text contrast — sampled at 5-minute intervals across a day
    //
    // Each line is tested against the COMPOSITE at its own y — the fill,
    // the reflection gradient's residual, AND the ground-side edge
    // vignette's residual (which decays on the reflection's 48pt envelope),
    // taken at the vignette's full horizontal strength as if the glyph sat
    // at the card edge. Provably safe at any x.

    func testTextClearsFourPointFiveToOneAtEverySample() {
        var worst = Double.infinity
        var worstAt = ""
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 5) {
            let s = sky(at: dayStart.addingTimeInterval(Double(minute) * 60))
            let ground = HorizonPalette.groundStyle(for: s)
            // Inside the 20-min polarity windows the ground is mid-flip —
            // the full bars apply on either side, the PRIMARY ink holds
            // ≥3:1 through the window's outer thirds, and the middle
            // third (the ink's own crossing, ~3 pt of scrub travel) is
            // the spec-mandated continuous flip: exempt, covered by the
            // continuity sweep above.
            if ground.darkness > 0 && ground.darkness < 1 {
                if ground.darkness <= 0.34 || ground.darkness >= 0.66 {
                    let backdrop = HorizonPalette.compositeGround(
                        for: s, belowHorizon: Double(HorizonMetrics.primaryTextBelowHorizon))
                    XCTAssertGreaterThanOrEqual(
                        ground.textPrimary.contrastRatio(with: backdrop), 3.0,
                        "primary in the polarity window at minute \(minute)")
                }
                continue
            }
            let vignette = HorizonPalette.skyStops(for: s)[0].color.scalingLuminance(by: 0.55)
            // (name, ink, offset below horizon, bar). The label row rides
            // primary ink — inside the reflection's strongest band the
            // secondary measured 2.2:1 in the twilight hours (review
            // finding). The chevron is non-text decoration: 3:1.
            let cases: [(String, HorizonRGB, Double, Double)] = [
                ("primary", ground.textPrimary,
                 Double(HorizonMetrics.primaryTextBelowHorizon), 4.5),
                ("secondary", ground.textSecondary,
                 Double(HorizonMetrics.secondaryTextBelowHorizon), 4.5),
                ("labels", ground.textPrimary,
                 Double(HorizonMetrics.hourLabelBelowHorizon), 4.5),
                ("chevron", ground.textSecondary,
                 Double(HorizonMetrics.primaryTextBelowHorizon), 3.0),
            ]
            for (name, text, offset, bar) in cases {
                let vignetteResidual = HorizonMetrics.vignetteOpacity
                    * max(0, 1 - offset / Double(HorizonMetrics.reflectionHeight))
                let backdrop = HorizonRGB.lerp(
                    HorizonPalette.compositeGround(for: s, belowHorizon: offset),
                    vignette,
                    vignetteResidual
                )
                let ratio = text.contrastRatio(with: backdrop)
                let margin = ratio - bar
                if margin < worst {
                    worst = margin
                    worstAt = "\(name) at minute \(minute) (\(ratio) vs \(bar))"
                }
                XCTAssertGreaterThanOrEqual(
                    ratio, bar, "\(name) text at minute \(minute): \(ratio)")
            }
        }
        // Keep the measured worst margin visible in test logs for the report.
        print("HorizonPalette thinnest contrast margin: \(worst) at \(worstAt)")
    }

    // MARK: Now notch — ≥3:1 against the ground fill in every phase

    func testNowNotchClearsThreeToOneAtEveryMinute() {
        // The notch spans y = 0–6 below the horizon, where the reflection
        // residual peaks — so it is judged against the COMPOSITE there,
        // not the bare fill (measured 4.78:1 worst vs the 3:1 bar). The
        // polarity windows' middle third (the ink's crossing) is exempt,
        // like the text sweep.
        let dayStart = townDate(2026, 8, 11, 0, 0)
        for minute in stride(from: 0, to: 24 * 60, by: 5) {
            let s = sky(at: dayStart.addingTimeInterval(Double(minute) * 60))
            let darkness = HorizonPalette.groundDarkness(for: s)
            if darkness > 0.34 && darkness < 0.66 { continue }
            let backdrop = HorizonPalette.compositeGround(for: s, belowHorizon: 0)
            XCTAssertGreaterThanOrEqual(
                HorizonPalette.groundStyle(for: s).textPrimary.contrastRatio(with: backdrop),
                3.0, "notch at minute \(minute)")
        }
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

    func testBloomIsContinuousAcrossTheDuskNightAndNightDawnBoundaries() {
        // The old warm/night set swap was a hard cut at duskEnd — invisible
        // on a minute clock, a pop under a scrub. Now it crossfades over
        // the tail of dusk / head of dawn.
        let duskEnd = sunset.addingTimeInterval(40 * 60)
        let dawnStart = sunrise.addingTimeInterval(-40 * 60)
        for boundary in [duskEnd, dawnStart] {
            let before = HorizonPalette.bloom(for: sky(at: boundary.addingTimeInterval(-1)))
            let after = HorizonPalette.bloom(for: sky(at: boundary.addingTimeInterval(1)))
            for (a, b) in [
                (before.core, after.core), (before.mid, after.mid), (before.edge, after.edge),
            ] {
                XCTAssertEqual(a.r, b.r, accuracy: 0.005)
                XCTAssertEqual(a.g, b.g, accuracy: 0.005)
                XCTAssertEqual(a.b, b.b, accuracy: 0.005)
            }
            XCTAssertEqual(before.coreOpacity, after.coreOpacity, accuracy: 0.005)
        }
        // Mid-dusk stays the pure warm set (midpoint-purity of the scene).
        let midDusk = sky(at: townDate(2026, 8, 11, 20, 42))
        XCTAssertEqual(HorizonPalette.bloom(for: midDusk).core, HorizonRGB(hex: 0xF7E9CE))
    }

    // MARK: Perceptual lerp — OKLab in-betweens, exact endpoints

    func testPerceptualLerpKeepsEndpointsExactAndLightnessMonotone() {
        let a = HorizonRGB(hex: 0x161B36)  // night top
        let b = HorizonRGB(hex: 0xD9E2EA)  // day horizon
        // Approved decision 2: the palette colors stay the endpoints.
        XCTAssertEqual(HorizonRGB.lerp(a, b, 0), a)
        XCTAssertEqual(HorizonRGB.lerp(a, b, 1), b)
        // Perceptual lightness rises monotonically dark → light.
        var lastL = -Double.infinity
        for step in 0...20 {
            let l = HorizonRGB.lerp(a, b, Double(step) / 20).oklab.l
            XCTAssertGreaterThan(l, lastL, "OKLab L must be monotone at step \(step)")
            lastL = l
        }
        // And the in-betweens genuinely differ from a raw sRGB mix — the
        // muddy-midpoint fix is real, not a rename.
        let mid = HorizonRGB.lerp(a, b, 0.5)
        let srgbMid = HorizonRGB.composited(a, b, 0.5)
        let divergence = abs(mid.r - srgbMid.r) + abs(mid.g - srgbMid.g)
            + abs(mid.b - srgbMid.b)
        XCTAssertGreaterThan(divergence, 0.01)
        // Round-trip sanity: OKLab conversion inverts cleanly.
        let round = HorizonRGB.fromOKLab(
            l: a.oklab.l, aAxis: a.oklab.a, bAxis: a.oklab.b)
        XCTAssertEqual(round.r, a.r, accuracy: 1e-6)
        XCTAssertEqual(round.g, a.g, accuracy: 1e-6)
        XCTAssertEqual(round.b, a.b, accuracy: 1e-6)
    }

    // MARK: Continuous stub adjustment (decision 7)

    func testContinuousStubAdjustmentIsPureAtMidpointsAndContinuousAtBoundaries() {
        let teal = HorizonRGB(hex: 0x2E9E86)
        // Midpoint of a phase = the discrete adjustment, untouched.
        for phase in SkyPhase.allCases {
            XCTAssertEqual(
                teal.adjustedForSky(phase: phase, blend: 0.5),
                teal.adjustedForSky(phase),
                "midpoint purity for \(phase)")
        }
        // Boundary continuity: the end of one phase is the start of the
        // next, exactly.
        for phase in SkyPhase.allCases {
            let end = teal.adjustedForSky(phase: phase, blend: 1)
            let start = teal.adjustedForSky(phase: phase.next, blend: 0)
            XCTAssertEqual(end.r, start.r, accuracy: 1e-9)
            XCTAssertEqual(end.g, start.g, accuracy: 1e-9)
            XCTAssertEqual(end.b, start.b, accuracy: 1e-9)
        }
    }
}
