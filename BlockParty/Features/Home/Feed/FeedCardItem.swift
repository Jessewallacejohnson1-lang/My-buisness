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
    var eventDate: String? = nil
    var startTime: String? = nil
    var location: String? = nil

    var shareTime: String? {
        if let startTime { return startTime }
        let parts = metaLine.components(separatedBy: " · ")
        guard parts.count > 1 else { return nil }
        let time = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return time.isEmpty ? nil : time
    }

    var shareLocation: String? {
        if let location { return location }
        let parts = metaLine.components(separatedBy: " · ")
        let location = (parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : metaLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? nil : location
    }
}

struct FeedCardActionState: Equatable {
    private(set) var likeCount: Int
    private(set) var isLiked: Bool
    private(set) var isSaved: Bool

    init(item: FeedCardItem) {
        likeCount = item.likeCount
        isLiked = item.isLiked
        isSaved = item.isSaved
    }

    @discardableResult
    mutating func toggleLike() -> Bool {
        isLiked.toggle()
        likeCount = max(0, likeCount + (isLiked ? 1 : -1))
        return isLiked
    }

    /// Like-only path for the image's double-tap. Returns whether state changed.
    @discardableResult
    mutating func like() -> Bool {
        guard !isLiked else { return false }
        isLiked = true
        likeCount += 1
        return true
    }

    @discardableResult
    mutating func toggleSave() -> Bool {
        isSaved.toggle()
        return isSaved
    }

    mutating func sync(with item: FeedCardItem) {
        likeCount = item.likeCount
        isLiked = item.isLiked
        isSaved = item.isSaved
    }
}

struct FeedCardJoinState: Equatable {
    private(set) var goingCount: Int
    private(set) var isJoined: Bool
    private(set) var hasCurrentUserAvatar: Bool

    init(item: FeedCardItem) {
        goingCount = item.goingCount
        isJoined = item.isJoined
        hasCurrentUserAvatar = item.isJoined
    }

    @discardableResult
    mutating func toggleJoin() -> Bool {
        isJoined.toggle()
        goingCount = max(0, goingCount + (isJoined ? 1 : -1))
        hasCurrentUserAvatar = isJoined
        return isJoined
    }

    mutating func sync(with item: FeedCardItem) {
        goingCount = item.goingCount
        isJoined = item.isJoined
        hasCurrentUserAvatar = item.isJoined
    }
}

/// What sits behind a feed card's title.
///
/// `venueLookup` is an INTENT, not an image: no first-party photo exists, but the
/// posting names a place we can ask Google Places about. It stays unresolved here
/// because `FeedCardItem`'s init is synchronous and a Places lookup is async AND
/// billed — resolving during the feed load would spend a call on every card,
/// including the ones nobody scrolls to. The card resolves it lazily when it
/// appears (`FeedEventCard.resolveVenuePhoto`), landing on `.placesPhoto`; until
/// then — and forever if the venue can't be confidently identified — the card
/// renders the `fallback` treatment.
enum FeedCardImageSource: Hashable {
    case eventPhoto(URL)
    case placesPhoto(URL, attribution: String)
    case venueLookup(name: String, hint: String?)
    case fallback
}
