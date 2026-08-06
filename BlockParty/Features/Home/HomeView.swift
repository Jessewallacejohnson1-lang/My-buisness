//
//  HomeView.swift
//  Block Party — Today. The daily town briefing.
//
//  The bar (`TodayTopBar`) is pinned ABOVE the scroll view rather than living inside
//  it, so the town name and the menu button stay put while the briefing moves. The
//  bar's bottom hairline is driven from here off the scroll geometry.
//
//  The screen's composition is `BriefingModuleID.order` — one array, looped. It is
//  deliberately FINITE: it ends at the caught-up footer rather than scrolling on,
//  which is the whole point of a briefing over a feed.
//
//  One round trip. `BriefingModel` loads the entire screen from a single RPC and
//  renders from disk cache first, so a briefing you have already downloaded opens
//  instantly and still opens with no network at all.
//

import SwiftUI

struct HomeView: View {
    var onCompose: (() -> Void)?
    /// The single top-right button → the town menu drawer (a corner "genie"
    /// reveal owned by MainTabsView so it can sit above the tab bar).
    var onMenu: (() -> Void)?
    /// Mirrors the drawer's presented state so the top bar's dots restore on close.
    var menuOpen: Bool = false
    /// Mirrors the profile sheet's presented state so the greeting refreshes when
    /// it closes (a name edit writes Interests.displayName synchronously).
    var profileShown: Bool = false
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var briefing = BriefingModel()

    /// The neighbor's first name for the almanac greeting. Read from the local
    /// mirror rather than fetched — it never needed a round trip.
    @State private var name: String?

    /// Drives the module spring entrance. The top bar is chrome and never
    /// reveals — it is simply there.
    @State private var revealed = false
    /// False only during a refresh collapse, so the reset is instant (see refresh).
    @State private var revealAnimated = true
    /// Bumped on each pull-to-refresh so the Almanac re-writes itself in sync with the
    /// spring-back (the first open writes on its own — see AlmanacSection).
    @State private var almanacReplay = 0
    /// Raises the top bar's bottom hairline once the briefing has moved beneath it.
    @State private var showsHairline = false

    /// DEBUG-only: `-header-hairline` forces the bar's hairline up so the scrolled
    /// chrome can be screenshotted headlessly. There is no scroll automation in this
    /// setup, so the state is otherwise unreachable in a capture. The 8pt threshold
    /// itself is covered by `TodayHeaderTests`.
    private var forcedHairline: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-header-hairline")
        #else
        return false
        #endif
    }

    private var briefingAPI: BriefingAPI { BriefingAPI(auth: auth) }
    private var communityAPI: CommunityAPI { CommunityAPI(auth: auth) }
    private var analytics: BriefingAnalytics { .shared }

    var body: some View {
        VStack(spacing: 0) {
            // Chrome, not content: fixed above the scroll view, present immediately,
            // and deliberately outside the spring entrance below.
            TodayTopBar(onMenu: onMenu, menuOpen: menuOpen,
                        showsHairline: showsHairline || forcedHairline)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(BriefingModuleID.order, id: \.self) { id in
                        module(id)
                    }

                    Color.clear.frame(height: 96)
                }
                .tint(Hue.ink)
            }
            // `contentOffset.y` is NOT zero at rest: a scroll view with a top content
            // inset rests at `-contentInsets.top`. Adding the inset back converts the
            // reading into "distance scrolled from rest" — the positive-at-rest-zero
            // convention `TodayHeader.showsHairline` is written against.
            .onScrollGeometryChange(for: Bool.self) { geo in
                TodayHeader.showsHairline(contentOffsetY: geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, shows in
                showsHairline = shows
            }
            .refreshable {
                // Refresh-once-daily. If today's briefing is already on screen,
                // pulling does NOT hit the network — the spring replay below IS the
                // acknowledgement. No spinner theatre, and no toast repeating
                // "new briefing at 6 AM" when the footer a thumb's width away
                // already says exactly that.
                if briefing.needsRefresh {
                    await briefing.refresh(briefingAPI)
                }

                // Collapse instantly, then spring the modules back in.
                revealAnimated = false
                revealed = false
                await Task.yield()
                revealAnimated = true
                revealed = true
                almanacReplay += 1
            }
            .tint(.clear)
        }
        .background(Hue.paper)
        .task {
            name = Interests.displayName ?? firstNameFromEmail(auth.email)
            await briefing.load(briefingAPI)
            // The north star: distinct users per day. Once per launch per briefing
            // date, so returning to the tab is not a second open.
            if let payload = briefing.payload, payload.status == .published {
                analytics.recordOnce(
                    BriefingEventName.briefingOpen,
                    key: payload.briefingDate,
                    payload: [
                        "featured_count": payload.featured.count,
                        "has_touch": payload.touch != nil,
                        "from_cache": !briefing.isRefreshing,
                    ],
                    auth: auth
                )
            }
        }
        // Cover the tab with the loading screen until the briefing is in. A cached
        // briefing satisfies this immediately.
        .tabReady(briefing.hasLoaded)
        // Springs in when Today first appears and each time it's returned to.
        .onAppear { revealed = true }
        // A name edit in the profile writes Interests.displayName synchronously;
        // pick it up when the genie closes so the greeting stays in sync.
        .onChange(of: profileShown) { _, shown in
            if !shown { name = Interests.displayName ?? firstNameFromEmail(auth.email) }
        }
    }

    // MARK: - Modules

    /// One case per `BriefingModuleID`. Order is owned by `BriefingModuleID.order`,
    /// not by this switch — adding a module is a constant, an array entry, and a
    /// case here.
    @ViewBuilder
    private func module(_ id: BriefingModuleID) -> some View {
        switch id {
        case .almanac:
            AlmanacSection(
                name: name,
                replay: almanacReplay,
                injectedLine: briefing.payload?.almanac?.line
            )
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .springReveal(0, revealed: revealed, animated: revealAnimated)
            .dwell(seconds: 3) {
                analytics.record(
                    BriefingEventName.almanacDwell,
                    payload: ["source": briefing.payload?.almanac?.source ?? "unknown"],
                    auth: auth
                )
            }

        case .utility:
            // Owns its own loading, caching, realtime AND entrance cascade
            // (`UtilityRowEntrance`), so it is deliberately NOT wrapped in the
            // module reveal — that would move the row twice.
            UtilityRowView()
                .padding(.top, 18)

        case .happeningSoon:
            if let payload = briefing.payload {
                HappeningSoonSection(
                    events: payload.featured,
                    fallback: payload.featuredFallback,
                    onRsvp: { event, going in
                        Task {
                            let landed = await briefing.setRsvp(communityAPI, event: event, going: going)
                            // Only a write that actually persisted counts.
                            guard landed, going else { return }
                            analytics.record(
                                BriefingEventName.rsvpFromHome,
                                payload: ["event_id": event.id, "rank": event.rank],
                                auth: auth
                            )
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(1, revealed: revealed, animated: revealAnimated)
            } else if showsSkeletons {
                HappeningSoonSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            } else if briefing.loadFailed {
                // A cold start with no connection used to render the header, the
                // almanac, the utility row, and then nothing at all — no message,
                // no retry. Silence reads as a broken app.
                BriefingUnavailableCard {
                    Task { await briefing.refresh(briefingAPI) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            }

        case .dailyTouch:
            if let touch = briefing.payload?.touch {
                DailyTouchCard(
                    touch: touch,
                    onVote: { index in
                        Task {
                            let landed = await briefing.vote(briefingAPI, optionIndex: index)
                            guard landed else { return }
                            analytics.record(
                                BriefingEventName.touchVote,
                                payload: ["touch_id": touch.id, "option_idx": index],
                                auth: auth
                            )
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(2, revealed: revealed, animated: revealAnimated)
            } else if showsSkeletons {
                DailyTouchSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            }

        case .spotlight:
            if let spotlight = briefing.payload?.spotlight {
                SpotlightCard(spotlight: spotlight)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .springReveal(3, revealed: revealed, animated: revealAnimated)
            } else if showsSkeletons {
                SpotlightSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            }

        case .caughtUp:
            if let payload = briefing.payload {
                CaughtUpFooter(
                    caughtUp: payload.caughtUp,
                    briefingDateLabel: BriefingDate.eyebrow(for: payload.briefingDate) ?? "",
                    briefingDate: payload.briefingDate
                )
                .padding(.horizontal, 18)
                .padding(.top, 34)
                .springReveal(4, revealed: revealed, animated: revealAnimated)
                .dwell(seconds: 1) {
                    analytics.recordOnce(
                        BriefingEventName.caughtUpReached,
                        key: payload.briefingDate,
                        auth: auth
                    )
                }
            }

        default:
            // An id served or persisted by a newer build. Skip it rather than
            // failing the screen.
            EmptyView()
        }
    }

    /// Placeholders belong to a genuinely cold start only. Once a briefing has been
    /// cached there is always something real to render, and a shimmer in front of
    /// content we already have would be theatre.
    private var showsSkeletons: Bool {
        briefing.payload == nil && !briefing.loadFailed
    }
}
