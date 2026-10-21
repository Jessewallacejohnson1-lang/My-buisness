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
    /// The Town feed's top: your Event of the day as its poster (BP app event-card 03).
    case eventOfTheDay(DailyEvent)

    var id: String {
        switch self {
        case .posting(let posting):     return "posting:" + posting.id
        case .event(let item):          return "event:" + item.id
        case .eventOfTheDay(let event): return "event-of-the-day:" + event.id
        }
    }

    /// The Event's id, for the views the Town feed counts (ticket 20); nil for a posting.
    var eventID: String? {
        switch self {
        case .posting: return nil
        case .event(let item): return item.id
        case .eventOfTheDay(let event): return event.id
        }
    }

    /// The Town feed's column: your Event of the day on top, then the cards in the feed's order,
    /// leaving out the one the poster shows, so it never shows twice (Jesse, 2026-10-21).
    static func town(_ cards: [FeedCardItem], eventOfTheDay: DailyEvent?) -> [DailyFeedItem] {
        guard let eventOfTheDay else { return cards.map { .event($0) } }
        return [.eventOfTheDay(eventOfTheDay)] + cards.filter { $0.id != eventOfTheDay.id }.map { .event($0) }
    }
}
