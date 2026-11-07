//
//  TownFeed.swift
//  Block Party — the Town feed: what's in it and in what order.
//
//  The database works both out (`get_town_feed`, the one function iOS and Android call;
//  BP app docs/plans/town-feed, ticket 05), so this never filters or re-sorts by its
//  own rules. It keeps the last good list across tab switches, failed refreshes and
//  relaunches, lets an event go once its leaves-at passes, and reads again then.
//
//  When the order may change is ticket 11's: a fresh order on pull to refresh, or on
//  coming back after 30 minutes or more away (a launch counts), and then only while
//  the screen is still at the top, so nothing moves under a finger. Any other read
//  keeps the order on screen: cards update in place, ones that went drop out, and new
//  ones wait for the next fresh order.
//
//  It also records what the feed showed and what was opened (ticket 20): a card at least
//  half on screen for 1 second is one view, once per card per feed load, and opening its
//  Event page is an open. They go up in one batch at most every 30 seconds and when the
//  app leaves the screen; the server turns views into popularity per view.
//
//  Not interested and Mute (ticket 21) take a card out at once and go to the server straight
//  away. The card folds into a "Hidden · Undo" line for 5 seconds, then goes; Undo brings it
//  back and takes the choice back. The ids and host names hidden this session stay out of
//  every list, so a read that raced the write, or a kept list, can't bring a card back.
//
//  A game's card carries its newest score from Live games (`LiveGames`, BP app codebase-health-2 08),
//  which the feed holds its games with while it's on screen.
//

import Foundation
import UIKit

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

    var isNews: Bool {
        if case .news = item { return true }
        return false
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
/// reason; Undo on its Hidden line is undoNotInterested, which lifts the hide and keeps the report.
enum FeedChoice: Equatable {
    case notInterested(String), undoNotInterested(String), mute(String), unmute(String)
    case report(String, ReportReason)
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

@MainActor @Observable
final class TownFeed {
    /// nil until there is a list to show, which the feed shows as its skeleton.
    private(set) var entries: [TownFeedEntry]?
    /// The last read failed. With no list the feed shows its retry; with one, it keeps
    /// the list and says it's offline.
    private(set) var failed = false
    /// When the list was last read or checked. Events that have left by then are hidden.
    private(set) var clock = Date()

    /// How far down the screen is scrolled (`scrolled(to:at:)`). Not observed, so scrolling
    /// re-renders nothing but the step on or off the top.
    @ObservationIgnored private(set) var scrollY: CGFloat = 0

    /// The screen scrolled to `y` at `now`: leaving the top holds the list and the poster there.
    func scrolled(to y: CGFloat, at now: Date = Date()) {
        scrollY = y
        guard atTop == holding else { return }
        if !atTop { heldClock = clock; heldAt = now }
        holding = !atTop
    }
    /// When the screen left the top: the Event of the day poster holds at what it showed then, as
    /// the list under it holds (event-card 03), and moves on back at the top.
    @ObservationIgnored private(set) var heldAt = Date()
    /// Scrolled down from the top: nothing leaves the list under the finger. A card whose
    /// time is up stays where it is until the top, a pull or a fresh order (Jesse,
    /// 2026-10-21: at 7 PM a finished game above dropped out and the feed jumped).
    private(set) var holding = false
    /// The clock the list goes by while holding: where it was when the screen left the top.
    @ObservationIgnored private var heldClock = Date()
    /// At the top is the only place a fresh order may replace the list.
    var atTop: Bool { scrollY <= 1 }
    /// A finger on the list: a fresh order waits, or it could land under a press (town-feed 41).
    @ObservationIgnored var fingerDown = false
    /// Where the screen was when the feed went away, so coming back within 10 minutes
    /// lands there. Kept apart from `scrollY`, which a rebuilt screen resets to 0
    /// before it can scroll back.
    @ObservationIgnored private(set) var returnY: CGFloat = 0
    /// The card that topped the screen when the feed went away: where a restart lands, since rows
    /// not yet measured would put `returnY` somewhere else.
    @ObservationIgnored private var returnCard: String?
    /// A restart brought this list back (`resume`), and the screen hasn't landed on it yet.
    @ObservationIgnored private var resumed = false

    /// Away this long, coming back brings a fresh order (ticket 11; Jesse, 2026-11-05, from 30).
    static let awayLimit: TimeInterval = 10 * 60

    /// When the feed went off screen; a launch counts as long away.
    @ObservationIgnored private var awaySince: Date? = .distantPast
    @ObservationIgnored private var freshDue = false
    @ObservationIgnored private var keptChecked = false
    /// Numbers each read, so only the newest one's answer is kept.
    @ObservationIgnored private var latestRead = 0
    /// The read out now and when it left. `refresh` shares it: an open's triggers overlap (the feed
    /// opening, the foreground, the leave timer), and one read costs the server a second or more
    /// (BP app town-feed 48).
    @ObservationIgnored private var readOut: (task: Task<Void, Never>, since: Date)?
    /// A read out this long may be dying (the phone slept mid-read), so a refresh asks again.
    static let joinFor: TimeInterval = 10
    /// When the feed last came on screen, for the speed log.
    @ObservationIgnored private var cameBackAt: Date?

    /// A card at least half on screen this long is one view (ticket 20).
    static let viewAfter: TimeInterval = 1
    /// Views and opens go up at most this often, and when the app leaves the screen.
    nonisolated static let sendEvery: TimeInterval = 30
    /// How long a pull waits for what you just saw to go up, before it reads anyway.
    nonisolated static let sendWait: Duration = .seconds(1)

    /// Cards half on screen now, and since when (reset when the feed comes back).
    @ObservationIgnored private var onScreen: [String: Date] = [:]
    /// Cards already counted in this feed load: a view is once per card per load.
    @ObservationIgnored private var viewed: Set<String> = []
    /// Views and opens not yet sent; a batch that fails for want of a network or an
    /// account goes back in front.
    @ObservationIgnored private(set) var unsent: [FeedAction] = []
    @ObservationIgnored private var lastSent: Date = .distantPast

    /// Events and News said Not interested to and host names muted this session (ticket 21).
    private(set) var hiddenIDs: Set<String> = []
    private(set) var mutedNames: Set<String> = []
    /// The card showing "Hidden · Undo" in its place, for 5 seconds.
    private(set) var undo: FeedHide?
    /// How long the Undo line stays.
    static let undoFor: Duration = .seconds(5)
    /// The host each Mute this session muted, by name, so its Undo can unmute it.
    @ObservationIgnored private var muteKeys: [String: String] = [:]
    /// The last choice on its way: Undo waits for it, so the take-back never lands first.
    @ObservationIgnored private var sending: Task<String?, Error>?
    /// Ends the Undo line after 5 seconds, wherever the line has scrolled to.
    @ObservationIgnored private var undoTimer: Task<Void, Never>?
    /// The Muted list as the last read gave it; nil until read.
    private(set) var muted: [MutedHost]?
    private(set) var mutedFailed = false
    /// Unmutes that didn't go through, by host: the row comes back and shakes.
    private(set) var unmuteFailures: [String: Int] = [:]

    private let read: () async throws -> [TownFeedEntry]
    private let kept: () -> [TownFeedEntry]?
    /// The same list unpacked off the main thread, for the first read at launch: unpacked on it,
    /// it froze the launch's ball for 90 ms (Jesse's phone, 2026-11-07). nil: `kept`.
    private let keptLater: (() async -> [TownFeedEntry]?)?
    /// Told each Event's Going and Heart from every list the feed takes, in the same
    /// turn, so a card and its Event page never disagree for a frame.
    private let actions: RealLifeActions?
    /// Where views and opens go: the live table, or nowhere (tests, sample modes).
    private let sender: ([FeedAction]) async throws -> Void
    /// Where Not interested, Mute and their undoing go; a Mute answers with its host.
    private let choose: (FeedChoice) async throws -> String?
    private let readMuted: () async throws -> [MutedHost]
    /// Every game's newest score: the feed holds its games there while it's on screen, and its cards
    /// carry what it says (codebase-health-2 08). nil in tests that don't need it.
    private let live: LiveGames?
    /// Past the ranked list (town-feed 23): the later Events, each round's order (given the places this
    /// phone opened, which go last, and the list's ids, the only repeats), and those opened places.
    private let readLater: () async throws -> [TownFeedEntry]
    private let readMore: (Int, [String], [String]) async throws -> [TownMoreRow]
    private let opened: () -> [String]
    /// Where your own post's Delete goes (town-feed 29).
    private let deletePost: (TownPost) async throws -> Void
    /// Keeps which Events of the day have had their one showing (town-feed 41), on the phone for the day.
    private let keepPosters: ([String]) -> Void
    /// Those shown so far, and those that have left the top: they go only when a fresh order lands, so
    /// nothing changes under the finger.
    @ObservationIgnored private var postersShown: Set<String>
    private var postersGone: Set<String>
    /// The pick on top now: its view is its showing.
    @ObservationIgnored private var posterOnTop: String?

    /// `kept` is the list the last session left on the phone, asked for once, at the
    /// first read, so it is built with the account that read sees.
    init(read: @escaping () async throws -> [TownFeedEntry],
         kept: @escaping () -> [TownFeedEntry]? = { nil },
         keptLater: (() async -> [TownFeedEntry]?)? = nil,
         actions: RealLifeActions? = nil,
         send: @escaping ([FeedAction]) async throws -> Void = { _ in },
         choose: @escaping (FeedChoice) async throws -> String? = { _ in nil },
         readMuted: @escaping () async throws -> [MutedHost] = { [] },
         live: LiveGames? = nil,
         readLater: @escaping () async throws -> [TownFeedEntry] = { [] },
         readMore: @escaping (Int, [String], [String]) async throws -> [TownMoreRow] = { _, _, _ in [] },
         opened: @escaping () -> [String] = { [] },
         deletePost: @escaping (TownPost) async throws -> Void = { _ in },
         postersShown: [String] = [],
         keepPosters: @escaping ([String]) -> Void = { _ in }) {
        self.keepPosters = keepPosters
        self.postersShown = Set(postersShown)
        postersGone = Set(postersShown)
        self.read = read
        self.kept = kept
        self.keptLater = keptLater
        self.actions = actions
        self.sender = send
        self.choose = choose
        self.readMuted = readMuted
        self.live = live
        self.readLater = readLater
        self.readMore = readMore
        self.opened = opened
        self.deletePost = deletePost
    }

    /// The live feed, or under DEBUG `-town-samples` the sample events, so design
    /// work has photos under the chrome and never reads the live database;
    /// `-town-offline` keeps the samples on screen with every read failing. Live, every read
    /// and write goes through `supabase`, the session's one client (`AppSession`).
    convenience init(supabase: Supabase, actions: RealLifeActions? = nil, live: LiveGames? = nil) {
        #if DEBUG
        switch LaunchFlags.backend {
        case .offline:
            self.init(read: { throw URLError(.notConnectedToInternet) },
                      kept: { TownFixtures.townEntries() }, actions: actions, live: live)
            return
        case .samples:
            // Mute and the Muted list kept in memory, so the Eyes pass shows both (ticket 21).
            let mutes = SampleMutes()
            self.init(read: { TownFixtures.townEntries() }, actions: actions,
                      choose: mutes.choose, readMuted: { mutes.list }, live: live)
            return
        case .live:
            break
        }
        #endif
        // A test run never records views for whatever account the simulator kept. A plain
        // closure, not a choice between one and the live send: Xcode 26.6's compiler, which
        // GitHub's check builds with, gave up on that (red from 2026-10-13).
        let testRun = AuthStore.isTestRun
        let api = CommunityAPI(supabase)
        self.init(read: { try await api.getTownFeed().map(TownFeed.entry) }, kept: Self.keptOnDisk,
                  keptLater: { await Self.keptLines()?.map(TownFeed.entry) }, actions: actions,
                  send: { batch in if !testRun { try await api.recordFeedActions(batch) } },
                  choose: { try await api.feedChoice($0) },
                  readMuted: { try await api.mutedHosts() },
                  live: live,
                  readLater: { try await api.getTownFeedLater().map(TownFeed.entry) },
                  readMore: { try await api.getTownMore(round: $0, opened: $1, shown: $2) },
                  opened: { OpenedPlaces.ids },
                  deletePost: { try await api.deletePost($0.id, photo: $0.photo != nil) },
                  postersShown: TownFeedCache.postersShown(),
                  keepPosters: { TownFeedCache.save(postersShown: $0) })
    }

    /// What's still on, events and news, in the database's order: not an event you hid, nor
    /// anything from a host you muted (ticket 21). A game's card carries its newest score.
    var shown: [TownFeedEntry] {
        (entries ?? []).compactMap { entry in
            guard entry.leavesAt > (holding ? heldClock : clock) else { return nil }
            switch entry.item {
            case .event(let card):
                guard !isHidden(card) else { return nil }
                guard let live, let game = live.game(card), game != card.game else { return entry }
                var card = card
                card.game = game
                return TownFeedEntry(card: card, leavesAt: entry.leavesAt)
            case .news(let news): return isHidden(id: news.id, host: news.place) ? nil : entry
            case .post(let post): return isHidden(id: post.id, host: "") ? nil : entry
            }
        }
    }

    /// The clock the Event of the day poster goes by: `now` at the top; scrolled down, when the
    /// feed left the top, so it holds as the list under it does (event-card 03).
    func posterClock(at now: Date) -> Date {
        DailyClock.now(holding ? heldAt : now)
    }

    /// The Town feed's column at `now`: your Event of the day on top, the first of `picks` still
    /// on or to come that hasn't had its one showing, unless you're Going (town-feed 41), never one you
    /// hid or whose host you muted (ticket 21); then the list.
    /// Past the ranked list, its places as Search holds them (`places`, by `places.id`), town-feed 23.
    func column(eventOfTheDay picks: [DailyEvent], now: Date,
                places: (String) -> SearchItem? = { _ in nil }) -> [TownFeedItem] {
        let top = DailyEvent.showing(picks.filter { !isHidden($0.item) && (!postersGone.contains($0.id) || $0.item.isJoined) },
                                     now: posterClock(at: now), limit: 1).first
        posterOnTop = top?.id
        let ranked = shown
        return TownFeedItem.town(ranked, eventOfTheDay: top) + past(ranked, places: places)
    }

    // MARK: After the best (town-feed 23)

    /// The 20 soonest Events past their show-from day, read once the ranked list's end comes near.
    private(set) var later: [TownFeedEntry] = []
    /// Each round past them, in `get_town_more`'s order: places to try and repeats.
    private(set) var rounds: [[TownMoreRow]] = []
    /// A round on its way: the column ends in a card's skeleton.
    private(set) var loadingMore = false
    /// Numbers the rounds' reads, so one that a fresh order or a new account overtook never lands.
    @ObservationIgnored private var moreRead = 0

    /// What shows past the ranked list: "You're all caught up", at once, so offline or between rounds the
    /// list still ends on it and it asks again when it comes back on screen; then the later Events not
    /// already above and not hidden, then each round's places Search can open and repeats of what the
    /// list above still shows, so a hidden or muted one never comes back. Nothing past an empty list,
    /// which keeps its own quiet screen.
    func past(_ ranked: [TownFeedEntry], places: (String) -> SearchItem?) -> [TownFeedItem] {
        guard !ranked.isEmpty else { return [] }
        let above = Dictionary(ranked.map { ($0.id, $0.item) }, uniquingKeysWith: { first, _ in first })
        let at = holding ? heldClock : clock
        var items: [TownFeedItem] = [.caughtUp]
        items += later.filter { $0.leavesAt > at && above[$0.id] == nil }
            .compactMap(\.card).filter { !isHidden($0) }.map(TownFeedItem.event)
        for (round, rows) in rounds.enumerated() {
            for row in rows {
                switch row.kind {
                case .place: if let place = places(row.id) { items.append(.place(place, round: round)) }
                case .again: if let item = above[row.id] { items.append(.again(item, round: round)) }
                case .unknown: break
                }
            }
        }
        return items
    }

    /// Near the end of the column: the next round. The first brings the later Events with its places.
    /// One at a time; a failed one is asked again when the end comes near again.
    func loadMore() async {
        guard !loadingMore, let entries, !entries.isEmpty else { return }
        loadingMore = true
        let mine = moreRead, round = rounds.count
        do {
            let newLater = round == 0 ? try await readLater() : later
            // Repeats past the list are Events and posts: News you've seen stays gone (town-feed 41).
            let rows = try await readMore(round, opened(), shown.filter { !$0.isNews }.map(\.id))
            guard mine == moreRead else { return }
            if round == 0 {
                actions?.read(newLater.compactMap(\.card))
                later = newLater
            }
            rounds.append(rows)
        } catch {
            guard mine == moreRead else { return }
            Log.network("TownFeed: round \(round) past the list: \(error)")
        }
        loadingMore = false
    }

    /// A fresh order or another account: what was past the old list goes, and a round still on its
    /// way is dropped when it lands.
    private func clearMore() {
        moreRead &+= 1
        later = []
        rounds = []
        loadingMore = false
    }

    /// The events still on, in the database's order.
    var cards: [FeedCardItem] { shown.compactMap(\.card) }

    /// When the next card leaves: the feed reads again then.
    var nextLeave: Date? {
        entries?.lazy.map(\.leavesAt).filter { $0 > self.clock }.min()
    }

    /// The feed went off screen: another tab, the map, an Event page, or the app left the
    /// foreground. Cards on screen long enough count first (a first card you never scrolled past too:
    /// Jesse, 2026-11-05); timing stops while away.
    /// `viewGone`: the screen itself went (a tab switch rebuilds it), so its cards will
    /// never report going off; they are forgotten, and a rebuilt screen's report again.
    func left(at now: Date = Date(), viewGone: Bool = false) {
        guard awaySince == nil else {
            if viewGone { onScreen = [:] }
            return
        }
        countOnScreen(at: now)
        // Not when a tab's slide-out has already reported every card off (swift-traps).
        if let top = topOnScreen { returnCard = top }
        if viewGone { onScreen = [:] }
        awaySince = now
        returnY = scrollY
        holdGames(at: now)
    }

    /// The first card half on screen, in the list's order.
    private var topOnScreen: String? {
        shown.first { onScreen[$0.id] != nil }?.id
    }

    /// What `LeftOff` keeps of the feed, whichever of the shell and the feed hears of leaving first.
    var spot: (feed: [String], top: String?, y: CGFloat, poster: String?) {
        (shown.map(\.id), topOnScreen ?? returnCard, awaySince == nil ? scrollY : returnY, posterOnTop)
    }

    /// iOS shut the app down and you came back inside `awayLimit`: the list you left, in its order,
    /// minus what has left or you hid since, with what shows at launch here rather than a read's
    /// worth later. What reads behind it treats it as any short time away: no fresh order.
    func resume(_ left: LeftOff, at now: Date = Date()) {
        awaySince = left.at
        returnY = left.feedY
        returnCard = left.top
        resumed = true
        if let poster = left.poster { postersGone.remove(poster) }
        keptChecked = true
        guard let kept = kept() else { return }
        let byID = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let list = left.feed.compactMap { byID[$0] }
        guard list.contains(where: { $0.leavesAt > now }) else { return }
        actions?.read(list.compactMap(\.card))
        actions?.read(posts: list.compactMap(\.post))
        entries = list
        clock = now
    }

    /// Whether this screen is the first after a restart: it draws as it was, with no rise-in. Once,
    /// so a tab switch later rises as ever.
    func takeResumed() -> Bool {
        defer { resumed = false }
        return resumed
    }

    /// The row `returnCard` is, as the column names it; nil once it's gone or past the kept list.
    var returnRow: String? {
        TownFeedItem.town(shown, eventOfTheDay: nil).first { $0.seenID == returnCard }?.id
    }

    /// The feed is back on screen. After 10 minutes away the next read may bring a
    /// fresh order, from the top; sooner, it lands where it was.
    func cameBack(at now: Date = Date()) {
        guard let since = awaySince else { return }
        awaySince = nil
        // Cards still half on screen start their second over.
        for id in onScreen.keys { onScreen[id] = now }
        cameBackAt = now
        if now.timeIntervalSince(since) >= Self.awayLimit {
            freshDue = true
            returnY = 0
        }
        holdGames(at: now)
    }

    /// Reads behind the list on screen (coming back, a card leaving).
    func refresh(at now: Date = Date()) async {
        if let readOut, now.timeIntervalSince(readOut.since) < Self.joinFor {
            await readOut.task.value
            // That read left earlier, and this caller may be the leave timer: a card whose time is
            // up still goes, though no read carried this moment.
            clock = max(clock, now)
            return
        }
        await readAgain(at: now, freshOrder: false)
    }

    /// The finger's off a list a fresh order was waiting on.
    func fingerLifted(at now: Date = Date()) async {
        guard freshDue, atTop else { return }
        await refresh(at: now)
    }

    /// Retry, a new account: the new order, whatever is on screen.
    func reload(at now: Date = Date()) async {
        await readAgain(at: now, freshOrder: true)
    }

    /// Pull to refresh: what you just saw goes up first, so the new order knows it, without holding
    /// the read up on a bad network.
    func pulled(at now: Date = Date()) async {
        countOnScreen(at: now)
        let sending = Task { await send(at: now, always: true) }
        let giveUp = Task {
            try? await Task.sleep(for: Self.sendWait)
            sending.cancel()
        }
        await sending.value
        giveUp.cancel()
        await reload(at: now)
    }

    /// A failed read keeps the list already showing, minus what has left; with no
    /// list, the feed shows its retry.
    ///
    /// The clock moves only once the read is done, and nothing is awaited after the
    /// list changes: `nextLeave` reads both, and the feed's leave timer is keyed on
    /// it, so changing either first cancelled the very read the timer had started.
    private func readAgain(at now: Date, freshOrder: Bool) async {
        if entries == nil { failed = false }
        // Reads overlap (the feed opening, the foreground, a new account): a slow one
        // that lands last must not overwrite a newer one's answer.
        latestRead &+= 1
        let thisRead = latestRead
        // Its own task, not the caller's: a view going away must not end a read others share.
        let task = Task { await land(thisRead, at: now, freshOrder: freshOrder) }
        readOut = (task, now)
        // The kept list shows while the read is out. It's looked for after the read is set up, so a
        // caller arriving while it unpacks joins this read rather than starting a second one.
        if entries == nil, !keptChecked {
            keptChecked = true
            let list = if let keptLater { await keptLater() } else { kept() }
            // A read may have landed while it was unpacked: then that read's list stands.
            if entries == nil, let kept = list, kept.contains(where: { $0.leavesAt > now }) {
                actions?.read(kept.compactMap(\.card))
                actions?.read(posts: kept.compactMap(\.post))
                entries = kept
                clock = now
            }
        }
        await task.value
    }

    private func land(_ thisRead: Int, at now: Date, freshOrder: Bool) async {
        do {
            let new = try await read()
            guard thisRead == latestRead else { return }
            if let cameBackAt {
                let ms = Int(Date().timeIntervalSince(cameBackAt) * 1000)
                Log.ui("TownFeed: read in \(ms) ms after the feed opened, \(entries == nil ? "nothing" : "a kept list") on screen meanwhile")
                self.cameBackAt = nil
            }
            actions?.read(new.compactMap(\.card))
            actions?.read(posts: new.compactMap(\.post))
            if entries == nil || freshOrder || (freshDue && atTop && !fingerDown) {
                entries = new
                viewed = []  // a new feed load: each card may count once more
                clearMore()
                postersGone = postersShown
            } else {
                let byID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                // Scrolled down, a card the read no longer has (called off, say) keeps its place,
                // marked to leave at the top with the finished ones.
                entries = entries?.compactMap {
                    byID[$0.id] ?? (holding ? TownFeedEntry(item: $0.item, leavesAt: min($0.leavesAt, now)) : nil)
                }
            }
            // A finger on the list holds the fresh order until it lifts (`fingerLifted`).
            freshDue = freshDue && atTop && fingerDown
            failed = false
            holdGames(at: now)
        } catch {
            guard thisRead == latestRead else { return }
            Log.network("TownFeed: \(error)")
            failed = true
        }
        clock = now
        readOut = nil
    }

    // MARK: Live scores (codebase-health-2 08)

    /// The feed's games to Live games while the feed is on screen, so it listens while one is played;
    /// none once it's gone. An Event page holds its own.
    private func holdGames(at now: Date) {
        let games = awaySince == nil ? (entries ?? []).compactMap(\.card).filter { $0.game != nil } : []
        live?.hold("town", games, at: now)
    }

    // MARK: Views and opens (ticket 20)

    /// Cards on screen long enough count now, as they would going off.
    private func countOnScreen(at now: Date) {
        for (id, since) in onScreen where now.timeIntervalSince(since) >= Self.viewAfter { counted(id) }
    }

    /// A card crossed half on screen, either way (`onScrollVisibilityChange`). Off after a
    /// second or more on screen, with the feed showing, is one view.
    func cardOnScreen(_ id: String, _ on: Bool, at now: Date = Date()) {
        if on {
            if onScreen[id] == nil { onScreen[id] = now }
        } else if let since = onScreen.removeValue(forKey: id), awaySince == nil,
                  now.timeIntervalSince(since) >= Self.viewAfter {
            counted(id)
        }
    }

    /// An Event page opened from the Town feed.
    func opened(_ id: String) {
        unsent.append(FeedAction(itemID: id, kind: .open))
    }

    /// Sends what is waiting, at most every 30 seconds, or now when the app leaves the
    /// screen. A batch that found no network, no account or a server down goes back in
    /// front of the next; one the server refuses (a bad row) is dropped, or it would
    /// fail every batch after it.
    func send(at now: Date = Date(), always: Bool = false) async {
        guard !unsent.isEmpty, always || now.timeIntervalSince(lastSent) >= Self.sendEvery else { return }
        let batch = unsent
        unsent = []
        lastSent = now
        do {
            try await sender(batch)
        } catch {
            Log.network("TownFeed: \(batch.count) views and opens not sent: \(error)")
            if SupabaseHTTP.noAnswer(error) || Task.isCancelled { unsent = batch + unsent }
        }
    }

    /// A new account: the last one's waiting views and hidden cards are not this one's.
    func accountChanged() {
        // The read out now was the old account's: it never lands, and nothing shares it.
        latestRead &+= 1
        readOut = nil
        clearMore()
        unsent = []
        viewed = []
        onScreen = [:]
        keepPosters([])
        postersShown = []
        postersGone = []
        hiddenIDs = []
        reportedIDs = []
        mutedNames = []
        muteKeys = [:]
        undoTimer?.cancel()
        undo = nil
        muted = nil
    }

    // MARK: Not interested and Mute (ticket 21)

    /// Out of the feed: said Not interested to, or its host muted. The card showing Undo stays
    /// in, drawn as its Undo line.
    func isHidden(_ card: FeedCardItem) -> Bool { isHidden(id: card.id, host: card.hostName) }

    /// An Event's card or a News post (news-menu), by its id and its host's name.
    private func isHidden(id: String, host: String) -> Bool {
        guard undo?.id != id else { return false }
        return hiddenIDs.contains(id) || (!host.isEmpty && mutedNames.contains(host))
    }

    /// Report a card (ticket 22), from its sheet, which waits for the answer to say thanks or shake.
    func report(_ card: FeedCardItem, _ reason: ReportReason) async throws {
        try await report(id: card.id, reason)
    }

    /// An Event's or a neighbour's post's report (town-feed 29), by its id.
    func report(id: String, _ reason: ReportReason) async throws {
        _ = try await choose(.report(id, reason))
        reportedIDs.insert(id)
    }

    /// Cards reported from this phone this session: their sheet has no Report row.
    private(set) var reportedIDs: Set<String> = []

    /// A reported card, once its sheet has closed: out, with the same Undo line as Not interested.
    /// The report already went; Undo lifts only the hide.
    func hideReported(_ card: FeedCardItem) {
        hideReported(id: card.id, host: card.hostName)
    }

    func hideReported(id: String, host: String) {
        hiddenIDs.insert(id)
        showUndo(FeedHide(id: id, hostName: host, mute: false))
    }

    /// Your own post, deleted from its ••• (town-feed 29): out at once, with no Undo; one the server
    /// didn't take comes back.
    func delete(_ post: TownPost) async {
        hiddenIDs.insert(post.id)
        do {
            try await deletePost(post)
        } catch {
            Log.network("TownFeed: post not deleted: \(error)")
            hiddenIDs.remove(post.id)
            Haptics.error()
        }
    }

    private func showUndo(_ hide: FeedHide) {
        undo = hide
        undoTimer?.cancel()
        // With VoiceOver on, the line waits for Undo or the next choice: 5 seconds is too short to
        // find it by swiping.
        if !UIAccessibility.isVoiceOverRunning {
            undoTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.undoFor)
                guard !Task.isCancelled else { return }
                self?.undoEnded(hide.id)
            }
        }
    }

    /// Not interested (`mute` false) or Mute on an Event's card or a News post (news-menu), by its
    /// id and its host's name: out at once, then to the server. One that doesn't go through comes
    /// back. A newer one ends the last one's Undo.
    func hide(id: String, host hostName: String, mute: Bool) async {
        if mute { mutedNames.insert(hostName) } else { hiddenIDs.insert(id) }
        showUndo(FeedHide(id: id, hostName: hostName, mute: mute))
        let choose = self.choose
        let send = Task { try await choose(mute ? .mute(id) : .notInterested(id)) }
        sending = send
        do {
            let host = try await send.value
            if mute, let host { muteKeys[hostName] = host }
            muted = nil
        } catch {
            Log.network("TownFeed: \(mute ? "Mute" : "Not interested") not sent: \(error)")
            if mute { mutedNames.remove(hostName) } else { hiddenIDs.remove(id) }
            if undo?.id == id { undo = nil }
            Haptics.error()
        }
    }

    /// Undo on the line: the card comes back, and the choice is taken back on the server.
    func undoHide() async {
        guard let hide = undo else { return }
        undo = nil
        undoTimer?.cancel()
        let earlier = sending
        if hide.mute { mutedNames.remove(hide.hostName) } else { hiddenIDs.remove(hide.id) }
        // The choice lands before it is taken back (a slow network sent both at once).
        let answer = (try? await earlier?.value) ?? nil
        if hide.mute {
            // The Mute's own answer, when its `hide` hasn't kept it yet.
            guard let host = muteKeys.removeValue(forKey: hide.hostName) ?? answer else { return }
            _ = try? await choose(.unmute(host))
            muted = nil
        } else {
            _ = try? await choose(.undoNotInterested(hide.id))
        }
    }

    /// The Undo line's 5 seconds are up: the card goes.
    func undoEnded(_ id: String) {
        if undo?.id == id { undo = nil }
    }

    /// The Muted list, read when it opens.
    func refreshMuted() async {
        do {
            muted = try await readMuted()
            mutedFailed = false
        } catch {
            Log.network("TownFeed: Muted list: \(error)")
            mutedFailed = muted == nil
        }
    }

    /// Unmute from the Muted list: off the list at once; the host's Events come back with a fresh
    /// read. One that doesn't go through comes back and shakes.
    func unmute(_ host: MutedHost, at now: Date = Date()) async {
        guard let at = muted?.firstIndex(of: host) else { return }
        muted?.remove(at: at)
        do {
            _ = try await choose(.unmute(host.host))
            mutedNames.remove(host.name)
            await reload(at: now)
        } catch {
            Log.network("TownFeed: Unmute not sent: \(error)")
            let count = muted?.count ?? 0
            muted?.insert(host, at: min(at, count))
            unmuteFailures[host.host, default: 0] += 1
            Haptics.error()
        }
    }

    /// Once per card per feed load, and only for a card still in the list or on top as the poster.
    private func counted(_ id: String) {
        guard !viewed.contains(id) else { return }
        if id == posterOnTop {
            postersShown.insert(id)
            keepPosters(postersShown.sorted())
        }
        let here = shown.first { $0.id == id } ?? later.first { $0.id == id }
        guard here != nil || id == posterOnTop else { return }
        viewed.insert(id)
        unsent.append(FeedAction(itemID: id, kind: here?.isNews == true ? .news : .view))
    }

    /// The list the last live read left on disk, or nil when there is none or it no
    /// longer decodes.
    private static func keptOnDisk() -> [TownFeedEntry]? {
        guard let data = TownFeedCache.load(),
              let lines = try? CommunityAPI.townFeedLines(from: data) else { return nil }
        return lines.map(entry)
    }

    /// The lines `keptOnDisk` reads, read and unpacked off the main thread (`keptLater`).
    @concurrent
    private nonisolated static func keptLines() async -> [TownFeedLine]? {
        TownFeedCache.load().flatMap { try? CommunityAPI.townFeedLines(from: $0) }
    }

    /// A line of the feed as its entry: an event's card, or news as it came (ticket 35).
    static func entry(_ line: TownFeedLine) -> TownFeedEntry {
        switch line {
        case .event(let row): entry(row)
        case .news(let news): TownFeedEntry(item: .news(news), leavesAt: news.leavesAt)
        case .post(let post): TownFeedEntry(item: .post(post), leavesAt: post.leavesAt)
        }
    }

    /// A row as the card a club's event gets. Whether its Going and Heart may be shown
    /// or changed is `RealLifeActions.canAct`'s, so a card read before the quiet account
    /// arrived offers Join and the heart once it has.
    static func entry(_ row: TownFeedRow) -> TownFeedEntry {
        TownFeedEntry(card: card(row), leavesAt: row.leavesAt)
    }

    static func card(_ row: TownFeedRow) -> FeedCardItem {
        var card = FeedCardItem(row.event, recurrence: row.recurrence)
        card.why = row.reason.flatMap { FeedCardMenu.line(reason: $0, name: row.reasonName) }
        card.followed = row.reason == "follow" ? row.reasonName : nil
        card.likeCount = row.heartCount
        card.isLiked = row.hearted
        card.isSaved = row.saved
        card.groupID = row.groupID
        card.inGroup = row.inGroup
        return card
    }
}

#if DEBUG
/// `-town-samples`' Muted list: a Mute keeps the host by name, an Unmute drops it.
@MainActor
private final class SampleMutes {
    var list = [MutedHost(host: "sample-library", name: "St. Joe Public Library")]
    /// Each sample's host by its id, news by its place (news-menu).
    private let names = Dictionary(TownFixtures.townEntries().map { entry in
        switch entry.item {
        case .event(let card): (card.id, card.hostName)
        case .news(let news): (news.id, news.place)
        case .post(let post): (post.id, post.poster.name)
        }
    }, uniquingKeysWith: { first, _ in first })

    func choose(_ choice: FeedChoice) async throws -> String? {
        switch choice {
        case .mute(let id):
            let name = names[id] ?? id
            list.insert(MutedHost(host: name, name: name), at: 0)
            return name
        case .unmute(let host):
            list.removeAll { $0.host == host }
        case .notInterested, .undoNotInterested, .report:
            break
        }
        return nil
    }
}
#endif
