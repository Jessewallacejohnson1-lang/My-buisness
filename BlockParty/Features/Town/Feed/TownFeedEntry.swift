//
//  TownFeedEntry.swift
//  Block Party — the Town feed's values: a line of the feed, what it sends about views and
//  opens, and the choices its ••• makes.
//

import Foundation

/// One line of the Town feed: an event's card, town news (ticket 35) or a neighbour's post (ticket 29),
/// and when it leaves.
struct TownFeedEntry: Identifiable {
    enum Item {
        case event(FeedCardItem)
        case news(TownNews)
        case post(TownPost)
    }
    let item: Item
    let leavesAt: Date

    var id: String {
        switch item {
        case .event(let card): card.id
        case .news(let news): news.id
        case .post(let post): post.id
        }
    }

    /// The event's card; nil for news and posts.
    var card: FeedCardItem? {
        if case .event(let card) = item { return card }
        return nil
    }

    var isNews: Bool { news != nil }

    /// The story; nil for the rest.
    var news: TownNews? {
        if case .news(let news) = item { return news }
        return nil
    }

    /// The neighbour's post; nil for the rest.
    var post: TownPost? {
        if case .post(let post) = item { return post }
        return nil
    }
}

extension TownFeedEntry {
    init(card: FeedCardItem, leavesAt: Date) {
        self.init(item: .event(card), leavesAt: leavesAt)
    }
}

/// What the feed showed (a view), what was opened, or an Event shared from the app (ticket 26),
/// for `feed_actions` (ticket 20).
struct FeedAction: Equatable {
    /// `news` is a view of Town news, which goes apart from the rest (`see_news`, town-feed 41).
    enum Kind: String { case view, open, share, news }
    let itemID: String
    let kind: Kind
}

/// Not interested, Mute and their undoing, for the server (ticket 21). Mute names an Event and
/// gets back the host it muted; Unmute names that host. Report (ticket 22) names an Event and a
/// reason, and with Wrong info maybe a note (BP app backlog 26); Undo on its Hidden line is
/// undoNotInterested, which lifts the hide and keeps the report.
enum FeedChoice: Equatable {
    case notInterested(String), undoNotInterested(String), mute(String), unmute(String)
    case report(String, ReportReason, note: String? = nil)
}

/// What a neighbour may add to a Wrong info report (BP app backlog 26, Jesse at Check-in 1, 2026-11-13: "yes to all"):
/// a few words on what's wrong, for the admin. The server trims and cuts it too, and keeps it only once the post check
/// says yes.
enum ReportNote {
    static let limit = 150

    /// The words as sent: trimmed, at most `limit` letters, nil when nothing is left.
    static func clean(_ words: String) -> String? {
        let trimmed = String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Why a neighbour reports an Event, in the sheet's order (words page `report-reasons`, Jesse
/// 2026-10-12). Wrong photo shows only on a card with a photo Block Party saved, Wrong info only
/// on a found Event; neither hides the card.
enum ReportReason: String, CaseIterable, Identifiable {
    case wrongPhoto = "wrong_photo", wrongInfo = "wrong_info", scam, bullying, violence, nudity,
         restricted, selfHarm = "self_harm"

    var id: String { rawValue }
    var hides: Bool { self != .wrongPhoto && self != .wrongInfo }

    var label: String {
        switch self {
        case .wrongPhoto: "Wrong photo"
        case .wrongInfo: "Wrong info"
        case .scam: "Scam, fraud or spam"
        case .bullying: "Bullying or unwanted contact"
        case .violence: "Violence, hate or exploitation"
        case .nudity: "Nudity or sexual activity"
        case .restricted: "Selling or promoting restricted items"
        case .selfHarm: "Suicide, self-injury or eating disorders"
        }
    }

    /// The reasons a card offers.
    static func offered(photo: Bool, found: Bool) -> [ReportReason] {
        allCases.filter { ($0 != .wrongPhoto || photo) && ($0 != .wrongInfo || found) }
    }
}

/// A host you muted, as the Muted list shows it.
struct MutedHost: Identifiable, Equatable, Decodable {
    let host: String
    let name: String
    var id: String { host }
}

/// A card just hidden, showing its Undo line.
struct FeedHide: Equatable {
    let id: String
    let hostName: String
    let mute: Bool
}
