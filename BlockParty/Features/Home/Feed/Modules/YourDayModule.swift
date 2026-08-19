//
//  YourDayModule.swift
//  Block Party — what is happening in this neighbour's town TODAY, fetched
//  independently.
//
//  Two lanes, both scoped to the town's today: what they personally committed to,
//  and what the whole town has on the calendar. See `DayItem` for the contract and
//  `YourDayItems.swift` for the rules.
//

import Combine
import SwiftUI
import UIKit

@MainActor
final class YourDayModule: @MainActor FeedModule {
    let id: FeedModuleID = .yourDay
    let order = 2
    let ownsFetch = true

    /// Today's rail, in render order. The published contract the rail and the day
    /// sheet build against.
    @Published private(set) var items: [DayItem] = []
    @Published private var loadState: LoadState = .loading

    /// Offered beside a lone commitment. Nil in production until there is a real
    /// source for "something else on today's calendar" — with one item in the rail
    /// there is, by definition, nothing left in today's candidates to suggest, so
    /// a real suggestion has to come from a wider read than `getTownDayCandidates`.
    /// Never fabricated: an empty suggestion slot is honest, an invented one is not.
    @Published private(set) var suggestion: DayItem?

    /// Drives the empty card's "N things happening in St. Joe →". Nil drops the
    /// number rather than inventing one.
    @Published private(set) var townCount: Int?

    /// Today's solar times for the horizon card, from the same Open-Meteo
    /// read the almanac uses (WeatherService's 15-minute cache — no new
    /// network call). Nil falls back to 6:30 AM / 8:30 PM inside SolarSky.
    @Published private(set) var sunrise: Date?
    @Published private(set) var sunset: Date?

    /// Who says a thing is done. The session store, so the rail and the day sheet
    /// give the same answer and a tick outlives the app.
    private let completion: DayCompletionStore

    // MARK: Live updates (mirrors MapModel's realtime pipeline)

    /// One socket on `club_events`, so a new posting's stub rises out of the
    /// horizon without a feed reload. Created on the first authenticated load.
    /// The module lives as long as the Home tab; if the tab tree is ever torn
    /// down without a signed-out load, the socket lingers until the server
    /// drops it — the same view-driven-stop ceiling MapModel accepts.
    private var realtime: RealtimeClient?
    private var resyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// The context of the last real load, so a realtime ping or the midnight
    /// rollover can re-run the same fetch against the same injected clock.
    private var lastContext: FeedModuleContext?

    /// The rows behind `items`, for anything that still takes an `UpcomingEvent`.
    /// Derived, never stored twice — `items` is the single source of truth.
    private var events: [UpcomingEvent] { items.map(\.event) }

    private enum LoadState {
        case loading
        case ready
        case failed
    }

    /// Optional-defaulted rather than `= .shared`, because a default argument is
    /// evaluated in a nonisolated context and `.shared` is main-actor state — the
    /// CLAUDE.md default-argument gotcha, and the same shape `DayScheduleSheet`
    /// already uses for this exact dependency.
    init(briefing _: BriefingModel, completion: DayCompletionStore? = nil) {
        self.completion = completion ?? .shared
    }

    var phase: FeedPhase {
        switch loadState {
        case .loading: .loading
        case .ready: .ready
        case .failed: .failed
        }
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool {
        #if DEBUG
        if FeedDebugFocus.isHidden(id) { return false }
        #endif
        return true
    }

    func load(_ ctx: FeedModuleContext) async {
        loadState = .loading

        // One instant for the whole build, so the day boundary cannot move
        // between the query and the filtering.
        let now = ctx.dates.now

        #if DEBUG
        if applyDebugStateIfRequested(now: now) { return }
        #endif

        guard ctx.auth.userId != nil else {
            stopLive()
            items = []
            loadState = .ready
            return
        }

        // Solar times ride along concurrently — WeatherService coalesces
        // with the almanac's in-flight read, so this adds no request.
        async let weather = WeatherService.current()

        do {
            let candidates = try await CommunityAPI(auth: ctx.auth).getTownDayCandidates(now: now)
            items = YourDayLogic.dayItems(from: candidates, now: now)
            loadState = .ready
        } catch {
            loadState = .failed
        }

        // Armed on the failure path too: the next realtime change quietly
        // recovers a rail the initial fetch could not deliver.
        lastContext = ctx
        startLive(ctx)

        // Stored completions, AFTER the rail is ready. Best-effort and separate
        // from the fetch above: a completions read that fails must not blank a day
        // we already have, and a day that failed to load has no ids to ask about.
        // Awaited before the weather so a slow Open-Meteo read delays neither.
        await completion.refresh(for: items.map(\.id))

        // Solar times hydrate LAST: the card opens on its 6:30/8:30 fallback
        // and cross-fades when the real times land.
        let w = await weather
        sunrise = w?.sunrise
        sunset = w?.sunset
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            // The horizon card's own loading state: the sky renders live,
            // stubs and counts become a quiet shimmer. Never a spinner.
            return AnyView(
                YourDayHorizonSection(
                    items: [],
                    sunrise: sunrise,
                    sunset: sunset,
                    isLoading: true,
                    dates: ctx.dates,
                    onSeeAll: { ctx.navigate(.activities(.happeningToday)) }
                )
                .padding(.top, YourDayRailMetrics.sectionTop)
            )

        case .failed:
            return AnyView(
                FeedUnavailableCard(title: FeedStateCopy.yourDayUnavailable) {
                    Task { await self.load(ctx) }
                }
                .padding(.horizontal, YourDayRailMetrics.pageMargin)
                .padding(.top, YourDayRailMetrics.sectionTop)
            )

        case .ready:
            return AnyView(
                YourDayHorizonSection(
                    items: items,
                    sunrise: sunrise,
                    sunset: sunset,
                    dates: ctx.dates,
                    // See all → today's postings in Activities. The card body
                    // routes to the day sheet inside the section (host lane).
                    onSeeAll: { ctx.navigate(.activities(.happeningToday)) }
                )
                .padding(.top, YourDayRailMetrics.sectionTop)
                .springReveal(
                    1,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
                .modifier(YourDayDebugDetailOpener(events: events, navigate: ctx.navigate))
            )

        case .empty:
            // Your Day is the deliberate exception: an empty RSVP list is an
            // onboarding opportunity, so this module never enters `.empty` — it
            // renders its designed empty state from the `.ready` branch instead.
            return AnyView(EmptyView())
        }
    }
}

// MARK: - Live updates

private extension YourDayModule {
    func startLive(_ ctx: FeedModuleContext) {
        if realtime == nil {
            let auth = ctx.auth
            let client = RealtimeClient(table: "club_events") {
                try? await auth.validAccessToken()
            }
            client.onChange = { [weak self] change in self?.handle(change) }
            realtime = client
        }
        realtime?.start()          // idempotent — a repeat load can't stack sockets
        scheduleMidnightRollover()
        installLifecycleObserversOnce()
    }

    func stopLive() {
        realtime?.stop()
        resyncTask?.cancel(); resyncTask = nil
        midnightTask?.cancel(); midnightTask = nil
    }

    func handle(_ change: RealtimeClient.Change) {
        guard let ctx = lastContext,
              YourDayLogic.changeIsRelevant(
                  change,
                  shownIDs: Set(items.map(\.id)),
                  now: ctx.dates.now
              ) else { return }
        scheduleResync()
    }

    /// Debounce a burst of changes (e.g. a weekly-repeat insert loop) into one
    /// fetch — same 300 ms as MapModel.
    func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.resync()
        }
    }

    /// A quiet reload: no `.loading` shimmer, and a failure keeps the rail we
    /// already have — stale-but-useful beats a flash or an error card.
    func resync() async {
        guard let ctx = lastContext, ctx.auth.userId != nil else { return }
        let now = ctx.dates.now
        do {
            let candidates = try await CommunityAPI(auth: ctx.auth).getTownDayCandidates(now: now)
            items = YourDayLogic.dayItems(from: candidates, now: now)
            loadState = .ready
        } catch {
            return
        }
        await completion.refresh(for: items.map(\.id))
        // Solar times only move at the midnight rollover; on ordinary event
        // pings WeatherService's 15-minute cache makes this read free.
        if let w = await WeatherService.current() {
            sunrise = w.sunrise
            sunset = w.sunset
        }
    }

    /// A "today" module changes meaning at midnight — same shape as
    /// MapModel.scheduleMidnightRollover, but on TOWN time (the rail's day;
    /// see YourDayItems.swift's header for why not the device timezone).
    func scheduleMidnightRollover() {
        midnightTask?.cancel()
        guard let ctx = lastContext else { return }
        let now = ctx.dates.now
        // 00:00:01 — a hair past town midnight so Town.day(now) has flipped.
        guard let next = Town.calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        ) else { return }
        let seconds = max(1, next.timeIntervalSince(now))
        midnightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.resync()
            self.scheduleMidnightRollover()          // arm the next day
        }
    }

    /// The socket is dropped on background (battery) and rebuilt on foreground
    /// with a re-sync, because Realtime never replays what was missed while
    /// away. Notification-based because a feed module has no scenePhase of its
    /// own; the observers live as long as the module (the Home tab's lifetime).
    func installLifecycleObserversOnce() {
        guard lifecycleObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        lifecycleObservers.append(nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.realtime != nil else { return }
                self.realtime?.start()
                self.scheduleMidnightRollover()
                self.scheduleResync()
            }
        })
        lifecycleObservers.append(nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopLive() }
        })
    }
}

#if DEBUG
private extension YourDayModule {
    /// `-yourday-sample|-yourday-loading|-yourday-error|-yourday-empty` bypass auth
    /// and the network so each state can be screenshotted. Production loaders are
    /// untouched; the fixtures are the same clearly-marked debug events.
    ///
    /// `-yourday-count <n>` drives the item-count states the rail's layout actually
    /// turns on — 0 (empty card), 1 (card + suggestion), 2+ (cards only).
    func applyDebugStateIfRequested(now: Date) -> Bool {
        let args = ProcessInfo.processInfo.arguments

        // The horizon card's mock lane: `-BPMockNow` / `-BPMockSunTimes` /
        // `-BPMockDayState <state>` stage any §7 state with pinned solar
        // times and no network. The section reads the same override for its
        // clock, so module and card cannot disagree.
        if let mock = HorizonMock.launchOverride {
            sunrise = mock.sunrise
            sunset = mock.sunset
            switch mock.state {
            case .loading:
                items = []
                loadState = .loading
            case .error:
                items = []
                loadState = .failed
            default:
                items = mock.items
                loadState = .ready
            }
            return true
        }

        if args.contains("-yourday-loading") {
            items = []
            loadState = .loading
            return true
        }
        if args.contains("-yourday-error") {
            items = []
            loadState = .failed
            return true
        }
        if args.contains("-yourday-empty") {
            applyDebugItems([], now: now)
            return true
        }
        // `-day-sheet-demo` drives the whole open → scroll → tick → dismiss
        // sequence, so it seeds its own rail rather than needing a second flag
        // alongside it. Four cards: enough day to scroll, few enough to see.
        if args.contains("-day-sheet-demo") {
            applyDebugItems(YourDayRailDebug.items(count: 4, now: now), now: now)
            return true
        }
        if let count = YourDayRailDebug.requestedCount(args) {
            applyDebugItems(YourDayRailDebug.items(count: count, now: now), now: now)
            return true
        }
        if args.contains("-yourday-sample") {
            applyDebugItems(YourDayLogic.debugDayItems(now: now), now: now)
            return true
        }
        return false
    }

    /// One place where a debug rail is staged, so the suggestion and the empty
    /// card's count follow the same rules under every flag.
    func applyDebugItems(_ debugItems: [DayItem], now: Date) {
        items = debugItems
        suggestion = debugItems.count == 1 ? YourDayRailDebug.suggestion(now: now) : nil
        townCount = debugItems.isEmpty ? YourDayRailDebug.townCount : nil
        loadState = .ready
    }
}
#endif

/// `-yourday-open-detail` opens the first upcoming event's detail on appear.
/// There is no tap automation in this simulator setup, so a screen only reachable
/// by tapping a card is otherwise unverifiable. No-op without the flag, and the
/// whole modifier compiles to a pass-through in Release.
///
/// The horizon card's two routes are driven separately, from their own
/// closures — see `HorizonDebugTapDriver`.
private struct YourDayDebugDetailOpener: ViewModifier {
    let events: [UpcomingEvent]
    let navigate: (FeedRoute) -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            let args = ProcessInfo.processInfo.arguments
            guard let flag = args.firstIndex(of: "-yourday-open-detail") else { return }
            let offset = (flag + 1 < args.count ? Int(args[flag + 1]) : nil) ?? 0
            guard events.indices.contains(offset) else { return }
            try? await Task.sleep(for: .milliseconds(400))
            navigate(.event(events[offset]))
        }
        #else
        content
        #endif
    }
}

// The bespoke "Your day couldn't load." card was replaced by the shared
// `FeedUnavailableCard`, so the three self-fetching modules fail the same way.
