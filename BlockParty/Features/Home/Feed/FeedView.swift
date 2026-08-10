//
//  FeedView.swift
//  Block Party — the Today tab body, rendered entirely from FeedRegistry.
//

import SwiftUI

struct FeedView: View {
    let auth: AuthStore
    var onMenu: (() -> Void)?
    var menuOpen = false
    var profileShown = false

    @StateObject private var controller: FeedController
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
        profileShown: Bool = false
    ) {
        self.auth = auth
        self.onMenu = onMenu
        self.menuOpen = menuOpen
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
            navigate: { route = $0 },
            revealed: revealed,
            contentRevealed: contentRevealed,
            revealAnimated: revealAnimated,
            refreshReplay: refreshReplay
        )
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
                showsHairline: showsHairline || forcedHairline
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
        .sheet(item: $route) { route in
            route.destination
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
        .tabReady(controller.briefing.hasLoaded)
        .onAppear {
            revealed = true
            if controller.briefing.payload != nil { contentRevealed = true }
        }
        .onChange(of: controller.briefing.payload == nil) { _, isEmpty in
            if !isEmpty { contentRevealed = true }
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
        VStack(spacing: 0) {
            ForEach(registry.visibleModules(in: context), id: \.id) { module in
                module.makeView(context)
            }
        }
    }
}
