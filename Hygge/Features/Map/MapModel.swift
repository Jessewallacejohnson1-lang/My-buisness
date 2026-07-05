//
//  MapModel.swift
//  Hygge — the map tab's view-model: today's events + the live Realtime pipeline.
//
//  Owns a single RealtimeClient subscribed to club_events. A change that touches
//  *today* re-syncs the event list (debounced), so a new happening lights its pin
//  and an ended / deleted one goes quiet — with no manual refresh. Handles the
//  full lifecycle the map depends on: teardown on disappear, reconnect + re-sync
//  on foreground, and the midnight rollover (a "today" event stops being today).
//

import Foundation
import Combine

@MainActor
final class MapModel: ObservableObject {

    /// What the header status line reflects. The base map + curated pins always
    /// render; this is only about *today's happenings* data.
    enum LoadState: Equatable { case loading, loaded, empty, error, offline }

    @Published private(set) var todayEvents: [TimelineEvent] = []
    @Published private(set) var state: LoadState = .loading

    private var auth: AuthStore?
    private var api: CommunityAPI? { auth.map(CommunityAPI.init(auth:)) }

    private var realtime: RealtimeClient?
    private var currentDate = DateHelpers.localDate()

    private var resyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var started = false
    /// Monotonic token so an older in-flight load can't clobber a newer one's
    /// result — load() is fired from start/foreground/retry/resync/midnight and
    /// its fetch suspends, so responses can arrive out of launch order.
    private var loadGeneration = 0

    // MARK: Lifecycle (driven by SJMapView.onAppear/onDisappear + scenePhase)

    func start(auth: AuthStore) {
        if self.auth == nil { self.auth = auth }
        guard !started else { return }
        started = true
        currentDate = DateHelpers.localDate()
        Task { await load(initial: true) }
        subscribe()
        scheduleMidnightRollover()
    }

    func stop() {
        started = false
        realtime?.stop()
        realtime = nil
        resyncTask?.cancel(); resyncTask = nil
        midnightTask?.cancel(); midnightTask = nil
    }

    /// App returned to foreground: the socket was dropped on background and the
    /// date may have rolled over while away. Re-filter, re-sync, re-subscribe.
    func onForeground() {
        guard started else { return }
        rolloverIfNeeded()
        Task { await load(initial: false) }
        subscribe()                     // start() on the existing client is a no-op if alive
        scheduleMidnightRollover()
    }

    /// App backgrounded: drop the socket to spare the battery; foreground rebuilds it.
    func onBackground() {
        realtime?.stop()
        midnightTask?.cancel(); midnightTask = nil
    }

    // MARK: Data

    private func load(initial: Bool) async {
        guard let api else { return }
        loadGeneration += 1
        let gen = loadGeneration
        if initial && todayEvents.isEmpty { state = .loading }
        do {
            let events = try await api.getTodayEvents()
            guard gen == loadGeneration else { return }   // a newer load superseded us
            todayEvents = events
            state = events.isEmpty ? .empty : .loaded
        } catch {
            guard gen == loadGeneration else { return }
            // A URLError means the network is down; keep any cached events visible.
            let offline = error is URLError
            if !todayEvents.isEmpty {
                state = .loaded                 // stale-but-useful beats an error screen
            } else {
                state = offline ? .offline : .error
            }
        }
    }

    /// Public retry hook for the error / offline states.
    func retry() { Task { await load(initial: true) } }

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

    /// A guaranteed-fresh access token for the socket join / keepalive. @MainActor
    /// so the nonisolated token-provider closure hops here to touch auth safely.
    private func freshToken() async -> String? {
        guard let auth else { return nil }
        return try? await auth.validAccessToken()
    }

    private func handle(_ change: RealtimeClient.Change) {
        // A new/updated row's full record tells us if it lands on today's map.
        func touchesToday(_ row: RealtimeClient.Change.Row?) -> Bool {
            guard let row else { return false }
            if let k = row.kind, k != "event" { return false }   // trails never map
            return row.eventDate == currentDate
        }
        // Is this row id currently on the map? Used for DELETE (whose old_record
        // carries only the primary key — Realtime never sends the full old row on
        // delete) and for an UPDATE that moves an event off today.
        func currentlyShown(_ id: String?) -> Bool {
            guard let id else { return false }
            return todayEvents.contains { $0.id == id }
        }
        let relevant: Bool
        switch change.kind {
        case .insert: relevant = touchesToday(change.new)
        case .update: relevant = touchesToday(change.new) || currentlyShown(change.new?.id ?? change.old?.id)
        case .delete: relevant = currentlyShown(change.old?.id)
        }
        guard relevant else { return }
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

    private func rolloverIfNeeded() {
        let today = DateHelpers.localDate()
        if today != currentDate { currentDate = today }
    }

    private func scheduleMidnightRollover() {
        midnightTask?.cancel()
        guard let seconds = Self.secondsUntilNextMidnight() else { return }
        midnightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.started else { return }
            self.currentDate = DateHelpers.localDate()
            await self.load(initial: false)
            self.scheduleMidnightRollover()          // arm the next day
        }
    }

    private static func secondsUntilNextMidnight() -> Double? {
        var cal = Calendar.current
        cal.timeZone = .current
        // 00:00:01 tomorrow — a hair past midnight so localDate() has flipped.
        guard let next = cal.nextDate(after: Date(),
                                      matching: DateComponents(hour: 0, minute: 0, second: 1),
                                      matchingPolicy: .nextTime) else { return nil }
        return max(1, next.timeIntervalSince(Date()))
    }
}
