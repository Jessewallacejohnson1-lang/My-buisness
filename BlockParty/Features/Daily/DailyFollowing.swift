//
//  DailyFollowing.swift
//  Block Party — the Block Party tab's last section: today's Events from the people, teams, places and
//  Groups you follow, as Instagram's activity rows, and under them the posts from you, your friends and
//  who you follow and the News of the places you follow, each as the Town feed draws it
//  (`docs/plans/daily-tab/SPEC.md` §5 and ticket 23 in the BP app folder).
//

import SwiftUI

/// One row: who it's from, what, when, and a small photo. The whole row opens the Event page.
struct DailyFollowing: Identifiable {
    var id: String
    /// The person, team, club or place you follow.
    var name: String
    /// Their round photo; a person without one shows their initial.
    var avatar: URL?
    /// `avatar` is a logo: drawn whole on a white disc, as a Town card's host, not filled and cut by the
    /// circle as a face is (River Lakes' wordmark showed "iver La", Jesse 2026-11-19).
    var logo = false
    /// What, after the name: "vs Sartell." Working words; Jesse writes the final ones.
    var what: String
    var event: DailyEvent

    /// The event's start.
    var when: Date { event.starts }

    var photo: URL? { event.item.image.url }

    /// In grey after the words: when the event starts ("7 PM", or "Now").
    func time(now: Date) -> String { event.startTime(now: now) }

    /// `day`'s from what you follow: the Town feed's cards it lifts for a follow, an activity or a
    /// whole school (BP app school-activities 03), a person, a Place or a Group you're in (town-feed
    /// 37). None hides the section; DEBUG `-daily-samples` gets the samples.
    static func today(from cards: [FeedCardItem], day: String, now: Date) -> [DailyFollowing] {
        #if DEBUG
        if DailySamples.on { return samples(on: now) }
        #endif
        return cards.compactMap { card in
            guard let name = card.followed, card.eventDate == day, !card.cancelled,
                  let event = YouCalendar.event(from: card) else { return nil }
            let face = avatar(of: card, name: name)
            return DailyFollowing(id: "follow-\(card.id)", name: name, avatar: face.url, logo: face.logo,
                                  what: what(card, name: name), event: event)
        }
    }

    /// Your side's logo for a game (`Game.sides`, a co-op's too), else who puts it on, and whether it's a logo.
    static func avatar(of card: FeedCardItem, name: String) -> (url: URL?, logo: Bool) {
        if let logo = card.game?.sides(followed: name)?.mine.logo { return (logo, true) }
        if let picture = card.hostPicture { return (picture.url, picture.kind == .logo) }
        return (card.hostAvatar, false)
    }

    /// After the name: "vs Sartell." for a game (Jesse, 2026-10-26), else the Event's own title without the name
    /// it starts with (daily-tab 27; Jesse, 2026-11-17): "City Council · Work Session.". A City board's Event
    /// titled only its name is "Meeting."; anyone else's keeps its title.
    static func what(_ card: FeedCardItem, name: String) -> String {
        if let other = card.game?.sides(followed: name)?.other { return "vs \(other.short)." }
        let title = card.title.trimmingCharacters(in: .whitespaces)
        guard let range = title.range(of: name, options: [.anchored, .caseInsensitive]),
              title[range.upperBound...].first.map({ $0.isWhitespace || ":-–—|,.".contains($0) }) ?? true
        else { return "\(title)." }
        let rest = title[range.upperBound...].trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        guard let first = rest.first else { return card.hostName == Town.cityPage ? "Meeting." : "\(title)." }
        return "\(first.uppercased())\(rest.dropFirst())."
    }

    /// What the rows show (Jesse, 2026-10-06): today's events still on or to come, soonest first,
    /// leaving out any a section above already shows; `limit` rows at most.
    static func showing(_ items: [DailyFollowing], now: Date, without shown: [DailyEvent] = [],
                        limit: Int) -> [DailyFollowing] {
        let calendar = Town.gregorian
        let shownIDs = Set(shown.map(\.id))
        return Array(items.filter {
            $0.event.ends > now && calendar.isDate($0.event.starts, inSameDayAs: now) && !shownIDs.contains($0.event.id)
        }
        .sorted { $0.when < $1.when }.prefix(limit))
    }

    #if DEBUG
    /// INVENTED: a neighbour, a club and a place you might follow, with the bundled town photos, the
    /// round photo never the same as the small one, as in Instagram's rows, then three schools' games. Every
    /// name but the real places' and schools', every time and every word is made up. The cards under them are `DailyFollowingCard.samples`.
    static func samples(on date: Date) -> [DailyFollowing] {
        let calendar = Town.gregorian
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        func photo(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "jpg") }
        func game(_ id: String, _ name: String, logo: String, against: String, hour: Double) -> DailyFollowing {
            DailyFollowing(
                id: id, name: name,
                avatar: URL(string: "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/\(logo).webp"),
                logo: true, what: "vs \(against).",
                event: DailyEvent.sample(
                    id: "daily-\(id)", title: "\(name) vs \(against)", host: name, photo: "memorial-park",
                    place: "Memorial Park", starts: at(hour), ends: at(hour + 2), category: .sports,
                    description: "A home game."))
        }
        return [
            DailyFollowing(
                id: "follow-1", name: "Kay Lindqvist", avatar: nil, what: "is hosting a porch sale.",
                event: DailyEvent.sample(
                    id: "daily-f1", title: "Porch sale", host: "Kay Lindqvist", photo: "downtown",
                    place: "College Avenue", starts: at(9), ends: at(13), category: .other,
                    description: "Kids' bikes, books and a lot of kitchen things. Everything goes.")),
            DailyFollowing(
                id: "follow-2", name: "College of Saint Benedict", avatar: photo("saint-bens"),
                what: "has an open choir rehearsal.",
                event: DailyEvent.sample(
                    id: "daily-f2", title: "Open choir rehearsal", host: "College of Saint Benedict",
                    photo: "sacred-heart-chapel", place: "Saint Benedict's Monastery", starts: at(15), ends: at(16),
                    category: .musicArts, description: "Sit in on the choirs getting ready for Sunday.")),
            DailyFollowing(
                id: "follow-3", name: "St. Joseph Running Group", avatar: photo("klinefelter-park-trail"),
                what: "has a group run.",
                event: DailyEvent.sample(
                    id: "daily-f3", title: "Group run", host: "St. Joseph Running Group",
                    photo: "centennial-park", place: "Klinefelter Park", starts: at(17.5), ends: at(18.5),
                    category: .sports, description: "Three or five miles at an easy pace. Everyone welcome.")),
            // Three schools' saved logos, read from the network (`TownFixtures`' games do the same): River Lakes' wide
            // wordmark (ROCORI's girls' hockey co-op), ROCORI's square crest and Saint John's J, each to sit whole.
            game("follow-4", "ROCORI", logo: "river-lakes/logo-4f698b753d", against: "Detroit Lakes", hour: 19),
            game("follow-5", "ROCORI", logo: "rocori/logo-5904ca0046", against: "Sauk Rapids-Rice", hour: 19.5),
            game("follow-6", "Saint John's", logo: "saint-johns/logo-65d82ce9fc", against: "Concordia", hour: 20),
        ]
    }
    #endif
}

/// Under the rows (daily-tab 23): a post from you, a friend or someone you follow, or News from a place
/// you follow, each as the Town feed draws it. Jesse at Check-in 1 (2026-11-08): the rows stay, News
/// joins, 10 in the section with the rows first, on today's page under Best of only.
enum DailyFollowingCard: Identifiable {
    case post(TownPost)
    case news(TownNews)

    var id: String {
        switch self {
        case .post(let post): "post-\(post.id)"
        case .news(let news): "news-\(news.id)"
        }
    }

    /// Its post's or story's own id, as the Town feed's entry has it.
    var entryID: String {
        switch self {
        case .post(let post): post.id
        case .news(let news): news.id
        }
    }

    /// When it went up: a post's own time; News's, when Block Party found it.
    var when: Date {
        switch self {
        case .post(let post): post.posted
        case .news(let news): news.published ?? .distantPast
        }
    }

    /// Today's, from the Town feed's posts and the followed places' News; DEBUG `-daily-samples` gets
    /// the samples.
    static func today(posts: [TownPost], news: [TownNews], rows: Int, now: Date) -> [DailyFollowingCard] {
        #if DEBUG
        if DailySamples.on { return samples(now: now) }
        #endif
        return showing(posts: posts, news: news, rows: rows, limit: DailyRowMetric.limit)
    }

    /// What shows under `rows` rows: the posts the feed says are from who you follow (`TownPost.followed`)
    /// and the News of the places you follow, newest first, as many as `limit` leaves after the rows.
    static func showing(posts: [TownPost], news: [TownNews], rows: Int, limit: Int) -> [DailyFollowingCard] {
        let cards = posts.filter(\.followed).map(DailyFollowingCard.post) + news.map(DailyFollowingCard.news)
        return Array(cards.sorted { $0.when > $1.when }.prefix(max(limit - rows, 0)))
    }

    #if DEBUG
    /// The Town feed's two sample posts and two of its sample News, as from who you follow.
    static func samples(now: Date) -> [DailyFollowingCard] {
        let posts = TownFixtures.postSamples(now: now).compactMap(\.post).map { post in
            var post = post
            post.followed = true
            return post
        }
        let news = TownFixtures.newsSamples(now: now).prefix(2).compactMap { entry -> TownNews? in
            if case .news(let news) = entry.item { return news }
            return nil
        }
        return showing(posts: posts, news: news, rows: 0, limit: DailyRowMetric.limit)
    }
    #endif
}

/// News from the places you follow (`get_following_news`, daily-tab 23), kept across tab switches as
/// Event of the day is, so coming back shows what it had while it reads again; a failed read keeps it.
/// Read when the Block Party tab opens and on a new account.
@MainActor @Observable
final class FollowingNews {
    private(set) var items: [TownNews] = []
    /// Numbers each read, so one an account change overtook never lands.
    @ObservationIgnored private var latestRead = 0
    @ObservationIgnored private let read: () async throws -> [TownNews]
    /// Where each story's hearts go once read (inside-cards 22), so a heart shows right from the first frame.
    @ObservationIgnored private let actions: RealLifeActions?

    init(read: @escaping () async throws -> [TownNews], actions: RealLifeActions? = nil) {
        self.read = read
        self.actions = actions
    }

    /// The live read through `supabase`, the session's one client (`AppSession`); under DEBUG
    /// `-daily-samples` nothing, since the samples are the section's own.
    convenience init(supabase: Supabase, actions: RealLifeActions? = nil) {
        #if DEBUG
        if DailySamples.on {
            self.init(read: { [] })
            return
        }
        #endif
        self.init(read: { try await CommunityAPI(supabase).getFollowingNews() }, actions: actions)
    }

    func refresh() async {
        latestRead += 1
        let mine = latestRead
        do {
            let new = try await read()
            guard mine == latestRead else { return }
            actions?.read(news: new)
            // Read on every visit: the same stories leave the page alone (tab-lag).
            if items != new { items = new }
        } catch {
            guard mine == latestRead else { return }
            Log.network("FollowingNews: \(error)")
        }
    }

    /// A new account: the last one's stories go, and its own are read.
    func accountChanged() {
        latestRead += 1
        items = []
    }
}

/// The section: its label, one row per Event as Instagram's activity rows, then the cards.
struct FollowingSection: View {
    let items: [DailyFollowing]
    var cards: [DailyFollowingCard] = []
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // In the logo's face, as the rows above it are (Jesse at daily-tab 20's Check-in 2). The first
            // row's photo sits `titleToCards` under it, its own inset counted; with no rows, the first card.
            DailyRowTitle(title: "Following")
                .padding(.bottom, DailyRowMetric.titleToCards - (items.isEmpty ? 0 : DailyMetric.followingRowInset))
            ForEach(items) { item in
                FollowingRow(item: item, now: now)
            }
            // The Town feed's post and News cards, as Town draws them (daily-tab 23), `followingCardGap`
            // under the last row and apart. A lazy stack, as the Town feed's: in a plain one the post's photo,
            // which takes its height from its width, was squeezed to nothing and its height left blank at the
            // page's end (seen in the first after recording).
            if !cards.isEmpty {
                LazyVStack(spacing: DailyMetric.followingCardGap) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        Group {
                            switch card {
                            case .post(let post): FeedPostCard(post: post)
                            case .news(let news): TownNewsCard(news: news)
                            }
                        }
                        // The pictures of the two screens below come in before they scroll on (BP app tab-lag 03).
                        .onAppear { read(after: index) }
                    }
                }
                // The first cards ask once the column is measured.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    let first = width == 0
                    width = new
                    if first { read(after: -1) }
                }
                .padding(.top, items.isEmpty ? 0 : DailyMetric.followingCardGap - DailyMetric.followingRowInset)
            }
        }
        // A finished event's row, or a card you hid, closes up instead of vanishing.
        .animation(reduceMotion ? nil : Motion.smooth, value: items.map(\.id) + cards.map(\.id))
    }

    private func read(after index: Int) {
        FeedReadAhead.read(count: cards.count, after: index, width: width, scale: displayScale) {
            switch cards[$0] {
            case .post(let post): TownFeedItem.post(post).pictures(width: width)
            case .news(let news): TownFeedItem.news(news).pictures(width: width)
            }
        }
    }
}

/// Instagram's activity row: the round photo, the name in bold and what in plain, the
/// time in grey, and a small photo on the right. The whole row is the tap.
private struct FollowingRow: View {
    let item: DailyFollowing
    let now: Date

    var body: some View {
        NavigationLink(value: item.event.item) { face }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("\(item.name) \(item.what) \(item.event.startSpoken(now: now))")
    }

    private var face: some View {
        HStack(spacing: DailyMetric.followingGap) {
            if item.logo {
                LogoDisc(logo: item.avatar, initial: item.name.first.map { String($0).uppercased() } ?? "",
                         logoSide: DailyMetric.followingPhoto, letter: .sansSemibold(14), fits: true)
                    .frame(width: DailyMetric.followingPhoto, height: DailyMetric.followingPhoto)
                    .overlay(Circle().strokeBorder(Hue.hairline.onLightCanvas, lineWidth: 0.5))
            } else {
                Avatar(item.avatar, size: DailyMetric.followingPhoto, blank: .initial(item.name))
            }
            Text(words)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            // With no photo the words run to the edge, as Instagram's do.
            if let url = item.photo {
                Hue.fill
                    .frame(width: DailyMetric.followingPhoto, height: DailyMetric.followingPhoto)
                    .overlay { FeedCardURLPhoto(url: url, whole: item.event.item.whole ? 0 : nil) }
                    .clipShape(RoundedRectangle(cornerRadius: DailyMetric.followingPhotoRadius, style: .continuous))
            }
        }
        .padding(.horizontal, DailyMetric.side)
        .padding(.vertical, DailyMetric.followingRowInset)
        .contentShape(Rectangle())
    }

    /// "**The Local Blend** has live music. 7 PM"
    private var words: AttributedString {
        var name = AttributedString(item.name)
        name.font = .sansSemibold(15)
        var time = AttributedString(item.time(now: now))
        time.foregroundColor = Hue.inkSecondary
        return name + AttributedString(" \(item.what) ") + time
    }
}
