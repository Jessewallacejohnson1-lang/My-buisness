//
//  FeedCardItem.swift
//  Block Party — normalized, data-layer-independent input for a feed card.
//

import Foundation

struct FeedCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let dateChip: String
    let metaLine: String
    let image: FeedCardImageSource
    let recurrence: String?
    let goingCount: Int
    let goingAvatars: [URL]
    let goingSummary: String
    var likeCount: Int
    var isLiked: Bool
    var isSaved: Bool
    var isJoined: Bool
}

enum FeedCardImageSource: Hashable {
    case eventPhoto(URL)
    case placesPhoto(URL, attribution: String)
    case fallback
}
