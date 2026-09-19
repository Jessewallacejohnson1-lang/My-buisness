//
//  DailyRanker.swift
//  Block Party — the Daily feed's ordering.
//
//  Reverse-chronological is honest and nobody reads it: the best thing on the block
//  last Tuesday sinks under three people posting about the weather this morning. So
//  the stream is scored, the way every feed that people actually finish is scored —
//  recency, engagement, who posted it, and who else already liked it.
//
//  It is a pure function over an array. No model, no state, no network, no learning.
//  Every weight below is a starting guess made before there was any real content to
//  look at; they are named constants precisely so tuning them later is one edit in
//  one place rather than an archaeology exercise.
//
//  ponytail: in-memory ranking over the whole fetched page. Move it server-side when
//  a page stops fitting in memory, not before.
//

import Foundation

enum DailyRanker {

    /// Every tunable number in the feed's ordering, in one block.
    private enum Weights {
        /// Hours until a post's recency term halves. Yesterday still shows up;
        /// last week does not float back to the top.
        static let recencyHalfLifeHours: Double = 18

        /// A comment costs more than a thumb, and a save costs more than a comment,
        /// so they count for more.
        static let commentWeight: Double = 2
        static let saveWeight: Double = 3

        /// Divisor on the log-damped engagement term. Larger = flatter, so one
        /// popular post cannot own the whole screen.
        static let engagementDamping: Double = 4

        /// Mutual follow beats one-way follow beats a stranger.
        static let friendMultiplier: Double = 2.0
        static let followedMultiplier: Double = 1.6
        static let strangerMultiplier: Double = 1.0

        /// Full marks when everyone you follow has liked something. Added rather
        /// than multiplied: social proof should be able to lift a stranger's post
        /// into view on its own, which a multiplier against a small base cannot do.
        static let socialProofMax: Double = 2.5

        /// An event you could still get to tonight beats one three weeks out.
        static let urgencyMultiplier: Double = 1.8
        /// How far ahead still counts as urgent.
        static let urgencyWindowHours: Double = 48
    }

    /// Order the feed, best first.
    ///
    /// Stable: items scoring equally keep their input order, so a refresh that
    /// changes nothing does not visibly reshuffle the screen.
    static func rank(_ items: [DailyFeedItem], now: Date = Date()) -> [DailyFeedItem] {
        // Spelled out in steps, not one chain: the inferred tuple made the type
        // checker give up ("unable to type-check this expression in reasonable time").
        var scored: [Scored] = []
        scored.reserveCapacity(items.count)

        for (index, item) in items.enumerated() where isVisible(item, now: now) {
            scored.append(Scored(index: index, item: item, score: score(item, now: now)))
        }

        scored.sort { a, b in
            a.score == b.score ? a.index < b.index : a.score > b.score
        }

        return scored.map(\.item)
    }

    private struct Scored {
        let index: Int
        let item: DailyFeedItem
        let score: Double
    }

    /// An event that has already happened is not news, it is a receipt. Postings
    /// never expire — an old one simply scores its way to the bottom.
    static func isVisible(_ item: DailyFeedItem, now: Date) -> Bool {
        guard case .event = item, let startsAt = item.signals.startsAt else { return true }
        return startsAt >= now
    }

    /// `recency × engagement × affinity × urgency + socialProof`
    static func score(_ item: DailyFeedItem, now: Date) -> Double {
        let signals = item.signals
        return recency(signals, now: now)
            * engagement(signals)
            * affinity(signals)
            * urgency(signals, now: now)
            + socialProof(signals)
    }

    // MARK: - Terms

    private static func recency(_ signals: FeedSignals, now: Date) -> Double {
        // Clamped at zero so a clock skew that puts a post slightly in the future
        // reads as "brand new" rather than scoring above 1 and outranking everything.
        let hours = max(0, now.timeIntervalSince(signals.createdAt) / 3600)
        return exp(-hours / Weights.recencyHalfLifeHours)
    }

    private static func engagement(_ signals: FeedSignals) -> Double {
        let weighted = Double(signals.likeCount)
            + Weights.commentWeight * Double(signals.commentCount)
            + Weights.saveWeight * Double(signals.saveCount)
        return 1 + log1p(max(0, weighted)) / Weights.engagementDamping
    }

    private static func affinity(_ signals: FeedSignals) -> Double {
        if signals.isFriend { return Weights.friendMultiplier }
        if signals.isFollowed { return Weights.followedMultiplier }
        return Weights.strangerMultiplier
    }

    /// A RATIO, not a count: following 400 people should not drown out the signal
    /// for someone who follows 12. Eight of your ten is loud either way.
    private static func socialProof(_ signals: FeedSignals) -> Double {
        guard signals.followedCount > 0, signals.followedLikerCount > 0 else { return 0 }
        let ratio = Double(signals.followedLikerCount) / Double(signals.followedCount)
        return Weights.socialProofMax * min(1, ratio)
    }

    private static func urgency(_ signals: FeedSignals, now: Date) -> Double {
        guard let startsAt = signals.startsAt, startsAt >= now else { return 1 }
        let hoursAway = startsAt.timeIntervalSince(now) / 3600
        return hoursAway <= Weights.urgencyWindowHours ? Weights.urgencyMultiplier : 1
    }
}
