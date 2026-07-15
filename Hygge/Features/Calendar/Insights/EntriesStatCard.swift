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
    @State private var expanded: Bool

    // Fixed placeholder content, sampled from the reference frame.
    private let count = 7
    private let months = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    private let bars: [CGFloat] = [0.30, 0.55, 0.90, 0.45, 0.35, 0.50,
                                   0.40, 0.60, 0.35, 0.50, 0.30, 0.45]
    private let markerIndex = 2   // March — the slightly brighter vertical line
    private let axisTicks = ["10", "5", "0"]
    private let subStats: [(String, String)] = [
        ("3", "Places"), ("2", "Audio"), ("2", "Reflections"),
        ("2", "Drawings"), ("2", "State of Mind"),
    ]

    private let compactH: CGFloat = 106
    private let expandedH: CGFloat = 172
    private var spring: Animation { .spring(response: 0.44, dampingFraction: 0.82) }

    init() { _expanded = State(initialValue: Self.debugExpanded()) }

    var body: some View {
        ZStack(alignment: .top) {
            chart
            content
            subStatRow
                .opacity(expanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: expanded ? expandedH : compactH)
        .background(
            LinearGradient(
                colors: [InsightsPalette.entriesTop, InsightsPalette.entriesBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: InsightsPalette.cardRadius, style: .continuous))
        .insightsCardShadow()
        .contentShape(Rectangle())
        .onTapGesture {
            if reduceMotion { expanded.toggle() }
            else { withAnimation(spring) { expanded.toggle() } }
        }
    }

    // MARK: - Foreground number + label (top-left)

    private var content: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(InsightsPalette.onDark)
                Text("Entries")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(InsightsPalette.onDark)
                Text("This Year")
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

    private var chart: some View {
        GeometryReader { geo in
            let plotWidth = geo.size.width
            // In the compact state the chart owns the whole card; when expanded the
            // sub-stat row takes the lower band, so the chart hugs the top.
            let bottomInset: CGFloat = expanded ? geo.size.height - compactH + 22 : 22
            let topInset: CGFloat = 16
            let sideInset: CGFloat = 16
            let plotBottom = geo.size.height - bottomInset
            let plotTop = topInset
            let plotHeight = plotBottom - plotTop
            let usableWidth = plotWidth - sideInset * 2
            let step = usableWidth / CGFloat(months.count)
            let barWidth = step * 0.30

            ZStack(alignment: .topLeading) {
                ForEach(months.indices, id: \.self) { i in
                    let x = sideInset + step * (CGFloat(i) + 0.5)
                    let h = plotHeight * bars[i]
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
                if !expanded {
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

#Preview {
    EntriesStatCard()
        .padding()
        .background(InsightsPalette.canvas)
}
