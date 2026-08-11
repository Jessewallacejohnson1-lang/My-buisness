//
//  YourDayRail.swift
//  Block Party — the "Your day" section: heading, count, and the horizontal rail.
//
//  Three states, and the count of items picks between them:
//    0   one full-width card. With the town calendar carrying nothing dated today,
//        this is the state that actually renders, so it is designed, not deferred.
//    1   the real card, then ONE suggestion, then the add tile.
//    2+  the cards, then the add tile. No suggestions — a day with plans in it
//        does not need to be sold anything.
//

import SwiftUI

private typealias M = YourDayRailMetrics

struct YourDayRail: View {
    let items: [DayItem]
    /// Whether each item is done, resolved by `DayCompletionStore` — a stored
    /// completion beats the clock's guess, and the rail has to agree with the day
    /// sheet or a tick would appear to come undone on closing it.
    var isComplete: (DayItem) -> Bool = { $0.isComplete }
    /// Shown only in the one-item state, and only when there genuinely is another
    /// happening today to offer. Nil is the honest default.
    let suggestion: DayItem?
    /// Drives the empty card's meta line. Nil drops the number rather than
    /// inventing one.
    let townCount: Int?
    let namespace: Namespace.ID
    /// Whether the cards hold their half of the matched-geometry pair.
    ///
    /// It is withdrawn while the day sheet is open, and under Reduce Motion. Two
    /// live sources for one id is undefined behaviour in SwiftUI; the morph is an
    /// insert/remove pair, so exactly one side may claim an id at a time — and the
    /// side that should visibly fly is the sheet's, because it is drawn above the
    /// backdrop rather than blurred behind it.
    var morphs = false
    let onOpenDay: (DayItem) -> Void
    let onAdd: () -> Void
    let onExplore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: M.headerToRail) {
            header

            if items.isEmpty {
                YourDayEmptyCard(townCount: townCount, onExplore: onExplore)
                    .padding(.horizontal, M.pageMargin)
            } else {
                rail
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        // `.firstTextBaseline`, and it only survives because the Jost side is now
        // frozen too (`Font.dayDisplaySemi`). While the display face scaled and the
        // SF count beside it did not, AX5 grew this heading to ~53pt and the shared
        // baseline dragged the count 40pt down into its descender.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(YourDayRailCopy.header)
                .font(.dayDisplaySemi(M.headerSize))
                .foregroundStyle(Hue.ink)

            Spacer(minLength: 0)

            if let countLabel = YourDayRailCopy.countLabel(items.count) {
                Text(countLabel)
                    .font(.sansMedium(M.bodySize))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, M.pageMargin)
        .accessibilityElement(children: .combine)
        // The count belongs to the rail, which labels itself with it below. Combining
        // it into the header too made VoiceOver say "7 things" on the heading and
        // again on entering the rail.
        .accessibilityLabel(YourDayRailCopy.header)
        .accessibilityAddTraits(.isHeader)
    }

    /// The add tile's scroll id — the anchor `-yourday-rail-end` jumps to.
    private static let addTileID = "yourday-add-tile"

    private var rail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: M.cardSpacing) {
                    ForEach(items) { item in
                        YourDayCard(
                            item: item,
                            isComplete: isComplete(item),
                            namespace: namespace,
                            morphs: morphs,
                            onOpenDay: onOpenDay
                        )
                    }

                    if let suggestion, items.count == 1 {
                        YourDaySuggestedCard(item: suggestion, onOpenDay: onOpenDay)
                    }

                    YourDayAddTile(onAdd: onAdd)
                        .id(Self.addTileID)
                }
                .scrollTargetLayout()
                // No vertical padding for the shadow: `.scrollClipDisabled()` below
                // already lets it draw past the scroll bounds, and 8pt of defensive
                // padding is 8pt this phase exists to reclaim.
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, M.pageMargin, for: .scrollContent)
            .scrollClipDisabled()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(YourDayRailAccessibility.railLabel(count: items.count))
            .modifier(YourDayRailEndScroller(proxy: proxy, anchorID: Self.addTileID))
        }
        .frame(height: M.cardHeight)
    }
}

/// `-yourday-rail-end` parks the rail at its trailing edge on appear.
///
/// There is no swipe automation in this simulator setup, so the tail of the rail —
/// the add tile above all, which must ALWAYS be last — is otherwise unphotographable
/// and therefore unverifiable. This drives the real rail rather than a mock of it.
/// No-op without the flag, and a pass-through in Release.
private struct YourDayRailEndScroller: ViewModifier {
    let proxy: ScrollViewProxy
    let anchorID: String

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            guard ProcessInfo.processInfo.arguments.contains("-yourday-rail-end") else { return }
            // The lazy stack has to realize the trailing item before it can be
            // scrolled to.
            try? await Task.sleep(for: .milliseconds(500))
            proxy.scrollTo(anchorID, anchor: .trailing)
        }
        #else
        content
        #endif
    }
}
