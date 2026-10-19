//
//  DailyFeedColumn.swift
//  Block Party — the social feed's card column, without a scroll view of its own.
//
//  Split out of `DailyView` so the feed can live inside the Town tab's existing
//  scroll (under `TodayTopBar`, which owns the only production route into the map)
//  rather than replacing it. `DailyView` is now just this column in its own scroll,
//  kept for the `-daily-feed-preview` flag.
//

import SwiftUI

/// Feed geometry the cards and the column have to agree on.
///
/// `nonisolated` because these are constants, not main-actor state — the module
/// defaults to MainActor isolation and an isolated enum here would trip the
/// zero-warning bar at every call site.
nonisolated enum DailyFeedMetric {
    /// The inset for a card's copy and controls — and, on an EVENT, for the picture
    /// too. A posting's photo is the one thing that still runs to both screen edges
    /// (Jesse, 2026-09-20: Instagram's feed, which is what a posting is).
    static let contentInset: CGFloat = 16

    /// The corner on a posting's picture. Square on purpose (Jesse, 2026-09-24:
    /// straight-edged cards). Still applied as a clip because the like-burst heart exits
    /// through this edge. An event's picture is inset with `Radius.card` since 2026-10-19.
    static let mediaRadius: CGFloat = 0

}

struct DailyFeedColumn: View {
    /// What to show, in the order to show it.
    var items: [DailyFeedItem]
    /// The first cards rise in as the column appears. Off when the Town feed comes
    /// back partway down, where they would fade in after the tab had slid in.
    var entrance = true
    /// A card crossed half on screen, with its Event's id: the Town feed counts views
    /// (ticket 20). The system reports crossings only, so scrolling costs nothing.
    var onCardOnScreen: ((String, Bool) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedIDs: Set<String> = []

    /// How many cards get the entrance cascade. Past this the delay would outlast
    /// the scroll that reveals them, so the rest simply appear.
    private static let entranceCardCount = 6

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if items.isEmpty {
                DailyFeedEmptyState()
                    .padding(.top, 72)
                    .padding(.horizontal, DailyFeedMetric.contentInset)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    card(for: item)
                        .modifier(DailyCardEntrance(
                            index: index,
                            enabled: entrance && index < Self.entranceCardCount && !reduceMotion,
                            revealed: revealedIDs.contains(item.id),
                            onReveal: { revealedIDs.insert(item.id) }
                        ))
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            if case .event(let event) = item { onCardOnScreen?(event.id, visible) }
                        }
                }
            }
        }
        // NO horizontal inset: the cards' media runs edge to edge. Each card insets
        // its own copy and controls by `DailyFeedMetric.contentInset`.
        .padding(.top, 12)
    }

    @ViewBuilder
    private func card(for item: DailyFeedItem) -> some View {
        switch item {
        case .posting(let posting):
            PostingCard(
                posting: posting,
                onShare: { Self.share(posting) }
            )
        case .event(let event):
            FeedEventCard(
                item: event,
                onShare: { ShareCenter.shared.present(.event(event)) },
                actionKind: .event
            )
        }
    }

    // MARK: - Share

    static func share(_ posting: PostingItem) {
        ShareCenter.shared.present(
            SharePayload(
                title: posting.authorName,
                shareText: posting.caption.isEmpty
                    ? "\(posting.authorName) posted on Block Party."
                    : "\(posting.authorName): \(posting.caption)",
                includesImage: false
            ) {
                PostingCard(posting: posting)
                    .frame(width: 320)
                    .padding(16)
                    .background(Hue.surface)
            }
        )
    }
}

/// Not an error — nothing is broken when the block is quiet, there is simply
/// nothing planned in the Town yet. Words from BP app's words page (`town-empty`).
struct DailyFeedEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            BlockPartyGlyph(side: 40)
            Text("Quiet on the block")
                .font(.display(22))
                .foregroundStyle(Hue.ink)
            Text("When something's planned in town, it shows up here.")
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
                // Narrow enough that the line breaks after "town," on every
                // phone, not before "shows" with "it" left hanging.
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Two event cards' shapes while the Town's events load: host row, picture and room
/// for the action row, at the card's own sizes, so the cards land where these stood.
/// No going line: a card shows one only once someone is going.
struct DailyFeedSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<2, id: \.self) { _ in
                // The card's own spacing (`FeedEventCard.body`): 10 to the picture,
                // 2 to the action row.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        SkeletonCircle(diameter: 32)
                        SkeletonLine(widthFraction: 0.4)
                    }
                    .padding(.horizontal, DailyFeedMetric.contentInset)

                    // Each card takes its photo's shape; 3:2 is the one it has without a size.
                    SkeletonBlock(cornerRadius: Radius.card)
                        .aspectRatio(3.0 / 2.0, contentMode: .fit)
                        .padding(.horizontal, DailyFeedMetric.contentInset)
                        .padding(.top, 10)

                    // The heart, share and bookmark row: no shapes, its height only.
                    Color.clear.frame(height: 44)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.top, 12)
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// The feed's arrival: the first few cards fade up 12pt, one after another.
///
/// Its own modifier rather than `staggeredAppear` because that one caps its delay
/// for a fixed block of rows inside a card; this is a scrolling column where a card
/// must reveal once and then stay revealed as the LazyVStack recycles it.
struct DailyCardEntrance: ViewModifier {
    let index: Int
    let enabled: Bool
    let revealed: Bool
    let onReveal: () -> Void

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || revealed || !enabled ? 1 : 0)
            .offset(y: shown || revealed || !enabled ? 0 : 12)
            .onAppear {
                guard enabled, !revealed else { return }
                withAnimation(
                    .spring(response: 0.4, dampingFraction: 0.8)
                        .delay(Double(index) * 0.05)
                ) {
                    shown = true
                }
                onReveal()
            }
    }
}
