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
//  It also counts what the feed showed (ticket 20): a card at least half on screen for
//  1 second is one view, once per card per feed load. Views and opens wait in `views`
//  (`FeedViews`) for the server.
//
//  What you took out (Not interested, Mute, Report; ticket 21) is `hides` (`FeedHides`):
//  the list leaves out whatever it says is hidden.
//
//  A game's card carries its newest score from Live games (`LiveGames`, BP app codebase-health-2 08),
//  which the feed holds its games with while it's on screen.
//

import Foundation

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

    /// Cards half on screen now, and since when (reset when the feed comes back).
    @ObservationIgnored private var onScreen: [String: Date] = [:]
    /// Cards already counted in this feed load: a view is once per card per load.
    @ObservationIgnored private var viewed: Set<String> = []
    /// Views and opens on their way to the server.
    let views: FeedViews
    /// Not interested, Mute, Report and their Undo, and the Muted list.
    let hides: FeedHides

    private let read: () async throws -> [TownFeedEntry]
    private let kept: () -> [TownFeedEntry]?
    /// The same list unpacked off the main thread, for the first read at launch: unpacked on it,
    /// it froze the launch's ball for 90 ms (Jesse's phone, 2026-11-07). nil: `kept`.
    private let keptLater: (() async -> [TownFeedEntry]?)?
    /// Told each Event's Going and Heart from every list the feed takes, in the same
    /// turn, so a card and its Event page never disagree for a frame.
    private let actions: RealLifeActions?
    /// Every game's newest score: the feed holds its games there while it's on screen, and its cards
    /// carry what it says (codebase-health-2 08). nil in tests that don't need it.
    private let live: LiveGames?
    /// Past the ranked list (town-feed 23): the later Events, each round's order (given the places this
    /// phone opened, which go last, and the list's ids, the only repeats), and those opened places.
    private let readLater: () async throws -> [TownFeedEntry]
    private let readMore: (Int, [String], [String]) async throws -> [TownMoreRow]
    private let opened: () -> [String]
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
        self.live = live
        self.readLater = readLater
        self.readMore = readMore
        self.opened = opened
        hides = FeedHides(choose: choose, readMuted: readMuted, deletePost: deletePost)
        views = FeedViews(send: send)
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
                guard !hides.isHidden(card) else { return nil }
                guard let live, let game = live.game(card), game != card.game else { return entry }
                var card = card
                card.game = game
                return TownFeedEntry(card: card, leavesAt: entry.leavesAt)
            case .news(let news): return hides.isHidden(id: news.id, host: news.place) ? nil : entry
            case .post(let post): return hides.isHidden(id: post.id, host: "") ? nil : entry
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
        let top = DailyEvent.showing(picks.filter { !hides.isHidden($0.item) && (!postersGone.contains($0.id) || $0.item.isJoined) },
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
            .compactMap(\.card).filter { !hides.isHidden($0) }.map(TownFeedItem.event)
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

    /// The neighbours' posts still on, in the database's order, for the Block Party tab's Following
    /// (daily-tab 23).
    var posts: [TownPost] { shown.compactMap(\.post) }

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
        actions?.read(news: list.compactMap(\.news))
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
        let sending = Task { await views.send(at: now, always: true) }
        let giveUp = Task {
            try? await Task.sleep(for: FeedViews.sendWait)
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
                actions?.read(news: kept.compactMap(\.news))
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
            actions?.read(news: new.compactMap(\.news))
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
        views.viewed(id, news: here?.isNews == true)
    }

    /// A new account: the last one's waiting views and hidden cards are not this one's.
    func accountChanged() {
        // The read out now was the old account's: it never lands, and nothing shares it.
        latestRead &+= 1
        readOut = nil
        clearMore()
        views.reset()
        viewed = []
        onScreen = [:]
        keepPosters([])
        postersShown = []
        postersGone = []
        hides.reset()
    }

    // MARK: Not interested and Mute (ticket 21)

    /// Unmute from the Muted list (`FeedHides.unmute`): the host's Events come back with a fresh read.
    func unmute(_ host: MutedHost, at now: Date = Date()) async {
        if await hides.unmute(host) { await reload(at: now) }
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
        var card = FeedCardItem(row.event)
        card.why = row.reason.flatMap { FeedCardMenu.line(reason: $0, name: row.reasonName) }
        card.followed = row.reason == "follow" ? row.reasonName : nil
        card.likeCount = row.heartCount
        card.isLiked = row.hearted
        card.groupID = row.groupID
        card.inGroup = row.inGroup
        return card
    }
}
