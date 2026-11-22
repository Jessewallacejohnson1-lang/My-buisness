//
//  DailyPage.swift
//  Block Party — the Block Party tab (Daily until BP app five-tabs 04): the neighbour's own page
//  for today. People you may know left it in five-tabs 04: Friends and Profiles hold them.
//
//  Top to bottom (`docs/plans/daily-tab/SPEC.md` in the BP app folder): the wordmark and the
//  Town's logo, the week, the topics (daily-tab 19, `DailyTop.swift`), Event of the
//  day as the Town tab's poster, then Friends are going, Suggestions, Following and For you,
//  on plain paper (no yellow: Jesse, 2026-10-21). Tap a day in the week and the page turns to it
//  (daily-tab 16).
//  A section with nothing in it is left out. Spotlight left the page on 2026-11-18 (Jesse: "remove
//  spotlight from app for now", BP app backlog 35). What you're Going
//  to lives on the You tab (BP app docs/plans/you-tab).
//

import SwiftUI

/// Daily's page sizes. The low sun, the tilt and the Spotlight card's sizes left with Spotlight
/// (BP app backlog 35).
nonisolated enum DailyMetric {
    static let side: CGFloat = 18
    /// Clears the floating tab bar: the same 96 the other tab scrollers reserve.
    static let tabBarClearance: CGFloat = 96

    /// The first section sits this far under the week's faces, or the topics under them. Picked on
    /// the Figma drafts (2026-10-21): no Reference has a week over a page like this one. Above the
    /// week, the wordmark and the Town's logo (`DailyTopMetric`, daily-tab 19).
    static let weekToSection: CGFloat = 24
    /// Another day's page: the last one fades out this fast, then the picked one fades in
    /// (guessed; no Reference recording).
    static let dayFadeOut: Double = 0.1
    static let dayFade: Double = 0.2
    /// The plain paper's height under the week on a day with nothing in it, or one still being read.
    static let emptyHeight: CGFloat = 420
    /// The clock's frosted edge comes in over this much scroll, as the week slides under the
    /// clock. At rest and pulled down it is gone. Picked.
    static let edgeFade: CGFloat = 20

    /// Between the sections, and from a section's label to what it labels: MEASURED from
    /// Airbnb's trips page (the gap between one trip's card and the next city's heading,
    /// and from that heading to its card), Daily's first Reference.
    static let eventSectionTop: CGFloat = 38
    /// Between Event of the day's posters on a busy day; the next one's edge shows by this
    /// much less than the page margin. Picked.
    static let eventGap: CGFloat = 10

    /// Following, MEASURED from Jesse's Reference: Instagram's activity rows
    /// (`references/daily-following/instagram-activity.jpg` in the BP app folder, an
    /// @3x 393pt screen): a 44pt round photo, 13pt to the words, a 44pt photo with 8pt
    /// corners on the right, rows 64pt apart. The rows start at `side` (18) where
    /// Instagram's start at 16, as the other Daily sections do.
    static let followingPhoto: CGFloat = 44
    static let followingPhotoRadius: CGFloat = 8
    static let followingGap: CGFloat = 13
    /// Above and below each row's 44pt photos, for Instagram's 64pt rows.
    static let followingRowInset: CGFloat = 10
    /// From the last row to the first post or News card under it, and between the cards (picked at
    /// daily-tab 23's Check-in 1; BP app `references/following-posts/SPEC.md`).
    static let followingCardGap: CGFloat = 12
}

#if DEBUG
/// `-daily-samples`: Daily's sample Event of the day, Suggestions and Following, for
/// design work. Without it a test build shows only what's real, as the App Store build does
/// (Jesse, 2026-10-20).
nonisolated enum DailySamples {
    static let on = LaunchFlags.has(.dailySamples)
}
#endif

/// The Town clock as Daily reads it: the low sun and Event of the day both run on it.
nonisolated enum DailyClock {
    static func now(_ date: Date) -> Date {
        #if DEBUG
        // `-daily-hour <h>` holds it at that hour of today in the Town, so morning and
        // evening can be shot at any time of day.
        if let hour = LaunchFlags.value(.dailyHour).flatMap({ Double($0) }) {
            let calendar = Town.gregorian
            return calendar.startOfDay(for: date).addingTimeInterval(hour * 3600)
        }
        #endif
        return date
    }
}

/// What one day's page shows under the week, section by section.
struct DailyLists {
    var events: [DailyEvent]
    var friendsGoing: [DailyEvent]
    var suggestions: [DailyEvent]
    var following: [DailyFollowing]
    /// Under Following's rows (daily-tab 23): posts from who you follow and the followed places' News.
    var followingCards: [DailyFollowingCard]
    /// Under Following (daily-tab 25): the Town feed's Events of the week, posts and News for you,
    /// on today's page under Best of only. With any, Suggestions' row folds into it.
    var forYou: [TownFeedEntry] = []

    /// Suggestions' row shows only where For you doesn't take it in (Jesse at daily-tab 25's Check-in 1).
    var showsSuggestions: Bool { forYou.isEmpty }

    /// Every event on the page, for its topics.
    var items: [FeedCardItem] {
        (events + friendsGoing + suggestions).map(\.item) + following.map(\.event.item)
    }

    /// `day`'s sections, `week` being today and the six days after it. Each leaves out what one
    /// above it shows (SPEC.md); a topic keeps only its own. `picks` are the day's Event of the day
    /// picks, `cards` the Town feed's, `posts` its neighbours' posts, `news` the followed places' News,
    /// `feed` the Town feed's whole list in its order, for For you.
    static func make(day: DailyWeekDay, week: [DailyWeekDay], now: Date, picks: [DailyEvent],
                     cards: [FeedCardItem], posts: [TownPost] = [], news: [TownNews] = [],
                     feed: [TownFeedEntry] = [], interests: [String], topic: String?,
                     isGoing: (FeedCardItem) -> Bool, isHearted: (FeedCardItem) -> Bool) -> DailyLists {
        let isToday = day == week.first
        // Another day's sections read from its midnight, so all of that day is still to come.
        let clock = isToday ? now : day.start
        let fits = { (item: FeedCardItem) in topic.map { DailyTopic.matches(item, $0) } ?? true }
        let events = DailyEvent.showing(picks.filter { fits($0.item) }, now: clock, limit: 3)
        // Today looks a week ahead; a day picked in the week, that day (Jesse, daily-tab 21).
        let friendDays = Set(isToday ? week.map(\.id) : [day.id])
        // What you follow is Following's: what that section shows, no section above takes
        // (school-activities 03).
        let following = DailyFollowing.showing(
            DailyFollowing.today(from: cards, day: day.id, now: clock)
                .filter { row in topic.map { DailyTopic.matches(row, $0) } ?? true },
            now: clock, without: events, limit: 10)
        // The cards under the rows: today's page under Best of only; a topic, or another day in the week,
        // shows the rows alone (Jesse at daily-tab 23's Check-in 1).
        let followingCards = isToday && topic == nil
            ? DailyFollowingCard.today(posts: posts, news: news, rows: following.count, now: clock) : []
        let followed = Set(following.map(\.event.id))
        let cards = cards.filter { !followed.contains($0.id) }
        let friendsGoing = (DailyEvent.sampleFriendsGoing(now: clock)
            ?? DailyEvent.friendsGoing(from: cards, days: friendDays, now: clock, without: events))
            .filter { fits($0.item) }
        // Suggestions never offer what you're Going to or hearted (SPEC.md; a heart is a save, BP app inside-cards 16).
        func left(_ item: FeedCardItem) -> Bool { fits(item) && !isGoing(item) && !isHearted(item) }
        let suggestions = DailyEvent.sampleSuggestions(now: clock).map {
            DailyEvent.showing($0.filter { left($0.item) }, now: clock, without: events + friendsGoing,
                               limit: DailyRowMetric.limit)
        } ?? DailyEvent.suggestions(from: cards, day: day.id, interests: interests, now: clock,
                                    without: events + friendsGoing, left: left)
        // For you: today's page under Best of only, as Following's cards; nothing a section above shows.
        let forYou = isToday && topic == nil
            ? DailyForYou.picks(from: feed, days: week.map(\.id), interests: interests,
                                shown: Set((events + friendsGoing).map(\.id)).union(followed)
                                    .union(followingCards.map(\.entryID)),
                                now: clock)
            : []
        return DailyLists(events: events, friendsGoing: friendsGoing, suggestions: suggestions, following: following,
                          followingCards: followingCards, forYou: forYou)
    }
}

struct DailyPage: View {
    /// Today's Event of the day picks as read (`EventOfTheDay`); the page leaves out what's over.
    let events: [DailyEvent]
    /// The day picked in the week, nil for today. Kept in `MainTabsView`, so it stays while you
    /// switch tabs, and a new launch opens on today.
    @Binding var picked: String?
    /// The week's other days' picks.
    let dayPicks: DailyDayPicks
    /// The friends going each day (`DailyWeek.friendsGoing`).
    let friends: [String: [FeedFriend]]
    /// The Town feed's cards, which Friends are going and Suggestions read (daily-tab 20 and 21).
    let cards: [FeedCardItem]
    /// The Town feed's posts and the followed places' News (`FollowingNews`), for Following's cards
    /// (daily-tab 23).
    var posts: [TownPost] = []
    var news: [TownNews] = []
    /// The Town feed's whole list in its order, for For you (daily-tab 25).
    var feed: [TownFeedEntry] = []
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the page has scrolled, held only up to `edgeFade`.
    @State private var scrolled: CGFloat = 0
    /// The topic picked under the week (daily-tab 19), nil for "Best of": everything.
    @State private var topic: String?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = DailyClock.now(context.date)
            let days = DailyWeek.days(from: now)
            page(now: now, days: days, shown: DailyWeek.shown(picked: picked, today: days[0].id))
        }
    }

    private func page(now: Date, days: [DailyWeekDay], shown: String) -> some View {
        let day = days.first { $0.id == shown } ?? days[0]
        let isToday = day == days[0]
        let interests = Interests.get()
        func lists(_ topic: String?) -> DailyLists {
            DailyLists.make(day: day, week: days, now: now, picks: isToday ? events : dayPicks.picks[day.id] ?? [],
                            cards: cards, posts: posts, news: news, feed: feed, interests: interests, topic: topic,
                            isGoing: { actions.going($0).isGoing }, isHearted: { actions.heart($0).isHearted })
        }
        let all = lists(nil)
        // The day's topics come from all it has. A topic the day lacks reads as "Best of" there and
        // comes back on a day that has it: the topic stays picked across the week (picked).
        let topics = DailyTopic.topics(for: all.items, mine: interests)
        let topic = self.topic.flatMap { topics.contains($0) ? $0 : nil }
        let onPage = topic == nil ? all : lists(topic)
        // A day still being read, offline, or with nothing in it shows plain paper under the week, with
        // no words; it fills in once a read answers (Jesse, BP app daily-tab 29).
        let blank = (!isToday && dayPicks.picks[day.id] == nil)
            || (onPage.items.isEmpty && onPage.following.isEmpty
                && onPage.followingCards.isEmpty && onPage.forYou.isEmpty)
        return ZStack {
            Hue.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    DailyMasthead()
                    DailyWeekRow(days: days, shown: shown, friends: friends) { tapped in
                        withAnimation(reduceMotion ? nil : Motion.select) {
                            picked = tapped == days[0] ? nil : tapped.id
                        }
                    }
                    .padding(.top, DailyTopMetric.toWeek)
                    // The system's selection tick on a tap, and only then (not at midnight).
                    .sensoryFeedback(.selection, trigger: picked)
                    // Always there, "Best of" alone on a day with no topics, so the page under it
                    // never jumps while another day reads.
                    DailyTopicRow(topics: topics, picked: topic) { tapped in
                        withAnimation(reduceMotion ? nil : Motion.select) { self.topic = tapped }
                    }
                    .padding(.top, DailyTopMetric.toTopics - DailyTopMetric.topicTapExtra)
                    .sensoryFeedback(.selection, trigger: self.topic)
                    // The last day's page fades out, then the picked day's fades in, in the same
                    // spot, so the two never sit on top of each other.
                    ZStack(alignment: .top) {
                        // The cards' chips count from now ("In 3 days"), though the day's are
                        // picked from its midnight.
                        sections(lists: onPage, blank: blank, now: now)
                            .id("\(day.id) \(topic ?? "")")
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: DailyMetric.dayFade).delay(DailyMetric.dayFadeOut)),
                                removal: .opacity.animation(.easeIn(duration: DailyMetric.dayFadeOut))))
                    }
                    Color.clear.frame(height: DailyMetric.tabBarClearance)
                }
            }
            .scrollRun()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), DailyMetric.edgeFade)
            } action: { _, offset in scrolled = offset }
        }
        // Today's are `EventOfTheDay`'s; a picked day reads at once, and the rest of the week reads
        // behind it, one day at a time, so a tap usually finds its day already there.
        .task(id: day.id) { if !isToday { await dayPicks.refresh(day) } }
        .task(id: days[0].id) {
            for other in days.dropFirst() {
                // Leaving Daily calls the rest off; they read when Daily opens again.
                guard !Task.isCancelled else { return }
                await dayPicks.refresh(other)
            }
        }
        // The Town feed's frosted band behind the clock, so the page blurs under it;
        // it comes in with the first bit of scroll.
        .statusEdge(opacity: scrolled / DailyMetric.edgeFade)
    }

    @ViewBuilder
    private func sections(lists: DailyLists, blank: Bool, now: Date) -> some View {
        if blank {
            Color.clear.frame(height: DailyMetric.emptyHeight)
        } else {
            VStack(spacing: DailyMetric.eventSectionTop) {
                // Event of the day first (Jesse, daily-tab 18).
                if !lists.events.isEmpty { EventOfTheDaySection(events: lists.events, now: now) }
                if !lists.friendsGoing.isEmpty { FriendsGoingSection(events: lists.friendsGoing, now: now) }
                if lists.showsSuggestions, !lists.suggestions.isEmpty {
                    SuggestionsSection(events: lists.suggestions, now: now)
                }
                if !lists.following.isEmpty || !lists.followingCards.isEmpty {
                    FollowingSection(items: lists.following, cards: lists.followingCards, now: now)
                }
                if !lists.forYou.isEmpty { ForYouSection(entries: lists.forYou) }
            }
            .padding(.top, DailyMetric.weekToSection)
        }
    }
}

/// A section's small label, centred: SF Mono, as in the Reference's typewriter-style
/// label (Jesse, 2026-09-30). The names are working names; Jesse writes the final words.
struct DailySectionLabel: View {
    let title: String
    let ink: Color

    var body: some View {
        Text(title.uppercased())
            .font(.monoMedium(11).monospaced()).tracking(1.5)
            .foregroundStyle(ink)
            .accessibilityAddTraits(.isHeader)
    }
}
