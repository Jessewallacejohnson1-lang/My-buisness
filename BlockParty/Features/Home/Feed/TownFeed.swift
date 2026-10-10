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

import Foundation

/// One event in the Town feed: its card, and when it leaves.
struct TownFeedEntry: Identifiable {
    let card: FeedCardItem
    let leavesAt: Date
    var id: String { card.id }
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

    /// The card at the top of the screen, so coming back within 30 minutes lands on
    /// it. The screen writes it as it scrolls; not observed, so scrolling re-renders
    /// nothing.
    @ObservationIgnored var topCardID: String?
    /// Whether the screen is scrolled to the top, the only place a fresh order may
    /// replace the list. Written by the screen.
    @ObservationIgnored var atTop = true

    /// Away this long, coming back brings a fresh order (ticket 11).
    static let awayLimit: TimeInterval = 30 * 60

    /// When the feed went off screen; a launch counts as long away.
    @ObservationIgnored private var awaySince: Date? = .distantPast
    @ObservationIgnored private var freshDue = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var keptChecked = false
    /// When the feed last came on screen, for the speed log.
    @ObservationIgnored private var cameBackAt: Date?

    private let read: () async throws -> [TownFeedEntry]
    private let kept: () -> [TownFeedEntry]?

    /// `kept` is the list the last session left on the phone, asked for once, at the
    /// first read, so it is built with the account that read sees.
    init(read: @escaping () async throws -> [TownFeedEntry],
         kept: @escaping () -> [TownFeedEntry]? = { nil }) {
        self.read = read
        self.kept = kept
    }

    /// The live feed, or under DEBUG `-town-samples` the sample events, so design
    /// work has photos under the chrome and never reads the live database;
    /// `-town-offline` keeps the samples on screen with every read failing.
    convenience init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-town-offline") {
            self.init(read: { throw URLError(.notConnectedToInternet) },
                      kept: { DailyFixtures.townEntries() })
            return
        }
        if arguments.contains("-town-samples") {
            self.init { DailyFixtures.townEntries() }
            return
        }
        #endif
        self.init(read: Self.live, kept: Self.keptOnDisk)
    }

    /// The cards still on, in the database's order.
    var cards: [FeedCardItem] {
        (entries ?? []).filter { $0.leavesAt > clock }.map(\.card)
    }

    /// When the next card leaves: the feed reads again then.
    var nextLeave: Date? {
        entries?.lazy.map(\.leavesAt).filter { $0 > self.clock }.min()
    }

    /// The feed went off screen: another tab, the map, or the app left the foreground.
    func left(at now: Date = Date()) {
        if awaySince == nil { awaySince = now }
    }

    /// The feed is back on screen. After 30 minutes away the next read may bring a
    /// fresh order, from the top; sooner, it lands on the card it left.
    func cameBack(at now: Date = Date()) {
        guard let since = awaySince else { return }
        awaySince = nil
        cameBackAt = now
        if now.timeIntervalSince(since) >= Self.awayLimit {
            freshDue = true
            topCardID = nil
        }
    }

    /// Reads behind the list on screen (coming back, a card leaving). A second call
    /// while one is reading does nothing.
    func refresh(at now: Date = Date()) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
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
                entries = kept
                clock = now
            }
        }
        if entries == nil { failed = false }
        do {
            let new = try await read()
            if let cameBackAt {
                let ms = Int(Date().timeIntervalSince(cameBackAt) * 1000)
                Log.ui("TownFeed: read in \(ms) ms after the feed opened, \(entries == nil ? "nothing" : "a kept list") on screen meanwhile")
                self.cameBackAt = nil
            }
            if entries == nil || freshOrder || (freshDue && atTop) {
                entries = new
            } else {
                let byID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                entries = entries?.compactMap { byID[$0.id] }
            }
            freshDue = false
            failed = false
        } catch {
            // Left mid-read (the tab went away): not a failure; the read runs again
            // when the feed comes back.
            guard !Task.isCancelled else { return }
            Log.network("TownFeed: \(error)")
            failed = true
        }
        clock = now
    }

    private static func live() async throws -> [TownFeedEntry] {
        let auth = AuthStore.shared
        return try await CommunityAPI(auth: auth).getTownFeed().map {
            entry($0, signedIn: auth.isSignedIn)
        }
    }

    /// The list the last live read left on disk, or nil when there is none or it no
    /// longer decodes.
    private static func keptOnDisk() -> [TownFeedEntry]? {
        let auth = AuthStore.shared
        guard let data = TownFeedCache.load(for: auth.userId),
              let rows = try? CommunityAPI.townFeedRows(from: data) else { return nil }
        return rows.map { entry($0, signedIn: auth.isSignedIn) }
    }

    /// A row as the card a club's event gets. Signed out, an RSVP can be neither read
    /// nor written, so the card offers no Join (`FeedCardItem.canJoin`).
    static func entry(_ row: TownFeedRow, signedIn: Bool) -> TownFeedEntry {
        var card = FeedCardItem(row.event, recurrence: row.recurrence)
        card.canJoin = signedIn
        return TownFeedEntry(card: card, leavesAt: row.leavesAt)
    }
}
