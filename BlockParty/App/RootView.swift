//
//  RootView.swift
//  Block Party — auth gate over the tab shell. Signed-out → Login; signed-in → tabs.
//

import SwiftUI

enum Tab: Int, CaseIterable, Identifiable {
    case home, activities, calendar, map
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home:       return "Today"
        case .activities: return "Activities"
        case .calendar:   return "Calendar"
        case .map:        return "Map"
        }
    }

    var symbol: String {
        switch self {
        case .home:       return "house"
        case .activities: return "square.grid.2x2"
        case .calendar:   return "calendar"
        case .map:        return "map"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    /// Set by the wizard's onDone (or a remote onboarded stamp) for the *current*
    /// session only. Onboarding-need is otherwise derived per-user from Interests,
    /// so signing out and into a different account re-evaluates from scratch.
    @State private var onboardingDone = false
    /// The user id we've already hydrated for. Reset-on-identity-change guard so a
    /// second account on the same device gets its own profile pulled (not the first
    /// account's leftover mirror).
    @State private var hydratedUserId: String?
    /// Set only when the user just finished the wizard, so they land on the Map tab
    /// the finale promised (a returning user still opens to Today).
    @State private var landOnMap = false
    #if DEBUG
    @State private var debugIntroDismissed = false
    #endif

    /// The launch loader plays for at least this long so it's actually seen (boot often
    /// resolves in <200ms).
    ///
    /// Derived from the bloom rather than hardcoded: hold just long enough for the
    /// animation to land, plus a beat to read as landed, and then hand off — the 0.4s
    /// cross-fade below supplies the rest of the dwell. The old flat 1.4s dated from
    /// the looping loader, where there was always a next bloom to show; against a
    /// one-shot it left ~0.4s of dead still frame on every cold start.
    private let loaderMinDuration: Double = LaunchLoaderView.bloomCompletesAt + 0.30
    /// Flipped true once `loaderMinDuration` has elapsed since launch.
    @State private var minLoaderShown = false

    var body: some View {
        Group {
            #if DEBUG
            // `-show-splash` / `-show-map-intro` force a first-run screen on stage
            // so it can be verified headlessly in the simulator. No effect in
            // release or without the flag. The intro's button falls through to the
            // gate, so "Explore the map" is live here too (not a dead preview).
            if ProcessInfo.processInfo.arguments.contains("-show-home") {
                // A deterministic Home route for simulator verification. The Home
                // preview loader supplies local data, so this bypasses auth and
                // onboarding without changing either production flow.
                MainTabsView()
            } else if ProcessInfo.processInfo.arguments.contains("-show-splash") {
                SplashView()
            } else if ProcessInfo.processInfo.arguments.contains("-show-loader") {
                // Preview the Pinterest-style launch loader full-screen (bypassing the
                // auth gate) so its looping bloom can be recorded/screenshotted headlessly.
                LaunchLoaderView()
            } else if ProcessInfo.processInfo.arguments.contains("-show-loading-cover") {
                // Preview the tab loading cover full-screen (bypassing the auth gate)
                // so the rainbow-wave indicator + copy can be verified headlessly.
                TabLoadingCover()
            } else if ProcessInfo.processInfo.arguments.contains("-feed-card-gallery") {
                // Preview the static feed-card states full-screen (bypassing the auth
                // gate) so the component can be verified headlessly.
                FeedCardGallery()
            } else if ProcessInfo.processInfo.arguments.contains("-utility-row-preview") {
                // Preview the Today Utility Row full-screen (bypassing the auth gate)
                // so the tiles + tap-expand can be verified headlessly. Weather /
                // garbage / library render live; roads shows its no-session state.
                UtilityRowPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-today-feed-preview")
                        || ProcessInfo.processInfo.arguments.contains("-today-feed-empty")
                        || ProcessInfo.processInfo.arguments.contains("-today-feed-skeleton") {
                // Preview the real Today feed pipeline and its empty/loading variants
                // full-screen, without auth or onboarding.
                TodayFeedPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-show-skeletons") {
                // Preview the per-tab shimmer skeletons (bypassing the auth gate).
                SkeletonGalleryPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-show-map-intro"),
                      !debugIntroDismissed {
                MapIntroView { debugIntroDismissed = true }
            } else if ProcessInfo.processInfo.arguments.contains("-show-onboarding") {
                // Render the onboarding wizard directly (bypassing the auth gate)
                // so any step can be screenshotted headlessly via -onboarding-step.
                OnboardingView { debugIntroDismissed = true }
            } else {
                gate
            }
            #else
            gate
            #endif
        }
    }

    @ViewBuilder
    private var gate: some View {
        // The launch loader plays while the app boots — "coming into the app", the same
        // slot Pinterest fills — and for a short minimum beyond so it's actually seen,
        // then cross-fades to the authed shell / login once auth resolves.
        ZStack {
            if auth.booting || !minLoaderShown {
                LaunchLoaderView()
                    .transition(.opacity)
            } else if auth.isSignedIn {
                authedRoot
                    .task(id: auth.userId) { await hydrateIfNeeded() }
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: auth.booting)
        .animation(.easeInOut(duration: 0.4), value: minLoaderShown)
        .task {
            try? await Task.sleep(for: .seconds(loaderMinDuration))
            minLoaderShown = true
        }
    }

    @ViewBuilder private var authedRoot: some View {
        if needsOnboarding {
            OnboardingView { markOnboarded() }
        } else {
            MainTabsView(startTab: landOnMap ? .map : nil)
        }
    }

    /// Per-user onboarding gate: the current user's own local flag (or a completed
    /// session), never a previous account's.
    private var needsOnboarding: Bool {
        guard let uid = auth.userId else { return false }
        if onboardingDone { return false }
        return !Interests.isOnboarded(uid: uid)
    }

    private func markOnboarded() {
        if let uid = auth.userId { Interests.setOnboarded(uid: uid) }
        landOnMap = true          // the map-intro finale promised the map — keep that promise
        onboardingDone = true
    }

    /// Pull the community profile once per *user*: mirror interests/name locally (so
    /// matching + greetings work offline) and honor a remote onboarded stamp (a
    /// reinstall/new device shouldn't re-run onboarding). Re-runs when the signed-in
    /// identity changes. Silent on failure.
    private func hydrateIfNeeded() async {
        guard let uid = auth.userId else { hydratedUserId = nil; return }   // signed out → allow re-hydrate on next sign-in
        guard hydratedUserId != uid else { return }
        hydratedUserId = uid
        onboardingDone = false   // new identity → re-derive from this user's own state
        let fetched = try? await ProfileAPI(auth: .shared).getMyProfile()
        guard let profile = fetched ?? nil else { return }
        if !profile.interests.isEmpty { Interests.set(profile.interests) }
        if let n = profile.displayName, !n.isEmpty { Interests.displayName = n }
        if profile.onboardedAt != nil {
            Interests.setOnboarded(uid: uid)
            onboardingDone = true   // @State change → re-render into MainTabs
        }
    }
}

/// The authed shell: four tabs + global "+" composer sheet.
struct MainTabsView: View {
    /// A one-shot starting tab (e.g. land on Map straight after onboarding). nil →
    /// the usual default (Today, or a DEBUG `-open-tab` override).
    let startTab: Tab?
    @State private var tab: Tab

    init(startTab: Tab? = nil) {
        self.startTab = startTab
        let resolved = startTab ?? MainTabsView.initialTab()
        _tab = State(initialValue: resolved)
        _mapDetail = State(initialValue: MapPlaceDetail.debugInitialDetail())
        _mapDetailHappenings = State(initialValue: [])
        _showMenu = State(initialValue: resolved == .home && MainTabsView.debugOpenMenu())
        _showProfileSheet = State(initialValue: MainTabsView.debugOpenProfile())
    }

    /// DEBUG-only: `-open-tab map|activities|calendar` launch argument selects
    /// the starting tab, so simulator verification can screenshot any tab
    /// without UI driving. No effect in release builds or without the flag.
    private static func initialTab() -> Tab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-open-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "map":        return .map
            case "activities": return .activities
            case "calendar":   return .calendar
            default:           break
            }
        }
        #endif
        return .home
    }

    /// DEBUG-only: `-open-menu` unfolds the town menu on launch; `-open-profile`
    /// presents the profile sheet. Both for headless screenshots. No effect in
    /// release or without the flag.
    private static func debugOpenMenu() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-open-menu")
        #else
        return false
        #endif
    }
    private static func debugOpenProfile() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-open-profile")
        #else
        return false
        #endif
    }

    @State private var expandedPlace: Place?
    /// The map's one open place, lifted above `SJMapView` so the global tab shell can
    /// morph into its compact detail. The enum carries the real Spot/POI value rather
    /// than copying display fields into a second source of truth.
    @State private var mapDetail: MapPlaceDetail?
    /// Today's real events matched to the selected civic spot by `SJMapView`'s
    /// `MapModel`. Kept beside the lightweight selection instead of bloating its
    /// matched-geometry identity with live data.
    @State private var mapDetailHappenings: [TimelineEvent]
    @State private var composing = false
    /// Readiness of the *current* tab's content, gathered from `TabReadyPreferenceKey`.
    /// Drives the loading cover that hides a not-yet-rendered tab.
    @State private var activeTabReady = false
    /// The compose "+" speed-dial (Explore / Calendar). Owned here so the wash can
    /// recede the tab content and float above the tab bar.
    @State private var speedDialOpen = false
    /// A bubble tap that routes straight into a kind-scoped composer (skips the
    /// AddView chooser).
    @State private var composeKind: AddKind?
    /// The town menu — a corner "genie" drawer out of Home's top-right button.
    /// Owned here (not in HomeView) so it renders above the tab bar.
    @State private var showMenu = false
    /// The profile, now a menu destination (presented as a standard sheet).
    @State private var showProfileSheet = false
    @Namespace private var cardNS
    /// Direction of the last tab change — whether the incoming screen slides in
    /// from the trailing edge (moving *forward* through the tab order) or the
    /// leading edge (moving back). Set in `select(_:)` right before the animation.
    @State private var slideForward = true
    /// Available height for the morphed map detail's relative rich-content cap.
    @State private var containerHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Hue.paper.ignoresSafeArea()

            // The tab content and the tab bar share ONE GlassEffectContainer. On the
            // Map tab the bottom sheet's Liquid Glass sits flush on top of the tab bar,
            // so the two glass shapes MERGE into a single continuous piece — the sheet
            // reads as the tab bar stretching upward. On the other three tabs there's
            // no adjacent glass, so the tab bar looks and behaves exactly as before.
            GlassEffectContainer(spacing: 22) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .home:
                            // Home carries the brand in its own "Block Party" masthead — a
                            // second badge would be redundant, so Home is the one tab without it.
                            HomeView(
                                onCompose: { composing = true },
                                onMenu: { showMenu = true },
                                menuOpen: showMenu,
                                profileShown: showProfileSheet,
                                expandedPlace: $expandedPlace,
                                cardNS: cardNS
                            )
                        // No brand badge on these tabs — the top-right corner carries
                        // screen chrome now (the map's compose "+" etc.).
                        case .activities: ActivitiesView(onCompose: { composing = true })
                        case .calendar:   CalendarView(onCompose: { composing = true })
                        // The map's non-admin "+" opens the speed-dial (admins still get
                        // QuickAddSheet, wired inside SJMapView).
                        case .map:
                            SJMapView(
                                mapDetail: $mapDetail,
                                mapDetailHappenings: $mapDetailHappenings,
                                onCompose: { speedDialOpen = true }
                            )
                        }
                    }
                    // Identity keyed on the tab so a switch is an insertion+removal that
                    // the page transition can animate: the outgoing screen slides off one
                    // edge while the incoming slides in from the other, in lockstep — a
                    // swipe to the new tab rather than a flat swap.
                    .id(tab)
                    .transition(pageTransition)
                    // The speed-dial recedes the content behind its wash (the reference's
                    // "home recedes"); tab bar stays put and is dimmed by the wash.
                    .scaleEffect(reduceMotion ? 1 : (speedDialOpen ? 0.97 : 1))
                    .animation(.spring(response: 0.34, dampingFraction: 0.72), value: speedDialOpen)
                    // Cover a not-yet-loaded tab with the rainbow-wave loading screen until
                    // its content reports ready. Sits above the content but below the tab
                    // bar (a later ZStack sibling), so switching tabs stays possible.
                    .onPreferenceChange(TabReadyPreferenceKey.self) { activeTabReady = $0 }
                    .overlay {
                        TabLoadingHost(isReady: activeTabReady, resetKey: AnyHashable(tab))
                    }

                    BlockPartyTabBar(
                        selection: $tab,
                        mapDetail: $mapDetail,
                        mapDetailHappenings: $mapDetailHappenings,
                        containerHeight: containerHeight,
                        onSelect: select
                    )
                    .zIndex(10)
                }
            }
            // This app is light-only BY CONSTRUCTION — every token in BlockPartyColor is a
            // fixed light hex (paper #FAFAF7, surface #FFFFFF), and the basemap is light-v11
            // recoloured to a fixed greyscale palette. Nothing here has a dark counterpart.
            // `.glassEffect` (the tab bar AND the map sheet) is the one appearance-ADAPTIVE
            // surface in the tree, so under iOS Dark Mode it resolved charcoal while every
            // colour drawn on it stayed light: the sheet's peek line and the tab labels fell
            // to ~1:1 contrast — the primary navigation, unreadable.
            //
            // Declared on the container so BOTH glass surfaces resolve the same way; pinning
            // only the sheet would light it while the tab bar stayed dark, visibly splitting
            // the one continuous piece this container exists to create.
            //
            // This states what the app already assumes rather than adding a behaviour. If real
            // Dark Mode support is ever wanted, removing this line is the START of that work
            // (a full dark ramp + a dark basemap palette), not the whole of it.
            .environment(\.colorScheme, .light)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { newHeight in
            containerHeight = newHeight
        }
        .overlay {
            // Place-expansion overlay
            if expandedPlace != nil {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            expandedPlace = nil
                        }
                    }
            }
            if let place = expandedPlace {
                PlaceExpandedCard(place: place, ns: cardNS) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        expandedPlace = nil
                    }
                }
                .padding(.horizontal, 18)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: expandedPlace?.id)
        // The town menu — Home's top-right ⋮ frosts the whole app into glass and
        // floats a centered showcase pane (its own overlay lane, above the tab bar).
        .overlay {
            GlassShowcaseOverlay(isPresented: $showMenu) { close in
                TownMenuView(onClose: close) { action in
                    close()
                    handleMenu(action)
                }
            }
        }
        // The compose "+" speed-dial — a top-right "+" on Explore / Calendar (coral
        // disc) and the Map (native chrome "+") expands DOWN into context-tailored
        // create bubbles. Explore/Calendar's disc lives in the overlay (replacing the
        // old bottom ComposeFAB); the Map keeps its native "+" and the overlay draws ✕.
        .overlay {
            if !speedDialItems.isEmpty {
                ComposeSpeedDial(items: speedDialItems,
                                 isOpen: $speedDialOpen,
                                 anchor: .topTrailing,
                                 chromeDisc: tab == .map,
                                 showsRestingDisc: tab != .map,
                                 onSelect: routeSpeedDial)
            }
        }
        // Profile is now a menu destination — a standard sheet.
        .sheet(isPresented: $showProfileSheet) { ProfileView() }
        // Global compose sheet — triggered by "Add an event" anywhere in the app
        .sheet(isPresented: $composing) {
            AddView()
        }
        // A bubble tap jumps straight into that kind's form, skipping the chooser.
        .sheet(item: $composeKind) { kind in AddFormView(kind: kind) }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-share-demo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    ShareCenter.shared.present(.event(title: "Farmers Market",
                                                      dateLabel: "Saturday, Jul 12",
                                                      time: "9:00 AM",
                                                      location: "College Ave"))
                }
            }
            // `-open-speeddial` unfolds the compose speed-dial on launch (pair with
            // `-open-tab activities|calendar`) so the reveal can be recorded headlessly.
            // `-speeddial-loop` repeats open↔close a few times so a single long
            // recording is sure to capture a clean transition regardless of boot time.
            if ProcessInfo.processInfo.arguments.contains("-open-speeddial") {
                let loop = ProcessInfo.processInfo.arguments.contains("-speeddial-loop")
                func openIt() { withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) { speedDialOpen = true } }
                func closeIt() { withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) { speedDialOpen = false } }
                func cycle(_ n: Int) {
                    guard n > 0 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { openIt() }
                    guard loop else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { closeIt() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { cycle(n - 1) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { cycle(loop ? 4 : 1) }
            }
        }
        #endif
    }

    /// Route a town-menu tap. The drawer is already collapsing; tab switches swap
    /// instantly behind it (no competing page slide), while sheets/overlays wait
    /// for the collapse to finish so two presentations don't fight.
    private func handleMenu(_ action: TownMenuAction) {
        switch action {
        case .calendar:   tab = .calendar
        case .activities: tab = .activities
        case .map:        tab = .map
        case .compose:    afterMenuClose { composing = true }
        case .invite:     afterMenuClose { ShareCenter.shared.present(.appInvite()) }
        case .profile:    afterMenuClose { showProfileSheet = true }
        }
    }

    private func afterMenuClose(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }

    /// Context-tailored bubbles for the current tab's compose "+".
    private var speedDialItems: [SpeedDialItem] {
        switch tab {
        case .calendar:   return SpeedDialItem.calendar()
        case .activities: return SpeedDialItem.explore()
        case .map:        return SpeedDialItem.map()
        default:          return []
        }
    }

    /// Route a bubble tap: create-kinds open a kind-scoped composer, Invite fires the
    /// app-invite reveal.
    private func routeSpeedDial(_ item: SpeedDialItem) {
        switch item.action {
        case .compose(let kind): composeKind = kind
        case .invite:            ShareCenter.shared.present(.appInvite())
        }
    }

    /// Switch tabs with a horizontal page slide. Direction is derived from the tab
    /// order (`Tab: Int`), so moving right through the bar slides content the way
    /// your thumb expects. A single spring drives both the content slide and the
    /// tab-bar pill so they travel together; Reduce Motion swaps it for a short
    /// crossfade. The haptic lives here (not the button) so it fires once per real
    /// change — re-tapping the current tab is a no-op.
    private func select(_ newTab: Tab) {
        guard newTab != tab else { return }
        slideForward = newTab.rawValue > tab.rawValue
        Haptics.selection()
        withAnimation(reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.44, dampingFraction: 0.86)) {
            if newTab != .map {
                mapDetail = nil
                mapDetailHappenings = []
            }
            tab = newTab
        }
    }

    /// The coupled slide: incoming enters from the edge you're travelling toward,
    /// outgoing exits the opposite edge (pure `.move`, no fade, so the two full-
    /// bleed screens tile seamlessly). Reduce Motion → crossfade, no positional
    /// motion.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading),
            removal:   .move(edge: slideForward ? .leading  : .trailing)
        )
    }
}

/// The global bottom shell. It normally hosts the four tab buttons; while a place is
/// selected on Map, this SAME persistent Liquid Glass view grows into a compact detail
/// and swaps the buttons out. Keeping `.glassEffect` outside the conditional content is
/// the container morph: no second card is inserted over the bar, and the shell never
/// leaves its topmost navigation lane.
struct BlockPartyTabBar: View {
    @Binding var selection: Tab
    @Binding var mapDetail: MapPlaceDetail?
    @Binding var mapDetailHappenings: [TimelineEvent]
    let containerHeight: CGFloat
    /// Tap handler — the parent owns the animated page slide + haptic, so the pill
    /// (driven by `selection`) and the screen slide ride the same spring.
    var onSelect: (Tab) -> Void
    #if DEBUG
    @State private var detailExpanded =
        BlockPartyTabBar.debugExpandedPreselectionRequested()
    @State private var debugExpandedPreselectionPending =
        BlockPartyTabBar.debugExpandedPreselectionRequested()
    #else
    @State private var detailExpanded = false
    #endif
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ObservedObject private var saved = SavedStore.shared

    /// Corner radii: outer glass shell vs. the inner sliding highlight.
    static let shellRadius: CGFloat = 26
    /// Two-line compact-detail baseline + home-indicator band + breathing room.
    /// `SJMapView` scales it with Dynamic Type before applying its viewport cap.
    static let detailCameraReserve: CGFloat = 250
    /// Rich content may use just over half the screen, but never exceed the
    /// comfortable iPhone 17 ceiling. The compact header and grabber sit outside
    /// this cap, preserving visible map above the shell on short devices.
    private static let expandedContentHeightFraction: CGFloat = 0.55
    private static let expandedContentHeightCeiling: CGFloat = 440
    private let pillRadius: CGFloat  = 18

    var body: some View {
        VStack(spacing: 0) {
            if let detail = activeDetail {
                detailPanel(detail)
                    .transition(contentTransition)
            } else {
                HStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .transition(contentTransition)
            }
        }
        .padding(5)
        // Real Liquid Glass (iOS 26): genuinely translucent and refractive, with
        // its own specular rim and floating shadow — no faked frost or white wash.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: Self.shellRadius, style: .continuous)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .animation(reduceMotion ? Motion.smooth : Motion.sheet, value: activeDetail?.id)
        .animation(reduceMotion ? Motion.smooth : Motion.sheet, value: detailExpanded)
        .onChange(of: activeDetail?.id, initial: true) { _, id in
            #if DEBUG
            // Keep the one-shot request pending while an async `-map-open-poi`
            // resolves. Once any launch-preselected detail appears, consume it so
            // later user-selected places retain the normal compact default.
            if debugExpandedPreselectionPending {
                if id != nil {
                    detailExpanded = true
                    debugExpandedPreselectionPending = false
                }
                return
            }
            #endif
            detailExpanded = false
        }
    }

    #if DEBUG
    /// Headless screenshot seam: only the combination of the expansion flag and
    /// an existing civic/POI preselection route starts the detail rich and tall.
    /// Release builds compile this entire launch-argument path out.
    private nonisolated static func debugExpandedPreselectionRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-map-detail-expanded")
            && (arguments.contains("-map-open") || arguments.contains("-map-open-poi"))
    }
    #endif

    private var activeDetail: MapPlaceDetail? {
        selection == .map ? mapDetail : nil
    }

    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom))
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        let selected = selection == tab
        Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .medium))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.sansMedium(11))
            }
            .foregroundStyle(selected ? Hue.ink : Hue.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                        .fill(Hue.fill)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailPanel(_ detail: MapPlaceDetail) -> some View {
        let isSaved = saved.isSaved(detail.saveID)
        let canExpand = hasExpandedContent(detail)

        return VStack(alignment: .leading, spacing: 11) {
            if canExpand {
                detailGrabber
            }

            HStack(alignment: .top, spacing: 12) {
                if let poi = detail.poi {
                    POIPanelLogo(poi: poi, diameter: 44)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(detail.name)
                        .font(.display(20))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Image(systemName: detail.glyph)
                            .font(.system(size: 11, weight: .semibold))
                        Text(detail.badgeLabel)
                            .font(.mono(11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Hue.fill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(detail.groupAccessibilityLabel)

                Spacer(minLength: 4)

                Button {
                    Haptics.light()
                    withAnimation(Motion.card) {
                        mapDetail = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Hue.ink)
                        .frame(width: 36, height: 36)
                        .background(
                            Hue.fill,
                            in: RoundedRectangle(
                                cornerRadius: Radius.button,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close place details")
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    if let url = detail.directionsURL { openURL(url) }
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.sansSemibold(15))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(MapDetailActionStyle(role: .primary))
                .accessibilityLabel("Directions to \(detail.name)")

                Button {
                    if isSaved { Haptics.light() } else { Haptics.success() }
                    saved.toggle(detail.saveID)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bookmark")
                            .foregroundStyle(isSaved ? Hue.accent : Hue.ink)
                        Text("Save")
                            .foregroundStyle(Hue.ink)
                    }
                    .font(.sansSemibold(15))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(MapDetailActionStyle(role: isSaved ? .selected : .neutral))
                .accessibilityLabel(
                    isSaved
                        ? "Remove \(detail.name) from saved places"
                        : "Save \(detail.name)"
                )
                .accessibilityAddTraits(isSaved ? .isSelected : [])
            }

            if detailExpanded && canExpand {
                expandedDetail(detail)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onChange(of: canExpand, initial: true) { _, expandable in
            guard !expandable, detailExpanded else { return }
            withAnimation(reduceMotion ? Motion.smooth : Motion.sheet) {
                detailExpanded = false
            }
        }
    }

    private var detailGrabber: some View {
        Button {
            setDetailExpanded(!detailExpanded)
        } label: {
            VStack(spacing: 3) {
                Capsule()
                    .fill(Hue.inkSecondary)
                    .frame(width: 34, height: 4)
                Image(systemName: detailExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Hue.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 23)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height <= -22 {
                        setDetailExpanded(true)
                    } else if value.translation.height >= 22 {
                        setDetailExpanded(false)
                    }
                }
        )
        .accessibilityLabel(
            detailExpanded ? "Collapse place details" : "Expand place details"
        )
        .accessibilityValue(detailExpanded ? "Expanded" : "Collapsed")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setDetailExpanded(true)
            case .decrement:
                setDetailExpanded(false)
            @unknown default:
                break
            }
        }
    }

    private func expandedDetail(_ detail: MapPlaceDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Rectangle()
                    .fill(Hue.hairline)
                    .frame(height: 1)

                if let spot = detail.spot {
                    if let blurb = spot.blurb, !blurb.isEmpty {
                        Text(blurb)
                            .font(.sans(15))
                            .foregroundStyle(Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VenueInfoView(
                        query: "\(spot.name) St Joseph MN",
                        palette: .map,
                        identity: VenueIdentity(
                            name: spot.name,
                            coordinate: spot.coordinate
                        )
                    )

                    if !mapDetailHappenings.isEmpty {
                        VStack(spacing: 13) {
                            ForEach(mapDetailHappenings) { happening in
                                let isLive = DateHelpers.isLiveNow(happening.startTime)
                                let time = happening.startTime ?? "all day"

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(isLive ? Hue.accent : Hue.inkSecondary)
                                        .frame(width: 6, height: 6)
                                    Text(happening.title)
                                        .font(.sansMedium(15))
                                        .foregroundStyle(Hue.ink)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(time)
                                        .font(.sans(13))
                                        .foregroundStyle(Hue.inkSecondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    isLive
                                        ? "\(happening.title), live now, \(time)"
                                        : "\(happening.title), \(time)"
                                )
                            }
                        }
                    }
                } else if let poi = detail.poi {
                    if let address = poi.address, !address.isEmpty {
                        Text(address)
                            .font(.sans(15))
                            .foregroundStyle(Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VenueInfoView(
                        query: poi.name,
                        palette: .map,
                        identity: VenueIdentity(
                            name: poi.name,
                            coordinate: poi.coordinate
                        )
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: expandedContentMaxHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded details for \(detail.name)")
    }

    private var expandedContentMaxHeight: CGFloat {
        // Use the ceiling itself as a conservative fallback during the first
        // measurement pass; once measured, short screens scale down immediately.
        let availableHeight = containerHeight > 0
            ? containerHeight
            : Self.expandedContentHeightCeiling
        return min(
            Self.expandedContentHeightCeiling,
            availableHeight * Self.expandedContentHeightFraction
        )
    }

    private func hasExpandedContent(_ detail: MapPlaceDetail) -> Bool {
        if let spot = detail.spot {
            return hasText(spot.blurb) || !mapDetailHappenings.isEmpty
        }
        if let poi = detail.poi {
            return hasText(poi.address)
        }
        return false
    }

    private func hasText(_ text: String?) -> Bool {
        text?.contains { !$0.isWhitespace } == true
    }

    private func setDetailExpanded(_ expanded: Bool) {
        guard !expanded || activeDetail.map(hasExpandedContent) == true else { return }
        guard detailExpanded != expanded else { return }
        Haptics.light()
        withAnimation(reduceMotion ? Motion.smooth : Motion.sheet) {
            detailExpanded = expanded
        }
    }
}

/// Compact square-corner-family action used only inside the morphed map detail.
/// Directions is always the primary plum CTA; Save takes plum only while active.
private enum MapDetailActionRole {
    case primary
    case selected
    case neutral
}

private struct MapDetailActionStyle: ButtonStyle {
    let role: MapDetailActionRole

    private var foreground: Color {
        switch role {
        case .primary:  return Hue.surface
        case .selected, .neutral: return Hue.ink
        }
    }

    private var background: Color {
        switch role {
        case .primary:            return Hue.accent
        case .selected, .neutral: return Hue.fill
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                background.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(role == .selected ? Hue.accent : .clear, lineWidth: 1.5)
            }
    }
}
