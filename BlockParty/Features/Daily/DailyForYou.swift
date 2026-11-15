//
//  DailyForYou.swift
//  Block Party — For you on the Block Party tab (BP app daily-tab 25): under Following, one list
//  that keeps going, as Instagram's home feed goes on past who you follow with posts it picks
//  for you (`references/bp-tab-for-you/` in the BP app folder). Its cards are the Town feed's,
//  drawn as Town draws them.
//

import SwiftUI

enum DailyForYou {
    /// How much a card that shares one of your interests counts: as if it sat this many times
    /// higher in the Town feed (Jesse's yes at daily-tab 25's Check-in 1, "the feed's score plus
    /// interests").
    static let interestLift = 2.0

    /// The Town feed's entries (`feed`, in its order) that For you shows: Events of `days` (today
    /// and the six after it), the neighbours' posts and News, still on at `now` (the feed holds its
    /// list while Town is scrolled down), never one whose id is in `shown` (a section above has it).
    /// One you heart or go to stays, as on Town, so its heart and Attend answer under your finger.
    /// Today's Events come first, so For you today's row folds in at the top; then the rest, each
    /// at its place in the feed, lifted by `interestLift` when it shares one of your `interests`.
    static func picks(from feed: [TownFeedEntry], days: [String], interests: [String],
                      shown: Set<String>, now: Date) -> [TownFeedEntry] {
        let week = Set(days)
        let today = days.first
        let ranked = feed.enumerated().compactMap { place, entry -> (entry: TownFeedEntry, today: Bool, score: Double, place: Int)? in
            guard !shown.contains(entry.id), entry.leavesAt > now else { return nil }
            if let card = entry.card {
                guard let day = card.eventDate, week.contains(day), !card.cancelled else { return nil }
            }
            let lift = shares(entry, interests) ? interestLift : 1
            return (entry, entry.card?.eventDate == today, lift / Double(place + 1), place)
        }
        // A tie goes to the card higher in the feed.
        return ranked.sorted { ($0.today ? 1 : 0, $0.score, -$0.place) > ($1.today ? 1 : 0, $1.score, -$1.place) }
            .map(\.entry)
    }

    /// Whether the card shares one of `interests`, by the words Daily's topics match on; News also
    /// by the interest the feed says it shares with you.
    static func shares(_ entry: TownFeedEntry, _ interests: [String]) -> Bool {
        let text: String
        switch entry.item {
        case .event(let card): text = DailyTopic.text(card)
        case .news(let news):
            if let interest = news.interest, interests.contains(interest) { return true }
            text = "\(news.headline) \(news.words) \(news.place)"
        case .post(let post): text = post.words
        }
        return interests.contains { DailyTopic.matches(text: text, $0) }
    }
}

/// The section: its title in the logo's face, as Following's, then the cards as Town draws them,
/// `followingCardGap` apart, as on the mock Jesse said yes to.
struct ForYouSection: View {
    let entries: [TownFeedEntry]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DailyRowMetric.titleToCards) {
            DailyRowTitle(title: "For you")
            // Lazy, as Following's cards: a post's photo takes its height from its width.
            LazyVStack(spacing: DailyMetric.followingCardGap) {
                ForEach(entries) { entry in
                    switch entry.item {
                    case .event(let card):
                        FeedEventCard(item: card, onShare: { ShareCenter.shared.present(.event(card)) })
                    case .news(let news): TownNewsCard(news: news)
                    case .post(let post): FeedPostCard(post: post)
                    }
                }
            }
        }
        // A card you hid closes up instead of vanishing.
        .animation(reduceMotion ? nil : Motion.smooth, value: entries.map(\.id))
    }
}
