//
//  HomeView.swift
//  Block Party — Today. The fixed top bar, almanac, and the town's social feed.
//
//  The bar (`TodayTopBar`) is pinned ABOVE the scroll view rather than living inside
//  it, so the town name and the menu button stay put while the feed moves. The bar's
//  bottom hairline is driven from here off the scroll geometry.
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
    @StateObject private var model = HomeModel()

    /// Drives the Almanac spring entrance. Feed cards own their separate,
    /// first-load-only reveal in TodayFeedView; the top bar is chrome and never
    /// reveals — it is simply there.
    @State private var revealed = false
    /// False only during a refresh collapse, so the reset is instant (see refresh).
    @State private var revealAnimated = true
    /// Bumped on each pull-to-refresh so the Almanac re-writes itself in sync with the
    /// spring-back (the first open writes on its own — see AlmanacSection).
    @State private var almanacReplay = 0
    @State private var feedRefreshing = false
    /// Raises the top bar's bottom hairline once the feed has moved beneath it.
    @State private var showsHairline = false

    /// DEBUG-only: `-header-hairline` forces the bar's hairline up so the scrolled
    /// chrome can be screenshotted headlessly. There is no scroll automation in this
    /// setup, and an empty Today tab has no scrollable content to drag anyway, so the
    /// state is otherwise unreachable in a capture. The 8pt threshold itself is
    /// covered by `TodayHeaderTests`.
    private var forcedHairline: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-header-hairline")
        #else
        return false
        #endif
    }

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var socialAPI: SocialAPI { SocialAPI(auth: auth) }

    var body: some View {
        VStack(spacing: 0) {
            // Chrome, not content: fixed above the scroll view, present immediately,
            // and deliberately outside the spring entrance below.
            TodayTopBar(onMenu: onMenu, menuOpen: menuOpen,
                        showsHairline: showsHairline || forcedHairline)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // The daily almanac — a warm time-of-day greeting over the read-of-
                    // the-day, in a white card with the coral accent border. On the first
                    // open of each launch (and on pull-to-refresh) it writes itself in
                    // (greeting types, read follows).
                    AlmanacSection(name: model.name, replay: almanacReplay)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        // Index 0: the almanac is the FIRST thing in the cascade now.
                        // It was 2 when the masthead led the scroll content; the masthead
                        // is chrome today (`TodayTopBar`, outside the reveal), so a
                        // non-zero index would just be a dead beat before anything moves.
                        .springReveal(0, revealed: revealed, animated: revealAnimated)

                    // Utility Row — glanceable town info (weather · garbage · roads ·
                    // library), full-bleed horizontal scroll, below the almanac.
                    UtilityRowView()
                        .padding(.top, 18)

                    TodayFeedView(
                        sections: model.feedSections,
                        isLoading: model.loading && !model.feedLoaded,
                        isRefreshing: feedRefreshing,
                        onCompose: onCompose,
                        onLike: { eventID, liked in
                            Task { await model.setFeedLike(socialAPI, eventID: eventID, liked: liked) }
                        },
                        onLoadComments: { eventID in
                            try await model.feedComments(socialAPI, eventID: eventID)
                        },
                        onComment: { eventID, body in
                            try await model.addFeedComment(socialAPI, eventID: eventID, body: body)
                        },
                        onShare: share,
                        onJoin: { eventID, joined in
                            Task { await model.setFeedJoined(api, eventID: eventID, joined: joined) }
                        },
                        onSave: { eventID, saved in
                            Task { await model.setFeedSaved(socialAPI, eventID: eventID, saved: saved) }
                        }
                    )

                    Color.clear.frame(height: 96)
                }
                .tint(Hue.ink)
            }
            // `contentOffset.y` is NOT zero at rest: a scroll view with a top content
            // inset rests at `-contentInsets.top`. Adding the inset back converts the
            // reading into "distance scrolled from rest" — the positive-at-rest-zero
            // convention `TodayHeader.showsHairline` is written against. Feeding the raw
            // offset in would hold the hairline back until a whole inset height had
            // been scrolled.
            .onScrollGeometryChange(for: Bool.self) { geo in
                TodayHeader.showsHairline(contentOffsetY: geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, shows in
                showsHairline = shows
            }
            .refreshable {
                feedRefreshing = true
                await model.loadFeed(socialAPI)
                feedRefreshing = false

                // Collapse instantly after the refreshed data arrives, then spring the
                // Almanac back in. Feed cards do not replay.
                revealAnimated = false
                revealed = false
                await Task.yield()
                revealAnimated = true
                revealed = true
                almanacReplay += 1
            }
            // SwiftUI does not expose the system refresh control directly. Clear its
            // tint and overlay TodayFeedView's block spinner in the feed's top padding.
            .tint(.clear)
        }
        .background(Hue.paper)
        .task { await loadHome() }
        // Cover the tab with the loading screen until Today's data is in.
        .tabReady(model.loaded)
        // Springs in when Today first appears and each time it's returned to.
        .onAppear { revealed = true }
        // A name edit in the profile writes Interests.displayName synchronously;
        // pick it up when the genie closes so the greeting stays in sync.
        .onChange(of: profileShown) { _, shown in
            if !shown { model.name = Interests.displayName ?? firstNameFromEmail(auth.email) }
        }
    }

    private func loadHome() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-community-feed-self-check") {
            CommunityFeedBucketerSelfCheck.run()
        }
        if arguments.contains("-community-feed-preview") {
            model.loadCommunityFeedPreview()
            return
        }
        #endif
        await model.load(api, socialAPI: socialAPI)
    }

    private func share(_ item: FeedCardItem) {
        ShareCenter.shared.present(
            .event(
                title: item.title,
                dateLabel: item.dateChip,
                time: item.shareTime,
                location: item.shareLocation
            )
        )
    }
}

/// Shimmering placeholder for the "Today" section — mirrors the real header
/// ("Today" + count) and a couple of event rows, so nothing shifts when the
/// events land. One light sweep travels across the whole group.
struct TodayLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonBlock(cornerRadius: 6).frame(width: 84, height: 22)
                Spacer()
                SkeletonBlock(cornerRadius: 6).frame(width: 52, height: 12)
            }
            eventRowShell
            eventRowShell
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading today's events")
    }

    private var eventRowShell: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(cornerRadius: 5).frame(width: 60, height: 11)   // time
                SkeletonBlock(cornerRadius: 6).frame(width: 178, height: 15)  // title
                SkeletonBlock(cornerRadius: 5).frame(width: 108, height: 11)  // club
                SkeletonBlock(cornerRadius: 5).frame(width: 140, height: 11)  // location
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                SkeletonBlock(cornerRadius: 14).frame(width: 74, height: 28)  // RSVP capsule
                SkeletonBlock(cornerRadius: 5).frame(width: 46, height: 10)   // "N going"
            }
        }
        .blockPartyCard(padding: 16)
    }
}
