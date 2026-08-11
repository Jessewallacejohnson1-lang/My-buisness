//
//  HorizonCard.swift
//  BlockParty
//
//  The "Your day" horizon card: a small window onto the sky over St. Joe
//  right now. Sky above, flat ground below, today's agenda rising out of
//  the line between them. All text lives below the horizon — that is what
//  lets the sky run from near-black to noon-bright with no contrast hacks.
//
//  Motion contract:
//  · Minute-to-minute color drift cross-fades at 0.8 s.
//  · The window swap (sunrise/sunset) is ONE 400 ms cross-dissolve — the
//    whole scene carries `.id(axis.start)`, so stubs, bloom and fill swap
//    together and nothing ever slides to a new time position.
//  · Text swaps polarity with a 250 ms dissolve, never a color lerp.
//  · Reduce Motion: all of it is instant.
//

import os
import SwiftUI

/// The card's user-facing strings, one place — wording is provisional by
/// design, so changing it is a one-line edit.
nonisolated enum HorizonCopy {
    static let yoursSuffix = " yours"
    static let openSuffix = " open"
    /// A real interpunct with hair spaces.
    static let separator = "\u{200A}·\u{200A}"
    static let seeAll = "See all"
    static let nothingPosted = "Nothing posted for today yet."

    static func cardAccessibilityLabel(yours: Int, open: Int) -> String {
        "Your day. \(yours) on your plan, \(open) open in town."
    }
    static let seeAllAccessibilityLabel = "See all of today's postings"
    static let loadingAccessibilityLabel = "Your day, loading"
}

struct HorizonCard: View {
    let now: Date
    let sunrise: Date?
    let sunset: Date?
    let items: [DayItem]
    var isLoading = false
    var onOpenDay: () -> Void = {}
    var onSeeAll: () -> Void = {}

    /// Counts and button scale with Dynamic Type; the sky, rail and stubs
    /// are fixed. The card may exceed its 164 pt target at AX sizes.
    @ScaledMetric(relativeTo: .footnote) private var textSize: CGFloat = HorizonMetrics.countsSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct SwapKey: Equatable {
        let windowStart: Date
        let isDark: Bool
    }

    var body: some View {
        let sky = SolarSky(now: now, sunrise: sunrise, sunset: sunset)
        let ground = HorizonPalette.groundStyle(for: sky)
        let counts = countsSource(sky: sky)

        ZStack(alignment: .bottomTrailing) {
            Button(action: onOpenDay) {
                groundContent(ground: ground, counts: counts)
            }
            .buttonStyle(FeedCardPressStyle())
            .disabled(isLoading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isLoading
                    ? HorizonCopy.loadingAccessibilityLabel
                    : HorizonCopy.cardAccessibilityLabel(yours: counts.yours, open: counts.open)
            )

            seeAllButton(ground: ground)
        }
        .background { scene(sky: sky) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: sky)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: SwapKey(windowStart: windowStart(sky: sky), isDark: ground.isDark)
        )
    }

    // MARK: Backdrop + rail (the scene behind the text)

    private func scene(sky: SolarSky) -> some View {
        GeometryReader { geo in
            let axis = TimeAxis(now: now, sunrise: sunrise, sunset: sunset, width: geo.size.width)
            let day = HorizonDay(items: items, axis: axis, now: now)
            ZStack(alignment: .topLeading) {
                HorizonBackdrop(sky: sky, axis: axis)
                if !isLoading {
                    HorizonRailView(sky: sky, axis: axis, day: day, now: now)
                }
            }
            // The swap is one moment, not three: new window, new sky phase,
            // new ground polarity arrive as a single cross-dissolve. A `.id`
            // change swaps identity, so stub positions never interpolate.
            .id(axis.start)
            .transition(.opacity)
            .onAppear {
                if axis.usedFallbackWindow {
                    Logger(subsystem: "Jesse.BlockParty", category: "horizon")
                        .error("Degenerate solar window — fixed 6-to-6 fallback in force")
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func windowStart(sky: SolarSky) -> Date {
        // Mirrors TimeAxis's window pick without needing a width.
        if now >= sky.sunrise && now < sky.sunset { return sky.sunrise }
        if now < sky.sunrise { return sky.sunset.addingTimeInterval(-24 * 3600) }
        return sky.sunset
    }

    // MARK: Ground content

    private func countsSource(sky: SolarSky) -> (yours: Int, open: Int) {
        // Counts are whole-day and window-independent, so any valid axis
        // works; width only affects stub layout, which isn't read here.
        let axis = TimeAxis(now: now, sunrise: sunrise, sunset: sunset, width: 400)
        let day = HorizonDay(items: items, axis: axis, now: now)
        return (day.yoursCount, day.openCount)
    }

    private func groundContent(
        ground: HorizonGroundStyle, counts: (yours: Int, open: Int)
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sky + the tick/label zone stay clear of text.
            Spacer(minLength: 0)
                .frame(height: HorizonMetrics.skyHeight + 22)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if isLoading {
                        loadingShimmer(ground: ground)
                    } else {
                        if counts.yours == 0 && counts.open == 0 {
                            // The one state that gets words: zero of
                            // everything with zero text reads as broken.
                            Text(HorizonCopy.nothingPosted)
                                .font(.sans(textSize))
                                .foregroundStyle(Color(ground.textSecondary))
                        }
                        countsLine(counts)
                            .font(.sans(textSize))
                            .foregroundStyle(Color(ground.textPrimary))
                            .monospacedDigit()
                    }
                }
                .id(ground.isDark)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25), value: ground.isDark)

                Spacer(minLength: 8)

                // Reserves the see-all pill's footprint inside the card
                // button's label; the real button overlays this space.
                seeAllPill(ground: ground).hidden()
            }
            .padding(.horizontal, HorizonMetrics.contentInset)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: HorizonMetrics.cardHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    private func countsLine(_ counts: (yours: Int, open: Int)) -> Text {
        // Numbers at weight 600, words at 400, same size.
        let yours = Text("\(counts.yours)").fontWeight(.semibold)
        let open = Text("\(counts.open)").fontWeight(.semibold)
        return Text(
            "\(yours)\(HorizonCopy.yoursSuffix)\(HorizonCopy.separator)\(open)\(HorizonCopy.openSuffix)"
        )
    }

    @ViewBuilder
    private func loadingShimmer(ground: HorizonGroundStyle) -> some View {
        // Stubs and counts become a quiet shimmer; the sky stays live.
        // Never a spinner.
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(ground.textSecondary, opacity: 0.22))
            .frame(width: 96, height: 12)
            .shimmering()
            .accessibilityHidden(true)
    }

    // MARK: See all

    private func seeAllButton(ground: HorizonGroundStyle) -> some View {
        Button(action: onSeeAll) {
            seeAllPill(ground: ground)
                // 44 pt hit area from padding, not from growing the pill
                // (pill is ~25 pt tall; 20 pt above clears the bar).
                .padding(.leading, 12)
                .padding(.top, 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(HorizonCopy.seeAllAccessibilityLabel)
        .padding(.trailing, HorizonMetrics.contentInset)
        .padding(.bottom, 12)
        .opacity(isLoading ? 0 : 1)
    }

    /// The app's primary-button pattern (ink fill, Radius.button rounded
    /// square — never a pill shape), inverted on dark ground. The colors are
    /// absolute, not Hue tokens: the card's polarity is solar, not the
    /// system scheme's.
    private func seeAllPill(ground: HorizonGroundStyle) -> some View {
        let fill = ground.isDark ? ground.textPrimary : HorizonRGB(hex: 0x111111)
        let label = ground.isDark ? HorizonPalette.nightGround : HorizonRGB(hex: 0xFAFAF7)
        return HStack(spacing: 5) {
            Text(HorizonCopy.seeAll)
                .font(.sansSemibold(textSize))
            Image(systemName: "chevron.right")
                .font(.system(size: textSize * 0.7, weight: .semibold))
        }
        .foregroundStyle(Color(label))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Color(fill))
        )
        .id(ground.isDark)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: ground.isDark)
    }
}
