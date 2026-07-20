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
            } else if ProcessInfo.processInfo.arguments.contains("-show-loading-cover") {
                // Preview the tab loading cover full-screen (bypassing the auth gate)
                // so the rainbow-wave indicator + copy can be verified headlessly.
                TabLoadingCover()
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
        if auth.booting {
            SplashView()
        } else if auth.isSignedIn {
            authedRoot
                .task(id: auth.userId) { await hydrateIfNeeded() }
        } else {
            LoginView()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Hue.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    // Home carries the brand in its own "Block Party" masthead — a second
                    // coral badge would be redundant, so Home is the one tab without it.
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
                case .map:        SJMapView(onCompose: { speedDialOpen = true })
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

            BlockPartyTabBar(selection: $tab, onSelect: select)
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

/// Floating frosted tab bar — a rounded glass pill with a coral-tinted selection
/// highlight that matched-geometry-slides to whichever tab is active. Selected
/// state reads coral-on-soft-coral (matches the map's Life360 look); each switch
/// fires a haptic.
struct BlockPartyTabBar: View {
    @Binding var selection: Tab
    /// Tap handler — the parent owns the animated page slide + haptic, so the pill
    /// (driven by `selection`) and the screen slide ride the same spring.
    var onSelect: (Tab) -> Void
    @Namespace private var pill

    /// Corner radii: outer glass shell vs. the inner sliding highlight.
    private let shellRadius: CGFloat = 26
    private let pillRadius: CGFloat  = 18

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(5)
        // Real Liquid Glass (iOS 26): genuinely translucent and refractive, with
        // its own specular rim and floating shadow — no faked frost or white wash.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: shellRadius, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
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
            .foregroundStyle(selected ? Hue.accent : Hue.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                        .fill(Hue.accentSoft)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
