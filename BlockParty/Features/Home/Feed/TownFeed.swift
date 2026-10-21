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

import Foundation

/// One event in the Town feed: its card, and when it leaves.
struct TownFeedEntry: Identifiable {
    let card: FeedCardItem
    let leavesAt: Date
    var id: String { card.id }
}

/// What the feed showed (a view) or what was opened, for `feed_actions` (ticket 20).
struct FeedAction: Equatable {
    enum Kind: String { case view, open }
    let itemID: String
    let kind: Kind
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

    /// How far down the screen is scrolled. Written by the screen as it scrolls; not
    /// observed, so scrolling re-renders nothing but the step on or off the top.
    @ObservationIgnored var scrollY: CGFloat = 0 {
        didSet {
            guard atTop == holding else { return }
            if !atTop { heldClock = clock }
            holding = !atTop
        }
    }
    /// Scrolled down from the top: nothing leaves the list under the finger. A card whose
    /// time is up stays where it is until the top, a pull or a fresh order (Jesse,
    /// 2026-10-21: at 7 PM a finished game above dropped out and the feed jumped).
    private(set) var holding = false
    /// The clock the list goes by while holding: where it was when the screen left the top.
    @ObservationIgnored private var heldClock = Date()
    /// At the top is the only place a fresh order may replace the list.
    var atTop: Bool { scrollY <= 1 }
    /// Where the screen was when the feed went away, so coming back within 30 minutes
    /// lands there. Kept apart from `scrollY`, which a rebuilt screen resets to 0
    /// before it can scroll back.
    @ObservationIgnored private(set) var returnY: CGFloat = 0

    /// Away this long, coming back brings a fresh order (ticket 11).
    static let awayLimit: TimeInterval = 30 * 60

    /// When the feed went off screen; a launch counts as long away.
    @ObservationIgnored private var awaySince: Date? = .distantPast
    @ObservationIgnored private var freshDue = false
    @ObservationIgnored private var keptChecked = false
    /// Numbers each read, so only the newest one's answer is kept.
    @ObservationIgnored private var latestRead = 0
    /// When the feed last came on screen, for the speed log.
    @ObservationIgnored private var cameBackAt: Date?

    /// A card at least half on screen this long is one view (ticket 20).
    static let viewAfter: TimeInterval = 1
    /// Views and opens go up at most this often, and when the app leaves the screen.
    static let sendEvery: TimeInterval = 30

    /// Cards half on screen now, and since when (reset when the feed comes back).
    @ObservationIgnored private var onScreen: [String: Date] = [:]
    /// Cards already counted in this feed load: a view is once per card per load.
    @ObservationIgnored private var viewed: Set<String> = []
    /// Views and opens not yet sent; a batch that fails for want of a network or an
    /// account goes back in front.
    @ObservationIgnored private(set) var unsent: [FeedAction] = []
    @ObservationIgnored private var lastSent: Date = .distantPast

    private let read: () async throws -> [TownFeedEntry]
    private let kept: () -> [TownFeedEntry]?
    /// Told each Event's Going and Heart from every list the feed takes, in the same
    /// turn, so a card and its Event page never disagree for a frame.
    private let actions: RealLifeActions?
    /// Where views and opens go: the live table, or nowhere (tests, sample modes).
    private let sender: ([FeedAction]) async throws -> Void

    /// `kept` is the list the last session left on the phone, asked for once, at the
    /// first read, so it is built with the account that read sees.
    init(read: @escaping () async throws -> [TownFeedEntry],
         kept: @escaping () -> [TownFeedEntry]? = { nil },
         actions: RealLifeActions? = nil,
         send: @escaping ([FeedAction]) async throws -> Void = { _ in }) {
        self.read = read
        self.kept = kept
        self.actions = actions
        self.sender = send
    }

    /// The live feed, or under DEBUG `-town-samples` the sample events, so design
    /// work has photos under the chrome and never reads the live database;
    /// `-town-offline` keeps the samples on screen with every read failing.
    convenience init(actions: RealLifeActions? = nil) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-town-offline") {
            self.init(read: { throw URLError(.notConnectedToInternet) },
                      kept: { DailyFixtures.townEntries() }, actions: actions)
            return
        }
        if arguments.contains("-town-samples") {
            self.init(read: { DailyFixtures.townEntries() }, actions: actions)
            return
        }
        #endif
        // A test run never records views for whatever account the simulator kept. A plain
        // closure, not a choice between one and `Self.sendLive`: Xcode 26.6's compiler, which
        // GitHub's check builds with, gave up on that (red from 2026-10-13).
        let testRun = AuthStore.isTestRun
        self.init(read: Self.live, kept: Self.keptOnDisk, actions: actions,
                  send: { batch in if !testRun { try await Self.sendLive(batch) } })
    }

    /// The cards still on, in the database's order. The admin's Score names each card's
    /// place as it is on screen, so it holds after a read that kept the order.
    var cards: [FeedCardItem] {
        let on = (entries ?? []).filter { $0.leavesAt > (holding ? heldClock : clock) }.map(\.card)
        return on.enumerated().map { place, card in
            var card = card
            card.score?.spot = place + 1
            card.score?.of = on.count
            return card
        }
    }

    /// When the next card leaves: the feed reads again then.
    var nextLeave: Date? {
        entries?.lazy.map(\.leavesAt).filter { $0 > self.clock }.min()
    }

    /// The feed went off screen: another tab, the map, an Event page, or the app left the
    /// foreground. Cards on screen long enough count first; timing stops while away.
    /// `viewGone`: the screen itself went (a tab switch rebuilds it), so its cards will
    /// never report going off; they are forgotten, and a rebuilt screen's report again.
    func left(at now: Date = Date(), viewGone: Bool = false) {
        guard awaySince == nil else {
            if viewGone { onScreen = [:] }
            return
        }
        for (id, since) in onScreen where now.timeIntervalSince(since) >= Self.viewAfter { counted(id) }
        if viewGone { onScreen = [:] }
        awaySince = now
        returnY = scrollY
    }

    /// The feed is back on screen. After 30 minutes away the next read may bring a
    /// fresh order, from the top; sooner, it lands where it was.
    func cameBack(at now: Date = Date()) {
        guard let since = awaySince else { return }
        awaySince = nil
        // Nobody had a finger on the list while away: what left goes now, and the hold
        // starts again with the next scroll.
        holding = false
        // Cards still half on screen start their second over.
        for id in onScreen.keys { onScreen[id] = now }
        cameBackAt = now
        if now.timeIntervalSince(since) >= Self.awayLimit {
            freshDue = true
            returnY = 0
        }
    }

    /// Reads behind the list on screen (coming back, a card leaving).
    func refresh(at now: Date = Date()) async {
        await readAgain(at: now, freshOrder: false)
    }

    /// Pull to refresh, retry, a new account: the new order, whatever is on screen.
    func reload(at now: Date = Date()) async {
        await readAgain(at: now, freshOrder: true)
    }

    /// A failed read keeps the list already showing, minus what has left; with no
    /// list, the feed shows its retry.
    ///
    /// The clock moves only once the read is done, and nothing is awaited after the
    /// list changes: `nextLeave` reads both, and the feed's leave timer is keyed on
    /// it, so changing either first cancelled the very read the timer had started.
    private func readAgain(at now: Date, freshOrder: Bool) async {
        if entries == nil, !keptChecked {
            keptChecked = true
            if let kept = kept(), kept.contains(where: { $0.leavesAt > now }) {
                actions?.read(kept.map(\.card))
                entries = kept
                clock = now
            }
        }
        if entries == nil { failed = false }
        // Reads overlap (the feed opening, the foreground, a new account): a slow one
        // that lands last must not overwrite a newer one's answer.
        latestRead &+= 1
        let thisRead = latestRead
        do {
            let new = try await read()
            guard thisRead == latestRead else { return }
            if let cameBackAt {
                let ms = Int(Date().timeIntervalSince(cameBackAt) * 1000)
                Log.ui("TownFeed: read in \(ms) ms after the feed opened, \(entries == nil ? "nothing" : "a kept list") on screen meanwhile")
                self.cameBackAt = nil
            }
            actions?.read(new.map(\.card))
            if entries == nil || freshOrder || (freshDue && atTop) {
                entries = new
                viewed = []  // a new feed load: each card may count once more
            } else {
                let byID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                // Scrolled down, a card the read no longer has keeps its place until the top.
                entries = entries?.compactMap { byID[$0.id] ?? (holding ? $0 : nil) }
            }
            freshDue = false
            failed = false
        } catch {
            // Left mid-read (the tab went away): not a failure; the read runs again
            // when the feed comes back.
            guard !Task.isCancelled, thisRead == latestRead else { return }
            Log.network("TownFeed: \(error)")
            failed = true
        }
        clock = now
    }

    // MARK: Views and opens (ticket 20)

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
            if Self.triesAgain(error) { unsent = batch + unsent }
        }
    }

    /// A new account: the last one's waiting views are not this one's.
    func accountChanged() {
        unsent = []
        viewed = []
    }

    nonisolated static func triesAgain(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let status = (error as? SupabaseError)?.status else { return false }
        return status == 401 || status >= 500
    }

    /// Once per card per feed load, and only for a card still in the list.
    private func counted(_ id: String) {
        guard !viewed.contains(id), cards.contains(where: { $0.id == id }) else { return }
        viewed.insert(id)
        unsent.append(FeedAction(itemID: id, kind: .view))
    }

    private static func sendLive(_ batch: [FeedAction]) async throws {
        try await CommunityAPI(auth: AuthStore.shared).recordFeedActions(batch)
    }

    private static func live() async throws -> [TownFeedEntry] {
        try await CommunityAPI(auth: AuthStore.shared).getTownFeed().map(entry)
    }

    /// The list the last live read left on disk, or nil when there is none or it no
    /// longer decodes.
    private static func keptOnDisk() -> [TownFeedEntry]? {
        guard let data = TownFeedCache.load(),
              let rows = try? CommunityAPI.townFeedRows(from: data) else { return nil }
        return rows.map(entry)
    }

    /// A row as the card a club's event gets. Whether its Going and Heart may be shown
    /// or changed is `RealLifeActions.canAct`'s, so a card read before the quiet account
    /// arrived offers Join and the heart once it has.
    static func entry(_ row: TownFeedRow) -> TownFeedEntry {
        var card = FeedCardItem(row.event, recurrence: row.recurrence)
        card.why = row.reason.flatMap { FeedCardMenu.line(reason: $0, name: row.reasonName) }
        card.score = row.score
        card.likeCount = row.heartCount
        card.isLiked = row.hearted
        card.isSaved = row.saved
        card.friendsGoing = row.friendsGoing
        card.groupID = row.groupID
        card.inGroup = row.inGroup
        return TownFeedEntry(card: card, leavesAt: row.leavesAt)
    }
}
