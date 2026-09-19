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
    /// The inset for a card's TEXT and controls. The media is deliberately not
    /// inset: photos run to both screen edges (Jesse, 2026-09-19), and the copy
    /// under them keeps this margin so it is not reading off the bezel.
    static let contentInset: CGFloat = 16
}

struct DailyFeedColumn: View {
    /// Everything available to show, in any order. `DailyRanker` decides the rest.
    var items: [DailyFeedItem]
    /// The clock the ranking is against. Bumped by the host's pull-to-refresh.
    var now: Date = Date()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedIDs: Set<String> = []

    /// How many cards get the entrance cascade. Past this the delay would outlast
    /// the scroll that reveals them, so the rest simply appear.
    private static let entranceCardCount = 6

    private var ranked: [DailyFeedItem] {
        DailyRanker.rank(items, now: now)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if ranked.isEmpty {
                DailyFeedEmptyState()
                    .padding(.top, 72)
                    .padding(.horizontal, DailyFeedMetric.contentInset)
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
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
        case .event(let event, _):
            FeedEventCard(
                item: event,
                onShare: { Self.share(event) },
                actionKind: .event
            )
        }
    }

    // MARK: - Share

    private static func share(_ posting: PostingItem) {
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

    private static func share(_ event: FeedCardItem) {
        ShareCenter.shared.present(
            .event(
                title: event.title,
                dateLabel: event.dateChip,
                time: event.shareTime,
                location: event.shareLocation
            )
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
