//
//  MapModel.swift
//  Block Party — the map tab's view-model: today's events + the live Realtime pipeline.
//
//  Owns a single RealtimeClient subscribed to club_events. A change that touches
//  *today* re-syncs the event list (debounced), so a new happening lights its pin
//  and an ended / deleted one goes quiet — with no manual refresh. Handles the
//  full lifecycle the map depends on: teardown on disappear, reconnect + re-sync
//  on foreground, and the midnight rollover (a "today" event stops being today).
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class MapModel: ObservableObject {

    /// What the header status line reflects. The base map + curated pins always
    /// render; this is only about *today's happenings* data.
    enum LoadState: Equatable { case loading, loaded, empty, error, offline }

    @Published private(set) var todayEvents: [TimelineEvent] = []
    /// The town's permanent food/business venues (Supabase `places`). Loaded once —
    /// they don't change with today's events or the Realtime pipeline.
    @Published private(set) var pois: [POI] = []
    @Published private(set) var state: LoadState = .loading
    /// Whether Mapbox has finished loading its style + first tiles (`onStyleLoaded`).
    /// The map tab is only visually "ready" once this is true: `state` can flip to
    /// `.loaded` (today's events are in) while the basemap is still blank — that
    /// blank-then-paint is exactly the pop-in the loading cover exists to hide.
    @Published private(set) var styleLoaded = false
    /// A 1-minute wall-clock heartbeat. Bumped on a timer so any view observing this
    /// model re-evaluates DateHelpers.isLiveNow off the current time even when no
    /// data changes — a pin/"Now" badge must light at an event's start minute and go
    /// quiet at start+2h without needing a pan/tap to force a re-render.
    @Published private(set) var clockTick = 0
    /// The town the map is currently panned over — names the top pill. Starts on
    /// St. Joe (the initial camera) and follows the map as it moves.
    @Published private(set) var townLabel = "Saint Joseph"
    /// Whether pins should show their icon+label (true) or shrink to a small dot
    /// (false) — driven by zoom, so labels only take up map space once there's
    /// room for them. Starts `false` to match SJMapView's default camera zoom
    /// (13.5, below `Self.pinExpandZoom`); the first `updateZoom` call corrects it
    /// immediately if the camera actually starts elsewhere (e.g. `-map-zoom`).
    @Published private(set) var pinsExpanded = false
    /// Zoom at/above which pins expand — matches the old pin-hierarchy's label
    /// threshold (T=14.5), a value already tuned by screenshot for this town.
    static let pinExpandZoom: Double = 14.5

    private var auth: AuthStore?
    private var api: CommunityAPI? { auth.map(CommunityAPI.init(auth:)) }

    private var realtime: RealtimeClient?
    private var currentDate = DateHelpers.localDate()

    private var resyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var townTask: Task<Void, Never>?
    private var zoomTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var started = false
    private var placesLoaded = false
    private var placesLoading = false
    /// Monotonic token so an older in-flight load can't clobber a newer one's
    /// result — load() is fired from start/foreground/retry/resync/midnight and
    /// its fetch suspends, so responses can arrive out of launch order.
    private var loadGeneration = 0

    // MARK: Lifecycle (driven by SJMapView.onAppear/onDisappear + scenePhase)

    /// Called from `SJMapView.onStyleLoaded` — the basemap has painted.
    func markStyleLoaded() { styleLoaded = true }

    func start(auth: AuthStore) {
        if self.auth == nil { self.auth = auth }
        guard !started else { return }
        started = true
        currentDate = DateHelpers.localDate()
        Task { await load(initial: true) }
        Task { await loadPlaces() }
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
        townTask?.cancel(); townTask = nil
        clockTask?.cancel(); clockTask = nil
    }

    /// Re-render observers once a minute so wall-clock-derived state (isLiveNow)
    /// stays truthful with no data change. Runs only while the map is active.
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

    // MARK: Town label (reverse-geocoded map center)

    /// The map center changed. High-frequency camera events land here — never the
    /// view's @State (Mapbox guidance) — debounced so only the settled town name
    /// publishes. A quiet failure (offline / unnamed area) keeps the last name.
    func updateTown(center: CLLocationCoordinate2D) {
        townTask?.cancel()
        townTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)   // wait for the pan to settle
            guard !Task.isCancelled else { return }
            let name = await GeocoderService.shared.town(lat: center.latitude, lon: center.longitude)
            guard !Task.isCancelled, let name else { return }
            self?.townLabel = name
        }
    }

    // MARK: Pin expand/shrink (zoom-driven)

    /// The map's zoom changed. Same "never the view's @State" rule as `updateTown`
    /// — `onCameraChanged` fires every rendering frame, so the actual `@Published`
    /// write is deferred to a task, not made synchronously in the callback. Unlike
    /// the town name this doesn't wait for the pan to fully settle (a shrink/expand
    /// that lagged the whole gesture would feel unresponsive) — just a short debounce
    /// so hovering exactly on the threshold during a bouncy fling doesn't flicker,
    /// and a same-value write is skipped so panning within one zoom band is a no-op.
    func updateZoom(_ zoom: Double) {
        let expanded = zoom >= Self.pinExpandZoom
        guard expanded != pinsExpanded else { return }
        zoomTask?.cancel()
        zoomTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.pinsExpanded = expanded
        }
    }

    /// App returned to foreground: the socket was dropped on background and the
    /// date may have rolled over while away. Re-filter, re-sync, re-subscribe.
    func onForeground() {
        guard started else { return }
        rolloverIfNeeded()
        Task { await load(initial: false) }
        Task { await loadPlaces() }     // retry if the initial places load failed (no-op once loaded)
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

    /// The town's permanent venues (Supabase `places`). Loaded once; a failure keeps
    /// the (empty) set and is retried on foreground / retry — never blocks the map.
    private func loadPlaces() async {
        // `placesLoading` guards the check-then-set across the await, so a start() +
        // foreground/retry overlap can't fire two duplicate fetches (mirrors load()'s
        // loadGeneration guard). `placesLoaded` makes it a true no-op once it succeeds.
        guard let api, !placesLoaded, !placesLoading else { return }
        placesLoading = true
        defer { placesLoading = false }
        do {
            pois = try await api.getPlaces()
            placesLoaded = true
        } catch {
            // Leave pois empty; foreground / retry will try again. The map still works.
        }
    }

    /// Public retry hook for the error / offline states.
    func retry() { Task { await load(initial: true); await loadPlaces() } }

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
