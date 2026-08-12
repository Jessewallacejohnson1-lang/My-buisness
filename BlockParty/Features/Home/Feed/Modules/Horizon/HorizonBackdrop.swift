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

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    skyRegion(width: width)
                        .frame(height: HorizonMetrics.skyHeight)
                        .clipped()
                    groundRegion
                }

                horizonLine
                    .offset(y: HorizonMetrics.skyHeight - HorizonMetrics.horizonLineHeight)

                solarDots(width: width)
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

            // Layer four — the sun (or moon) disc at "now", the scene's own
            // marker. The sky stays a pure picture: no text, no UI glyphs.
            nowDisc(width: width)
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

    // MARK: Now disc + light pillar

    /// A quiet 9pt disc riding the solar arc at now's x — sun by day, moon
    /// by night (its height is the same sin arc run over the night; clock,
    /// not astronomy). Hidden when now is outside the 7a–10p window — the
    /// rail's ruler notch is the only marker then. Never clamped.
    @ViewBuilder
    private func nowDisc(width: CGFloat) -> some View {
        if let fraction = axis.fraction(for: sky.now) {
            let radius = HorizonMetrics.discDiameter / 2
            // Tangent to the card edge, like the solar dots — a marker
            // half-clipped by the corner marks nothing.
            let x = min(max(CGFloat(fraction) * width, radius + 1), width - radius - 1)
            let elevation = sky.isSunUp ? sky.solarElevation : sky.nightElevation
            let y = HorizonMetrics.skyHeight
                - CGFloat(elevation)
                * (HorizonMetrics.skyHeight - HorizonMetrics.discTopMargin)
            let core = sky.isSunUp ? HorizonPalette.sunCore : HorizonPalette.moonCore
            let pillar = sky.isSunUp ? HorizonRGB(r: 1, g: 1, b: 1) : HorizonPalette.pillarNight

            // The pillar pins the exact x without a hard line: light falling
            // from the disc, gone by the time it reaches the horizon.
            let pillarHeight = max(HorizonMetrics.skyHeight - y, 0)
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

            if sky.isSunUp {
                Circle()
                    .fill(Color(core))
                    .frame(
                        width: HorizonMetrics.discGlowRadius * 2,
                        height: HorizonMetrics.discGlowRadius * 2
                    )
                    .blur(radius: 5)
                    .opacity(HorizonMetrics.discGlowOpacity)
                    .position(x: x, y: y)
            }

            Circle()
                .fill(Color(core, opacity: sky.isSunUp ? 1 : HorizonMetrics.moonOpacity))
                .overlay(
                    Circle().stroke(
                        Color(HorizonPalette.discRim, opacity: HorizonMetrics.discRimOpacity),
                        lineWidth: 1
                    )
                )
                .frame(
                    width: HorizonMetrics.discDiameter, height: HorizonMetrics.discDiameter
                )
                .position(x: x, y: y)
        }
    }

    private func bloom(width: CGFloat) -> some View {
        let b = HorizonPalette.bloom(for: sky)
        let rx = width * (0.55 + 0.7 * sky.solarElevation)
        let ry = HorizonMetrics.skyHeight * (0.5 + 0.35 * sky.solarElevation)
        // The bloom rides the fixed ruler: the sun's clock position while it
        // is up (clamped to the edges when it rises before 7a or sets after
        // 10p), and the nearer solar event's position at night — pre-dawn
        // glow hugs the morning edge, evening afterglow sits on sunset.
        let anchor: Date =
            sky.isSunUp ? sky.now : (sky.now < sky.sunrise ? sky.sunrise : sky.sunset)
        let x = axis.clampedFraction(for: anchor)
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
            .position(x: x * width, y: HorizonMetrics.skyHeight)
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

    // MARK: Sunrise / sunset dots — the rail's bookends.

    private func solarDots(width: CGFloat) -> some View {
        ZStack {
            dot(at: sky.sunrise, color: HorizonPalette.sunriseDot, width: width)
            dot(at: sky.sunset, color: HorizonPalette.sunsetDot, width: width)
        }
    }

    private func dot(at date: Date, color: HorizonRGB, width: CGFloat) -> some View {
        let x = axis.clampedX(for: date)
        let radius = HorizonMetrics.solarDotDiameter / 2
        return Circle()
            .fill(Color(color, opacity: HorizonMetrics.solarDotOpacity))
            .frame(
                width: HorizonMetrics.solarDotDiameter,
                height: HorizonMetrics.solarDotDiameter
            )
            // Tangent to the card edge rather than half-clipped by it —
            // a bookend has to be visible to bookend anything.
            .position(
                x: min(max(x, radius), width - radius),
                y: HorizonMetrics.skyHeight - HorizonMetrics.horizonLineHeight / 2
            )
    }
}
