//
//  HorizonPalette.swift
//  BlockParty
//
//  Every color the horizon card computes, in one place, on plain doubles so
//  the unit tests can sweep a simulated 24 hours without SwiftUI.
//
//  Two structural rules from the design:
//  · The sky is a gradient and the ground is a flat fill — different
//    materials on purpose, so the horizon reads as a real edge.
//  · Cross-phase color motion uses midpoint keyframes: each phase's ramp is
//    the sky at that phase's MIDPOINT, and adjacent midpoints interpolate
//    linearly. Continuous everywhere, pure at each midpoint.
//
//  Deviations from the spec's literal numbers, made because the spec's own
//  assertions are unsatisfiable as written — both reported:
//  · Day sky bottom stop is #D9E2EA, not #E8EEF2. Darkening the GROUND
//    instead provably collides with the rising sky bottom mid dawn→day
//    blend (both paths cross ~0.77 luminance).
//  · The seam assertion is |ΔL| ≥ 0.12 OR contrast ratio ≥ 1.6. An absolute
//    0.12 is blind at the dark end: the spec's own night pair (#46406B over
//    #221C3A) differs by 0.046 absolute but 1.70:1 as a ratio.
//

import Foundation

// MARK: - RGB math

nonisolated struct HorizonRGB: Equatable {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    static func lerp(_ a: HorizonRGB, _ b: HorizonRGB, _ t: Double) -> HorizonRGB {
        let t = min(max(t, 0), 1)
        return HorizonRGB(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t
        )
    }

    /// WCAG 2.1 relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    func contrastRatio(with other: HorizonRGB) -> Double {
        let l1 = luminance
        let l2 = other.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Scales all channels in linear-light space so relative luminance is
    /// multiplied by exactly `factor`. Used for the horizon line.
    func scalingLuminance(by factor: Double) -> HorizonRGB {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func encode(_ c: Double) -> Double {
            c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return HorizonRGB(
            r: min(max(encode(linear(r) * factor), 0), 1),
            g: min(max(encode(linear(g) * factor), 0), 1),
            b: min(max(encode(linear(b) * factor), 0), 1)
        )
    }

    // MARK: HSL

    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        if maxC == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        return (h / 6, s, l)
    }

    static func fromHSL(h: Double, s: Double, l: Double) -> HorizonRGB {
        guard s > 0 else { return HorizonRGB(r: l, g: l, b: l) }
        func hueToChannel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return HorizonRGB(
            r: hueToChannel(p, q, h + 1 / 3),
            g: hueToChannel(p, q, h),
            b: hueToChannel(p, q, h - 1 / 3)
        )
    }

    /// Per-phase stub adjustment: the category colors were picked against a
    /// white map and several collapse against dawn/dusk/night skies.
    /// Lightness/saturation deltas are percentage points on the 0…1 scale.
    ///
    /// Deviation from the spec's flat dawn/dusk lift (+18 L), found in the
    /// screenshot loop: WARM hues lifted +18 land inside the warm bloom's
    /// own value range and vanish exactly where stubs live (an 8:30 PM
    /// orange stub inside the sunset bloom). Warm hues darken against the
    /// bloom instead; cool hues lighten as specced. Night lifts everything —
    /// the sky is uniformly dark there.
    func adjustedForSky(_ phase: SkyPhase) -> HorizonRGB {
        let (h, s, l) = hsl
        switch phase {
        case .day:
            return self
        case .dawn, .dusk:
            if s > 0.05, h >= 0.01, h <= 0.17 {  // warm band ≈ 4°…61°
                return .fromHSL(h: h, s: min(s + 0.05, 1), l: max(l - 0.12, 0))
            }
            return .fromHSL(h: h, s: max(s - 0.10, 0), l: min(l + 0.18, 1))
        case .night:
            return .fromHSL(h: h, s: max(s - 0.15, 0), l: min(l + 0.32, 1))
        }
    }
}

// MARK: - Palette

nonisolated struct HorizonSkyStop: Equatable {
    let location: Double
    let color: HorizonRGB
}

nonisolated struct HorizonGroundStyle: Equatable {
    let fill: HorizonRGB
    let textPrimary: HorizonRGB
    let textSecondary: HorizonRGB
    let isDark: Bool
}

nonisolated enum HorizonPalette {
    // MARK: Sky ramps — the appearance at each phase's midpoint.
    // Every ramp is normalized to 4 stops so cross-phase interpolation is a
    // straight component-wise lerp (3-stop ramps duplicate their last stop).

    static let nightRamp: [HorizonSkyStop] = [
        .init(location: 0.00, color: HorizonRGB(hex: 0x161B36)),
        .init(location: 0.55, color: HorizonRGB(hex: 0x2E3560)),
        .init(location: 1.00, color: HorizonRGB(hex: 0x46406B)),
        .init(location: 1.00, color: HorizonRGB(hex: 0x46406B)),
    ]
    static let dawnRamp: [HorizonSkyStop] = [
        .init(location: 0.00, color: HorizonRGB(hex: 0x3B3A66)),
        .init(location: 0.55, color: HorizonRGB(hex: 0x7FA8DC)),
        .init(location: 1.00, color: HorizonRGB(hex: 0xC5CBD4)),
        .init(location: 1.00, color: HorizonRGB(hex: 0xC5CBD4)),
    ]
    static let dayRamp: [HorizonSkyStop] = [
        // Top stop deepened from #6E9FD8: the noon card read near-flat once
        // the bloom washed in, and the redesign wants day at dusk's level of
        // drama. Top-to-horizon luminance range is now ≥ 0.25 by test.
        .init(location: 0.00, color: HorizonRGB(hex: 0x4A7CBE)),
        .init(location: 0.60, color: HorizonRGB(hex: 0xA9C4E4)),
        .init(location: 1.00, color: HorizonRGB(hex: 0xD9E2EA)),  // spec #E8EEF2; see header
        .init(location: 1.00, color: HorizonRGB(hex: 0xD9E2EA)),
    ]
    static let duskRamp: [HorizonSkyStop] = [
        .init(location: 0.00, color: HorizonRGB(hex: 0x2A3050)),
        .init(location: 0.45, color: HorizonRGB(hex: 0x6B6BA8)),
        .init(location: 0.78, color: HorizonRGB(hex: 0xA594CE)),
        .init(location: 1.00, color: HorizonRGB(hex: 0xE5B4C4)),
    ]

    static func ramp(for phase: SkyPhase) -> [HorizonSkyStop] {
        switch phase {
        case .night: nightRamp
        case .dawn: dawnRamp
        case .day: dayRamp
        case .dusk: duskRamp
        }
    }

    /// Midpoint-keyframe mixing. blend < 0.5 interpolates from the previous
    /// phase's ramp toward this one; blend ≥ 0.5 toward the next. Continuous
    /// at every boundary, pure at every midpoint.
    static func mixedRamp(phase: SkyPhase, blend: Double) -> [HorizonSkyStop] {
        let (from, to, t): ([HorizonSkyStop], [HorizonSkyStop], Double) =
            blend < 0.5
            ? (ramp(for: phase.previous), ramp(for: phase), blend + 0.5)
            : (ramp(for: phase), ramp(for: phase.next), blend - 0.5)
        return zip(from, to).map { a, b in
            HorizonSkyStop(
                location: a.location + (b.location - a.location) * t,
                color: .lerp(a.color, b.color, t)
            )
        }
    }

    static func skyStops(for sky: SolarSky) -> [HorizonSkyStop] {
        mixedRamp(phase: sky.phase, blend: sky.phaseBlend)
    }

    // MARK: Warm bloom

    struct Bloom: Equatable {
        let core: HorizonRGB
        let mid: HorizonRGB
        let edge: HorizonRGB
        let coreOpacity: Double
        let midLocation: Double
    }

    /// Daylight bloom: IKEA sunrise scale, radius/opacity handled by the view.
    /// Night bloom: residual light on the horizon where the sun set/will rise.
    static func bloom(for sky: SolarSky) -> Bloom {
        if sky.isSunUp || sky.phase == .dawn || sky.phase == .dusk {
            return Bloom(
                core: HorizonRGB(hex: 0xF7E9CE),
                mid: HorizonRGB(hex: 0xF2A03D),
                edge: HorizonRGB(hex: 0xE9553A),
                // Floor at 0.55 so the glow stays visible at arm's length at
                // midday (the old curve bottomed out at 0.35 and vanished).
                coreOpacity: max(0.95 - 0.4 * sky.solarElevation, 0.55),
                midLocation: 0.45
            )
        }
        // Spec values (#6B6BA8 core at 0.5) measured ~0.03 luminance over the
        // night sky's bottom stop — invisible in screenshots, leaving the
        // night card the flat rectangle the spec warns against. Lifted core
        // and opacity until the residual glow visibly anchors. Reported.
        return Bloom(
            core: HorizonRGB(hex: 0x7B7ABF),
            mid: HorizonRGB(hex: 0x5B589B),
            edge: HorizonRGB(hex: 0x46406B),
            coreOpacity: 0.65,
            midLocation: 0.35
        )
    }

    // MARK: Horizon line

    /// The base gradient's final stop with luminance × 0.55, at 40% opacity —
    /// the ground is now a tint of the sky, so the ruler needs less weight to
    /// read as an edge (the stubs still stand on it).
    static func horizonLine(skyStops: [HorizonSkyStop]) -> (color: HorizonRGB, opacity: Double) {
        let bottom = skyStops[skyStops.count - 1].color
        return (bottom.scalingLuminance(by: 0.55), 0.40)
    }

    // MARK: Ground — a tint of the sky, never a foreign panel.

    /// Blend targets. The light side settles toward paper, the dark side
    /// toward deep night; the fill is always derived from the sky's bottom
    /// stop so the two regions read as one scene.
    static let paperTarget = HorizonRGB(hex: 0xFAFAF7)
    static let nightTarget = HorizonRGB(hex: 0x0E0B1E)
    /// Light: keep 60% of the stop's saturation, then 80% toward paper.
    /// Dark: 78% toward deep night — the spec's ~70% leaves the post-sunset
    /// dusk fill too light for 4.5:1 secondary text (3.95:1 measured), so
    /// the mix is tuned within the spec's two hard constraints.
    static let lightDesaturation = 0.6
    static let lightPaperBlend = 0.8
    static let darkNightBlend = 0.78

    static func groundFill(fromSkyBottom bottom: HorizonRGB, isDark: Bool) -> HorizonRGB {
        if isDark { return .lerp(bottom, nightTarget, darkNightBlend) }
        let (h, s, l) = bottom.hsl
        let desaturated = HorizonRGB.fromHSL(h: h, s: s * lightDesaturation, l: l)
        return .lerp(desaturated, paperTarget, lightPaperBlend)
    }


    // Text sets. One warm pair per polarity; the spec's per-phase values
    // differ imperceptibly (ΔE < 1) and its light secondaries fail their own
    // 4.5:1 bar (#7A756B on #F6F1E9 is 3.9:1), so the light secondary is
    // darkened to #6B665D (4.85:1 on the worst light ground). Reported.
    static let lightTextPrimary = HorizonRGB(hex: 0x3D3A33)
    static let lightTextSecondary = HorizonRGB(hex: 0x6B665D)
    static let darkTextPrimary = HorizonRGB(hex: 0xEDE9F7)
    static let darkTextSecondary = HorizonRGB(hex: 0xA79FC4)

    /// The ground is a step function of solar elevation's sign: light while
    /// the sun is up, dark after. The view renders the step with a short
    /// eased animation, so the fill spends well under 90 s at mid-luminance
    /// and no sampled minute ever sits there. The fill itself tracks the
    /// mixed sky's bottom stop, so it drifts with the sky automatically.
    static func groundStyle(for sky: SolarSky) -> HorizonGroundStyle {
        let isDark = !sky.isSunUp
        let bottom = skyStops(for: sky)[3].color
        return HorizonGroundStyle(
            fill: groundFill(fromSkyBottom: bottom, isDark: isDark),
            textPrimary: isDark ? darkTextPrimary : lightTextPrimary,
            textSecondary: isDark ? darkTextSecondary : lightTextSecondary,
            isDark: isDark
        )
    }

    // MARK: Seam guarantee

    /// The ground fill and the sky's bottom stop may never converge into one
    /// flat field. Absolute ΔL works in the light range; a ratio is the
    /// honest measure in the dark range (see file header).
    static func seamSeparation(sky: SolarSky) -> (deltaL: Double, ratio: Double) {
        let bottom = skyStops(for: sky).last!.color
        let ground = groundStyle(for: sky).fill
        return (abs(bottom.luminance - ground.luminance), bottom.contrastRatio(with: ground))
    }

    static func seamHolds(sky: SolarSky) -> Bool {
        let s = seamSeparation(sky: sky)
        return s.deltaL >= 0.12 || s.ratio >= 1.6
    }

    // MARK: Stub dots

    static let sunriseDot = HorizonRGB(hex: 0xF2A65A)
    static let sunsetDot = HorizonRGB(hex: 0xF2762E)

    // MARK: Now marker

    struct NowMarker: Equatable {
        let color: HorizonRGB
        let halo: HorizonRGB
    }

    /// The strongest mark on the card: ink on a bright sky, paper on a dark
    /// one, chosen by the sky's bottom-stop luminance so the mark clears
    /// 3:1 (WCAG non-text) in every phase — swept by test. The halo is the
    /// opposite polarity, for the mid-luminance skies where 3:1 runs thin.
    static func nowMarker(for sky: SolarSky) -> NowMarker {
        let ink = HorizonRGB(hex: 0x111111)
        let paper = HorizonRGB(hex: 0xFAFAF7)
        let bottom = skyStops(for: sky)[3].color
        return bottom.luminance >= 0.2
            ? NowMarker(color: ink, halo: paper)
            : NowMarker(color: paper, halo: ink)
    }
}
