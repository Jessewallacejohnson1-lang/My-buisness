//
//  RootView.swift
//  Block Party — auth gate over the tab shell. Signed-out → Login; signed-in → tabs.
//

import SwiftUI

/// The four destinations, in bar order (2026-09-18). `Int`-backed because the page
/// slide derives its direction from the order: moving right through the bar slides
/// the content the way a thumb expects.
enum Tab: Int, CaseIterable, Identifiable {
    /// The town feed — everything happening on the block, for everyone.
    case town
    /// The neighbour's own paper: the town feed crossed with what they follow.
    case daily
    /// The town's business network — the owners' side of Main Street.
    case business
    /// Their own profile.
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .town:     return "Town"
        case .daily:    return "Daily"
        case .business: return "Business"
        case .you:      return "You"
        }
    }

    /// The resting glyph. Outline at rest, filled while selected (`selectedSymbol`),
    /// so the active tab reads by WEIGHT rather than by a second colour.
    var symbol: String {
        switch self {
        case .town:     return "house"
        case .daily:    return "newspaper"
        case .business: return "briefcase"
        case .you:      return "person"
        }
    }

    var selectedSymbol: String { symbol + ".fill" }

    /// One line on what the slot is for — shown by the placeholder screens, so an
    /// unbuilt tab reads as reserved rather than broken.
    var promise: String {
        switch self {
        case .town:     return "Everything happening on the block."
        case .daily:    return "Your paper — the town, filtered to what you follow."
        case .business: return "The town's business network — owners, hours, hiring, who's open."
        case .you:      return "Your profile."
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    /// The user id we've already hydrated for. Reset-on-identity-change guard so a
    /// second account on the same device gets its own profile pulled (not the first
    /// account's leftover mirror).
    @State private var hydratedUserId: String?
    #if DEBUG
    @State private var debugIntroDismissed = false
    #endif

    /// The neighbour's System / Light / Dark choice, set in the town menu. Held
    /// here because THIS is the root of the presentation `.preferredColorScheme`
    /// acts on — the request has to be made once, at the top, or a sheet and the
    /// screen behind it can disagree about what appearance they are in.
    @StateObject private var appearance = AppearanceStore.shared

    var body: some View {
        Group {
            #if DEBUG
            // `-show-map-intro` forces the map's first-run explainer on stage so it
            // can be verified headlessly in the simulator. No effect in release or
            // without the flag.
            if ProcessInfo.processInfo.arguments.contains("-show-home") {
                // A deterministic Home route for simulator verification. The Home
                // preview loader supplies local data, so this bypasses auth and
                // onboarding without changing either production flow.
                MainTabsView()
            } else if ProcessInfo.processInfo.arguments.contains("-horizon-sky-gallery")
                        || ProcessInfo.processInfo.arguments.contains("-horizon-card-gallery") {
                // Preview the Your Day horizon card at the eight spec test times
                // (bypassing the auth gate) so sky continuity, bloom shape, the
                // seam and the rail can be verified headlessly. `-horizon-sky-gallery`
                // is sky only; `-horizon-card-gallery` adds the busy-fixture rail.
                // Pair either with `-horizon-sky-gallery-page 2` for the
                // afternoon/night half.
                HorizonSkyGallery()
            } else if ProcessInfo.processInfo.arguments.contains("-feed-card-gallery") {
                // Preview the static feed-card states full-screen (bypassing the auth
                // gate) so the component can be verified headlessly.
                FeedCardGallery()
            } else if ProcessInfo.processInfo.arguments.contains("-briefing-preview") {
                // Mount the real Today briefing composition (bypassing the auth
                // gate) with BriefingModel seeded from a canned payload and no
                // network, so module order, spacing and every payload state can be
                // screenshotted. Pair with `-briefing-state <name>`.
                BriefingHomePreview()
            } else if ProcessInfo.processInfo.arguments.contains("-town-rain-preview") {
                // Preview the map's town-rain drop full-screen (bypassing the auth
                // gate) so its physics can be recorded and measured headlessly — the
                // real trigger is a touch on the town pill, which can't be automated.
                TownRainPreview()
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
            } else if ProcessInfo.processInfo.arguments.contains("-daily-feed-preview") {
                // The Daily social feed over fixtures, without auth or network, so
                // both card shapes and the ranked order can be screenshotted.
                DailyFeedPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-show-skeletons") {
                // Preview the per-tab shimmer skeletons (bypassing the auth gate).
                SkeletonGalleryPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-show-map-intro"),
                      !debugIntroDismissed {
                MapIntroView { debugIntroDismissed = true }
            } else if ProcessInfo.processInfo.arguments.contains("-day-sheet-demo") {
                // The whole day-sheet TRANSITION, driven programmatically over the
                // real Today feed: open on a rail card, scroll, tick a checkbox,
                // dismiss — on a loop. There is no tap or scroll automation here,
                // so this is the only way the accent-bar morph can be recorded.
                DayScheduleDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("-day-sheet-preview") {
                // The Your Day schedule sheet, mounted from fixtures with no auth
                // and no network. Its only real entry point is a tap on a rail
                // card, which this simulator setup cannot drive. Pair with
                // `-day-sheet-state upcoming|inprogress|completed|empty`.
                DaySchedulePreview()
            } else {
                gate
            }
            #else
            gate
            #endif
        }
        // THE APPEARANCE SWITCH, APPLIED ONCE, HERE — on the ROOT of the window's
        // content, not on `gate` below. `gate` is only the auth branch: every DEBUG
        // preview root above bypasses it, and a preference attached there would
        // silently do nothing on exactly the screens used to verify it.
        //
        // `.system` resolves to `nil` — no request — so the app keeps following the
        // phone and keeps following it as the phone changes. `.light` / `.dark` turn
        // the hosting window's interface style over, which is why every `Hue` token,
        // every `.glassEffect` surface and every presented sheet move together.
        //
        // NOT `.environment(\.colorScheme, …)`: that forces a value into the SwiftUI
        // tree only, leaving the UIKit-backed materials resolving the device's
        // appearance underneath the ink drawn on them. It was removed a commit ago
        // (see the note further down this file) and must not come back.
        .preferredColorScheme(appearance.choice.colorScheme)
        #if DEBUG
        // `-appearance <state>` / `-appearance-demo` — the stand-in for a tap on the
        // town-menu control, which no automation in this setup can perform.
        .task { appearance.applyDebugLaunchArguments() }
        #endif
    }

    /// Whether a session is REQUIRED to reach the app. False since 2026-09-18
    /// (Jesse: "remove the sign-in process for now"), so the gate hands straight to
    /// the tabs with or without one.
    ///
    /// A switch rather than a deletion, because "for now" is the whole point:
    /// `LoginView`, `AuthStore`, the keychain session and every authed API path are
    /// untouched and still work — flip this back to `true` and sign-in returns
    /// exactly as it was. What signing out now does is drop the session and leave you
    /// in the app, not bounce you to a login screen.
    ///
    /// Signed OUT, the app is honest about it rather than broken: authed reads fail
    /// and their screens land in their own empty/failed states (the feed's briefing
    /// sets `hasLoaded` on the failure path too, so the column still reveals), and
    /// `hydrateIfNeeded` returns immediately with no `userId`. Nothing force-unwraps
    /// a session.
    private static let requiresSignIn = false

    @ViewBuilder
    private var gate: some View {
        // One state while sign-in is off; two when it is back on. The pre-auth
        // 20-screen flow and the signed-in onboarding wizard were both deleted on
        // 2026-09-18, along with the launch splash, so nothing sits in front of the
        // tabs at all — cold launch lands on Town.
        if auth.isSignedIn || !Self.requiresSignIn {
            MainTabsView()
                .task(id: auth.userId) { await hydrateIfNeeded() }
        } else {
            LoginView()
        }
    }

    /// Pull the community profile once per *user*: mirror interests/name locally (so
    /// matching + greetings work offline) and honor a remote onboarded stamp (a
    /// reinstall/new device shouldn't re-run onboarding). Re-runs when the signed-in
    /// identity changes. Silent on failure.
    private func hydrateIfNeeded() async {
        guard let uid = auth.userId else { hydratedUserId = nil; return }   // signed out → allow re-hydrate on next sign-in
        guard hydratedUserId != uid else { return }
        hydratedUserId = uid

        let fetched = try? await ProfileAPI(auth: .shared).getMyProfile()
        guard let profile = fetched ?? nil else { return }
        if !profile.interests.isEmpty { Interests.set(profile.interests) }
        if let n = profile.displayName, !n.isEmpty { Interests.displayName = n }
    }
}

/// The authed shell: the four tabs and the sheets and covers they open.
struct MainTabsView: View {
    /// A one-shot starting tab (e.g. land on Map straight after onboarding). nil →
    /// the usual default (Today, or a DEBUG `-open-tab` override).
    let startTab: Tab?
    @State private var tab: Tab

    init(startTab: Tab? = nil) {
        self.startTab = startTab
        let resolved = startTab ?? MainTabsView.initialTab()
        _tab = State(initialValue: resolved)
        _showMap = State(initialValue: MainTabsView.debugOpenMap())
        _showMenu = State(initialValue: resolved == .town && MainTabsView.debugOpenMenu())
        _showProfileSheet = State(initialValue: MainTabsView.debugOpenProfile())
    }

    /// DEBUG-only: `-open-map` raises the map cover on launch. It replaces the old
    /// `-open-tab map`, which died with the map's tab: the map is a presented cover
    /// now, so a tab argument can no longer reach it. Screenshot automation needs
    /// SOME way in, and tapping the Today button is not available headlessly.
    private static func debugOpenMap() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-open-map")
        #else
        return false
        #endif
    }

    /// DEBUG-only: `-open-tab block|daily|shops|you` launch argument selects
    /// the starting tab, so simulator verification can screenshot any tab
    /// without UI driving. No effect in release builds or without the flag.
    private static func initialTab() -> Tab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-open-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "town":     return .town
            case "daily":    return .daily
            case "business": return .business
            case "you":      return .you
            default:         break
            }
        }
        #endif
        return .town
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

    /// DEBUG-only: raise a sheet on launch by flag name. `-open-search` and
    /// `-open-notifications` are the Today bar's two new marks, whose only real
    /// trigger is a tap — and there is no tap automation in this setup, so without a
    /// flag those screens cannot be screenshotted OR added to the accessibility
    /// audit's walk. Generic because the pattern above had already been copy-pasted
    /// three times. No effect in release or without the flag.
    private static func debugOpen(_ flag: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(flag)
        #else
        return false
        #endif
    }

    @State private var expandedPlace: Place?
    /// The map, presented full-screen from the Today tab's top-right button
    /// rather than living in the bar. Its selected-pin state belongs to
    /// `SJMapView` itself now — the shell has no tab bar to hide under it.
    @State private var showMap = false
    /// The Today bar's two new controls, added 2026-09-20. Both open a reserved
    /// screen for now — the marks shipped ahead of what sits behind them, and a
    /// named empty room is the same call `BlankTab` makes for the unbuilt tabs.
    @State private var showSearch = MainTabsView.debugOpen("-open-search")
    @State private var showNotifications = MainTabsView.debugOpen("-open-notifications")
    /// The town menu — a corner "genie" drawer out of Home's top-right button.
    /// Owned here (not in HomeView) so it renders above the tab bar.
    @State private var showMenu = false
    /// The profile, now a menu destination (presented as a standard sheet).
    @State private var showProfileSheet = false
    @Namespace private var cardNS
    /// The Your Day rail ↔ day sheet morph, and the sheet's own presentation.
    ///
    /// Both live HERE rather than in the Today tab because the day sheet is
    /// presented in-hierarchy (a `.sheet` cannot carry a namespace across its
    /// boundary, so the morph the spec asks for is impossible through one), and an
    /// in-hierarchy full-height surface has to be a sibling of the tab bar or the
    /// tab bar floats over its bottom rows. Same lane as the town menu.
    @Namespace private var dayNS
    @StateObject private var daySchedule = DaySchedulePresentation()
    /// Direction of the last tab change — whether the incoming screen slides in
    /// from the trailing edge (moving *forward* through the tab order) or the
    /// leading edge (moving back). Set in `select(_:)` right before the animation.
    @State private var slideForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Hue.paper.ignoresSafeArea()

            // Tab content only — the tab BAR lives OUTSIDE this GlassEffectContainer,
            // deliberately. When the two shared one (2026-07-19 "one continuous bottom
            // glass"), the map sheet's glass metaball-merged with the bar into a single
            // tall panel on the Map tab ONLY, so switching tabs visibly swapped between
            // "one attached panel" and "a lone floating capsule" — two different bars
            // (Jesse's round-2 ask 6). Out here the bar's silhouette can never fuse
            // with anything: one identical capsule on every tab.
            GlassEffectContainer(spacing: 22) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .town:
                            HomeView(
                                onMenu: { showMenu = true },
                                menuOpen: showMenu,
                                profileShown: showProfileSheet,
                                onOpenMap: { showMap = true },
                                onOpenSearch: { showSearch = true },
                                onOpenNotifications: { showNotifications = true },
                                expandedPlace: $expandedPlace,
                                cardNS: cardNS
                            )
                        // Daily and Business are named, reserved slots: the bar and
                        // its motion are built, the screens behind them are not yet.
                        case .daily:    BlankTab(tab: .daily)
                        case .business: BlankTab(tab: .business)
                        // Profile is a real screen, mounted WITHOUT its sheet chrome —
                        // a tab has no "close", so the X is suppressed here.
                        case .you:      ProfileView(showsClose: false)
                        }
                    }
                    // Identity keyed on the tab so a switch is an insertion+removal that
                    // the page transition can animate: the outgoing screen slides off one
                    // edge while the incoming slides in from the other, in lockstep — a
                    // swipe to the new tab rather than a flat swap.
                    .id(tab)
                    .transition(pageTransition)
                    // NO LOADING COVER. A tab that is still fetching renders its own
                    // skeleton in its own layout (Features/Components/Skeleton.swift);
                    // nothing is ever hidden behind a full-screen cover. The dark
                    // rainbow-wave cover that used to sit here was deleted 2026-09-21 —
                    // it had begun covering content that was already on screen.

                }
            }

            BlockPartyTabBar(selection: $tab, onSelect: select)
                .transition(.opacity)
                .zIndex(10)
            // THE `.environment(\.colorScheme, .light)` THAT USED TO BE HERE IS GONE.
            //
            // It existed because the app was light-only BY CONSTRUCTION — every `Hue`
            // token was a fixed light hex — while `.glassEffect` (the tab bar AND the
            // map sheet) was the one appearance-ADAPTIVE surface in the tree. Under
            // iOS Dark Mode the glass resolved charcoal and everything drawn on it
            // stayed light, so the peek line and the tab labels fell to ~1:1: the
            // primary navigation, unreadable. Its own comment named the exit — "a full
            // dark ramp + a dark basemap palette" — and that is what has now been
            // built: `Hue` carries both appearances, so ink on charcoal glass is
            // near-white and the contrast runs the right way round.
            //
            // The basemap did NOT get a dark palette, and deliberately: Mapbox renders
            // light-v11 cartography in both modes, so map INK is pinned to its light
            // value instead (`Color.onLightCanvas`). See `BlockPartyColor`.
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
        // Profile is now a menu destination — a standard sheet.
        .sheet(isPresented: $showProfileSheet) { ProfileView() }
        // The Today bar's search mark and bell. Reserved screens until the real ones
        // land; see `ReservedScreen`.
        .sheet(isPresented: $showSearch) { ReservedScreen.search }
        .sheet(isPresented: $showNotifications) { ReservedScreen.notifications }
        // The map is a destination now, not a tab. Full-screen cover rather than a
        // sheet: the map owns its own bottom sheet, and two stacked drag surfaces
        // fight each other for the same gesture.
        .fullScreenCover(isPresented: $showMap) {
            SJMapView(onClose: { showMap = false })
        }
        // The Your Day sheet's own lane, applied LAST so it sits above the tab bar
        // and the town menu. Injects the namespace and the presenter the Your Day
        // rail reaches for.
        .dayScheduleHost(daySchedule, namespace: dayNS)
        #if DEBUG
        .onAppear {
            // `-tab-cycle` walks the bar end to end on a loop so the pill travel, the
            // symbol swap and the page slide can be recorded headlessly — there is no
            // tap automation in this setup, and motion is the whole point of the bar.
            if ProcessInfo.processInfo.arguments.contains("-tab-cycle") {
                cycleTabs(from: 1)
            }
            if ProcessInfo.processInfo.arguments.contains("-share-demo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    ShareCenter.shared.present(.event(title: "Farmers Market",
                                                      dateLabel: "Saturday, Jul 12",
                                                      time: "9:00 AM",
                                                      location: "College Ave"))
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// Walks forward through the bar, one tab every 1.4s, wrapping at the end. Each
    /// step goes through `switchTab`, so what gets recorded is the real transition,
    /// not a preview of it.
    private func cycleTabs(from index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            let all = Tab.allCases
            switchTab(to: all[index % all.count])
            cycleTabs(from: index + 1)
        }
    }
    #endif

    /// Route a town-menu tap. The drawer is already collapsing; tab switches swap
    /// instantly behind it (no competing page slide), while sheets/overlays wait
    /// for the collapse to finish so two presentations don't fight.
    private func handleMenu(_ action: TownMenuAction) {
        switch action {
        case .map:        afterMenuClose { showMap = true }
        case .invite:     afterMenuClose { ShareCenter.shared.present(.appInvite()) }
        case .profile:    afterMenuClose { showProfileSheet = true }
        }
    }

    private func afterMenuClose(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }

    /// A tab-bar tap. The haptic lives here (not the button) so it fires once per
    /// real change — re-tapping the current tab is a no-op.
    private func select(_ newTab: Tab) {
        guard newTab != tab else { return }
        Haptics.selection()
        switchTab(to: newTab)
    }

    /// The tab change itself, with its horizontal page slide. Direction is derived
    /// from the tab order (`Tab: Int`), so moving right through the bar slides content
    /// the way your thumb expects. A single spring drives both the content slide and
    /// the tab-bar pill so they travel together; Reduce Motion swaps it for a short
    /// crossfade. Shared, so a route-driven change feels exactly like a tapped one.
    private func switchTab(to newTab: Tab) {
        slideForward = newTab.rawValue > tab.rawValue
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

/// The global bottom shell — the surviving tab buttons on one persistent Liquid
/// Glass bar. It mounts on every tab now: the map left the bar for a button on
/// Today, so there is no longer a surface that needs to hide it.
struct BlockPartyTabBar: View {
    @Binding var selection: Tab
    /// Tap handler — the parent owns the animated page slide + haptic, so the pill
    /// (driven by `selection`) and the screen slide ride the same spring.
    var onSelect: (Tab) -> Void
    @Namespace private var pill

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Corner radii: the outer glass shell and the inner sliding highlight are both
    // CAPSULES — fully rounded, the way the reference bar is. A capsule inside a
    // capsule keeps the highlight concentric with the shell at every position, which
    // a fixed radius cannot do once the pill reaches either end.

    private let iconSize: CGFloat = 20
    private let iconLane: CGFloat = 23

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(5)
        // Real Liquid Glass (iOS 26): genuinely translucent and refractive, with
        // its own specular rim and floating shadow — no faked frost or white wash.
        .glassEffect(.regular, in: Capsule(style: .continuous))
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
                // Outline → filled on selection. `contentTransition` makes that a
                // symbol REPLACE (the glyph re-draws in place) rather than a
                // cross-fade between two images, and the bounce is the little
                // acknowledgement the tap deserves. Both are dropped under Reduce
                // Motion, where the fill swap alone still carries the state.
                Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                    .font(.glyph(iconSize, weight: selected ? .semibold : .medium))
                    .frame(height: iconLane)
                    .contentTransition(.symbolEffect(.replace))
                    // The swap gets its OWN short curve instead of inheriting the page
                    // spring (0.44s). Stretched over that spring, `.replace` held the
                    // outgoing glyph half-faded for ~150ms — the icon read as missing
                    // mid-travel while the pill slid out from under it. 0.22s snappy
                    // lands the new glyph before the pill arrives, which is the order
                    // the eye wants: the destination lights up, then the pill catches up.
                    .animation(.snappy(duration: 0.22), value: selected)
                    .symbolEffect(.bounce, options: .speed(1.6), value: reduceMotion ? false : selected)
                Text(tab.title)
                    .font(selected ? .sansSemibold(12) : .sansMedium(12))
            }
            .foregroundStyle(selected ? Hue.ink : Hue.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(Hue.fill)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        // Frozen chrome owes the reader another way in: the glyph never grows, so a
        // long press has to enlarge it. Apple's requirement for a custom bar, and
        // until now the app had zero call sites of it.
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: selected ? tab.selectedSymbol : tab.symbol)
        }
    }
}

/// The press reaction for a tab button: a small, fast scale-down that springs back.
/// Separate from `PressableStyle` because a tab must not dim — the label has to stay
/// legible while the finger is down, since the pill is already moving underneath it.
private struct TabPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.92 : 1))
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// What a reserved tab shows until its screen is built: the slot's name and the one
/// line describing what will live there. Deliberately quiet — a named, empty room
/// reads as reserved, where a bare screen reads as broken.
private struct BlankTab: View {
    let tab: Tab

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(tab.title)
                    .font(.display(22))
                    .foregroundStyle(Hue.ink)
                Text(tab.promise)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
