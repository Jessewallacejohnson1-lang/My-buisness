//
//  MapModel.swift
//  Block Party — the map's view-model: today's events at their real spots, kept live.
//
//  Today's events are the Town feed's own cards (`TownFeed`, already read when the map
//  opens from the Town bar), so the map shows what the Town feed shows, with the same
//  hearts and Going, hides and mutes, and adds no second feed read: `get_town_feed` can
//  take 8 s for a new account (2026-10-30). Each event's spot comes from
//  `club_events.lat,lng` (BP app references/map-reset), read once per event. Follows the
//  app's one `club_events` connection (`LiveGames`, BP app codebase-health-2 08): a change
//  that touches today asks the Town feed to read again (debounced), so a new happening gets
//  its bubble and a deleted one goes, with no refresh. Lets go on disappear, re-reads on
//  foreground, and rolls over at midnight.
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class MapModel: ObservableObject {

    @Published private(set) var today = TodayPlaces.none
    /// A 1-minute wall-clock heartbeat, so a bubble that ends drops off and "Nothing else
    /// today" comes on with no data change.
    @Published private(set) var clockTick = 0
    /// The last read of today's spots failed: the map's pill offers to try again.
    @Published private(set) var spotsFailed = false

    /// Where each event is: the account's `CommunityAPI.eventSpots`, from `start`, unless a test
    /// passes its own.
    private var readSpots: (([String]) async throws -> [String: CLLocationCoordinate2D])?
    /// The time, for today and midnight. A test passes its own.
    private let now: () -> Date

    private weak var feed: TownFeed?
    /// The app's one `club_events` connection, which the map follows while it's open.
    private weak var live: LiveGames?
    /// Each of today's events' spot, once read; `asked` holds every id read, found or not.
    private var spots: [String: CLLocationCoordinate2D] = [:]
    private var asked: Set<String> = []

    private var currentDate: String

    private var resyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var started = false

    init(readSpots: (([String]) async throws -> [String: CLLocationCoordinate2D])? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.readSpots = readSpots
        self.now = now
        currentDate = Town.day(now())
    }

    // MARK: Lifecycle (driven by SJMapView.onAppear/onDisappear + scenePhase)

    func start(auth: AuthStore, feed: TownFeed, live: LiveGames) {
        if readSpots == nil { readSpots = { try await CommunityAPI(auth: auth).eventSpots($0) } }
        self.feed = feed
        self.live = live
        guard !started else { return }
        started = true
        currentDate = Town.day(now())
        show(feed.cards)
        if feed.entries == nil { readAgain() }
        // Every change on the app's one `club_events` connection (`LiveGames`).
        live.follow { [weak self] change in self?.handle(change) }
        scheduleMidnightRollover()
        startClock()
    }

    func stop() {
        started = false
        live?.follow(nil)
        resyncTask?.cancel(); resyncTask = nil
        midnightTask?.cancel(); midnightTask = nil
        clockTask?.cancel(); clockTask = nil
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, self.started else { break }
                self.clockTick &+= 1
            }
        }
    }

    /// App returned to foreground: the connection was dropped on background (`LiveGames.away`)
    /// and the date may have rolled over while away. Re-read.
    func onForeground() {
        guard started else { return }
        currentDate = Town.day(now())
        readAgain()
        scheduleMidnightRollover()
        startClock()
    }

    /// App backgrounded: the timers stop; `LiveGames` drops the connection.
    func onBackground() {
        midnightTask?.cancel(); midnightTask = nil
        clockTask?.cancel(); clockTask = nil
    }

    // MARK: Data

    /// The Town feed's cards, as they change: today's, at the spots read for them. A new
    /// event's spot is read once; a failed read is asked again at the next change.
    func show(_ cards: [FeedCardItem]) {
        let day = Town.day(now())
        let events = cards.filter { $0.eventDate == day }
        today = TodayPlaces(events: events, spots: spots)
        let new = events.map(\.id).filter { !asked.contains($0) }
        guard !new.isEmpty, let readSpots else { return }
        asked.formUnion(new)
        Task { @MainActor [weak self] in
            do {
                let found = try await readSpots(new)
                guard let self else { return }
                self.spotsFailed = false
                self.spots.merge(found) { $1 }
                self.today = TodayPlaces(events: self.today.events, spots: self.spots)
                // Warm the bubbles' pictures so each pops in with its photo, not empty glass.
                POILogoCache.shared.prefetch(self.today.bubbles(now: TodayBubbleClock.now()).compactMap { $0.picture?.url })
            } catch {
                self?.asked.subtract(new)
                self?.spotsFailed = true
            }
        }
    }

    /// The Town feed reads again, and every spot of today's with it (the morning job may
    /// have set one since), even when the feed's cards come back the same.
    func readAgain() {
        asked.removeAll()
        Task { @MainActor [weak self] in
            await self?.feed?.refresh()
            if let self, let feed = self.feed { self.show(feed.cards) }
        }
    }

    // MARK: Realtime

    private func handle(_ change: RealtimeClient.Change) {
        // A live score coming in (game-card 03) moves nothing on the map: no refetch for it. A
        // final does: the game is over, so its bubble goes.
        if change.kind == .update, let new = change.new, let old = change.old,
           new.withoutScores == old.withoutScores, new.finalScore == old.finalScore,
           new.liveScore != old.liveScore || new.scoringPlays != old.scoringPlays { return }
        // Today's map: a row dated today, or one it shows (an edit that moves it off today, a delete).
        guard ClubEventRelevance.matters(change, shownIDs: Set(today.events.map(\.id)),
                                         days: currentDate...currentDate) else { return }
        scheduleResync()
    }

    /// Debounce a burst of changes (e.g. a weekly-repeat insert loop) into one fetch.
    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.readAgain()
        }
    }

    // MARK: Midnight rollover

    private func scheduleMidnightRollover() {
        midnightTask?.cancel()
        guard let seconds = Self.secondsUntilNextMidnight(after: now()) else { return }
        midnightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.started else { return }
            self.currentDate = Town.day(self.now())
            self.readAgain()
            self.scheduleMidnightRollover()          // arm the next day
        }
    }

    private static func secondsUntilNextMidnight(after now: Date) -> Double? {
        // 00:00:01 tomorrow in the Town — a hair past midnight so Town.day has flipped.
        guard let next = Town.gregorian.nextDate(after: now,
                                      matching: DateComponents(hour: 0, minute: 0, second: 1),
                                      matchingPolicy: .nextTime) else { return nil }
        return max(1, next.timeIntervalSince(now))
    }
}
