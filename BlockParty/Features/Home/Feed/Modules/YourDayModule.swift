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

    /// The rows behind `items`, for anything that still takes an `UpcomingEvent`.
    /// Derived, never stored twice — `items` is the single source of truth.
    private var events: [UpcomingEvent] { items.map(\.event) }

    private enum LoadState {
        case loading
        case ready
        case failed
    }

    init(briefing _: BriefingModel) {}

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
            items = []
            loadState = .ready
            return
        }

        do {
            let candidates = try await CommunityAPI(auth: ctx.auth).getTownDayCandidates(now: now)
            items = YourDayLogic.dayItems(from: candidates, now: now)
            loadState = .ready
        } catch {
            loadState = .failed
        }
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                YourDaySkeleton()
                    .padding(.horizontal, YourDayRailMetrics.pageMargin)
                    .padding(.top, 22)
            )

        case .failed:
            return AnyView(
                FeedUnavailableCard(title: FeedStateCopy.yourDayUnavailable) {
                    Task { await self.load(ctx) }
                }
                .padding(.horizontal, YourDayRailMetrics.pageMargin)
                .padding(.top, 22)
            )

        case .ready:
            return AnyView(
                YourDaySection(
                    items: items,
                    suggestion: suggestion,
                    townCount: townCount,
                    dates: ctx.dates,
                    // Where a tap lands when no day-sheet host is mounted above
                    // this feed — the galleries and the module previews. The real
                    // app always has one (see `MainTabsView`), so these are the
                    // fallbacks, not the route.
                    onOpenDayWithoutHost: { ctx.navigate(.event($0.event)) },
                    onAddWithoutHost: { ctx.navigate(.feedDiscovery) },
                    onExplore: { ctx.navigate(.feedDiscovery) }
                )
                .padding(.top, 22)
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

/// The section's heading. Shared with the skeleton so the two are the same object
/// and the title cannot move when content swaps in.
private struct YourDayHeading: View {
    var body: some View {
        Text(YourDayRailCopy.header)
            .font(.displaySemi(YourDayRailMetrics.headerSize))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Resolves which namespace the rail draws in, and where a tap goes.
///
/// The morph needs the rail card and the timeline row to share ONE namespace, and
/// the only view that is an ancestor of both is `DayScheduleHost` — mounted on
/// `MainTabsView`, above the tab bar, because a full-height day sheet under a
/// floating tab bar would have its "Add to today" button covered. So the namespace
/// and the presenter arrive through the environment. Neither is guaranteed: the
/// galleries and previews mount this rail with no host above it, and there the
/// local namespace keeps the code valid and the fallback routes keep it alive.
private struct YourDaySection: View {
    let items: [DayItem]
    let suggestion: DayItem?
    let townCount: Int?
    let dates: any DateProviding
    let onOpenDayWithoutHost: (DayItem) -> Void
    let onAddWithoutHost: () -> Void
    let onExplore: () -> Void

    @Environment(\.daySchedule) private var host
    @Environment(\.dayScheduleNamespace) private var hostNamespace
    @Namespace private var localNamespace

    var body: some View {
        if let host, let hostNamespace {
            YourDayHostedRail(
                host: host,
                namespace: hostNamespace,
                items: items,
                suggestion: suggestion,
                townCount: townCount,
                dates: dates,
                onExplore: onExplore
            )
        } else {
            YourDayRail(
                items: items,
                suggestion: suggestion,
                townCount: townCount,
                namespace: localNamespace,
                onOpenDay: onOpenDayWithoutHost,
                onAdd: onAddWithoutHost,
                onExplore: onExplore
            )
        }
    }
}

/// The rail with a day-sheet host above it: a card tap opens the day on that card,
/// the add tile opens it on the bottom "Add to today" button.
///
/// Split out purely so `host` can be an `@ObservedObject` — the rail has to re-read
/// `isOpen` to hand its half of the matched pair over to the sheet and take it back
/// on dismissal, and an `@Environment` value does not publish.
private struct YourDayHostedRail: View {
    @ObservedObject var host: DaySchedulePresentation
    let namespace: Namespace.ID
    let items: [DayItem]
    let suggestion: DayItem?
    let townCount: Int?
    let dates: any DateProviding
    let onExplore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        YourDayRail(
            items: items,
            suggestion: suggestion,
            townCount: townCount,
            namespace: namespace,
            morphs: !reduceMotion && !host.isOpen,
            onOpenDay: { open(.item($0.id)) },
            onAdd: { open(.callToAction) },
            onExplore: onExplore
        )
        .modifier(DayScheduleDemoOpener(items: items, open: open))
    }

    /// One transaction: the sheet arrives, the rail lets go of the matched ids, and
    /// the accent bar flies out of the tapped card into the timeline row.
    private func open(_ anchor: DayScheduleAnchor) {
        withAnimation(reduceMotion ? DayScheduleMotion.reduced : DayScheduleMotion.open) {
            host.open(DayScheduleRequest(items: items, anchor: anchor, dates: dates))
        }
    }
}

/// The heading is real; only the cards are placeholders. Their widths, height,
/// radius and gap are the rail's own (236 × 116, 12pt, 16pt radius), and the
/// trailing 100pt block is the add tile, so nothing shifts on swap-in.
private struct YourDaySkeleton: View {
    var body: some View {
        FeedSkeletonSection(spacing: YourDayRailMetrics.headerToRail) {
            YourDayHeading()
        } content: {
            FeedSkeletonStrip(
                widths: [YourDayRailMetrics.cardWidth,
                         YourDayRailMetrics.cardWidth,
                         YourDayRailMetrics.addTileWidth],
                height: YourDayRailMetrics.cardHeight
            )
        }
    }
}

// The bespoke "Your day couldn't load." card was replaced by the shared
// `FeedUnavailableCard`, so the three self-fetching modules fail the same way.
