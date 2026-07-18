//
//  EntriesStatCard.swift
//  Hygge — the wide "Entries This Year" stat card for the Insights face.
//
//  Reference-faithful first pass (fixed placeholder content, matched 1:1 to the
//  reference recording). A periwinkle gradient card with a big "7", stacked
//  "Entries / This Year" label, and a faint decorative 12-month mini bar chart.
//  Tapping it springs the card taller to reveal a row of category sub-stats
//  (Places · Audio · Reflections · Drawings · State of Mind), matching the
//  reference. Real calendar data is wired in a follow-up.
//

import SwiftUI

struct EntriesStatCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Bool = Self.debugExpanded()

    // Injectable content, defaulting to the reference-frame look.
    var line1: String = "Entries"
    var line2: String = "This Year"
    var count: Int = 7
    var monthData: [(letter: String, count: Int)] = [
        ("J", 3), ("F", 5), ("M", 9), ("A", 4), ("M", 3), ("J", 5),
        ("J", 4), ("A", 6), ("S", 3), ("O", 5), ("N", 3), ("D", 4),
    ]
    var markerIndex: Int = 2   // the bright vertical marker column
    var expandable: Bool = true

    private let axisTicks = ["10", "5", "0"]
    private let subStats: [(String, String)] = [
        ("3", "Places"), ("2", "Audio"), ("2", "Reflections"),
        ("2", "Drawings"), ("2", "State of Mind"),
    ]

    private let compactH: CGFloat = 106
    private let expandedH: CGFloat = 172
    private var spring: Animation { .spring(response: 0.44, dampingFraction: 0.82) }

    var body: some View {
        let isExpanded = expandable && expanded
        ZStack(alignment: .top) {
            chart(isExpanded: isExpanded)
            content
            subStatRow
                .opacity(isExpanded ? 1 : 0)
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

    // MARK: - Sub-stat row (revealed when expanded)

    private var subStatRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(subStats, id: \.1) { s in
                VStack(spacing: 2) {
                    Text(s.0).font(.system(size: 20, weight: .bold))
                        .foregroundStyle(InsightsPalette.onDark)
                    Text(s.1).font(.sans(10.5))
                        .foregroundStyle(InsightsPalette.onDark.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Background chart (decorative, low-contrast)

    private func chart(isExpanded: Bool) -> some View {
        let months = monthData.map(\.letter)
        let maxC = max(1, monthData.map(\.count).max() ?? 1)
        return GeometryReader { geo in
            let plotWidth = geo.size.width
            // In the compact state the chart owns the whole card; when expanded the
            // sub-stat row takes the lower band, so the chart hugs the top.
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
                ForEach(monthData.indices, id: \.self) { i in
                    let x = sideInset + step * (CGFloat(i) + 0.5)
                    let fraction = CGFloat(monthData[i].count) / CGFloat(maxC)
                    let h = plotHeight * fraction
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: barWidth, height: max(h, 3))
                        .position(x: x, y: plotBottom - h / 2)
                }

                let markerX = sideInset + step * (CGFloat(markerIndex) + 0.5)
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: plotHeight)
                    .position(x: markerX, y: plotTop + plotHeight / 2)

                // Month labels sit along the plot's baseline; hidden when the
                // sub-stat row occupies the bottom.
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
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .position(x: plotWidth - sideInset + 2, y: y)
                }
            }
        }
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
    EntriesStatCard()
        .padding()
        .background(InsightsPalette.canvas)
}
