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

/// Category → stub color, adjusted CONTINUOUSLY for the sky (approved
/// decision 7 — the old 4-phase step popped at phase edges under a
/// scrub). Resolves the light-trait value of the existing CategoryGradient
/// palette — the card's colors are solar, not scheme-driven, exactly like
/// the map's onLightCanvas rule.
@MainActor
enum HorizonStubColor {
    /// The UIColor bridge + trait resolution stay the expensive part, and
    /// they don't vary with the sky — cache the BASE per category and do
    /// the (cheap, pure) continuous adjustment per frame.
    private static var baseCache: [EventCategory: HorizonRGB] = [:]

    static func rgb(for category: EventCategory) -> HorizonRGB {
        if let cached = baseCache[category] { return cached }
        let light = CategoryGradient.of(category).stops.top.onLightCanvas
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(light).getRed(&r, green: &g, blue: &b, alpha: &a)
        let resolved = HorizonRGB(r: r, g: g, b: b)
        baseCache[category] = resolved
        return resolved
    }

    static func adjustedRGB(for category: EventCategory, sky: SolarSky) -> HorizonRGB {
        rgb(for: category).adjustedForSky(phase: sky.phase, blend: sky.phaseBlend)
    }

    static func color(for category: EventCategory, sky: SolarSky) -> Color {
        Color(adjustedRGB(for: category, sky: sky))
    }
}

struct HorizonRailView: View {
    let sky: SolarSky
    let axis: TimeAxis
    let day: HorizonDay
    let now: Date
    let stripOffset: CGFloat
    /// A scrub session is live (including the exit rewind) — stubs wake
    /// within ±15 min of the marker.
    var isScrubbing = false
    /// The session is ACTIVE (not the rewind) — the on-an-event bubble
    /// shows only here.
    var showsBubble = false

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
                eventBubble(width: width)
            }
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: The on-an-event bubble

    /// Jesse's gate addition: when the scrub is ON an event (the magnet's
    /// own ±8-min space), a capsule filled with that event's live stub
    /// color names it — white text, small tail pointing down at the stub,
    /// floating just above the stub's tip under the centered marker.
    /// White ink falls back to the brand ink when the tint is too light
    /// to carry it (night-lifted pastels; flagged). Crossfades in/out and
    /// between neighboring events, in place. The time pill yields upward
    /// while this is present (HorizonCard reads the same geometry).
    @ViewBuilder
    private func eventBubble(width: CGFloat) -> some View {
        let item = showsBubble ? day.onEventItem(at: sky.now) : nil
        ZStack(alignment: .topLeading) {
            if let item {
                let tint = HorizonStubColor.adjustedRGB(for: item.event.category, sky: sky)
                let white = HorizonRGB(r: 1, g: 1, b: 1)
                let ink: Color = white.contrastRatio(with: tint) >= M.bubbleInkContrastBar
                    ? .white : Hue.ink
                let isYours = item.source == .committed
                let totalHeight = M.bubbleBodyHeight + M.bubbleTailHeight
                VStack(spacing: 0) {
                    Text(item.title)
                        .font(.sansSemibold(M.bubbleTextSize))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, M.bubbleHorizontalPadding)
                        .frame(height: M.bubbleBodyHeight)
                        .frame(maxWidth: M.bubbleMaxWidth)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(Capsule(style: .continuous).fill(Color(tint)))
                    BubbleTail()
                        .fill(Color(tint))
                        .frame(width: M.bubbleTailWidth, height: M.bubbleTailHeight)
                }
                // On an event the stub sits within ~4 pt of the card's
                // center, so the bubble stays comfortably on-card.
                .position(
                    x: stripOffset + axis.x(for: item.start),
                    y: M.bubbleBodyTop(overYoursStub: isYours) + totalHeight / 2)
                .id(item.id)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: M.eventLineFadeSeconds), value: item?.id)
        .allowsHitTesting(false)
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
        let color = HorizonStubColor.color(for: placed.stub.category, sky: sky)
        // The wake (spec): within ±15 min of the marker a stub rises to
        // full presence — the whole tape stays 1:1 while the stub under
        // the finger springs alive, then settles back as you pass.
        let awake = isScrubbing
            && abs(placed.stub.start.timeIntervalSince(sky.now)) <= M.stubWakeWindow
        // One glance = what's done vs what's left: ended stubs recede
        // (unless woken — presence wins while the marker is on it).
        let restingOpacity = baseOpacity
            * (HorizonDay.isPast(placed.stub, now: now) ? M.pastStubOpacityFactor : 1)
        let opacity = awake ? 1 : restingOpacity
        let restingHalo = contrast == .increased ? 0.35 : M.haloOpacity
        let haloOpacity = awake ? M.stubWakeHaloOpacity : restingHalo
        let scaleY: CGFloat = awake ? M.stubWakeScaleY : 1

        ZStack(alignment: .topLeading) {
            // Fade 3 — the halo, what makes a stub glow against the sky
            // instead of sitting on it.
            if halo {
                stubBody(color: color, width: placed.width * M.haloWidthScale,
                         height: height, radius: radius, solid: solid)
                    .blur(radius: M.haloBlur)
                    .opacity(haloOpacity * opacity)
                    .scaleEffect(x: 1, y: scaleY, anchor: .bottom)
                    .offset(
                        x: placed.x - placed.width * (M.haloWidthScale - 1) / 2,
                        y: M.skyHeight - height
                    )
            }
            stubBody(color: color, width: placed.width, height: height, radius: radius,
                     solid: solid)
                .opacity(opacity)
                .scaleEffect(x: 1, y: scaleY, anchor: .bottom)
                .offset(x: placed.x, y: M.skyHeight - height)
        }
        .animation(
            .spring(response: M.stubWakeResponse, dampingFraction: M.stubWakeDamping),
            value: awake)
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

    /// The bubble's down-pointing tail: a small triangle, apex centered on
    /// the anchored stub's x.
    private struct BubbleTail: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
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
