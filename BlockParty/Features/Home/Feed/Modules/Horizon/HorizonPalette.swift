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

    /// Perceptual interpolation: endpoints are returned EXACTLY (the palette
    /// colors stay the palette colors — approved decision 2); every
    /// in-between mixes in OKLab, so a dawn→day or ground crossfade never
    /// passes through the muddy sRGB midpoints the spec bans.
    static func lerp(_ a: HorizonRGB, _ b: HorizonRGB, _ t: Double) -> HorizonRGB {
        if t <= 0 { return a }
        if t >= 1 { return b }
        let la = a.oklab
        let lb = b.oklab
        return .fromOKLab(
            l: la.l + (lb.l - la.l) * t,
            aAxis: la.a + (lb.a - la.a) * t,
            bAxis: la.b + (lb.b - la.b) * t
        )
    }

    /// Straight sRGB mix — the model of what alpha COMPOSITING does on
    /// screen. Interpolating designed colors goes through `lerp` (OKLab);
    /// simulating a translucent layer over a fill must stay in the space
    /// the renderer actually composites in, or the contrast sweeps stop
    /// measuring the shipped pixels.
    static func composited(_ a: HorizonRGB, _ b: HorizonRGB, _ t: Double) -> HorizonRGB {
        let t = min(max(t, 0), 1)
        return HorizonRGB(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t
        )
    }

    // MARK: OKLab (Björn Ottosson's reference constants)

    var oklab: (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let lr = linear(r)
        let lg = linear(g)
        let lb = linear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    static func fromOKLab(l: Double, aAxis: Double, bAxis: Double) -> HorizonRGB {
        let l3 = l + 0.3963377774 * aAxis + 0.2158037573 * bAxis
        let m3 = l - 0.1055613458 * aAxis - 0.0638541728 * bAxis
        let s3 = l - 0.0894841775 * aAxis - 1.2914855480 * bAxis
        let lCubed = l3 * l3 * l3
        let mCubed = m3 * m3 * m3
        let sCubed = s3 * s3 * s3
        func encode(_ c: Double) -> Double {
            let clamped = min(max(c, 0), 1)
            return clamped <= 0.0031308
                ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return HorizonRGB(
            r: encode(4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed),
            g: encode(-1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed),
            b: encode(-0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed)
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

    /// Continuous stub adjustment (approved decision 7): the same
    /// midpoint-keyframe scheme the sky ramps use — each phase's discrete
    /// adjustment is exact at that phase's midpoint, and adjacent
    /// midpoints interpolate perceptually. Kills the phase-edge pop the
    /// step function had under a scrub.
    func adjustedForSky(phase: SkyPhase, blend: Double) -> HorizonRGB {
        blend < 0.5
            ? .lerp(adjustedForSky(phase.previous), adjustedForSky(phase), blend + 0.5)
            : .lerp(adjustedForSky(phase), adjustedForSky(phase.next), blend - 0.5)
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
    /// Continuous polarity, 0 light … 1 dark — the 20-min sunset/sunrise
    /// crossfade. `isDark` is this at ≥ 0.5, kept for step consumers.
    let darkness: Double
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

    /// How far into the NIGHT bloom set the sky is: 0 through dawn/day and
    /// mid-dusk, 1 through deep night, crossfading over the tail of dusk
    /// (blend 0.75→1, ≈30 min) and the head of dawn (blend 0→0.25). The
    /// old warm/night set swap was a hard cut at the dusk→night boundary —
    /// invisible on a once-a-minute clock, a visible pop under a scrub.
    static let duskBloomFadeStart = 0.75
    static let dawnBloomFadeEnd = 0.25

    static func bloomNightness(phase: SkyPhase, blend: Double) -> Double {
        switch phase {
        case .night:
            return 1
        case .dusk:
            return min(max((blend - duskBloomFadeStart) / (1 - duskBloomFadeStart), 0), 1)
        case .dawn:
            return min(max(1 - blend / dawnBloomFadeEnd, 0), 1)
        case .day:
            return 0
        }
    }

    /// Daylight bloom: IKEA sunrise scale, radius/opacity handled by the view.
    /// Night bloom: residual light on the horizon where the sun set/will rise.
    /// Spec's night values (#6B6BA8 core at 0.5) measured ~0.03 luminance over
    /// the night sky's bottom stop — invisible in screenshots. Lifted core and
    /// opacity until the residual glow visibly anchors. Reported.
    static func bloom(for sky: SolarSky) -> Bloom {
        let warm = Bloom(
            core: HorizonRGB(hex: 0xF7E9CE),
            mid: HorizonRGB(hex: 0xF2A03D),
            edge: HorizonRGB(hex: 0xE9553A),
            // Floor at 0.55 so the glow stays visible at arm's length at
            // midday (the old curve bottomed out at 0.35 and vanished).
            coreOpacity: max(0.95 - 0.4 * sky.solarElevation, 0.55),
            midLocation: 0.45
        )
        let night = Bloom(
            core: HorizonRGB(hex: 0x7B7ABF),
            mid: HorizonRGB(hex: 0x5B589B),
            edge: HorizonRGB(hex: 0x46406B),
            coreOpacity: 0.65,
            midLocation: 0.35
        )
        let nightness = bloomNightness(phase: sky.phase, blend: sky.phaseBlend)
        if nightness <= 0 { return warm }
        if nightness >= 1 { return night }
        return Bloom(
            core: .lerp(warm.core, night.core, nightness),
            mid: .lerp(warm.mid, night.mid, nightness),
            edge: .lerp(warm.edge, night.edge, nightness),
            coreOpacity: warm.coreOpacity + (night.coreOpacity - warm.coreOpacity) * nightness,
            midLocation: warm.midLocation + (night.midLocation - warm.midLocation) * nightness
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
    /// Light: keep 60% of the stop's saturation, then 68% toward paper —
    /// the daytime ground keeps a real sky tint instead of reading as a
    /// gray panel. Dark: 78% toward deep night — the spec's ~70% left the
    /// post-sunset dusk fill too light for 4.5:1 secondary text (3.95:1
    /// measured), tuned within the spec's two hard constraints.
    static let lightDesaturation = 0.6
    static let lightPaperBlend = 0.68
    static let darkNightBlend = 0.78

    /// The effective ground color at a distance below the horizon: the flat
    /// fill with the reflection gradient's residual mixed in. Text stands
    /// on THIS, so the contrast sweep samples it rather than the bare fill.
    /// `composited`, not `lerp`: this models the renderer's alpha blend.
    static func compositeGround(for sky: SolarSky, belowHorizon offset: Double) -> HorizonRGB {
        let fill = groundStyle(for: sky).fill
        let bottom = skyStops(for: sky)[3].color
        let residual = HorizonMetrics.reflectionOpacity
            * max(0, 1 - offset / Double(HorizonMetrics.reflectionHeight))
        return .composited(fill, bottom, residual)
    }

    static func groundFill(fromSkyBottom bottom: HorizonRGB, isDark: Bool) -> HorizonRGB {
        if isDark { return .lerp(bottom, nightTarget, darkNightBlend) }
        let (h, s, l) = bottom.hsl
        let desaturated = HorizonRGB.fromHSL(h: h, s: s * lightDesaturation, l: l)
        return .lerp(desaturated, paperTarget, lightPaperBlend)
    }


    // Text sets. One warm pair per polarity; the spec's per-phase values
    // differ imperceptibly (ΔE < 1) and its light secondaries fail their own
    // 4.5:1 bar (#7A756B on #F6F1E9 is 3.9:1). The light secondary has been
    // darkened twice, both measured: to #6B665D for the original grounds,
    // then — when the deepened reflection dropped #6B665D to 4.35:1 against
    // the pre-sunset composite at the secondary line's y — to the shipped
    // #625D55, which sweeps at 4.55:1 worst (the addendum's rule: protect
    // the tint, adjust the ink). Reported.
    static let lightTextPrimary = HorizonRGB(hex: 0x3D3A33)
    static let lightTextSecondary = HorizonRGB(hex: 0x625D55)
    static let darkTextPrimary = HorizonRGB(hex: 0xEDE9F7)
    static let darkTextSecondary = HorizonRGB(hex: 0xA79FC4)

    // MARK: Ground polarity — a pure 20-min crossfade, f(scrubTime)

    /// The full crossfade window around the exact sunset instant (spec).
    /// Sunrise gets the same window: a scrub crosses dawn too, and a hard
    /// cut there would break the same no-steps rule. Reported.
    static let polarityWindow: TimeInterval = 20 * 60

    /// 0 in full daylight, 1 in full night, linear across the window
    /// centered on the exact sunrise/sunset instants. Pure f(sky.now) —
    /// this is what retired the view-side `.id(isDark)` dissolve.
    static func groundDarkness(for sky: SolarSky) -> Double {
        let half = polarityWindow / 2
        func rise(around instant: Date) -> Double {
            let t = sky.now.timeIntervalSince(instant)
            return min(max((t + half) / polarityWindow, 0), 1)
        }
        return min(max(1 - rise(around: sky.sunrise) + rise(around: sky.sunset), 0), 1)
    }

    /// The ink pair crosses inside the MIDDLE THIRD of the fill's window.
    /// Any continuous flip must pass a low-contrast center; compressing
    /// the ink's travel keeps the ambiguous span to ~3 pt of scrub travel
    /// (≈6 real minutes at rest) while the fill takes the full soft 20.
    static func textPolarityBlend(_ darkness: Double) -> Double {
        min(max((darkness - 0.35) / 0.3, 0), 1)
    }

    /// The ground, continuously: the fill crossfades (OKLab) between its
    /// light and dark derivations of the mixed sky's bottom stop; the ink
    /// pair crossfades on the sharpened curve above. No step anywhere —
    /// scrubbing across sunset re-lights every frame purely from time.
    static func groundStyle(for sky: SolarSky) -> HorizonGroundStyle {
        let darkness = groundDarkness(for: sky)
        let bottom = skyStops(for: sky)[3].color
        let fill = HorizonRGB.lerp(
            groundFill(fromSkyBottom: bottom, isDark: false),
            groundFill(fromSkyBottom: bottom, isDark: true),
            darkness
        )
        let ink = textPolarityBlend(darkness)
        return HorizonGroundStyle(
            fill: fill,
            textPrimary: .lerp(lightTextPrimary, darkTextPrimary, ink),
            textSecondary: .lerp(lightTextSecondary, darkTextSecondary, ink),
            isDark: darkness >= 0.5,
            darkness: darkness
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

    // MARK: Now disc — the scene marks "now" in its own language.

    static let sunCore = HorizonRGB(hex: 0xFFFDF5)
    static let moonCore = HorizonRGB(hex: 0xE8E6F0)
    /// The 1px rim that keeps the disc findable inside the dawn/dusk bloom —
    /// the same warm ink as the light-side text.
    static let discRim = lightTextPrimary
    /// The light pillar's night tone (day uses plain white).
    static let pillarNight = HorizonRGB(hex: 0xC8CFEA)
}
