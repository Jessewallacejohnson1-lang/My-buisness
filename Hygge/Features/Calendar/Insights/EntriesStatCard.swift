//
//  EntriesStatCard.swift
//  Hygge — the wide "Your Year Ahead" stat card for the Insights face.
//
//  A periwinkle gradient card with a big count, a stacked "Your Year / Ahead"
//  label, and a faint two-series 12-month mini bar chart: the town's monthly
//  totals as ghost bars (the ceiling) with YOUR interest-matched subset drawn
//  brighter in front at the same x positions. A bright marker column highlights
//  the peak month; month letters + axis ticks read the town ceiling.
//
//  Non-expandable in the Insights face — the TapToExpand machinery is kept intact
//  (inert when `expandable: false`). The significance caption is rendered by the
//  orchestrator BELOW the card, not inside it.
//

import SwiftUI

struct EntriesStatCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Bool = Self.debugExpanded()

    // Injectable content, defaulting to the reference-frame look.
    var line1: String = "Your Year"
    var line2: String = "Ahead"
    var count: Int = 7
    // Two-series month data: the town's total (ghost ceiling) + your matched subset.
    var monthData: [(letter: String, yours: Int, town: Int)] = [
        ("J", 3, 3), ("F", 4, 5), ("M", 5, 9), ("A", 2, 4), ("M", 1, 3), ("J", 2, 5),
        ("J", 1, 4), ("A", 3, 6), ("S", 1, 3), ("O", 2, 5), ("N", 1, 3), ("D", 1, 4),
    ]
    var markerIndex: Int = 2   // the bright vertical marker column
    var expandable: Bool = true

    private let compactH: CGFloat = 106
    private let expandedH: CGFloat = 172
    private var spring: Animation { .spring(response: 0.44, dampingFraction: 0.82) }

    var body: some View {
        let isExpanded = expandable && expanded
        ZStack(alignment: .top) {
            chart(isExpanded: isExpanded)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? expandedH : compactH)
        .background(
            LinearGradient(
                colors: [InsightsPalette.entriesTop, InsightsPalette.entriesBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: InsightsPalette.cardRadius, style: .continuous))
        .insightsCardShadow()
        .contentShape(Rectangle())
        .modifier(TapToExpand(enabled: expandable, reduceMotion: reduceMotion,
                              spring: spring, expanded: $expanded))
    }

    // MARK: - Foreground number + label (top-left)

    private var content: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(InsightsPalette.onDark)
                Text(line1)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(InsightsPalette.onDark)
                Text(line2)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(InsightsPalette.onDark)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Background chart (decorative, low-contrast, two series)

    private func chart(isExpanded: Bool) -> some View {
        let months = monthData.map(\.letter)
        // Both series scale to the town ceiling so ghost bars define the top and
        // your (subset) bars sit within them.
        let maxC = max(1, monthData.map(\.town).max() ?? 1)
        let axisTicks = axisTickLabels(max: maxC)
        return GeometryReader { geo in
            let plotWidth = geo.size.width
            // In the compact state the chart owns the whole card; when expanded the
            // chart still hugs the top band.
            let bottomInset: CGFloat = isExpanded ? geo.size.height - compactH + 22 : 22
            let topInset: CGFloat = 16
            let sideInset: CGFloat = 16
            let plotBottom = geo.size.height - bottomInset
            let plotTop = topInset
            let plotHeight = plotBottom - plotTop
            let usableWidth = plotWidth - sideInset * 2
            let step = usableWidth / CGFloat(months.count)
            let barWidth = step * 0.30

            ZStack(alignment: .topLeading) {
                // Ghost bars — the town's totals, behind.
                ForEach(monthData.indices, id: \.self) { i in
                    let x = sideInset + step * (CGFloat(i) + 0.5)
                    let h = plotHeight * (CGFloat(monthData[i].town) / CGFloat(maxC))
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: barWidth, height: max(h, 3))
                        .position(x: x, y: plotBottom - h / 2)
                }

                // Foreground bars — your interest-matched subset, in front.
                ForEach(monthData.indices, id: \.self) { i in
                    let x = sideInset + step * (CGFloat(i) + 0.5)
                    let yours = min(monthData[i].yours, monthData[i].town)
                    let h = plotHeight * (CGFloat(yours) / CGFloat(maxC))
                    if yours > 0 {
                        Capsule()
                            .fill(Color.white.opacity(0.30))
                            .frame(width: barWidth, height: max(h, 3))
                            .position(x: x, y: plotBottom - h / 2)
                    }
                }

                let markerX = sideInset + step * (CGFloat(markerIndex) + 0.5)
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: plotHeight)
                    .position(x: markerX, y: plotTop + plotHeight / 2)

                // Month labels sit along the plot's baseline.
                if !isExpanded {
                    ForEach(months.indices, id: \.self) { i in
                        let x = sideInset + step * (CGFloat(i) + 0.5)
                        Text(months[i])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .position(x: x, y: geo.size.height - 14)
                    }
                }

                ForEach(axisTicks.indices, id: \.self) { i in
                    let y = plotTop + plotHeight * (CGFloat(i) / CGFloat(axisTicks.count - 1))
                    Text(axisTicks[i])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .position(x: plotWidth - sideInset + 2, y: y)
                }
            }
        }
    }

    /// Axis ticks reading the town ceiling: max, half, 0. A sparse town (peak
    /// month == 1) would collapse the half to 0 and print "1 / 0 / 0", so drop the
    /// mid tick until there's a real midpoint — the quiet case stays honest and clean.
    private func axisTickLabels(max: Int) -> [String] {
        max >= 2 ? ["\(max)", "\(max / 2)", "0"] : ["\(max)", "0"]
    }

    /// DEBUG-only: `-entries-expand` forces the expanded state on launch for a
    /// headless screenshot.
    private static func debugExpanded() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-entries-expand")
        #else
        return false
        #endif
    }
}

/// Attaches the tap-to-expand gesture only when the card is expandable, so a
/// non-expandable card stays inert.
private struct TapToExpand: ViewModifier {
    let enabled: Bool
    let reduceMotion: Bool
    let spring: Animation
    @Binding var expanded: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture {
                if reduceMotion { expanded.toggle() }
                else { withAnimation(spring) { expanded.toggle() } }
            }
        } else {
            content
        }
    }
}

#Preview {
    EntriesStatCard(expandable: false)
        .padding()
        .background(InsightsPalette.canvas)
}
