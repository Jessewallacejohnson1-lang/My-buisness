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

    /// The corner on every Town feed card's picture — postings and events alike.
    /// Square on purpose (Jesse, 2026-09-24: straight-edged cards). Still applied as
    /// a clip because the like-burst heart exits through this edge.
    static let mediaRadius: CGFloat = 0

}

struct DailyFeedColumn: View {
    /// What to show, in the order to show it.
    var items: [DailyFeedItem]

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
                            enabled: index < Self.entranceCardCount && !reduceMotion,
                            revealed: revealedIDs.contains(item.id),
                            onReveal: { revealedIDs.insert(item.id) }
                        ))
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

/// Written as onboarding, not as an error — nothing is broken when the block is
/// quiet, there is simply nobody followed yet.
struct DailyFeedEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            BlockPartyGlyph(side: 40)
            Text("Quiet on the block")
                .font(.display(22))
                .foregroundStyle(Hue.ink)
            Text("Follow a few neighbors and this fills up.")
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Two event cards' shapes while the Town's events load: host row, picture, going
/// line (signed in only, as on the card), and room for the action row, at the card's
/// own sizes, so the cards land where these stood.
struct DailyFeedSkeleton: View {
    var showsGoing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<2, id: \.self) { _ in
                // The card's own spacing (`FeedEventCard.body`): 10 to the picture,
                // 10 to the going line, 2 to the action row.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        SkeletonCircle(diameter: 32)
                        SkeletonLine(widthFraction: 0.4)
                    }
                    .padding(.horizontal, DailyFeedMetric.contentInset)

                    SkeletonBlock(cornerRadius: DailyFeedMetric.mediaRadius)
                        .aspectRatio(3.0 / 2.0, contentMode: .fit)
                        .padding(.top, 10)

                    if showsGoing {
                        SkeletonLine(widthFraction: 0.5)
                            .frame(height: 24)
                            .padding(.top, 10)
                            .padding(.horizontal, DailyFeedMetric.contentInset)
                    }

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
