//
//  HorizonBackdrop.swift
//  BlockParty
//
//  The horizon card's ground truth: live sky over a flat ground, split by
//  a perfectly straight horizon line. All curvature in this design lives
//  in the light (the bloom); the baseline is a time ruler and stays flat.
//
//  Sky z-order, bottom → top: base gradient · warm/cool bloom ·
//  (future sun/moon disc slot) · stubs. Keep it that way — the disc task
//  drops its layer in between bloom and stubs without restructuring.
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
                    Color(HorizonPalette.groundStyle(for: sky).fill)
                }

                horizonLine
                    .offset(y: HorizonMetrics.skyHeight - HorizonMetrics.horizonLineHeight)

                solarDots(width: width)
            }
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

            // (sun/moon disc slot — a later task inserts its layer here)
        }
    }

    private func bloom(width: CGFloat) -> some View {
        let b = HorizonPalette.bloom(for: sky)
        let rx = width * (0.55 + 0.7 * sky.solarElevation)
        let ry = HorizonMetrics.skyHeight * (0.5 + 0.35 * sky.solarElevation)
        // While the sun is up the bloom rides the DRAWN ruler, not the raw
        // solar fraction — identical whenever the window is the real
        // sunrise→sunset, but in the degenerate 6-to-6 fallback it keeps
        // the glow aligned with the ticks and the now line.
        let x = sky.isSunUp ? (axis.fraction(for: sky.now) ?? sky.sunX) : sky.sunX
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
        let sunriseToday = axis.kind == .night && axis.end > sky.sunset
            ? sky.sunrise.addingTimeInterval(24 * 3600)  // night window ends at tomorrow's sunrise
            : sky.sunrise
        let sunsetVisible = axis.kind == .night && axis.start < sky.sunrise
            ? sky.sunset.addingTimeInterval(-24 * 3600)  // pre-dawn window began at yesterday's sunset
            : sky.sunset
        return ZStack {
            dot(at: sunriseToday, color: HorizonPalette.sunriseDot, width: width)
            dot(at: sunsetVisible, color: HorizonPalette.sunsetDot, width: width)
        }
    }

    @ViewBuilder
    private func dot(at date: Date, color: HorizonRGB, width: CGFloat) -> some View {
        if let x = axis.x(for: date) {
            let radius = HorizonMetrics.solarDotDiameter / 2
            Circle()
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
}
