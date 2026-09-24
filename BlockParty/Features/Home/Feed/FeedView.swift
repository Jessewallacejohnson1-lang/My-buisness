//
//  FeedView.swift
//  Block Party — the Today tab body, rendered entirely from FeedRegistry.
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
    let auth: AuthStore
    /// The top bar's three controls. The shell owns every presentation; the feed
    /// only forwards the taps.
    var onOpenSearch: () -> Void = {}
    var onOpenMap: () -> Void = {}
    var onOpenNotifications: () -> Void = {}
    var profileShown = false

    @StateObject private var controller: FeedController
    @State private var name: String?
    @State private var route: FeedRoute?
    @State private var revealed = false
    @State private var revealAnimated = true
    @State private var contentRevealed = false
    @State private var refreshReplay = 0
    /// Drives the DEBUG `-feed-scrolled` jump. There is no scroll automation in this
    /// setup, so without it the scrolled state — where the top glass fade actually
    /// does anything — cannot be screenshotted at all.
    @State private var feedPosition = ScrollPosition()
    /// The clock the social feed ranks against. Bumped on pull-to-refresh so a
    /// stale ordering cannot outlive the gesture that asked for a new one.
    @State private var feedClock = Date()

    init(
        auth: AuthStore,
        onOpenSearch: @escaping () -> Void = {},
        onOpenMap: @escaping () -> Void = {},
        onOpenNotifications: @escaping () -> Void = {},
        profileShown: Bool = false
    ) {
        self.auth = auth
        self.onOpenSearch = onOpenSearch
        self.onOpenMap = onOpenMap
        self.onOpenNotifications = onOpenNotifications
        self.profileShown = profileShown

        let briefing = BriefingModel()
        let context = FeedModuleContext(
            auth: auth,
            briefing: briefing,
            displayName: nil,
            navigate: { _ in }
        )
        _controller = StateObject(wrappedValue: FeedController(context: context))
    }

    private var context: FeedModuleContext {
        FeedModuleContext(
            auth: auth,
            briefing: controller.briefing,
            displayName: name,
            navigate: { navigate($0) },
            revealed: revealed,
            contentRevealed: contentRevealed,
            revealAnimated: revealAnimated,
            refreshReplay: refreshReplay
        )
    }

    /// One place a module's route is fulfilled: every route presents its own sheet
    /// over the feed. Routing here — rather than inside a module — keeps every
    /// module's one way out (`ctx.navigate`) the same.
    private func navigate(_ route: FeedRoute) {
        self.route = route
    }

    /// DEBUG-only: `-feed-scrolled` starts the feed partway down, so the top edge
    /// effect has content under it to blur.
    /// DEBUG-only: `-feed-scrolled-y <pt>` picks where the jump lands, so a state
    /// INSIDE the fade band can be held still and watched.
    static var forcedScrollY: CGFloat {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-feed-scrolled-y"), i + 1 < args.count,
           let y = Double(args[i + 1]) {
            return CGFloat(y)
        }
        #endif
        return 420
    }

    /// Is the top bar off the screen right now? Driven by scroll DIRECTION —
    /// `TodayHeader.chromeHidden` holds the rule — and written only when it flips,
    /// so a scroll does not invalidate this view on every frame.
    @State private var chromeHidden = false

    /// DEBUG-only: `-header-collapsed` pins the bar to its scrolled-away state.
    /// There is no scroll automation in this setup, so without it that state cannot
    /// be screenshotted at all.
    private var forcedCollapse: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-header-collapsed")
        #else
        return false
        #endif
    }

    private var forcedScroll: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-feed-scrolled")
        #else
        return false
        #endif
    }

    var body: some View {
        #if DEBUG
        let _ = FeedRenderLog.enabled ? Self._printChanges() : ()
        #endif
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                FeedModuleColumn(
                    registry: controller.registry,
                    briefing: controller.briefing,
                    context: context
                )

                // The social feed. Below the module column rather than instead
                // of it: the registry is empty today, but a module that lands
                // later is town-wide chrome (weather, the almanac) and belongs
                // above the stream, not buried in it.
                DailyFeedColumn(items: DailyView.currentItems, now: feedClock)

                Color.clear.frame(height: 96)
            }
            .tint(Hue.ink)
        }
        // The top bar's come-and-go, off the scroll's DIRECTION. The old value this
        // hands back IS the previous offset, so the rule needs nothing stored: the
        // only state kept is the answer, and it is written only when it changes.
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
            let hidden = TodayHeader.chromeHidden(wasHidden: chromeHidden,
                                                  previousOffset: previousOffset,
                                                  offset: offset)
            if hidden != chromeHidden { chromeHidden = hidden }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-scroll-log") {
                print("SCROLLLOG offset=\(offset) hidden=\(hidden)")
            }
            #endif
        }
        // The bar rides ON the scroll, not above it: as a top safe-area inset the
        // feed's content passes UNDERNEATH it. While the bar is showing it carries
        // its own paper-to-clear backdrop (2026-09-24), so the logo sits on paper
        // mid-feed; when it leaves, the backdrop leaves with it and the soft edge
        // below takes over.
        .safeAreaBar(edge: .top, spacing: 0) {
            TodayTopBar(onOpenSearch: onOpenSearch,
                        onOpenMap: onOpenMap,
                        onOpenNotifications: onOpenNotifications,
                        chromeHidden: forcedCollapse || chromeHidden)
        }
        // The glass fade at the top of the screen (Jesse, 2026-09-19, matching
        // Instagram's feed): content sliding under the status bar is blurred and
        // washed toward the page instead of being covered by a white bar. It is
        // what the band shows while the bar is away; while the bar is showing, the
        // bar's own paper backdrop (`TodayTopBar.backdrop`) covers it.
        //
        // `.soft`, restored 2026-09-21. It went to `.hard` for the few hours the bar
        // was locked in place, because a bar that never leaves shares this band with
        // the feed and `.soft` passed the card action row through legibly — a ghost
        // heart under the search mark. Now that the chrome leaves on a downward
        // scroll, the band is the feed's again and the gradient is the point: a
        // wash, not a cut, and no hairline anywhere (Jesse: "no clean cut white
        // line, a fade gradient like Instagram").
        .scrollEdgeEffectStyle(.soft, for: .top)
        // PROBE (2026-09-24) of the scheme flip: mid-feed the bar's ink, status bar
        // and paper backdrop all rendered dark over photos. Hide the edge effect
        // while the bar (and its backdrop) is showing; the soft fade stays for
        // while the bar is away. If the flip survives this, it goes to Jesse (Q4).
        .scrollEdgeEffectHidden(!(forcedCollapse || chromeHidden), for: .top)
        .scrollPosition($feedPosition)
        .refreshable {
            if controller.briefing.needsRefresh {
                await controller.refreshBriefing()
            }

            feedClock = Date()

            revealAnimated = false
            revealed = false
            contentRevealed = false
            await Task.yield()
            revealAnimated = true
            revealed = true
            contentRevealed = true
            refreshReplay += 1
        }
        .tint(.clear)
        .background(Hue.paper)
        .sheet(item: $route) { route in
            if let destination = route.destination { destination }
        }
        .task {
            name = Interests.displayName ?? firstNameFromEmail(auth.email)
            controller.updateContext(context)
            await controller.load()

            if let payload = controller.briefing.payload, payload.status == .published {
                context.analytics.recordOnce(
                    BriefingEventName.briefingOpen,
                    key: payload.briefingDate,
                    payload: [
                        "featured_count": payload.featured.count,
                        "has_touch": payload.touch != nil,
                        "from_cache": !controller.briefing.isRefreshing,
                    ],
                    auth: auth
                )
            }
        }
        .onAppear {
            if forcedScroll { feedPosition.scrollTo(y: Self.forcedScrollY) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-feed-scroll-sweep") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.linear(duration: 4)) {
                        feedPosition.scrollTo(y: 200)
                    }
                }
            }
            #endif
            revealed = true
            if controller.briefing.hasLoaded { contentRevealed = true }
            #if DEBUG
            if FrameGapLog.enabled { FrameGapLog.shared.start() }
            #endif
        }
        // Gated on the briefing having FINISHED, not on it having SUCCEEDED.
        //
        // `contentRevealed` used to key off `payload != nil`. But the modules below
        // the almanac are `springReveal`'d on it, and springReveal hides with
        // opacity/scale/offset — all non-layout-affecting. So when the briefing RPC
        // failed (outage, expired token, or simply `-briefing-preview` without
        // `-briefing-state`, which makes a live authenticated call), `payload`
        // stayed nil, the flag never flipped, and Your Day / Town Notes / For You
        // rendered INVISIBLE WHILE STILL RESERVING THEIR FULL HEIGHT — a column of
        // blank gaps holding content those modules had successfully fetched on
        // their own. They own their fetches (`ownsFetch`), so the briefing's fate
        // was never theirs to share.
        //
        // `hasLoaded` is set on both the success and the failure path, so the
        // self-fetching modules now reveal either way.
        .onChange(of: controller.briefing.hasLoaded) { _, loaded in
            if loaded { contentRevealed = true }
        }
        .onChange(of: profileShown) { _, shown in
            guard !shown else { return }
            name = Interests.displayName ?? firstNameFromEmail(auth.email)
            controller.updateContext(context)
        }
    }
}

/// Generic observation host. It knows only the registry contract: visible modules
/// render their erased view. No module ids, branches, spacing, or module constants
/// belong here.
private struct FeedModuleColumn: View {
    @ObservedObject var registry: FeedRegistry
    @ObservedObject var briefing: BriefingModel
    let context: FeedModuleContext

    var body: some View {
        #if DEBUG
        let _ = FeedRenderLog.enabled ? Self._printChanges() : ()
        #endif
        // The registry is EMPTY today, so this column renders nothing and the Town
        // tab has no wait to stand in for — which is why no skeleton is mounted here.
        // Whoever ships the first briefing module gates it on `briefing.hasLoaded` and
        // renders `HappeningSoonSkeleton` / `DailyTouchSkeleton` / `SpotlightSkeleton`
        // (BriefingSkeletons.swift) underneath. They are written and screenshotted via
        // `-show-skeletons`; they have simply never had a live caller.
        return VStack(spacing: 0) {
            ForEach(registry.visibleModules(in: context), id: \.id) { module in
                module.makeView(context)
            }
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
    static let enabled = ProcessInfo.processInfo.arguments.contains("-feed-render-log")
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
        ProcessInfo.processInfo.arguments.contains("-frame-gap-log")
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
