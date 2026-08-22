//
//  HorizonBackdrop.swift
//  BlockParty
//
//  The horizon card's ground truth: live sky over a flat ground, split by
//  a perfectly straight horizon line. All curvature in this design lives
//  in the light (the bloom); the baseline is a time ruler and stays flat.
//
//  Sky z-order, bottom → top: base gradient · warm/cool bloom · edge
//  vignette · sun/moon disc (+ pillar). The rail's stubs render above all
//  of it in HorizonCard. The vignette sits under the disc on purpose —
//  it decides whether the disc reads at the card edges.
//
//  Under the tape model the marker (disc + pillar) is ALWAYS horizontally
//  centered; the strip (solar dots here, ticks/stubs in the rail) slides
//  beneath it by `stripOffset`.
//

import SwiftUI

extension Color {
    nonisolated init(_ rgb: HorizonRGB, opacity: Double = 1) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }
}

/// Sky gradient + bloom + horizon line + solar dots + flat ground fill.
/// The rail and the ground's text render on top of this, in HorizonCard.
struct HorizonBackdrop: View {
    let sky: SolarSky
    let axis: TimeAxis
    let stripOffset: CGFloat
    var isScrubbing = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    skyRegion(width: width)
                        // Perf gate: flatten the whole sky stack (base
                        // gradient · bloom ellipse · vignette · disc glow
                        // blur) into one Metal-composited layer, so a
                        // per-frame scrub redraws one texture instead of
                        // re-compositing four gradient layers.
                        .drawingGroup()
                        .frame(height: HorizonMetrics.skyHeight)
                        .clipped()
                    groundRegion
                }

                horizonLine
                    .offset(y: HorizonMetrics.skyHeight - HorizonMetrics.horizonLineHeight)

                solarDots
            }
        }
    }

    // MARK: Ground — the sky's reflection over a solid tinted fill.

    private var groundRegion: some View {
        let bottom = HorizonPalette.skyStops(for: sky)[3].color
        return ZStack(alignment: .top) {
            Color(HorizonPalette.groundStyle(for: sky).fill)
            LinearGradient(
                stops: [
                    .init(
                        color: Color(bottom, opacity: HorizonMetrics.reflectionOpacity),
                        location: 0
                    ),
                    .init(color: Color(bottom, opacity: 0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: HorizonMetrics.reflectionHeight)
            // The same edge fade the sky carries, continued past the horizon
            // with the reflection's own 48pt decay — the vignette belongs to
            // the scene and dissolves before the copy. A full-strength fade
            // over the text zone measured 3.37:1 for secondary text; this
            // envelope is swept in the contrast test and passes.
            edgeVignette
                .frame(height: HorizonMetrics.reflectionHeight)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    // MARK: Sky

    private func skyRegion(width: CGFloat) -> some View {
        let stops = HorizonPalette.skyStops(for: sky)
        return ZStack {
            // Layer one — the cool base.
            LinearGradient(
                stops: stops.map {
                    Gradient.Stop(color: Color($0.color), location: $0.location)
                },
                startPoint: .top,
                endPoint: .bottom
            )

            // Layer two — the bloom, anchored ON the horizon. An ellipse
            // radiating from a point, so the warm/cool boundary is a curve —
            // that curvature is what makes this read as sky.
            bloom(width: width)

            // Layer three — edge vignette: the sky deepening away from the
            // light. Restrained on purpose; if a screenshot ever reads as a
            // photo filter, halve the opacity rather than delete it.
            edgeVignette

            // Layer four — the sun (or moon) disc: the card's permanently
            // centered marker. The sky stays a pure picture: no text, no
            // UI glyphs.
            marker(width: width)
        }
    }

    private var edgeVignette: some View {
        let dark = HorizonPalette.skyStops(for: sky)[0].color.scalingLuminance(by: 0.55)
        return LinearGradient(
            stops: [
                .init(color: Color(dark, opacity: HorizonMetrics.vignetteOpacity), location: 0),
                .init(color: Color(dark, opacity: 0), location: 0.22),
                .init(color: Color(dark, opacity: 0), location: 0.78),
                .init(color: Color(dark, opacity: HorizonMetrics.vignetteOpacity), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: The marker — disc + light pillar, always centered

    /// The sun-lollipop's sky half: a quiet 9pt disc at the card's center
    /// x — sun by day, moon by night, crossfading on the same 20-min
    /// polarity window the ground uses (a scrub across sunset must never
    /// pop the disc) — over a light pillar falling to the horizon. While
    /// scrubbing it grows into the "lens" state: ×1.12 with a soft glow
    /// halo. Both elevation arcs hit zero at the solar instants, so the
    /// height is continuous across the swap by construction.
    private func marker(width: CGFloat) -> some View {
        let lens: CGFloat = isScrubbing ? HorizonMetrics.discLensScale : 1
        let x = width / 2
        let darkness = HorizonPalette.groundDarkness(for: sky)
        let elevation = sky.isSunUp ? sky.solarElevation : sky.nightElevation
        let y = HorizonMetrics.skyHeight
            - CGFloat(elevation)
            * (HorizonMetrics.skyHeight - HorizonMetrics.discTopMargin)
        let core = HorizonRGB.lerp(HorizonPalette.sunCore, HorizonPalette.moonCore, darkness)
        let pillar = HorizonRGB.lerp(
            HorizonRGB(r: 1, g: 1, b: 1), HorizonPalette.pillarNight, darkness)
        let restGlowOpacity = HorizonMetrics.discGlowOpacity * (1 - darkness)
        let pillarHeight = max(HorizonMetrics.skyHeight - y, 0)

        return ZStack(alignment: .topLeading) {
            // The pillar pins the exact x without a hard line: light
            // falling from the disc, gone by the time it reaches the
            // horizon.
            if pillarHeight > 0 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: Color(pillar, opacity: HorizonMetrics.pillarOpacity),
                                    location: 0),
                                .init(color: Color(pillar, opacity: 0), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: HorizonMetrics.pillarWidth, height: pillarHeight)
                    .position(x: x, y: y + pillarHeight / 2)
            }

            // The glow: the sun's own halo at rest (fading out with the
            // polarity window), and the lens halo for either disc while
            // scrubbing.
            if restGlowOpacity > 0.005 || isScrubbing {
                Circle()
                    .fill(Color(core))
                    .frame(
                        width: HorizonMetrics.discGlowRadius * 2 * lens,
                        height: HorizonMetrics.discGlowRadius * 2 * lens
                    )
                    .blur(radius: 5)
                    .opacity(
                        isScrubbing
                            ? HorizonMetrics.lensGlowOpacity
                            : restGlowOpacity)
                    .position(x: x, y: y)
            }

            Circle()
                .fill(Color(core, opacity: 1 - (1 - HorizonMetrics.moonOpacity) * darkness))
                .overlay(
                    Circle().stroke(
                        Color(HorizonPalette.discRim, opacity: HorizonMetrics.discRimOpacity),
                        lineWidth: 1
                    )
                )
                .frame(
                    width: HorizonMetrics.discDiameter * lens,
                    height: HorizonMetrics.discDiameter * lens
                )
                .position(x: x, y: y)
        }
        // Scoped tightly to the marker so the strip's own transactions
        // (drag 1:1, exit glide) never inherit this spring.
        .animation(
            .spring(
                response: HorizonMetrics.liftResponse,
                dampingFraction: HorizonMetrics.liftDamping),
            value: isScrubbing)
    }

    private func bloom(width: CGFloat) -> some View {
        let b = HorizonPalette.bloom(for: sky)
        let rx = width * (0.55 + 0.7 * sky.solarElevation)
        let ry = HorizonMetrics.skyHeight * (0.5 + 0.35 * sky.solarElevation)
        // The bloom anchors to the MARKER while the sun is up — the sun at
        // now sits under the marker by definition. At night it hugs the
        // nearer solar event's position on the strip, clamped to the card
        // edges so pre-dawn glow still hugs the morning edge and evening
        // afterglow sits on sunset.
        let anchorX: CGFloat = sky.isSunUp
            ? width / 2
            : min(
                max(
                    stripOffset
                        + axis.x(for: sky.now < sky.sunrise ? sky.sunrise : sky.sunset),
                    0),
                width)
        return Ellipse()
            .fill(
                EllipticalGradient(
                    stops: [
                        .init(color: Color(b.core), location: 0),
                        .init(color: Color(b.mid), location: b.midLocation),
                        .init(color: Color(b.edge, opacity: 0), location: 1),
                    ],
                    center: .center
                )
            )
            .frame(width: rx * 2, height: ry * 2)
            .position(x: anchorX, y: HorizonMetrics.skyHeight)
            .opacity(b.coreOpacity)
            .blendMode(.normal)
    }

    // MARK: Horizon line — perfectly straight, edge to edge.

    private var horizonLine: some View {
        let line = HorizonPalette.horizonLine(skyStops: HorizonPalette.skyStops(for: sky))
        return Rectangle()
            .fill(Color(line.color, opacity: line.opacity))
            .frame(height: HorizonMetrics.horizonLineHeight)
    }

    // MARK: Sunrise / sunset dots — exact solar times ON the strip.

    /// They keep their exact solar positions and slide with the strip —
    /// off-card they simply clip at the card edge (the old bookend clamp
    /// retired with the fixed window).
    private var solarDots: some View {
        ZStack {
            dot(at: sky.sunrise, color: HorizonPalette.sunriseDot)
            dot(at: sky.sunset, color: HorizonPalette.sunsetDot)
        }
    }

    private func dot(at date: Date, color: HorizonRGB) -> some View {
        Circle()
            .fill(Color(color, opacity: HorizonMetrics.solarDotOpacity))
            .frame(
                width: HorizonMetrics.solarDotDiameter,
                height: HorizonMetrics.solarDotDiameter
            )
            .position(
                x: stripOffset + axis.x(for: date),
                y: HorizonMetrics.skyHeight - HorizonMetrics.horizonLineHeight / 2
            )
    }
}
