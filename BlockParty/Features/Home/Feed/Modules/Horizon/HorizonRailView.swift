//
//  HorizonRailView.swift
//  BlockParty
//
//  The timeline on the horizon: stubs rising out of the line, hour ticks
//  and labels hanging below it, and the now notch — all laid out ONCE in
//  strip coordinates and slid together by `stripOffset` (now centered at
//  rest, scrubTime under the marker while scrubbing). Stubs are light,
//  not chart bars — four fades stack to get there (vertical falloff, soft
//  cap, halo, rail-edge dissolve).
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
    let stripOffset: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    private var M: HorizonMetrics.Type { HorizonMetrics.self }
    private var ground: HorizonGroundStyle { HorizonPalette.groundStyle(for: sky) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                stubLayer(width: width)
                // Ticks, labels and the now notch share one sliding
                // container so the whole below-horizon ruler moves as one
                // piece with the stubs above it.
                ZStack(alignment: .topLeading) {
                    tickLayer()
                    nowNotch()
                }
                .offset(x: stripOffset)
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
        // The strip slides INSIDE the fixed frame + fade, so an edge item
        // melts into the card exactly where the card ends, wherever the
        // tape happens to sit.
        .offset(x: stripOffset)
        // Explicit full-card width: offset children don't grow a ZStack, and
        // an intrinsically-sized layer here would clip the rail to a few
        // points (the whole skyline vanished the first time around).
        .frame(width: width, height: M.skyHeight, alignment: .topLeading)
        .clipped()
        // Fade 4 — the whole layer dissolves over the outermost 20 pt, so a
        // card-edge item melts into the card instead of clipping.
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
        // One glance = what's done vs what's left: ended stubs recede.
        let baseOpacity = baseOpacity
            * (HorizonDay.isPast(placed.stub, now: now) ? M.pastStubOpacityFactor : 1)
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

    // MARK: Now notch — a strip mark at now, in the tick family

    /// The below-horizon half of the "now" marker: an emphasized member of
    /// the tick system (2.5×6 pt, full-strength ink where labeled ticks
    /// sit at 50%), with a small semibold "now" in the hour-label row. A
    /// STRIP element: centered under the lollipop at rest (now is under
    /// the marker by definition) and sliding with the tape while
    /// scrubbing, so now stays answerable mid-scrub.
    private func nowNotch() -> some View {
        let x = axis.x(for: now)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(ground.textPrimary))
                .frame(width: M.notchWidth, height: M.notchHeight)
                .offset(x: x - M.notchWidth / 2, y: M.skyHeight)
            Text(HorizonCopy.now)
                .font(.sansSemibold(M.hourLabelSize))
                .foregroundStyle(Color(ground.textPrimary))
                .fixedSize()
                .frame(width: M.railLabelWidth)
                .offset(
                    x: x - M.railLabelWidth / 2,
                    y: M.hourLabelBaseline - M.hourLabelSize
                )
        }
    }

    // MARK: Ticks and labels

    private func tickLayer() -> some View {
        // The hour label nearest the now notch yields to the "now" label —
        // both live on the strip, so the clearance is strip-relative.
        let nowX = axis.x(for: now)

        return ForEach(axis.ticks(), id: \.date) { tick in
            let labeled = tick.isLabeled && abs(tick.x - nowX) >= M.nowLabelClearance

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
                // Full-opacity PRIMARY at 12 pt: the label row sits inside
                // the reflection gradient's strongest band, where secondary
                // ink measured 2.2:1 in the twilight hours (review finding,
                // swept in HorizonPaletteTests at the row's real y). The
                // labels are data, not texture — they get the ink that
                // survives their own backdrop.
                Text(label)
                    .font(.sans(M.hourLabelSize))
                    .foregroundStyle(Color(ground.textPrimary))
                    .fixedSize()
                    .frame(width: M.railLabelWidth)
                    .offset(
                        x: tick.x - M.railLabelWidth / 2,
                        y: M.hourLabelBaseline - M.hourLabelSize
                    )
            }
        }
    }
}
