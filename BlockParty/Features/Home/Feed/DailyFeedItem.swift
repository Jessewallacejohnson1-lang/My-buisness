//
//  DailyFeedItem.swift
//  Block Party — what a feed column carries: neighbour postings and town events,
//  one stream, two shapes.
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
    /// You already follow whoever posted this, so the card offers no Follow.
    var isFollowed = false
}

enum DailyFeedItem: Identifiable {
    case posting(PostingItem)
    case event(FeedCardItem)

    var id: String {
        switch self {
        case .posting(let posting): return "posting:" + posting.id
        case .event(let item):      return "event:" + item.id
        }
    }
}
