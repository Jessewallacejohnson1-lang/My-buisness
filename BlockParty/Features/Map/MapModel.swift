//
//  MapModel.swift
//  Block Party — the map's view-model: today's events at their real spots, kept live.
//
//  Today's events are the Town feed's own cards (`TownFeed`, already read when the map
//  opens from the Town bar), so the map shows what the Town feed shows, with the same
//  hearts and Going, hides and mutes, and adds no second feed read: `get_town_feed` can
//  take 8 s for a new account (2026-10-30). Each event's spot comes from
//  `club_events.lat,lng` (BP app references/map-reset), read once per event. Owns a
//  single RealtimeClient on club_events: a change that touches today asks the Town feed
//  to read again (debounced), so a new happening gets its bubble and a deleted one goes,
//  with no refresh. Tears down on disappear, re-reads and resubscribes on foreground, and
//  rolls over at midnight.
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

    private var auth: AuthStore?
    private var api: CommunityAPI? { auth.map(CommunityAPI.init(auth:)) }

    private weak var feed: TownFeed?
    /// Each of today's events' spot, once read; `asked` holds every id read, found or not.
    private var spots: [String: CLLocationCoordinate2D] = [:]
    private var asked: Set<String> = []

    private var realtime: RealtimeClient?
    private var currentDate = Town.day(.now)

    private var resyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var started = false

    // MARK: Lifecycle (driven by SJMapView.onAppear/onDisappear + scenePhase)

    func start(auth: AuthStore, feed: TownFeed) {
        if self.auth == nil { self.auth = auth }
        self.feed = feed
        guard !started else { return }
        started = true
        currentDate = Town.day(.now)
        show(feed.cards)
        if feed.entries == nil { readAgain() }
        subscribe()
        scheduleMidnightRollover()
        startClock()
    }

    func stop() {
        started = false
        realtime?.stop()
        realtime = nil
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

    /// App returned to foreground: the socket was dropped on background and the date may
    /// have rolled over while away. Re-read and re-subscribe.
    func onForeground() {
        guard started else { return }
        currentDate = Town.day(.now)
        readAgain()
        subscribe()                     // start() on the existing client is a no-op if alive
        scheduleMidnightRollover()
        startClock()
    }

    /// App backgrounded: drop the socket to spare the battery; foreground rebuilds it.
    func onBackground() {
        realtime?.stop()
        midnightTask?.cancel(); midnightTask = nil
        clockTask?.cancel(); clockTask = nil
    }

    // MARK: Data

    /// The Town feed's cards, as they change: today's, at the spots read for them. A new
    /// event's spot is read once; a failed read is asked again at the next change.
    func show(_ cards: [FeedCardItem]) {
        let day = Town.day(.now)
        let events = cards.filter { $0.eventDate == day }
        today = TodayPlaces(events: events, spots: spots)
        let new = events.map(\.id).filter { !asked.contains($0) }
        guard !new.isEmpty, let api else { return }
        asked.formUnion(new)
        Task { @MainActor [weak self] in
            do {
                let found = try await api.eventSpots(new)
                guard let self else { return }
                self.spots.merge(found) { $1 }
                self.today = TodayPlaces(events: self.today.events, spots: self.spots)
                // Warm the bubbles' pictures so each pops in with its photo, not empty glass.
                POILogoCache.shared.prefetch(self.today.bubbles(now: TodayBubbleClock.now()).compactMap { $0.picture?.url })
            } catch {
                self?.asked.subtract(new)
            }
        }
    }

    /// The Town feed reads again, and every spot of today's with it (the morning job may
    /// have set one since).
    private func readAgain() {
        asked.removeAll()
        Task { await feed?.refresh() }
    }

    // MARK: Realtime

    private func subscribe() {
        if realtime == nil {
            let client = RealtimeClient(table: "club_events") { [weak self] in
                await self?.freshToken() ?? nil
            }
            client.onChange = { [weak self] change in self?.handle(change) }
            realtime = client
        }
        realtime?.start()
    }

    /// A guaranteed-fresh access token for the socket join / keepalive. @MainActor so the
    /// nonisolated token-provider closure hops here to touch auth safely.
    private func freshToken() async -> String? {
        guard let auth else { return nil }
        return try? await auth.validAccessToken()
    }

    private func handle(_ change: RealtimeClient.Change) {
        // A game's score coming in (game-card 03) moves nothing on the map: no refetch for it.
        if change.kind == .update, let new = change.new, let old = change.old,
           new.withoutScores == old.withoutScores,
           new.finalScore != old.finalScore || new.liveScore != old.liveScore || new.scoringPlays != old.scoringPlays { return }
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
        guard let seconds = Self.secondsUntilNextMidnight() else { return }
        midnightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.started else { return }
            self.currentDate = Town.day(.now)
            self.readAgain()
            self.scheduleMidnightRollover()          // arm the next day
        }
    }

    private static func secondsUntilNextMidnight() -> Double? {
        // 00:00:01 tomorrow in the Town — a hair past midnight so Town.day has flipped.
        guard let next = Town.gregorian.nextDate(after: Date(),
                                      matching: DateComponents(hour: 0, minute: 0, second: 1),
                                      matchingPolicy: .nextTime) else { return nil }
        return max(1, next.timeIntervalSince(Date()))
    }
}
