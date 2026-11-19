//
//  TownView.swift
//  Block Party — the Town tab body: the top bar over the Town feed.
//

import SwiftUI

struct TownView: View {
    /// The top bar's controls. The shell owns every presentation; the feed
    /// only forwards the taps.
    var onOpenMap: () -> Void = {}
    var onOpenNotifications: () -> Void = {}
    /// The bar's + → New post (BP app references/post-screen).
    var onCreate: () -> Void = {}
    /// The wordmark's menu: the Town's own page or its City's (follows 04).
    var onOpenPage: (TownPageKind) -> Void = { _ in }
    /// The Town feed's events, held by the shell so a tab switch doesn't read them again.
    var townFeed: TownFeed
    /// Your Event of the day, Daily's own (BP app event-card 03): the feed's top.
    var eventOfTheDay: EventOfTheDay

    /// A place as Search holds it, by `places.id`: the feed's places to try (town-feed 23).
    var places: (String) -> SearchItem?
    /// Goes up by one each time the Town tab is tapped while on Town: scrolled down, the feed
    /// goes to its top; at the top, it reads again as a pull does (BP app town-feed 61).
    var tappedAgain = 0

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the DEBUG `-feed-scrolled` jump. There is no scroll automation in this
    /// setup, so without it the scrolled state — where the top glass fade actually
    /// does anything — cannot be screenshotted at all.
    @State private var feedPosition = ScrollPosition()
    /// Fixed for this view's life: whether the Town feed's first cards rise in. Not
    /// when it comes back partway down (`TownFeed.returnY`).
    @State private var entrance: Bool
    /// The first screen after a restart (`TownFeed.resume`), until it lands.
    @State private var resumed: Bool

    /// Your post the check just let up, on top for the session (`PostOutbox.justPosted`), while the feed has it.
    private var justPosted: TownPost? {
        PostOutbox.shared.justPosted.flatMap { id in townFeed.shown.lazy.compactMap(\.post).first { $0.id == id } }
    }

    /// A read failed while a list is showing: the bar says so (ticket 11).
    private var offline: Bool { townFeed.failed && townFeed.entries != nil }

    /// Skeleton, retry or cards: what the Town feed's cross-fade keys on.
    private var townFeedPhase: Int {
        townFeed.entries != nil ? 2 : townFeed.failed ? 1 : 0
    }

    init(
        onOpenMap: @escaping () -> Void = {},
        onOpenNotifications: @escaping () -> Void = {},
        onCreate: @escaping () -> Void = {},
        onOpenPage: @escaping (TownPageKind) -> Void = { _ in },
        townFeed: TownFeed,
        eventOfTheDay: EventOfTheDay,
        places: @escaping (String) -> SearchItem? = { _ in nil },
        tappedAgain: Int = 0
    ) {
        self.tappedAgain = tappedAgain
        self.onOpenMap = onOpenMap
        self.onOpenNotifications = onOpenNotifications
        self.onCreate = onCreate
        self.onOpenPage = onOpenPage
        self.townFeed = townFeed
        self.eventOfTheDay = eventOfTheDay
        self.places = places
        let resumed = townFeed.takeResumed()
        _resumed = State(initialValue: resumed)
        _entrance = State(initialValue: townFeed.returnY == 0 && !resumed)
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
    /// `TownBarRules.chromeHidden` holds the rule — and written only when it flips,
    /// so a scroll does not invalidate this view on every frame.
    @State private var chromeHidden = false
    /// Where the current scroll direction started (`TownBarRules.directionAnchor`).
    /// Written only when the direction reverses, or at home, where it tracks the
    /// offset — never touches the bar's height.
    @State private var chromeAnchor: CGFloat = 0
    /// Is the bar floating over the feed rather than at home on the paper
    /// (`TownBarRules.chromeFloating`)? Written only when it flips.
    @State private var chromeFloating = false
    /// How far the feed has carried the bar off the top (`TownBarRules.barTravel`).
    /// Written here, read only by the bar, so this view does not re-run per frame.
    @State private var barTravel = BarTravel()
    /// How far the feed is pulled, and the read out now: only the refresh loop reads it (town-feed 69).
    @State private var refreshPull = RefreshPull()
    /// The gap a Town tab tap opens for the loop above the first card, as a pull's read holds one.
    /// Set from the read, never from the scroll's geometry (swift-traps.md).
    @State private var refreshGap: CGFloat = 0

    /// A read the loop shows: at least one lap, however fast the read comes back. A pull's read holds
    /// its own gap open (`.refreshable`) while this runs; a tab tap's opens one here.
    private func read(from start: RefreshStart) async {
        // One at a time: a tab tap during a pull's read (still at the top) would open a second gap.
        guard refreshPull.reading == nil else { return }
        refreshPull.reading = start
        if start == .tab { withAnimation(reduceMotion ? nil : Motion.sheet) { refreshGap = LoopRide.heldGap } }
        let began = Date.now
        await townFeed.pulled()
        try? await Task.sleep(for: .seconds(LoopRide.rest(afterReading: Date.now.timeIntervalSince(began))))
        refreshPull.reading = nil
        if start == .tab { withAnimation(reduceMotion ? nil : Motion.sheet) { refreshGap = 0 } }
    }

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
                // The pull-to-refresh: a line round a loop in the gap above the first card (town-feed 69).
                RefreshLoop(pull: refreshPull, held: refreshGap)
                // Your post on its way, faded on top until it's up, or until Review let it up while it waited;
                // once up, the post itself there for the session (town-feed 29).
                if let sent = PostOutbox.shared.sent, !townFeed.shown.contains(where: { $0.id == sent.id }) {
                    PostingPostCard(sent: sent) {
                        PostOutbox.shared.reopen()
                        onCreate()
                    }
                    .padding(.top, 12)
                    .transition(.opacity)
                } else if let mine = justPosted {
                    FeedPostCard(post: mine)
                        .padding(.top, 12)
                        .environment(townFeed)
                        .transition(.opacity)
                }
                // The social feed.
                ZStack(alignment: .top) {
                    if townFeed.entries != nil {
                        // Your Event of the day on top, the one Daily shows first: when it's over
                        // the next takes its place within the minute, and with none left it goes.
                        // Scrolled down it holds as the list under it does, and moves on at the top.
                        TimelineView(.everyMinute) { context in
                            let items = townFeed.column(eventOfTheDay: eventOfTheDay.events ?? [], now: context.date,
                                                        places: places)
                                .filter { item in justPosted.map { item.id != "post:" + $0.id } ?? true }
                            let top = items.first.flatMap { item -> String? in
                                if case .eventOfTheDay(let event) = item { return event.id }
                                return nil
                            }
                            TownFeedColumn(items: items,
                                            entrance: entrance,
                                            onCardOnScreen: { townFeed.cardOnScreen($0, $1) },
                                            now: townFeed.posterClock(at: context.date),
                                            onNearEnd: { Task { await townFeed.loadMore() } },
                                            loadingMore: townFeed.loadingMore)
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
                        .animation(Motion.sheet, value: townFeed.hides.undo)
                        .animation(Motion.sheet, value: townFeed.hides.hiddenIDs)
                        .animation(Motion.sheet, value: townFeed.hides.mutedNames)
                        .environment(townFeed)
                        .transition(.opacity)
                    } else if townFeed.failed {
                        FeedUnavailableBody(title: FeedStateCopy.townEventsUnavailable) {
                            Task { await townFeed.reload() }
                        }
                        .padding(.top, 72)
                        .padding(.horizontal, TownFeedMetric.contentInset)
                        .transition(.opacity)
                    } else {
                        TownFeedSkeleton()
                            .transition(.opacity)
                    }
                }
                .animation(Motion.smooth, value: townFeedPhase)

                Color.clear.frame(height: 96)
            }
            .padding(.top, refreshGap)
            .tint(Hue.ink)
            // Your post comes in on top and goes once it's up; the cards make room (town-feed 29).
            .animation(Motion.smooth, value: PostOutbox.shared.sent?.id)
            .animation(Motion.smooth, value: PostOutbox.shared.justPosted)
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
        // (see `TownBarRules.contentHeight`). Opacity and offset are free.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { previousOffset, offset in
            let anchor = TownBarRules.directionAnchor(anchor: chromeAnchor,
                                                     previousOffset: previousOffset,
                                                     offset: offset)
            let hidden = TownBarRules.chromeHidden(wasHidden: chromeHidden,
                                                  floating: chromeFloating,
                                                  anchor: anchor,
                                                  offset: offset)
            let floating = TownBarRules.chromeFloating(wasFloating: chromeFloating,
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
            barTravel.points = TownBarRules.barTravel(offset: offset)
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
            TownBar(onOpenMap: onOpenMap,
                        onOpenNotifications: onOpenNotifications,
                        onCreate: onCreate,
                        onOpenPage: onOpenPage,
                        chromeHidden: forcedCollapse || (chromeHidden && !forcedBack),
                        chromeFloating: chromeFloating,
                        travel: barTravel,
                        offline: offline)
                // Rises into place as the launch's yellow clears (Jesse, 2026-11-02).
                .launchSettle()
        }
        // The tab bar shrinks on the same signal, as Instagram's does.
        .preference(key: TabBarCompactKey.self, value: forcedCollapse || chromeHidden)
        // The clock stays black over the photos scrolling under it, as Instagram's
        // does (taste.md: the status bar stays dark along with the bar). Released when
        // an event page covers the feed, so its hero photo keeps a white clock.
        //
        // Leaving and coming back are also the Town feed's (ticket 11): back within 30
        // minutes it lands where it was, which a tab switch used to lose, since the
        // tab's view was rebuilt. The tab now stays built (TabPages.swift), so these mark the visit.
        .onScreen {
            AppearanceStore.shared.holdsClock = true
            townFeed.cameBack()
            // Back partway down: land there at once, and a turn later leave the bar
            // as a scroll there would, gone and floating once it comes back. The
            // rebuilt view starts with the bar at home, and the jump isn't always
            // reported to the bar's rule, which left it at home over the cards.
            let returnY = townFeed.returnY
            // After a restart no row is measured, so it lands on the card, or stays at the top
            // when that card has gone.
            let row = resumed ? townFeed.returnRow : nil
            if returnY > 0, !resumed || row != nil {
                if let row {
                    feedPosition.scrollTo(id: row, anchor: .top)
                } else {
                    feedPosition.scrollTo(y: returnY)
                }
                Task {
                    chromeHidden = true
                    chromeFloating = true
                    chromeAnchor = returnY
                    barTravel.points = TownBarRules.barTravel(offset: returnY)
                }
            }
            resumed = false
        } disappear: {
            AppearanceStore.shared.holdsClock = false
            townFeed.left(viewGone: true)
        }
        // How far the feed is pulled past its top, for the refresh loop alone. Read off where the content
        // sits, not off `offset` above: `.refreshable` adds to the top inset as its read starts, which
        // jumped that 40 pt mid-pull.
        .onScrollGeometryChange(for: RefreshPull.Scroll.self) { geometry in
            RefreshPull.Scroll(top: -geometry.contentOffset.y, inset: geometry.contentInsets.top)
        } action: { _, scroll in
            refreshPull.scrolled(scroll)
        }
        .scrollPosition($feedPosition)
        .onScrollPhaseChange { _, phase in
            townFeed.fingerDown = phase == .tracking || phase == .interacting
            if phase == .idle { Task { await townFeed.fingerLifted() } }
        }
        // Apple's pull, trigger and held gap, its swirl hidden (`SwirlHider`); the loop rides at least
        // one lap, so a quick read holds the gap that long.
        // Its own task, as TeamPage's: SwiftUI cancelled the refresh's task as the new cards landed,
        // which cut the lap short and let the gap go (measured 0.75 s in, refresh-coaster).
        .refreshable {
            await Task { await read(from: .pull) }.value
        }
        // An open after an hour or more away rolled a new top five (town-feed 73): to the top at once, where it lands.
        .onChange(of: townFeed.rolls) {
            feedPosition.scrollTo(edge: .top)
        }
        // The Town tab tapped again, as Instagram's Home: to the top, then a read, the loop
        // riding in a gap of its own.
        .onChange(of: tappedAgain) {
            if townFeed.atTop {
                Task { await read(from: .tab) }
            } else {
                withAnimation(reduceMotion ? nil : Motion.smooth) { feedPosition.scrollTo(edge: .top) }
            }
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
        // While a read has failed (the Offline pill, or the retry with no list), read again on its own, 2 s, then 4, 8,
        // then every 15 s, so the feed comes back soon after signal does, with no pull or tap (town-feed 47). Not
        // NWPathMonitor: the simulator never tells it signal came back, so no proof could run.
        .task(id: townFeed.failed) {
            var wait = 2.0
            while townFeed.failed {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                await townFeed.refresh()
                wait = min(wait * 2, 15)
            }
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
        // And again once the live list is in: on a first launch the jump landed on the skeleton.
        .onChange(of: townFeedPhase) { _, phase in
            if forcedScroll, phase == 2 { feedPosition.scrollTo(y: Self.forcedScrollY) }
        }
        .onAppear {
            if forcedScroll { feedPosition.scrollTo(y: Self.forcedScrollY) }
            #if DEBUG
            if LaunchFlags.has(.feedScrollRun) {
                Task { await ScrollRun.run { feedPosition.scrollTo(y: $0) } }
            }
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
    /// The last tap's finger lift (`UITouch.timestamp`, the display link's clock), until its line prints.
    private var tapUp: TimeInterval?
    private var tapName = "touch"
    private var tapWorstMs = 0.0
    private var tapStallMs = 0.0

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        let clock = TapClock { [weak self] up in self?.timeTap("touch", from: up) }
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
            .addGestureRecognizer(clock)
    }

    /// A tap made by code (`-pill-cycle`), timed as a finger's lift is.
    func tapped(_ name: String) {
        start()
        timeTap(name, from: CACurrentMediaTime())
    }

    private func timeTap(_ name: String, from up: TimeInterval) {
        tapUp = up
        tapName = name
        tapWorstMs = 0
        tapStallMs = 0
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
        // A tap: the longest freeze in the 0.6 s after the finger's lift (the screen can't start to move
        // before it ends) and all the time lost to freezes there (tab-lag 02).
        if let up = tapUp {
            let now = CACurrentMediaTime()
            tapWorstMs = max(tapWorstMs, gapMs)
            if gapMs > budgetMs { tapStallMs += gapMs - l.duration * 1000 }
            if now - up > 0.6 {
                print("FrameGapLog: TAP \(tapName) worst=\(Int(tapWorstMs))ms stall=\(Int(tapStallMs))ms")
                tapUp = nil
            }
        }
    }
}

/// Sees every finger lift in the window without taking part: it never recognizes, cancels nothing and
/// lets every other recognizer run. A finger that moved over 10 pt was a scroll, not a tap.
private final class TapClock: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let lifted: (TimeInterval) -> Void
    private var down: CGPoint?

    init(lifted: @escaping (TimeInterval) -> Void) {
        self.lifted = lifted
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        down = touches.first?.location(in: view)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let down, hypot(touch.location(in: view).x - down.x,
                                                      touch.location(in: view).y - down.y) < 10 {
            lifted(touch.timestamp)
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// `-feed-scroll-run`: a brisk thumb, 700 pt down every second 30 times from 5 s after launch, then back up two of
/// those steps (BP app tab-lag 03), printing each part as it starts. Town runs it on its feed; any other page on
/// the tab `-open-tab` opens through `scrollRun()`.
@MainActor
enum ScrollRun {
    static func run(_ scrollTo: @escaping (CGFloat) -> Void) async {
        try? await Task.sleep(for: .seconds(5))
        print("ReadAhead: scroll down")
        for step in 1...30 {
            withAnimation(.easeOut(duration: 0.35)) { scrollTo(CGFloat(step) * 700) }
            try? await Task.sleep(for: .seconds(1))
        }
        // Back up two steps: the screen behind should still be drawn.
        print("ReadAhead: scroll back")
        for step in 1...2 {
            withAnimation(.easeOut(duration: 0.35)) { scrollTo(CGFloat(30 - step) * 700) }
            try? await Task.sleep(for: .seconds(1))
        }
        print("ReadAhead: run done")
    }
}

private struct ScrollRunModifier: ViewModifier {
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .task { await ScrollRun.run { position.scrollTo(y: $0) } }
    }
}

/// `-read-ahead-log`: one line per photo or logo as it comes on, drawn in its first frame or not (BP app tab-lag 03).
enum ReadAheadLog {
    static let enabled = LaunchFlags.has(.readAheadLog)

    static func cameOn(_ kind: String, ready: Bool, _ url: URL) {
        if enabled { print("ReadAhead: \(ready ? "READY" : "BLANK") \(kind) \(url.absoluteString)") }
    }
}
#endif

extension View {
    /// DEBUG `-feed-scroll-run` on this scroll view (`ScrollRun`); nothing otherwise, and nothing in a release build.
    @ViewBuilder
    func scrollRun() -> some View {
        #if DEBUG
        if LaunchFlags.has(.feedScrollRun) { modifier(ScrollRunModifier()) } else { self }
        #else
        self
        #endif
    }
}
