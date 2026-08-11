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

    /// Who says a thing is done. The session store, so the rail and the day sheet
    /// give the same answer and a tick outlives the app.
    private let completion: DayCompletionStore

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

        // Stored completions, AFTER the rail is ready. Best-effort and separate
        // from the fetch above: a completions read that fails must not blank a day
        // we already have, and a day that failed to load has no ids to ask about.
        await completion.refresh(for: items.map(\.id))
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                YourDaySkeleton()
                    .padding(.horizontal, YourDayRailMetrics.pageMargin)
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
                YourDaySection(
                    items: items,
                    suggestion: suggestion,
                    townCount: townCount,
                    dates: ctx.dates,
                    completion: completion,
                    // Where a CARD tap lands when no day-sheet host is mounted above
                    // this feed — the galleries and the module previews. The real
                    // app always has one (see `MainTabsView`), so this is the
                    // fallback, not the route.
                    onOpenDayWithoutHost: { ctx.navigate(.event($0.event)) },
                    // The plus tile and the zero-state card, which are the same
                    // invitation twice: go and see what the town has posted for
                    // today. Not host-dependent — a browse is a browse whether or
                    // not a day sheet could have been opened.
                    onBrowseToday: { ctx.navigate(.activities(.happeningToday)) }
                )
                .padding(.top, YourDayRailMetrics.sectionTop)
                .springReveal(
                    1,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
                .modifier(YourDayDebugRouteOpener(events: events, navigate: ctx.navigate))
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

/// Fires one of the rail's routes on appear. There is no tap automation in this
/// simulator setup, so a destination only reachable by tapping is otherwise
/// unverifiable — these drive the REAL routes, through the real navigate closure.
///
/// * `-yourday-open-detail [index]` opens an item's detail sheet.
/// * `-yourday-open-explore` fires the zero-state card's route (pair it with
///   `-yourday-count 0`), which switches to the Activities tab on today's events.
///
/// No-op without a flag, and the whole modifier compiles to a pass-through in
/// Release.
private struct YourDayDebugRouteOpener: ViewModifier {
    let events: [UpcomingEvent]
    let navigate: (FeedRoute) -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            let args = ProcessInfo.processInfo.arguments

            if args.contains("-yourday-open-explore") {
                // Long enough for the reveal to settle, so the screenshot before it
                // is the resting zero state rather than a mid-spring frame.
                try? await Task.sleep(for: .milliseconds(1200))
                navigate(.activities(.happeningToday))
                return
            }

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
            .font(.dayDisplaySemi(YourDayRailMetrics.headerSize))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Resolves which namespace the rail draws in, and where a tap goes.
///
/// TWO TAPS, TWO DESTINATIONS, and only one of them cares about the host: a CARD
/// opens the day sheet ("what you have planned, in more depth"), while the plus
/// tile and the zero-state card leave for today's postings in Activities. The plus
/// used to open the sheet scrolled to its bottom CTA; it no longer opens the sheet
/// at all.
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
    /// Observed, not just read: a tick in the day sheet has to dim the rail card
    /// behind it, and un-dim it when the neighbour changes their mind.
    @ObservedObject var completion: DayCompletionStore
    let onOpenDayWithoutHost: (DayItem) -> Void
    /// The plus tile AND the zero-state card. One closure because they are one
    /// destination — today's postings — and nothing about it depends on a host.
    let onBrowseToday: () -> Void

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
                isComplete: completion.isComplete,
                onBrowseToday: onBrowseToday
            )
        } else {
            YourDayRail(
                items: items,
                isComplete: completion.isComplete,
                suggestion: suggestion,
                townCount: townCount,
                namespace: localNamespace,
                onOpenDay: onOpenDayWithoutHost,
                onAdd: onBrowseToday,
                onExplore: onBrowseToday
            )
        }
    }
}

/// The rail with a day-sheet host above it. A card tap opens the day on that card;
/// the plus tile does not touch the host at all (see the seam below), so this view
/// only ever opens on an item.
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
    let isComplete: (DayItem) -> Bool
    let onBrowseToday: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        YourDayRail(
            items: items,
            isComplete: isComplete,
            suggestion: suggestion,
            townCount: townCount,
            namespace: namespace,
            morphs: !reduceMotion && !host.isOpen,
            onOpenDay: { open(.item($0.id)) },
            // THE TWO TAPS LAND IN DIFFERENT PLACES, deliberately. A card opens
            // the day sheet — what you have planned, in depth. The plus does NOT:
            // it goes straight to today's postings in Activities, because "add
            // something" is a question about the town's day, not about yours.
            //
            // It used to open the sheet scrolled to its bottom CTA (the original
            // spec's §3). That put a browse action behind a read surface: you asked
            // for something to do and got your own empty day first. The sheet's own
            // sticky "+ Add to today" still opens the composer — that one is a
            // different question, asked from inside the day.
            onAdd: onBrowseToday,
            onExplore: onBrowseToday
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
