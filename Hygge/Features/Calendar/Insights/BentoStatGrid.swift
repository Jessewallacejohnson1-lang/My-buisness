//
//  BentoStatGrid.swift
//  Hygge — the 3-tile "bento" row on the Upcoming Insights face, with the
//  reference's tap-to-expand motion: tapping a tile springs it to a big card on
//  its home side while the other two shrink into a stacked column opposite,
//  revealing that tile's sub-stats. Tap again to collapse. Ported frame-by-frame
//  from the reference recording.
//
//  Layout is driven by explicit per-tile frames (not matchedGeometryEffect) so
//  the spring is fully controllable and each tile keeps a stable identity
//  through the transition.
//
//  CONTENT is PERSONAL now: three of your onboarding interests, each a live
//  upcoming count. The big tile reveals "This week" plus a DOORWAY — "Next"
//  over the next matching day-part — that routes to that day when tapped. Zero
//  counts render honestly ("0" + a quiet empty line), never inflated.
//

import SwiftUI

/// Opaque slot identity — the three fixed slots keep stable case names so the
/// frame math, per-slot colors, and expand sides are unchanged. The names are
/// legacy ids only; the content they carry is now interest tiles.
enum BentoCard: String, CaseIterable, Identifiable {
    case journaled, visited, written
    var id: String { rawValue }
}

private struct BentoSpec {
    let card: BentoCard
    let tile: InsightsData.InterestTile
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

    /// Exactly 3 interest tiles, mapped onto the fixed slot colors + sides.
    var tiles: [InsightsData.InterestTile]
    /// The doorway: tapping "Next" on an expanded tile opens that day (YYYY-MM-DD).
    var onOpenDay: ((String) -> Void)?

    init(tiles: [InsightsData.InterestTile], onOpenDay: ((String) -> Void)? = nil) {
        self.tiles = tiles
        self.onOpenDay = onOpenDay
        _expanded = State(initialValue: Self.debugExpanded())
    }

    /// Colors + expand sides are stable per slot so the motion is identical
    /// regardless of the interest content: slot0 leading, slot1/slot2 trailing.
    private var specs: [BentoSpec] {
        let slots: [(BentoCard, Color, Color, HorizontalEdge)] = [
            (.journaled, InsightsPalette.journaledTop, InsightsPalette.journaledBottom, .leading),
            (.visited, InsightsPalette.visitedTop, InsightsPalette.visitedBottom, .trailing),
            (.written, InsightsPalette.writtenTop, InsightsPalette.writtenBottom, .trailing),
        ]
        return slots.enumerated().compactMap { idx, slot in
            guard idx < tiles.count else { return nil }
            return BentoSpec(card: slot.0, tile: tiles[idx], top: slot.1, bottom: slot.2, side: slot.3)
        }
    }

    /// The expanded slot resolved to its spec — nil when collapsed OR when
    /// `expanded` names a slot with no backing tile (a truncated `tiles` array via
    /// the DEBUG flags), so the layout falls back to compact instead of crashing.
    private var expandedSpec: BentoSpec? {
        expanded.flatMap { e in specs.first { $0.card == e } }
    }

    var body: some View {
        let big = expandedSpec
        return GeometryReader { geo in
            let total = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(specs, id: \.card) { spec in
                    let f = frame(for: spec.card, big: big, total: total)
                    tile(spec, f)
                        .offset(x: f.x, y: f.y)
                }
            }
        }
        .frame(height: big == nil ? compactH : expandedH)
        .animation(reduceMotion ? nil : spring, value: expanded)
        .onAppear { debugAutoExpand() }
    }

    // MARK: - Frame math

    private struct Rect { let x, y, w, h: CGFloat }

    private func frame(for card: BentoCard, big: BentoSpec?, total: CGFloat) -> Rect {
        guard let e = big else {
            let w = (total - gap * 2) / 3
            let i = CGFloat(index(of: card))
            return Rect(x: i * (w + gap), y: 0, w: w, h: compactH)
        }
        let bigW = (total - gap) * 0.635
        let colW = total - gap - bigW
        let leading = e.side == .leading
        let bigX: CGFloat = leading ? 0 : colW + gap
        let colX: CGFloat = leading ? bigW + gap : 0

        if card == e.card {
            return Rect(x: bigX, y: 0, w: bigW, h: expandedH)
        }
        // The two non-expanded cards, in their original order, stack in the column.
        let others = specs.map(\.card).filter { $0 != e.card }
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

    /// Compact tile: interest title over its live count. No unit line — the
    /// count stands on its own; "0" reads honestly.
    private func compactContent(_ spec: BentoSpec) -> some View {
        VStack(spacing: 0) {
            Text(compactTitle(spec.tile.title))
                .font(.sansSemibold(13))
                .foregroundStyle(InsightsPalette.onDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Text("\(spec.tile.count)")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(InsightsPalette.onDark)
            Spacer(minLength: 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private func expandedContent(_ spec: BentoSpec) -> some View {
        let tile = spec.tile
        VStack(spacing: 0) {
            Text(tile.title)
                .font(.sansSemibold(15))
                .foregroundStyle(InsightsPalette.onDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Text("\(tile.count)")
                .font(.system(size: 68, weight: .bold))
                .foregroundStyle(InsightsPalette.onDark)
            Spacer(minLength: 6)

            if tile.count == 0 || tile.nextDayKey == nil {
                // Honest zero: no sub-stats, just a quiet empty line.
                Text(tile.emptyLine ?? "")
                    .font(.sans(12))
                    .foregroundStyle(InsightsPalette.onDark.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                subStatsRow(tile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Bottom row: "This week" static sub-stat + the "Next" doorway. The doorway is
    /// a DESCENDANT tap gesture, which SwiftUI resolves ahead of the tile's ancestor
    /// collapse tap — so tapping "Next" opens the day WITHOUT collapsing the tile.
    /// Kept as an accessibility button so VoiceOver still announces + activates it.
    private func subStatsRow(_ tile: InsightsData.InterestTile) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(tile.thisWeek)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(InsightsPalette.onDark)
                Text("This week")
                    .font(.sans(11))
                    .foregroundStyle(InsightsPalette.onDark.opacity(0.78))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let key = tile.nextDayKey, let part = tile.nextDayPart {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next")
                        .font(.sans(11))
                        .foregroundStyle(InsightsPalette.onDark.opacity(0.78))
                    HStack(spacing: 3) {
                        Text(part)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(InsightsPalette.onDark)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(InsightsPalette.onDark.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onOpenDay?(key) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Next: \(part)")
                .accessibilityHint("Opens that day")
            }
        }
    }

    // MARK: - Helpers

    private func toggle(_ card: BentoCard) {
        // Layout animates via `.animation(_:value: expanded)` on the body.
        expanded = (expanded == card) ? nil : card
    }

    private func index(of card: BentoCard) -> Int { specs.firstIndex { $0.card == card } ?? 0 }

    /// Long category labels ("Breweries & Taprooms") don't fit the narrow compact
    /// tile — show the leading segment there; the expanded tile keeps the full name.
    private func compactTitle(_ label: String) -> String {
        label.components(separatedBy: " & ").first ?? label
    }

    /// DEBUG-only: `-bento-autoexpand journaled|visited|written` fires the expand
    /// spring ~1.5s after appear so the tap-to-expand motion can be recorded
    /// headlessly (values map to slots 0/1/2 as opaque ids).
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
    /// state on launch so each slot can be screenshotted headlessly.
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

#if DEBUG
#Preview {
    BentoStatGrid(tiles: Array(InsightsData.sample.bento.prefix(3)))
        .padding()
        .background(InsightsPalette.canvas)
}
#endif
