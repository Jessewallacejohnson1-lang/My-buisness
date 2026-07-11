//
//  FeedSection.swift
//  Hygge — Zone 3 of the Today tab remake: "New in town", a vertical list of
//  komoot-style `FeedCard`s ordered by the viewer's onboarding interests, then
//  recency. A dumb section: callbacks are keyed by posting id and forwarded to
//  whichever `FeedCard` fired them; HomeModel owns the actual API calls.
//
//  See docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §4 Zone 3.
//

import SwiftUI

struct FeedSection: View {
    let postings: [FeedPosting]
    var onLike: (String) -> Void
    var onFollow: (String) -> Void
    var onSave: (String) -> Void
    var onShare: (String) -> Void
    var onComment: (String) -> Void
    var onOpen: (String) -> Void

    init(postings: [FeedPosting],
         onLike: @escaping (String) -> Void,
         onFollow: @escaping (String) -> Void,
         onSave: @escaping (String) -> Void,
         onShare: @escaping (String) -> Void,
         onComment: @escaping (String) -> Void,
         onOpen: @escaping (String) -> Void) {
        self.postings = postings
        self.onLike = onLike
        self.onFollow = onFollow
        self.onSave = onSave
        self.onShare = onShare
        self.onComment = onComment
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New in town")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if ordered.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { i, posting in
                        FeedCard(
                            posting: posting,
                            onLike: { onLike(posting.id) },
                            onFollow: { onFollow(posting.id) },
                            onSave: { onSave(posting.id) },
                            onShare: { onShare(posting.id) },
                            onComment: { onComment(posting.id) },
                            onOpen: { onOpen(posting.id) }
                        )
                        .appearStagger(i)
                    }
                }
            }
        }
    }

    // MARK: - Ordering

    private var interestIds: [String] { Interests.get() }

    /// Interest matches (via the free-text `Interests.matches` primitive over
    /// title + location) rise to the top; everything else follows. Within each
    /// bucket, newest first. No interests chosen → plain recency.
    private var ordered: [FeedPosting] {
        guard !interestIds.isEmpty else {
            return postings.sorted { $0.createdAt > $1.createdAt }
        }
        let matched = postings.filter(matchesInterests)
        let rest = postings.filter { !matchesInterests($0) }
        return matched.sorted { $0.createdAt > $1.createdAt }
            + rest.sorted { $0.createdAt > $1.createdAt }
    }

    private func matchesInterests(_ posting: FeedPosting) -> Bool {
        Interests.matches("\(posting.title) \(posting.location ?? "")", interestIds)
    }

    // MARK: - Empty state

    /// Honest — no fabricated posts. Real neighbor/club posts fill this in.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Hue.accent.opacity(0.6))
            Text("Nothing new yet")
                .font(.sansBold(15))
                .foregroundStyle(Hue.mapInk)
            Text("Real posts from neighbors and clubs will show up here as they're added.")
                .font(.sans(13))
                .foregroundStyle(Hue.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(Hue.paper100)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}
