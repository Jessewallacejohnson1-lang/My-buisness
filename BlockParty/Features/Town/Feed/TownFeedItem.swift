//
//  TownFeedItem.swift
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
    /// You already follow whoever posted this, so the card offers no Follow.
    var isFollowed = false
}

enum TownFeedItem: Identifiable {
    case posting(PostingItem)
    case event(FeedCardItem)
    /// The Town feed's top: your Event of the day as its poster (BP app event-card 03).
    case eventOfTheDay(DailyEvent)
    /// Town news, below the events (town-feed 35).
    case news(TownNews)
    /// A neighbour's post, among the Events (town-feed 29).
    case post(TownPost)
    /// Where the ranked Town feed ends (town-feed 23).
    case caughtUp
    /// A place to try past the later Events, in the round that brought it (town-feed 23).
    case place(SearchItem, round: Int)
    /// An Event or News item from the ranked list above, again in a later round (town-feed 23).
    case again(TownFeedEntry.Item, round: Int)

    var id: String {
        switch self {
        case .posting(let posting):     return "posting:" + posting.id
        case .event(let item):          return "event:" + item.id
        case .eventOfTheDay(let event): return "event-of-the-day:" + event.id
        case .news(let news):           return "news:" + news.id
        case .post(let post):           return "post:" + post.id
        case .caughtUp:                 return "caught-up"
        case .place(let place, let round): return "place:\(round):" + place.id
        case .again(let item, let round):  return "again:\(round):" + TownFeedEntry(item: item, leavesAt: .distantFuture).id
        }
    }

    /// The Event's id, for the views the Town feed counts (ticket 20); nil for a posting or news.
    /// A repeat is counted where it first showed, so its two rows never cross each other's timing.
    var eventID: String? {
        switch self {
        case .posting, .news, .post, .caughtUp, .place, .again: return nil
        case .event(let item): return item.id
        case .eventOfTheDay(let event): return event.id
        }
    }

    /// What a view of it counts against: an Event, a neighbour's post or a news item (town-feed 41).
    var seenID: String? {
        if case .again = self { return nil }
        return hideID
    }

    /// The id Not interested and Mute fold it by: the Event's, or the news item's (news-menu). Not
    /// `eventID`, whose ids go to the views table, which takes Events only.
    var hideID: String? {
        switch self {
        case .news(let news): return news.id
        case .post(let post): return post.id
        case .again(.news(let news), _): return news.id
        case .again(.post(let post), _): return post.id
        case .again(.event(let card), _): return card.id
        default: return eventID
        }
    }

    /// The Town feed's column: your Event of the day on top, then the events and news in the feed's
    /// order, leaving out the event the poster shows, so it never shows twice (Jesse, 2026-10-21).
    static func town(_ entries: [TownFeedEntry], eventOfTheDay: DailyEvent?) -> [TownFeedItem] {
        let below = entries.filter { entry in eventOfTheDay.map { entry.card?.id != $0.id } ?? true }
        return (eventOfTheDay.map { [.eventOfTheDay($0)] } ?? []) + below.map { entry in
            switch entry.item {
            case .event(let card):
                return .event(card)
            case .news(let news):
                return .news(news)
            case .post(let post):
                return .post(post)
            }
        }
    }
}
