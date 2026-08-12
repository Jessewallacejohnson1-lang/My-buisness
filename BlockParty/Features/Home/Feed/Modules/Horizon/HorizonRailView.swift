//
//  HorizonRailView.swift
//  BlockParty
//
//  The timeline on the horizon: stubs rising out of the line, hour ticks
//  and labels hanging below it, the now indicator and overflow markers.
//  Stubs are light, not chart bars — four fades stack to get there
//  (vertical falloff, soft cap, halo, rail-edge dissolve).
//

import SwiftUI

/// Category → stub color, adjusted per sky phase. Resolves the light-trait
/// value of the existing CategoryGradient palette — the card's colors are
/// solar, not scheme-driven, exactly like the map's onLightCanvas rule.
@MainActor
enum HorizonStubColor {
    /// 10 categories × 4 phases — resolved once each, not per stub per tick
    /// (the UIColor bridge and trait resolution are the expensive part).
    private static var cache: [String: Color] = [:]

    static func rgb(for category: EventCategory) -> HorizonRGB {
        let light = CategoryGradient.of(category).stops.top.onLightCanvas
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(light).getRed(&r, green: &g, blue: &b, alpha: &a)
        return HorizonRGB(r: r, g: g, b: b)
    }

    static func color(for category: EventCategory, phase: SkyPhase) -> Color {
        let key = "\(category.rawValue)|\(phase)"
        if let cached = cache[key] { return cached }
        let resolved = Color(rgb(for: category).adjustedForSky(phase))
        cache[key] = resolved
        return resolved
    }
}

struct HorizonRailView: View {
    let sky: SolarSky
    let axis: TimeAxis
    let day: HorizonDay
    let now: Date

    @Environment(\.colorSchemeContrast) private var contrast

    private var M: HorizonMetrics.Type { HorizonMetrics.self }
    private var ground: HorizonGroundStyle { HorizonPalette.groundStyle(for: sky) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                stubLayer(width: width)
                nowLine
                tickLayer(width: width)
                overflowMarkers(width: width)
            }
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: Stubs

    private func stubLayer(width: CGFloat) -> some View {
        let publicPlaced = HorizonDay.layout(
            day.publicStubs, axis: axis, minWidth: M.publicStubMinWidth)
        let yourPlaced = HorizonDay.layout(
            day.yourStubs, axis: axis, minWidth: M.yourStubMinWidth)
        let increased = contrast == .increased

        return ZStack(alignment: .topLeading) {
            // Both lanes anchor to the horizon and overlap; your items draw
            // on top. A busy day is a skyline, and the tall buildings are
            // the user's commitments.
            ForEach(publicPlaced) { placed in
                stub(placed, height: M.publicStubHeight, radius: M.publicStubRadius,
                     baseOpacity: increased ? 1 : M.publicStubOpacity, halo: false)
            }
            ForEach(yourPlaced) { placed in
                stub(placed, height: M.yourStubHeight, radius: M.yourStubRadius,
                     baseOpacity: 1, halo: true)
            }
        }
        // Explicit full-card width: offset children don't grow a ZStack, and
        // an intrinsically-sized layer here would clip the rail to a few
        // points (the whole skyline vanished the first time around).
        .frame(width: width, height: M.skyHeight, alignment: .topLeading)
        .clipped()
        // Fade 4 — the whole layer dissolves over the outermost 20 pt, so a
        // sunrise-edge item melts into the card instead of clipping.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: M.railEdgeFade / max(width, 1)),
                    .init(color: .white, location: 1 - M.railEdgeFade / max(width, 1)),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    @ViewBuilder
    private func stub(
        _ placed: HorizonPlacedStub, height: CGFloat, radius: CGFloat,
        baseOpacity: Double, halo: Bool
    ) -> some View {
        let color = HorizonStubColor.color(for: placed.stub.category, phase: sky.phase)
        let haloOpacity = contrast == .increased ? 0.35 : M.haloOpacity

        ZStack(alignment: .topLeading) {
            // Fade 3 — the halo, what makes a stub glow against the sky
            // instead of sitting on it.
            if halo {
                stubBody(color: color, width: placed.width * M.haloWidthScale,
                         height: height, radius: radius)
                    .blur(radius: M.haloBlur)
                    .opacity(haloOpacity * baseOpacity)
                    .offset(
                        x: placed.x - placed.width * (M.haloWidthScale - 1) / 2,
                        y: M.skyHeight - height
                    )
            }
            stubBody(color: color, width: placed.width, height: height, radius: radius)
                .opacity(baseOpacity)
                .offset(x: placed.x, y: M.skyHeight - height)
        }
    }

    private func stubBody(color: Color, width: CGFloat, height: CGFloat, radius: CGFloat)
        -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            // Fade 1 — brightest where it meets the light.
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.45)],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .frame(width: width, height: height)
            // Fade 2 — defined bottom, dissolved top. No hard terminating edge.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 1 - M.stubCapFadeFraction),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .bottom, endPoint: .top
                )
            )
    }

    // MARK: Now indicator

    /// Clamped, never hidden: before 7a it pins to the morning edge, after
    /// 10p to the evening edge — "now" is always answerable.
    private var nowLine: some View {
        let x = axis.clampedX(for: now)
        let color: Color = sky.phase == .day
            ? Color.black.opacity(0.3)
            : Color.white.opacity(0.7)
        return Rectangle()
            .fill(color)
            .frame(width: M.nowLineWidth, height: M.nowLineHeight)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .offset(x: x - M.nowLineWidth / 2, y: M.skyHeight - M.nowLineHeight)
    }

    // MARK: Ticks and labels

    private func tickLayer(width: CGFloat) -> some View {
        // A label colliding with an overflow marker loses; the marker wins.
        let markerZone: CGFloat = 56
        let dropLeading = day.earlierCount > 0
        let dropTrailing = day.laterCount > 0

        return ForEach(axis.ticks(), id: \.date) { tick in
            let suppressed = (dropLeading && tick.x < markerZone)
                || (dropTrailing && tick.x > width - markerZone)
            let labeled = tick.isLabeled && !suppressed

            Rectangle()
                .fill(Color(
                    ground.textSecondary,
                    opacity: labeled ? 0.5 : 0.3
                ))
                .frame(
                    width: M.tickWidth,
                    height: labeled ? M.labeledTickHeight : M.tickHeight
                )
                .offset(x: tick.x - M.tickWidth / 2, y: M.skyHeight)

            if labeled, let label = tick.label {
                Text(label)
                    .font(.sans(M.hourLabelSize))
                    .foregroundStyle(Color(ground.textPrimary, opacity: 0.45))
                    .fixedSize()
                    .frame(width: 40)
                    .offset(x: tick.x - 20, y: M.hourLabelBaseline - M.hourLabelSize)
            }
        }
    }

    // MARK: Overflow markers

    @ViewBuilder
    private func overflowMarkers(width: CGFloat) -> some View {
        if day.earlierCount > 0 {
            overflowMarker(count: day.earlierCount, suffix: "earlier", leading: true, width: width)
        }
        if day.laterCount > 0 {
            overflowMarker(count: day.laterCount, suffix: "later", leading: false, width: width)
        }
    }

    private func overflowMarker(count: Int, suffix: String, leading: Bool, width: CGFloat)
        -> some View {
        let bar = Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(ground.textSecondary, opacity: 0.4),
                        Color(ground.textSecondary, opacity: 0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: M.overflowBarWidth, height: 14)

        let label = Text("+\(count) \(suffix)")
            .font(.sans(M.overflowTextSize))
            .foregroundStyle(Color(ground.textSecondary))
            .fixedSize()

        return HStack(alignment: .top, spacing: 4) {
            if leading {
                bar
                label.padding(.top, 2)
            } else {
                label.padding(.top, 2)
                bar
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .topLeading : .topTrailing)
        .offset(y: M.skyHeight + 2)
    }
}
