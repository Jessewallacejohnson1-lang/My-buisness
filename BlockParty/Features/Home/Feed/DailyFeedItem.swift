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
    /// Town news, below the events (town-feed 35).
    case news(TownNews)

    var id: String {
        switch self {
        case .posting(let posting):     return "posting:" + posting.id
        case .event(let item):          return "event:" + item.id
        case .eventOfTheDay(let event): return "event-of-the-day:" + event.id
        case .news(let news):           return "news:" + news.id
        }
    }

    /// The Event's id, for the views the Town feed counts (ticket 20); nil for a posting or news.
    var eventID: String? {
        switch self {
        case .posting, .news: return nil
        case .event(let item): return item.id
        case .eventOfTheDay(let event): return event.id
        }
    }

    /// The Town feed's column: your Event of the day on top, then the events and news in the feed's
    /// order, leaving out the event the poster shows, so it never shows twice (Jesse, 2026-10-21).
    /// The admin's Score names each card's place as it sits on screen, the poster's first, news
    /// counted (taste.md).
    static func town(_ entries: [TownFeedEntry], eventOfTheDay: DailyEvent?) -> [DailyFeedItem] {
        var top = eventOfTheDay
        let below = entries.filter { entry in top.map { entry.card?.id != $0.id } ?? true }
        let first = top == nil ? 1 : 2
        let of = below.count + first - 1
        top?.item.score?.spot = 1
        top?.item.score?.of = of
        return (top.map { [.eventOfTheDay($0)] } ?? []) + below.enumerated().map { place, entry in
            switch entry.item {
            case .event(var card):
                card.score?.spot = place + first
                card.score?.of = of
                return .event(card)
            case .news(let news):
                return .news(news)
            }
        }
    }
}
