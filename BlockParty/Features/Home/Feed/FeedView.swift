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
    var onMenu: (() -> Void)?
    var menuOpen = false
    var profileShown = false
    /// Where a route that leaves the feed goes. The shell (`MainTabsView`) owns tab
    /// selection, so it — not this screen — fulfils an Activities route. Nil where
    /// no shell is mounted above the feed (the DEBUG galleries and module previews),
    /// and there the route is simply dropped rather than faked with a sheet.
    var onOpenActivities: ((ActivitiesRequest) -> Void)?

    @StateObject private var controller: FeedController
    @StateObject private var headerProfile: TodayHeaderProfileModel
    @State private var name: String?
    @State private var route: FeedRoute?
    @State private var revealed = false
    @State private var revealAnimated = true
    @State private var contentRevealed = false
    @State private var refreshReplay = 0
    @State private var showsHairline = false

    init(
        auth: AuthStore,
        onMenu: (() -> Void)? = nil,
        menuOpen: Bool = false,
        profileShown: Bool = false,
        onOpenActivities: ((ActivitiesRequest) -> Void)? = nil
    ) {
        self.auth = auth
        self.onMenu = onMenu
        self.menuOpen = menuOpen
        self.profileShown = profileShown
        self.onOpenActivities = onOpenActivities

        let briefing = BriefingModel()
        let context = FeedModuleContext(
            auth: auth,
            briefing: briefing,
            displayName: nil,
            navigate: { _ in }
        )
        _controller = StateObject(wrappedValue: FeedController(context: context))
        _headerProfile = StateObject(wrappedValue: TodayHeaderProfileModel(auth: auth))
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

    /// One place a module's route is fulfilled. A route that leaves the feed goes up
    /// to the shell, which owns tab selection; everything else is a sheet over the
    /// feed. Splitting here — rather than inside a module — keeps every module's one
    /// way out (`ctx.navigate`) the same.
    private func navigate(_ route: FeedRoute) {
        if let request = route.activitiesRequest {
            onOpenActivities?(request)
        } else {
            self.route = route
        }
    }

    private var forcedHairline: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-header-hairline")
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            TodayTopBar(
                onMenu: onMenu,
                menuOpen: menuOpen,
                showsHairline: showsHairline || forcedHairline,
                avatarUrl: headerProfile.avatarUrl
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    FeedModuleColumn(
                        registry: controller.registry,
                        briefing: controller.briefing,
                        context: context
                    )

                    Color.clear.frame(height: 96)
                }
                .tint(Hue.ink)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                TodayHeader.showsHairline(
                    contentOffsetY: geometry.contentOffset.y + geometry.contentInsets.top
                )
            } action: { _, shows in
                showsHairline = shows
            }
            .refreshable {
                if controller.briefing.needsRefresh {
                    await controller.refreshBriefing()
                }

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
        }
        .background(Hue.paper)
        // Only sheet-presenting routes ever reach this binding — `navigate(_:)`
        // intercepts the ones the shell fulfils, so the optional cannot be nil here.
        .sheet(item: $route) { route in
            if let destination = route.destination { destination }
        }
        .task {
            async let profileRefresh: Void = headerProfile.refresh()
            name = Interests.displayName ?? firstNameFromEmail(auth.email)
            controller.updateContext(context)
            await controller.load()
            await profileRefresh

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
        .tabReady(controller.briefing.hasLoaded)
        .onAppear {
            revealed = true
            if controller.briefing.hasLoaded { contentRevealed = true }
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
            Task { await headerProfile.refresh() }
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
        VStack(spacing: 0) {
            ForEach(registry.visibleModules(in: context), id: \.id) { module in
                module.makeView(context)
            }
        }
    }
}
