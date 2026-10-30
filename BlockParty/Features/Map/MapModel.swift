//
//  MapModel.swift
//  Block Party — the map's view-model: today's events at their real spots, kept live.
//
//  Today's events are the Town feed's (`get_town_feed`, the one read iOS and Android
//  share), so the map shows what the Town feed shows, with the same hearts and Going,
//  and the card opens the same Event page. Their spots come from `club_events.lat,lng`
//  (BP app references/map-reset). Owns a single RealtimeClient on club_events: a change
//  that touches today re-reads (debounced), so a new happening gets its bubble and a
//  deleted one goes, with no refresh. Tears down on disappear, re-reads and resubscribes
//  on foreground, and rolls over at midnight.
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class MapModel: ObservableObject {

    /// Whether today's events have been read. The map always draws; this only says
    /// whether its one pill offers a retry.
    enum LoadState: Equatable { case loading, loaded, offline, error }

    @Published private(set) var today = TodayPlaces.none
    @Published private(set) var state: LoadState = .loading
    /// A 1-minute wall-clock heartbeat, so a bubble that ends drops off and "Nothing else
    /// today" comes on with no data change.
    @Published private(set) var clockTick = 0

    private var auth: AuthStore?
    private var api: CommunityAPI? { auth.map(CommunityAPI.init(auth:)) }

    private var realtime: RealtimeClient?
    private var currentDate = Town.day(.now)

    private var resyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var started = false
    /// Monotonic token so an older in-flight load can't clobber a newer one's result:
    /// load() is fired from start/foreground/retry/resync/midnight and its reads suspend.
    private var loadGeneration = 0

    // MARK: Lifecycle (driven by SJMapView.onAppear/onDisappear + scenePhase)

    func start(auth: AuthStore) {
        if self.auth == nil { self.auth = auth }
        guard !started else { return }
        started = true
        currentDate = Town.day(.now)
        Task { await load(initial: true) }
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
        Task { await load(initial: false) }
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

    func retry() { Task { await load(initial: true) } }

    // MARK: Data

    private func load(initial: Bool) async {
        guard let api else { return }
        loadGeneration += 1
        let gen = loadGeneration
        if initial && today.events.isEmpty { state = .loading }
        do {
            let day = Town.day(.now)
            let events = try await api.getTownFeed().compactMap { line -> FeedCardItem? in
                guard case .event(let row) = line else { return nil }
                let card = TownFeed.card(row)
                return card.eventDate == day ? card : nil
            }
            let spots = try await api.eventSpots(events.map(\.id))
            guard gen == loadGeneration else { return }   // a newer load superseded us
            today = TodayPlaces(events: events, spots: spots)
            state = .loaded
            // Warm the bubbles' pictures so each pops in with its photo, not empty glass.
            POILogoCache.shared.prefetch(today.bubbles(now: TodayBubbleClock.now()).compactMap { $0.picture?.url })
        } catch {
            guard gen == loadGeneration else { return }
            // Stale but useful beats a pill: keep what's on the map.
            if today.events.isEmpty { state = error is URLError ? .offline : .error }
        }
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
            await self?.load(initial: false)
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
            await self.load(initial: false)
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
