//
//  BentoStatGrid.swift
//  Hygge — the 3-card "bento" row (Journaled · Visited · Written) on the
//  Upcoming Insights face, with the reference's tap-to-expand motion: tapping a
//  tile springs it to a big card on its home side while the other two shrink
//  into a stacked column opposite, revealing that card's sub-stats. Tap again
//  to collapse. Ported frame-by-frame from the reference recording.
//
//  Layout is driven by explicit per-tile frames (not matchedGeometryEffect) so
//  the spring is fully controllable and each tile keeps a stable identity
//  through the transition. FIRST pass = reference placeholder content.
//

import SwiftUI

enum BentoCard: String, CaseIterable, Identifiable {
    case journaled, visited, written
    var id: String { rawValue }
}

private struct SubStat: Identifiable {
    let value: String
    let label: String
    var id: String { label }
}

private struct BentoSpec {
    let card: BentoCard
    let title: String
    let expandedTitle: String
    let value: String?          // big numeral (nil → icon-only, e.g. Visited)
    let icon: String?           // SF Symbol for icon cards / pill
    let unit: String
    let subStats: [SubStat]     // Journaled / Written reveal these
    let storePill: String?      // Visited reveals this instead
    let top: Color
    let bottom: Color
    let side: HorizontalEdge    // which side the big card anchors to
}

struct BentoStatGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: BentoCard?

    private let gap = InsightsPalette.cardGap
    private let compactH: CGFloat = 92
    private var expandedH: CGFloat { compactH * 2 + gap }   // big tile == 2 stacked compacts
    private var spring: Animation { .spring(response: 0.44, dampingFraction: 0.82) }

    init() { _expanded = State(initialValue: Self.debugExpanded()) }

    private let specs: [BentoSpec] = [
        BentoSpec(card: .journaled, title: "Journaled", expandedTitle: "Journaled",
                  value: "2", icon: nil, unit: "Days",
                  subStats: [SubStat(value: "2", label: "This Month"),
                             SubStat(value: "2", label: "This Year")],
                  storePill: nil,
                  top: InsightsPalette.journaledTop, bottom: InsightsPalette.journaledBottom,
                  side: .leading),
        BentoSpec(card: .visited, title: "Visited", expandedTitle: "Visited Places",
                  value: nil, icon: "briefcase.fill", unit: "1 time",
                  subStats: [], storePill: "Store",
                  top: InsightsPalette.visitedTop, bottom: InsightsPalette.visitedBottom,
                  side: .trailing),
        BentoSpec(card: .written, title: "Written", expandedTitle: "Written",
                  value: "66", icon: nil, unit: "Words",
                  subStats: [SubStat(value: "66", label: "This Month"),
                             SubStat(value: "66", label: "This Year")],
                  storePill: nil,
                  top: InsightsPalette.writtenTop, bottom: InsightsPalette.writtenBottom,
                  side: .trailing),
    ]

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(specs, id: \.card) { spec in
                    let f = frame(for: spec.card, total: total)
                    tile(spec, f)
                        .offset(x: f.x, y: f.y)
                }
            }
        }
        .frame(height: expanded == nil ? compactH : expandedH)
        .animation(reduceMotion ? nil : spring, value: expanded)
        .onAppear { debugAutoExpand() }
    }

    // MARK: - Frame math

    private struct Rect { let x, y, w, h: CGFloat }

    private func frame(for card: BentoCard, total: CGFloat) -> Rect {
        guard let e = expanded else {
            let w = (total - gap * 2) / 3
            let i = CGFloat(index(of: card))
            return Rect(x: i * (w + gap), y: 0, w: w, h: compactH)
        }
        let bigW = (total - gap) * 0.635
        let colW = total - gap - bigW
        let bigSpec = spec(e)
        let leading = bigSpec.side == .leading
        let bigX: CGFloat = leading ? 0 : colW + gap
        let colX: CGFloat = leading ? bigW + gap : 0

        if card == e {
            return Rect(x: bigX, y: 0, w: bigW, h: expandedH)
        }
        // The two non-expanded cards, in their original order, stack in the column.
        let others = specs.map(\.card).filter { $0 != e }
        let slot = others.firstIndex(of: card) ?? 0
        return Rect(x: colX, y: CGFloat(slot) * (compactH + gap), w: colW, h: compactH)
    }

    // MARK: - Tile

    private func tile(_ spec: BentoSpec, _ f: Rect) -> some View {
        let isBig = expanded == spec.card
        // Size FIRST, then clip — so the (opacity-0) expanded content, whose
        // intrinsic height is taller than a compact tile, can't overflow the tile.
        return ZStack {
            compactContent(spec).frame(width: f.w, height: f.h).opacity(isBig ? 0 : 1)
            expandedContent(spec).frame(width: f.w, height: f.h).opacity(isBig ? 1 : 0)
        }
        .frame(width: f.w, height: f.h)
        .background(
            LinearGradient(colors: [spec.top, spec.bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .insightsCardShadow()
        .contentShape(Rectangle())
        .onTapGesture { toggle(spec.card) }
    }

    private func compactContent(_ spec: BentoSpec) -> some View {
        VStack(spacing: 0) {
            Text(spec.title).font(.sansSemibold(13)).foregroundStyle(InsightsPalette.onDark)
            Spacer(minLength: 2)
            if let icon = spec.icon, spec.value == nil {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(InsightsPalette.onDark)
            } else if let value = spec.value {
                Text(value).font(.system(size: 30, weight: .bold)).foregroundStyle(InsightsPalette.onDark)
            }
            Spacer(minLength: 2)
            Text(spec.unit).font(.sansMedium(12)).foregroundStyle(InsightsPalette.onDark.opacity(0.9))
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private func expandedContent(_ spec: BentoSpec) -> some View {
        if let store = spec.storePill {
            // Visited Places → centered title + store pill.
            VStack(spacing: 0) {
                Text(spec.expandedTitle).font(.sansSemibold(15)).foregroundStyle(InsightsPalette.onDark)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    Image(systemName: spec.icon ?? "bag.fill").font(.system(size: 13, weight: .semibold))
                    Text(store).font(.sansSemibold(14))
                    Text("1").font(.sansSemibold(14)).foregroundStyle(InsightsPalette.onDark.opacity(0.7))
                }
                .foregroundStyle(InsightsPalette.onDark)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        } else {
            // Journaled / Written → big centered numeral like the compact tile,
            // with the This Month / This Year sub-stats pinned to the bottom.
            VStack(spacing: 0) {
                Text(spec.expandedTitle).font(.sansSemibold(15)).foregroundStyle(InsightsPalette.onDark)
                Spacer(minLength: 2)
                if let value = spec.value {
                    Text(value).font(.system(size: 68, weight: .bold)).foregroundStyle(InsightsPalette.onDark)
                }
                Text(spec.unit).font(.sansBold(17)).foregroundStyle(InsightsPalette.onDark)
                Spacer(minLength: 6)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(spec.subStats) { s in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.value).font(.system(size: 19, weight: .bold))
                                .foregroundStyle(InsightsPalette.onDark)
                            Text(s.label).font(.sans(11))
                                .foregroundStyle(InsightsPalette.onDark.opacity(0.78))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Helpers

    private func toggle(_ card: BentoCard) {
        // Layout animates via `.animation(_:value: expanded)` on the body.
        expanded = (expanded == card) ? nil : card
    }

    private func spec(_ card: BentoCard) -> BentoSpec { specs.first { $0.card == card }! }
    private func index(of card: BentoCard) -> Int { specs.firstIndex { $0.card == card } ?? 0 }

    /// DEBUG-only: `-bento-autoexpand journaled|visited|written` fires the expand
    /// spring ~1.1s after appear so the tap-to-expand motion can be recorded
    /// headlessly (mirrors the app's other `-tap-*` recording flags).
    private func debugAutoExpand() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-bento-autoexpand"), i + 1 < args.count,
              let card = BentoCard(rawValue: args[i + 1]) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expanded = card
        }
        #endif
    }

    /// DEBUG-only: `-bento-expand journaled|visited|written` forces an expanded
    /// state on launch so each can be screenshotted headlessly.
    private static func debugExpanded() -> BentoCard? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-bento-expand"), i + 1 < args.count {
            return BentoCard(rawValue: args[i + 1])
        }
        #endif
        return nil
    }
}

#Preview {
    BentoStatGrid()
        .padding()
        .background(InsightsPalette.canvas)
}
