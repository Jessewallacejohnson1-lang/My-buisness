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
                nowMarker(width: width)
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
            // Yours-stubs are SOLID — tall countable marks whose count must
            // match the card's primary line at arm's length. The open lane
            // keeps its light, faded texture underneath.
            ForEach(yourPlaced) { placed in
                stub(placed, height: M.yourStubHeight, radius: M.yourStubRadius,
                     baseOpacity: 1, halo: true, solid: true)
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
        baseOpacity: Double, halo: Bool, solid: Bool = false
    ) -> some View {
        let color = HorizonStubColor.color(for: placed.stub.category, phase: sky.phase)
        let haloOpacity = contrast == .increased ? 0.35 : M.haloOpacity

        ZStack(alignment: .topLeading) {
            // Fade 3 — the halo, what makes a stub glow against the sky
            // instead of sitting on it.
            if halo {
                stubBody(color: color, width: placed.width * M.haloWidthScale,
                         height: height, radius: radius, solid: solid)
                    .blur(radius: M.haloBlur)
                    .opacity(haloOpacity * baseOpacity)
                    .offset(
                        x: placed.x - placed.width * (M.haloWidthScale - 1) / 2,
                        y: M.skyHeight - height
                    )
            }
            stubBody(color: color, width: placed.width, height: height, radius: radius,
                     solid: solid)
                .opacity(baseOpacity)
                .offset(x: placed.x, y: M.skyHeight - height)
        }
    }

    private func stubBody(
        color: Color, width: CGFloat, height: CGFloat, radius: CGFloat, solid: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            // Fade 1 — brightest where it meets the light. Solid stubs skip
            // it: a countable mark is one unbroken color.
            .fill(
                LinearGradient(
                    colors: solid ? [color, color] : [color, color.opacity(0.45)],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .frame(width: width, height: height)
            // Fade 2 — defined bottom, dissolved top. Solid stubs keep their
            // top edge.
            .mask(
                LinearGradient(
                    stops: solid
                        ? [.init(color: .white, location: 0), .init(color: .white, location: 1)]
                        : [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 1 - M.stubCapFadeFraction),
                            .init(color: .clear, location: 1),
                        ],
                    startPoint: .bottom, endPoint: .top
                )
            )
    }

    // MARK: Now marker — the strongest mark on the card

    /// A solid 2×34 pt line capped with "Now", in whichever polarity clears
    /// the current sky (HorizonPalette.nowMarker), with a 1 px opposite-
    /// polarity halo. Clamped, never hidden: before 7a it pins to the
    /// morning edge, after 10p to the evening edge.
    private func nowMarker(width: CGFloat) -> some View {
        // Tangent-clamp like the solar dots: pinned at an edge, the line and
        // its halo stay fully visible instead of half-clipped by the card.
        let haloHalf = (M.nowLineWidth + 2) / 2
        let x = min(max(axis.clampedX(for: now), haloHalf), width - haloHalf)
        let style = HorizonPalette.nowMarker(for: sky)
        let color = Color(style.color)
        let halo = Color(style.halo)
        let labelWidth: CGFloat = 40
        let lineTop = M.skyHeight - M.nowLineHeight

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(halo)
                .frame(width: M.nowLineWidth + 2, height: M.nowLineHeight + 1)
                .offset(x: x - (M.nowLineWidth + 2) / 2, y: lineTop - 1)
            Rectangle()
                .fill(color)
                .frame(width: M.nowLineWidth, height: M.nowLineHeight)
                .offset(x: x - M.nowLineWidth / 2, y: lineTop)
            Text(HorizonCopy.now)
                .font(.sansSemibold(M.nowLabelSize))
                .foregroundStyle(color)
                .shadow(color: halo, radius: 1)
                .fixedSize()
                .frame(width: labelWidth)
                // The cap label stays inside the card at the clamped edges.
                .offset(
                    x: min(max(x - labelWidth / 2, 0), width - labelWidth),
                    y: lineTop - 15
                )
        }
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
                // Full-opacity secondary at 12 pt: the four labels are data,
                // not texture — legible without zooming.
                Text(label)
                    .font(.sans(M.hourLabelSize))
                    .foregroundStyle(Color(ground.textSecondary))
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
