//
//  FeedView.swift
//  Block Party — the Town tab body: the top bar over the Town feed.
//

import SwiftUI
import Combine

/// The Today chrome needs only the signed-in neighbor's avatar, not the profile
/// screen's activity lists. Keeping this loader narrow avoids fetching RSVPs, clubs,
/// and quests just to paint a 38pt button, while still sharing `ProfileAPI` as the
/// source of truth.
@MainActor
final class TodayHeaderProfileModel: ObservableObject {
    @Published private(set) var avatarUrl: String?

    private let loadProfile: () async throws -> TownProfile?

    init(loadProfile: @escaping () async throws -> TownProfile?) {
        self.loadProfile = loadProfile
    }

    convenience init(auth: AuthStore) {
        self.init { try await ProfileAPI(auth: auth).getMyProfile() }
    }

    /// A failed refresh keeps the last good photo instead of making the header flash
    /// back to its placeholder during a transient network outage.
    func refresh() async {
        guard let profile = try? await loadProfile() else { return }
        avatarUrl = profile.avatarUrl
    }
}

struct FeedView: View {
    /// The top bar's three controls. The shell owns every presentation; the feed
    /// only forwards the taps.
    var onOpenFriends: () -> Void = {}
    var onOpenMap: () -> Void = {}
    var onOpenNotifications: () -> Void = {}
    /// The wordmark's menu: the Town's own page or its City's (follows 04).
    var onOpenPage: (TownPageKind) -> Void = { _ in }
    /// The Town feed's events, held by the shell so a tab switch doesn't read them again.
    var townFeed: TownFeed
    /// Your Event of the day, Daily's own (BP app event-card 03): the feed's top.
    var eventOfTheDay: EventOfTheDay

    @Environment(\.scenePhase) private var scenePhase
    /// Drives the DEBUG `-feed-scrolled` jump. There is no scroll automation in this
    /// setup, so without it the scrolled state — where the top glass fade actually
    /// does anything — cannot be screenshotted at all.
    @State private var feedPosition = ScrollPosition()
    /// Fixed for this view's life: whether the Town feed's first cards rise in. Not
    /// when it comes back partway down (`TownFeed.returnY`).
    @State private var entrance: Bool

    /// A read failed while a list is showing: the bar says so (ticket 11).
    private var offline: Bool { townFeed.failed && townFeed.entries != nil }

    /// Skeleton, retry or cards: what the Town feed's cross-fade keys on.
    private var townFeedPhase: Int {
        townFeed.entries != nil ? 2 : townFeed.failed ? 1 : 0
    }

    init(
        onOpenFriends: @escaping () -> Void = {},
        onOpenMap: @escaping () -> Void = {},
        onOpenNotifications: @escaping () -> Void = {},
        onOpenPage: @escaping (TownPageKind) -> Void = { _ in },
        townFeed: TownFeed,
        eventOfTheDay: EventOfTheDay
    ) {
        self.onOpenFriends = onOpenFriends
        self.onOpenMap = onOpenMap
        self.onOpenNotifications = onOpenNotifications
        self.onOpenPage = onOpenPage
        self.townFeed = townFeed
        self.eventOfTheDay = eventOfTheDay
        _entrance = State(initialValue: townFeed.returnY == 0)
    }

    /// DEBUG-only: `-feed-scrolled` starts the feed partway down, so the top edge
    /// effect has content under it to blur.
    /// DEBUG-only: `-feed-scrolled-y <pt>` picks where the jump lands, so a state
    /// INSIDE the fade band can be held still and watched.
    static var forcedScrollY: CGFloat {
        #if DEBUG
        if let y = LaunchFlags.value(.feedScrolledY).flatMap({ Double($0) }) {
            return CGFloat(y)
        }
        #endif
        return 420
    }

    /// Is the top bar off the screen right now? Driven by scroll DIRECTION —
    /// `TodayHeader.chromeHidden` holds the rule — and written only when it flips,
    /// so a scroll does not invalidate this view on every frame.
    @State private var chromeHidden = false
    /// Where the current scroll direction started (`TodayHeader.directionAnchor`).
    /// Written only when the direction reverses, or at home, where it tracks the
    /// offset — never touches the bar's height.
    @State private var chromeAnchor: CGFloat = 0
    /// Is the bar floating over the feed rather than at home on the paper
    /// (`TodayHeader.chromeFloating`)? Written only when it flips.
    @State private var chromeFloating = false
    /// How far the feed has carried the bar off the top (`TodayHeader.homeTravel`).
    /// Written here, read only by the bar, so this view does not re-run per frame.
    @State private var barTravel = BarTravel()

    /// DEBUG-only: `-header-collapsed` pins the bar to its scrolled-away state.
    /// There is no scroll automation in this setup, so without it that state cannot
    /// be screenshotted at all.
    private var forcedCollapse: Bool {
        LaunchFlags.has(.headerCollapsed)
    }

    /// DEBUG-only: `-feed-bar-back` holds the bar out over a `-feed-scrolled` feed,
    /// so the floating bar's edge can be shot still.
    private var forcedBack: Bool {
        LaunchFlags.has(.feedBarBack)
    }

    /// `-feed-scrolled-y` alone jumps too: on its own it once did nothing (BP app backlog 03).
    private var forcedScroll: Bool {
        LaunchFlags.has(.feedScrolled) || LaunchFlags.has(.feedScrolledY)
    }

    var body: some View {
        #if DEBUG
        let _ = FeedRenderLog.enabled ? Self._printChanges() : ()
        #endif
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // The social feed.
                ZStack(alignment: .top) {
                    if townFeed.entries != nil {
                        // Your Event of the day on top, the one Daily shows first: when it's over
                        // the next takes its place within the minute, and with none left it goes.
                        // Scrolled down it holds as the list under it does, and moves on at the top.
                        TimelineView(.everyMinute) { context in
                            let items = townFeed.column(eventOfTheDay: eventOfTheDay.events ?? [], now: context.date)
                            let top = items.first.flatMap { item -> String? in
                                if case .eventOfTheDay(let event) = item { return event.id }
                                return nil
                            }
                            DailyFeedColumn(items: items,
                                            entrance: entrance,
                                            onCardOnScreen: { townFeed.cardOnScreen($0, $1) },
                                            now: townFeed.posterClock(at: context.date))
                                // The poster comes, changes and goes, and the cards make room,
                                // rather than popping.
                                .animation(Motion.smooth, value: top)
                        }
                        // A card whose time is up goes, and a series' next date
                        // comes in, rather than popping.
                        .animation(Motion.smooth, value: townFeed.clock)
                        // and back at the top, the finished ones held while scrolled down go.
                        .animation(Motion.smooth, value: townFeed.holding)
                        // A card hidden or muted folds into its Undo line, then away, and the cards
                        // under it slide up; Undo brings it back the same way (ticket 21).
                        .animation(Motion.sheet, value: townFeed.undo)
                        .animation(Motion.sheet, value: townFeed.hiddenIDs)
                        .animation(Motion.sheet, value: townFeed.mutedNames)
                        .environment(townFeed)
                        .transition(.opacity)
                    } else if townFeed.failed {
                        FeedUnavailableBody(title: FeedStateCopy.townEventsUnavailable) {
                            Task { await townFeed.reload() }
                        }
                        .padding(.top, 72)
                        .padding(.horizontal, DailyFeedMetric.contentInset)
                        .transition(.opacity)
                    } else {
                        DailyFeedSkeleton()
                            .transition(.opacity)
                    }
                }
                .animation(Motion.smooth, value: townFeedPhase)

                Color.clear.frame(height: 96)
            }
            .tint(Hue.ink)
        }
        // The top bar's come-and-go, off the scroll's DIRECTION. The old value this
        // hands back is the previous offset; the one other thing stored is
        // `chromeAnchor`, where the current direction started, so slow drags add
        // up. Both it and the answer are written only when they change.
        //
        // Note the offset expression: `contentOffset.y` rests at `-contentInsets
        // .top`, so the `+ geometry.contentInsets.top` term is what makes 0 mean
        // "at rest" — drop it and the bar leaves on the wrong schedule, silently.
        //
        // NOTHING here may touch the bar's HEIGHT: this bar is the scroll's own top
        // inset, so height-from-scroll closes a loop that rings rather than settling
        // (see `TodayHeader.contentHeight`). Opacity and offset are free.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { previousOffset, offset in
            let anchor = TodayHeader.directionAnchor(anchor: chromeAnchor,
                                                     previousOffset: previousOffset,
                                                     offset: offset)
            let hidden = TodayHeader.chromeHidden(wasHidden: chromeHidden,
                                                  floating: chromeFloating,
                                                  anchor: anchor,
                                                  offset: offset)
            let floating = TodayHeader.chromeFloating(wasFloating: chromeFloating,
                                                      hidden: hidden,
                                                      offset: offset)
            if anchor != chromeAnchor { chromeAnchor = anchor }
            // A bar the feed has carried out of home has already gone, so it leaves
            // without the slide: animated, it snapped back to rest the moment it
            // started floating and slid out again over the first post (a flick past
            // the bar's height in one frame).
            var transaction = Transaction()
            transaction.disablesAnimations = hidden && !chromeFloating
            withTransaction(transaction) {
                if hidden != chromeHidden { chromeHidden = hidden }
                if floating != chromeFloating { chromeFloating = floating }
            }
            barTravel.points = TodayHeader.homeTravel(offset: offset)
            townFeed.scrolled(to: offset)
            #if DEBUG
            if LaunchFlags.has(.scrollLog) {
                print("SCROLLLOG offset=\(offset) hidden=\(hidden)")
            }
            #endif
        }
        // A plain safe-area INSET, not `.safeAreaBar`: the feed's content still
        // passes underneath it, but `.safeAreaBar` let iOS adapt the bar to what was
        // behind it and flip it dark over photos — white logo and marks, dark paper
        // (recorded 2026-09-24). `.safeAreaInset` opts out of that adaptation, and
        // the bar brings its own soft edge instead (`StatusEdge`, `BarEdge`), which
        // also covers the status band when the bar is away. Height stays the constant 58pt.
        .safeAreaInset(edge: .top, spacing: 0) {
            TodayTopBar(onOpenFriends: onOpenFriends,
                        onOpenMap: onOpenMap,
                        onOpenNotifications: onOpenNotifications,
                        onOpenPage: onOpenPage,
                        chromeHidden: forcedCollapse || (chromeHidden && !forcedBack),
                        chromeFloating: chromeFloating,
                        travel: barTravel,
                        offline: offline)
        }
        // The tab bar shrinks on the same signal, as Instagram's does.
        .preference(key: TabBarCompactKey.self, value: forcedCollapse || chromeHidden)
        // The clock stays black over the photos scrolling under it, as Instagram's
        // does (taste.md: the status bar stays dark along with the bar). Released when
        // an event page covers the feed, so its hero photo keeps a white clock.
        //
        // Leaving and coming back are also the Town feed's (ticket 11): back within 30
        // minutes it lands where it was, which a tab switch used to lose, since the
        // tab's view is rebuilt.
        .onAppear {
            AppearanceStore.shared.holdsClock = true
            townFeed.cameBack()
            // Back partway down: land there at once, and a turn later leave the bar
            // as a scroll there would, gone and floating once it comes back. The
            // rebuilt view starts with the bar at home, and the jump isn't always
            // reported to the bar's rule, which left it at home over the cards.
            let returnY = townFeed.returnY
            if returnY > 0 {
                feedPosition.scrollTo(y: returnY)
                Task {
                    chromeHidden = true
                    chromeFloating = true
                    chromeAnchor = returnY
                    barTravel.points = TodayHeader.homeTravel(offset: returnY)
                }
            }
        }
        .onDisappear {
            AppearanceStore.shared.holdsClock = false
            townFeed.left(viewGone: true)
        }
        .scrollPosition($feedPosition)
        .refreshable {
            await townFeed.reload()
        }
        .tint(.clear)
        .background(Hue.paper)
        // Coming back to the tab reads again behind the list already showing.
        .task { await townFeed.refresh() }
        // The Event of the day beside it, which reads again only when its picks may have moved.
        .task { await eventOfTheDay.refresh() }
        // When a card's time is up it goes, and the feed reads again behind it.
        .task(id: townFeed.nextLeave) {
            guard let next = townFeed.nextLeave else { return }
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 1))
            guard !Task.isCancelled else { return }
            await townFeed.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                townFeed.cameBack()
                Task { await townFeed.refresh() }
                Task { await eventOfTheDay.refresh() }
            case .background:
                townFeed.left()
            default:
                break
            }
        }
        // Someone partway down the list never reaches the pill, so it is read out once.
        .onChange(of: offline) { _, offline in
            if offline { AccessibilityNotification.Announcement(FeedStateCopy.offline).post() }
        }
        .onAppear {
            if forcedScroll { feedPosition.scrollTo(y: Self.forcedScrollY) }
            #if DEBUG
            if LaunchFlags.has(.feedScrollSweep) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.linear(duration: 4)) {
                        feedPosition.scrollTo(y: 200)
                    }
                }
            }
            if FrameGapLog.enabled { FrameGapLog.shared.start() }
            #endif
        }
    }
}

#if DEBUG
/// `-feed-render-log`: prints every body re-evaluation of the feed's
/// layers (`Self._printChanges`) so the scrub's isolation contract — the
/// perf gate's "per-frame updates never leave the card's subtree; only
/// enter/exit crosses the seam" — is verifiable on a console capture
/// instead of asserted from memory. Compiled out of Release.
nonisolated enum FeedRenderLog {
    static let enabled = LaunchFlags.has(.feedRenderLog)
}

/// `-frame-gap-log`: counts dropped display frames — CADisplayLink
/// callback gaps beyond 1.5× the nominal refresh interval — during a
/// scrub. This is the simulator substitute for Instruments' Animation
/// Hitches instrument, which refuses the simulator platform outright
/// ("Hitches is not supported on this platform"); it sees main-thread /
/// runloop stalls, not GPU-side commit hitches, so the true hitch +
/// ProMotion check stays a device pass. Compiled out of Release.
@MainActor
final class FrameGapLog {
    static let shared = FrameGapLog()
    static var enabled: Bool {
        LaunchFlags.has(.frameGapLog)
    }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var dropped = 0
    private var worstMs = 0.0

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        defer { last = l.timestamp }
        guard last > 0 else { return }
        let gapMs = (l.timestamp - last) * 1000
        let budgetMs = l.duration * 1000 * 1.5
        frames += 1
        worstMs = max(worstMs, gapMs)
        if gapMs > budgetMs {
            dropped += 1
            print("FrameGapLog: DROP gap=\(Int(gapMs))ms budget=\(Int(budgetMs))ms")
        }
        if frames % 300 == 0 {
            print("FrameGapLog: \(frames) frames, \(dropped) drops, worst \(Int(worstMs))ms")
        }
    }
}
#endif
