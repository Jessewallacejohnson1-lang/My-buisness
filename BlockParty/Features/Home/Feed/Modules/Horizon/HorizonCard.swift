//
//  HorizonCard.swift
//  BlockParty
//
//  The "Your day" horizon card: a small window onto the sky over St. Joe
//  right now. Sky above, tinted ground below, today's agenda rising out of
//  the line between them. All text lives below the horizon — that is what
//  lets the sky run from near-black to noon-bright with no contrast hacks.
//
//  The rail is a FIXED 7a–10p window (see TimeAxis) — the axis never
//  re-windows, so there is no swap choreography. Motion contract:
//  · Minute-to-minute color drift cross-fades at 0.8 s.
//  · Text swaps polarity with a 250 ms dissolve, never a color lerp.
//  · Reduce Motion: all of it is instant.
//

import SwiftUI

/// The card's user-facing strings, one place — wording is provisional by
/// design, so changing it is a one-line edit.
nonisolated enum HorizonCopy {
    /// The ruler notch's label in the hour-label row — lowercase, one of
    /// the 8a·12p·4p·8p family.
    static let now = "now"
    static let nothingPosted = "Nothing posted for today yet."
    static let nothingPlanned = "Nothing planned yet"

    /// Primary line — the user's own day, plain words, Apple hierarchy.
    static func primaryLine(yours: Int, open: Int) -> String {
        if yours == 0 && open == 0 { return nothingPosted }
        if yours == 0 { return nothingPlanned }
        return yours == 1 ? "1 plan today" : "\(yours) plans today"
    }

    /// Secondary line — the town's open postings. Omitted entirely at zero.
    static func secondaryLine(open: Int) -> String? {
        guard open > 0 else { return nil }
        return open == 1 ? "1 more around town" : "\(open) more around town"
    }

    /// No "Your day" prefix: the section header is its own VoiceOver
    /// element and already says it — repeating it here made the swipe
    /// order read "Your day → Your day, 5 plans…" (review finding).
    static func cardAccessibilityLabel(yours: Int, open: Int) -> String {
        let primary = primaryLine(yours: yours, open: open)
        guard let secondary = secondaryLine(open: open) else { return primary }
        return "\(primary), \(secondary)."
    }
    static let cardAccessibilityHint = "Opens your day schedule"
    /// The section header's trailing link: "See all 16 ›". Nil at zero —
    /// no postings, nothing to link.
    static func seeAllLink(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "See all \(count) ›"
    }
    static func seeAllLinkAccessibilityLabel(_ count: Int) -> String {
        "See all \(count) of today's postings"
    }
    static let loadingAccessibilityLabel = "Your day, loading"
}

struct HorizonCard: View {
    let now: Date
    let sunrise: Date?
    let sunset: Date?
    let items: [DayItem]
    var isLoading = false
    var onOpenDay: () -> Void = {}

    /// Copy and button scale with Dynamic Type; the sky, rail and stubs
    /// are fixed. The card may exceed its 164 pt target at AX sizes.
    @ScaledMetric(relativeTo: .body) private var primarySize: CGFloat =
        HorizonMetrics.primaryTextSize
    @ScaledMetric(relativeTo: .footnote) private var secondarySize: CGFloat =
        HorizonMetrics.secondaryTextSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sky = SolarSky(now: now, sunrise: sunrise, sunset: sunset)
        let ground = HorizonPalette.groundStyle(for: sky)
        // Day membership is width-independent, so one HorizonDay serves both
        // the footer counts and the rail (which lays it out at real width).
        let day = HorizonDay(
            items: items,
            axis: TimeAxis(now: now, width: 1),
            now: now
        )
        let counts = (yours: day.yoursCount, open: day.openCount)

        // The whole card is the single button — one obvious tap, one route.
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
        .accessibilityHint(HorizonCopy.cardAccessibilityHint)
        .background { scene(sky: sky, day: day) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(HorizonMetrics.cardShadowOpacity),
            radius: 10, x: 0, y: 4
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: sky)
    }

    // MARK: Backdrop + rail (the scene behind the text)

    private func scene(sky: SolarSky, day: HorizonDay) -> some View {
        GeometryReader { geo in
            let axis = TimeAxis(now: now, width: geo.size.width)
            ZStack(alignment: .topLeading) {
                HorizonBackdrop(sky: sky, axis: axis)
                if !isLoading {
                    HorizonRailView(sky: sky, axis: axis, day: day, now: now)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Ground content

    private func groundContent(
        ground: HorizonGroundStyle, counts: (yours: Int, open: Int)
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sky + the tick/label zone stay clear of text. Same constant
            // the contrast sweep samples — nudging one moves both.
            Spacer(minLength: 0)
                .frame(
                    height: HorizonMetrics.skyHeight
                        + HorizonMetrics.primaryTextBelowHorizon)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: HorizonMetrics.copyLineSpacing) {
                    if isLoading {
                        loadingShimmer(ground: ground)
                    } else {
                        HStack(spacing: 5) {
                            Text(HorizonCopy.primaryLine(
                                yours: counts.yours, open: counts.open))
                                .font(.sansSemibold(primarySize))
                                .foregroundStyle(Color(ground.textPrimary))
                                .monospacedDigit()
                            // The card must advertise that it opens.
                            Image(systemName: "chevron.right")
                                .font(.system(size: secondarySize, weight: .semibold))
                                .foregroundStyle(Color(ground.textSecondary))
                        }
                        if let secondary = HorizonCopy.secondaryLine(open: counts.open) {
                            Text(secondary)
                                .font(.sans(secondarySize))
                                .foregroundStyle(Color(ground.textSecondary))
                                .monospacedDigit()
                        }
                    }
                }
                .id(ground.isDark)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25), value: ground.isDark)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, HorizonMetrics.contentInset)
            .padding(.bottom, HorizonMetrics.copyBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: HorizonMetrics.cardHeight, alignment: .top)
        .contentShape(Rectangle())
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

}
