//
//  HomeView.swift
//  Block Party — Today. Masthead, almanac, and the town's social feed.
//

import SwiftUI

struct HomeView: View {
    var onCompose: (() -> Void)?
    /// The single top-right button → the town menu drawer (a corner "genie"
    /// reveal owned by MainTabsView so it can sit above the tab bar).
    var onMenu: (() -> Void)?
    /// Mirrors the drawer's presented state so the masthead's dots restore on close.
    var menuOpen: Bool = false
    /// Mirrors the profile sheet's presented state so the greeting refreshes when
    /// it closes (a name edit writes Interests.displayName synchronously).
    var profileShown: Bool = false
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = HomeModel()

    /// Drives the masthead/Almanac spring entrance. Feed cards own their separate,
    /// first-load-only reveal in TodayFeedView.
    @State private var revealed = false
    /// False only during a refresh collapse, so the reset is instant (see refresh).
    @State private var revealAnimated = true
    /// Bumped on each pull-to-refresh so the Almanac re-writes itself in sync with the
    /// spring-back (the first open writes on its own — see AlmanacSection).
    @State private var almanacReplay = 0
    @State private var feedRefreshing = false

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var socialAPI: SocialAPI { SocialAPI(auth: auth) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    Masthead(onMenu: onMenu, menuOpen: menuOpen)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .springReveal(0, revealed: revealed, animated: revealAnimated)

                    // The daily almanac — a warm time-of-day greeting over the read-of-
                    // the-day, in a white card with the coral accent border. On the first
                    // open of each launch (and on pull-to-refresh) it writes itself in
                    // (greeting types, read follows).
                    AlmanacSection(name: model.name, replay: almanacReplay)
                        .padding(.horizontal, 18)
                        .springReveal(2, revealed: revealed, animated: revealAnimated)
                }

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
                        // Phase 5 (staged): wire onSave → SocialAPI.saveEvent/unsaveEvent once event_saves is applied
                        model.setFeedSaved(eventID: eventID, saved: saved)
                    }
                )

                Color.clear.frame(height: 96)
            }
            .tint(Hue.ink)
        }
        .background(Hue.paper)
        .refreshable {
            feedRefreshing = true
            await model.loadFeed(socialAPI)
            feedRefreshing = false

            // Collapse instantly after the refreshed data arrives, then spring the
            // masthead and Almanac back in together. Feed cards do not replay.
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
