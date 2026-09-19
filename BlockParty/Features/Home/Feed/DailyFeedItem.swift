//
//  DailyFeedItem.swift
//  Block Party — what the Daily feed carries: neighbour postings and town events,
//  one stream, two shapes.
//
//  Ranking inputs live HERE rather than on `FeedCardItem`, which is a presentation
//  shape the card reads straight off. A card should not be able to see how it was
//  ranked, and the ranker should not have to care what a card looks like.
//

import Foundation

/// A neighbour's post: a photo and something they said about it.
struct PostingItem: Identifiable, Hashable {
    let id: String
    let authorName: String
    let authorAvatar: URL?
    let createdAt: Date
    let image: FeedCardImageSource
    let caption: String
    var likeCount: Int
    var commentCount: Int
    var isLiked: Bool
    var isSaved: Bool
    let signals: FeedSignals
}

/// Everything the ranker needs and the card never shows.
///
/// `followedCount` rides on every item rather than being passed in beside the
/// array because it makes `DailyRanker.rank` a pure function of its input — no
/// ambient "who am I" to thread through, and a test can describe one item's whole
/// world in one literal.
struct FeedSignals: Hashable {
    /// You follow whoever posted this.
    var isFollowed: Bool = false
    /// Mutual — they follow you back. A stronger tie than a one-way follow.
    var isFriend: Bool = false
    /// How many of the people YOU follow have given this a thumbs-up.
    var followedLikerCount: Int = 0
    /// How many people you follow in total, for the ratio.
    var followedCount: Int = 0
    /// Engagement the ranker weighs but the posting shape carries separately for
    /// events (a `FeedCardItem` has no comment count of its own).
    var commentCount: Int = 0
    var saveCount: Int = 0
    /// When this entered the feed. For an event that is when it was posted, NOT
    /// when it happens — `startsAt` covers that.
    var createdAt: Date = .distantPast
    var likeCount: Int = 0
    /// Only set for events: when the thing actually happens.
    var startsAt: Date?
}

enum DailyFeedItem: Identifiable {
    case posting(PostingItem)
    case event(FeedCardItem, signals: FeedSignals)

    var id: String {
        switch self {
        case .posting(let posting): return "posting:" + posting.id
        case .event(let item, _):   return "event:" + item.id
        }
    }

    var signals: FeedSignals {
        switch self {
        case .posting(let posting):
            var s = posting.signals
            // The posting is the authority on its own visible counts; the signal
            // block only has to carry what the card cannot show.
            s.likeCount = posting.likeCount
            s.commentCount = posting.commentCount
            s.createdAt = posting.createdAt
            return s
        case .event(_, let signals):
            return signals
        }
    }
}
