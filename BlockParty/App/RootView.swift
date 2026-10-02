//
//  RootView.swift
//  Block Party — auth gate over the tab shell. Signed-out → Login; signed-in → tabs.
//

import SwiftUI

/// The four destinations, in bar order (2026-09-18; Search took Business's slot on
/// 2026-09-29, Jesse). `Int`-backed because the page
/// slide derives its direction from the order: moving right through the bar slides
/// the content the way a thumb expects.
enum Tab: Int, CaseIterable, Identifiable {
    /// The town feed — everything happening on the block, for everyone.
    case town
    /// The neighbour's own paper: the town feed crossed with what they follow.
    case daily
    /// Search: the magnifier that sat at the Town bar's leading edge until 2026-09-29.
    case search
    /// Their own profile.
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .town:     return "Town"
        case .daily:    return "Daily"
        case .search:   return "Search"
        case .you:      return "You"
        }
    }

    /// The resting glyph, drawn as an ink outline. The selected tab shows the filled
    /// `selectedSymbol` in the same ink, as Instagram's bar does. Search draws BP's own
    /// traced magnifier instead (`MagnifierGlyph`); this name is only its large-content
    /// stand-in.
    var symbol: String {
        switch self {
        case .town:     return "house"
        case .daily:    return "newspaper"
        case .search:   return "magnifyingglass"
        case .you:      return "person"
        }
    }

    /// A magnifier has no fill: selected, it thickens instead (`MagnifierGlyph.bold`).
    var selectedSymbol: String { self == .search ? symbol : symbol + ".fill" }

    /// One line on what the slot is for — shown by the placeholder screens, so an
    /// unbuilt tab reads as reserved rather than broken.
    var promise: String {
        switch self {
        case .town:     return "Everything happening on the block."
        case .daily:    return "Your paper — the town, filtered to what you follow."
        case .search:   return "Find a place, a happening, or someone on the block."
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
                // `-show-map-intro` forces the map's first-run explainer on stage so it
                // can be verified headlessly in the simulator. No effect in release or
                // without the flag.
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
        // `.system` resolves to no request, so the app keeps following the phone —
        // except while the Town feed holds the clock (`AppearanceStore.holdsClock`),
        // when it requests the phone's own scheme: with no request iOS 26 inks the
        // clock from whatever scrolls under it, white over every dark photo.
        // `.light` / `.dark` turn the hosting window's interface style over, which is
        // why every `Hue` token, every `.glassEffect` surface and every presented
        // sheet move together.
        //
        // NOT `.environment(\.colorScheme, …)`: that forces a value into the SwiftUI
        // tree only, leaving the UIKit-backed materials resolving the device's
        // appearance underneath the ink drawn on them. It was removed a commit ago
        // (see the note further down this file) and must not come back.
        .preferredColorScheme(appearance.requestedScheme)
        .onAppear {
            // ponytail: the first window scene; per-scene following if iPad
            // multi-window ever matters.
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
                appearance.followPhone(on: scene.screen)
            }
        }
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
    /// A one-shot starting tab. nil → the usual default (Town, or a DEBUG `-open-tab`
    /// override).
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
    /// SOME way in, and tapping the Today bar's map disc is not available headlessly.
    private static func debugOpenMap() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-open-map")
        #else
        return false
        #endif
    }

    /// DEBUG-only: `-open-tab town|daily|search|you` launch argument selects
    /// the starting tab, so simulator verification can screenshot any tab
    /// without UI driving. No effect in release builds or without the flag.
    private static func initialTab() -> Tab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-open-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "town":     return .town
            case "daily":    return .daily
            case "search":   return .search
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

    /// DEBUG-only: raise a sheet on launch by flag name. `-open-friends` and
    /// `-open-notifications` are the Today bar's two marks, whose only real
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
    /// Search's places and recents, kept across tab switches so the tab doesn't fetch
    /// the Town's places again each time it comes back.
    @State private var searchModel = SearchModel()
    /// The map, presented full-screen from the map disc in the Town tab's Today bar
    /// rather than living in the tab bar. Its selected-pin state belongs to
    /// `SJMapView` itself now — the shell has no tab bar to hide under it.
    @State private var showMap = false
    /// The Today bar's friends mark (2026-09-29, where search sat) and bell. Both open
    /// a reserved screen for now — the marks shipped ahead of what sits behind them,
    /// and a named empty room is the same call `BlankTab` makes for the unbuilt tabs.
    @State private var showFriends = MainTabsView.debugOpen("-open-friends")
    @State private var showNotifications = MainTabsView.debugOpen("-open-notifications")
    /// The town menu — a glass panel grown from the top-right corner. Nothing in the
    /// Today bar opens it since the avatar was retired (2026-09-18); `-open-menu` still
    /// does. Owned here (not in HomeView) so it renders above the tab bar.
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
    /// The Town feed is reading down (`TabBarCompactKey`): the tab bar rests small.
    @State private var tabBarCompact = false
    /// The You tab's photo. The narrow loader the Today header once used: one
    /// profile read, and a failed refresh keeps the last good photo.
    @StateObject private var avatar = TodayHeaderProfileModel(auth: .shared)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One stack over the whole shell, so a pushed event page covers the tab bar
    /// and the edge swipe brings the town back under the finger. The shell draws
    /// its own chrome, so the system bar is hidden with `.toolbar(.hidden)` —
    /// never `navigationBarBackButtonHidden`, which kills the swipe back.
    /// `SwipeBack` keeps that swipe alive once the pushed page hides the bar too.
    var body: some View {
        NavigationStack {
            shell
                .toolbar(.hidden, for: .navigationBar)
                .background { SwipeBack().frame(width: 0, height: 0) }
                .navigationDestination(for: FeedCardItem.self) { item in
                    FeedEventDetailDestination(item: item)
                }
        }
    }

    private var shell: some View {
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
                                onOpenFriends: { showFriends = true },
                                onOpenNotifications: { showNotifications = true },
                                expandedPlace: $expandedPlace,
                                cardNS: cardNS
                            )
                        // Daily shows its page once it has something real to show;
                        // until then it is a named, reserved slot.
                        case .daily:
                            if let spotlight = DailySpotlight.today {
                                DailyPage(spotlight: spotlight)
                            } else {
                                BlankTab(tab: .daily)
                            }
                        case .search:   SearchPage(model: searchModel)
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
            .onPreferenceChange(TabBarCompactKey.self) { tabBarCompact = $0 }

            BlockPartyTabBar(selection: tab, onSelect: select,
                             avatarURL: avatar.avatarUrl, compact: tabBarCompact)
                // Re-read on every tab change, so a photo changed on You (or missed
                // by an offline launch) shows as soon as the neighbour moves on.
                .task(id: tab) { await avatar.refresh() }
                // Apple's measured spot: 21pt above the PHYSICAL bottom edge, not
                // above the home-indicator safe area. The full-height frame is what
                // lets `ignoresSafeArea` reach the edge: on the fixed-height bar alone
                // it moved nothing, and the capsule sat 34pt too high (measured).
                .padding(.bottom, TabBarMetric.margin)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
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
        // The town menu — frosts the whole app into glass and grows its panel from the
        // top-right corner (its own overlay lane, above the tab bar).
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
        // The Today bar's friends mark and bell. Reserved screens until the real ones
        // land; see `ReservedScreen`.
        .sheet(isPresented: $showFriends) { ReservedScreen.friends }
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
            // `-tab-cycle` walks the bar end to end on a loop so the bubble travel, the
            // icon swap and the page slide can be recorded headlessly — there is no
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

    /// Route a town-menu tap. The drawer is already collapsing, so every action
    /// waits for the collapse to finish and two presentations don't fight.
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
    /// the way your thumb expects. The bar's bubble rides its own fitted spring
    /// (`TabBarMetric.travel`); Reduce Motion swaps both for a short crossfade.
    /// Shared, so a route-driven change feels exactly like a tapped one.
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

/// The tab bar's measured geometry, in CAPSULE-LOCAL points: x = 0 at the capsule's
/// leading edge, y = 0 at its top. One set of numbers places the items and the
/// bubble, and will hit-test the finger. Source: Instagram's iOS 26 bar, measured
/// from Jesse's recording (`/Users/owner/BP app/references/instagram-tab-bar/`,
/// 2026-09-27), where it sets a value; Apple's own bar (`references/tab-bar/`)
/// where Instagram's recording cannot.
///
/// `nonisolated`: constants and pure arithmetic, callable from any context.
nonisolated enum TabBarMetric {
    /// Capsule height, and its gap to the screen's sides and physical bottom edge.
    /// Height: Instagram's capsule is 0.167x its width, 60pt at 360 (MEASURED as a
    /// ratio, so the recording's scale drops out). Gaps: 21pt, Apple's MEASURED
    /// value; Instagram's side gap matches it, its bottom gap is outside the crop.
    static let height: CGFloat = 60
    static let margin: CGFloat = 21
    /// The Selection bubble: 50pt tall, so 5pt inside the capsule top and bottom,
    /// and as wide as one tab's slot. The slots split the capsule evenly inside a
    /// 9pt side inset, so the end bubbles sit 9pt in. MEASURED on Instagram's five
    /// slots (69.4pt bubble, 68.5pt slot, first centre 43pt in); four here.
    static let sideInset: CGFloat = 9
    static let bubbleHeight: CGFloat = 50
    /// Icon point size, centred up and down: Instagram's glyph boxes are 22pt and
    /// its strokes ~1.6pt (MEASURED). At 23 the house drew 26.7pt wide on the eyes
    /// sim; 19.5 brings the widest glyph to ~22.5pt.
    static let iconSize: CGFloat = 19.5
    /// Search's traced magnifier fills its own box: Instagram's search mark, 22pt
    /// (66px @3x, MEASURED on Mobbin's Instagram tab bar, 2026-09-29).
    static let searchGlyphSize: CGFloat = 22
    static let iconCentreY: CGFloat = height / 2
    /// The You tab's photo: a 25pt circle (MEASURED on Instagram's profile tab).
    static let avatarSize: CGFloat = 25
    /// How far past the first and last centres the Lens may travel. MEASURED at the
    /// right end on Apple's bar (§3.5); the left end mirrors it, GUESSED.
    static let lensOvershoot: CGFloat = 9

    /// One tab's share of the capsule, and the bubble's width.
    static func bubbleWidth(capsuleWidth: CGFloat) -> CGFloat {
        (capsuleWidth - 2 * sideInset) / CGFloat(Tab.allCases.count)
    }

    /// The Lens while held: 1.20x the bubble's width and 1.30x its height, so it
    /// stands ~4pt proud of the capsule. MEASURED on TabProbe (Air, hold (d)).
    static let lensScale = CGSize(width: 1.20, height: 1.30)
    /// Apple's whole bar swells while pressed. MEASURED 1.042x peak, 1.039x held
    /// (Instagram's 1.044x). The interactive glass draws it; this maps the finger.
    static let swell: CGFloat = 1.04
    /// Icons under the Lens centre magnify 1.2x (MEASURED §3.7), falling off
    /// linearly to 1.0 one tab away (GUESSED method: no jump between tabs).
    static let magnificationPeak: CGFloat = 0.2

    static func bubbleSize(capsuleWidth: CGFloat, held: Bool) -> CGSize {
        let rest = CGSize(width: bubbleWidth(capsuleWidth: capsuleWidth), height: bubbleHeight)
        guard held else { return rest }
        return CGSize(width: rest.width * lensScale.width, height: rest.height * lensScale.height)
    }

    /// The distance between neighbouring tab centres.
    static func pitch(capsuleWidth: CGFloat) -> CGFloat {
        centreX(of: .daily, capsuleWidth: capsuleWidth) - centreX(of: .town, capsuleWidth: capsuleWidth)
    }

    static func magnification(itemX: CGFloat, lensX: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        1 + magnificationPeak * max(0, 1 - abs(lensX - itemX) / pitch(capsuleWidth: capsuleWidth))
    }

    /// The Lens growing on touch-down and the bar's swell: 89% there at 37ms, 96%
    /// at 70ms, no overshoot. MEASURED; fitted as a critically damped spring.
    static let growth = Animation.spring(response: 0.06, dampingFraction: 1)
    /// The bubble travelling between tabs (a tap, a touch-down away from the
    /// selected tab, a release). MEASURED target: Apple's arrives ~270–280ms after a
    /// tap (its centre 96.5% of the way at +272ms, TabProbe) and does not overshoot.
    /// Critically damped at 0.33 matches that point; 0.45/0.8 arrived at ~350ms and
    /// overshot 2.5pt, and 0.27 read as early on the eyes sim. Fitted, not measured.
    static let travel = Animation.spring(response: 0.33, dampingFraction: 1)

    /// How long the Lens keeps its look after the finger lifts. After a tap it lasts
    /// to the end of the travel (Apple's re-forms its grey bubble ~323–353ms after
    /// touch-down); after a drag it collapses in ~76ms (MEASURED §3.6). The tap
    /// value is GUESSED from those, counted from lift rather than touch-down.
    static let landingAfterTap: Duration = .milliseconds(260)
    static let collapseAfterDrag: Duration = .milliseconds(70)

    /// The white layer behind the bar's glass that holds it in its light state.
    /// MEASURED threshold: 20% flipped, 30% held. 35% read 202–208 over a near-black
    /// photo (2026-09-27), lighter than Instagram's 192 over black, so it sits at the
    /// threshold that held.
    static let glassUnderlay: Double = 0.30
    /// The same layer under a finger, so the pressed bar lightens by Instagram's
    /// middling amount (~+30 over a dark photo, with the interactive glass's own).
    static let pressedUnderlay: Double = 0.40
    /// The Selection bubble's black: Instagram's reads 0.87x the glass on any
    /// ground (168 on 192 over black, 221 on 255 over white; MEASURED).
    static let bubbleShade: Double = 0.13

    /// While the feed reads down, the whole bar rests at 0.84x (Instagram's
    /// 462×78px against 550×92px, MEASURED), and gets there with no overshoot: half
    /// way at ~80ms, 98% at ~250ms. Fitted as a critically damped spring; the way
    /// back is GUESSED to mirror it (the recording never scrolls up).
    static let compactScale: CGFloat = 0.84
    static let compaction = Animation.spring(response: 0.3, dampingFraction: 1)

    /// A tab's centre: the middle of its slot.
    static func centreX(of tab: Tab, capsuleWidth: CGFloat) -> CGFloat {
        sideInset + bubbleWidth(capsuleWidth: capsuleWidth) * (CGFloat(tab.rawValue) + 0.5)
    }

    /// The tab a release picks: the centre nearest the finger's x. Its height does
    /// not matter — Apple's bar switches on a release 150pt above it (MEASURED on
    /// the Air probe, 2026-09-25), so there is no cancel zone.
    static func tab(atX x: CGFloat, capsuleWidth: CGFloat) -> Tab {
        Tab.allCases.min {
            abs(centreX(of: $0, capsuleWidth: capsuleWidth) - x) < abs(centreX(of: $1, capsuleWidth: capsuleWidth) - x)
        } ?? .town
    }

    /// Where the Lens sits under a finger: on it, clamped `lensOvershoot` past the
    /// end centres.
    static func lensCentreX(fingerX: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        let first = centreX(of: .town, capsuleWidth: capsuleWidth) - lensOvershoot
        let last = centreX(of: .you, capsuleWidth: capsuleWidth) + lensOvershoot
        return min(max(fingerX, first), last)
    }
}

/// The global bottom shell: one floating Liquid Glass capsule, a copy of Instagram's
/// iOS 26 bar with BP's icons (Jesse, 2026-09-27). It mounts on every tab and never
/// hides; while the Town feed reads down it shrinks, as Instagram's does.
///
/// One touch drives it, the way Apple's own bar works (TabProbe, 2026-09-25): the
/// Selection bubble lifts into a Lens under the finger on touch-down (a plain tap
/// included), follows the finger, and the tab nearest the finger's x on release is
/// picked, however far above the bar the finger ends.
struct BlockPartyTabBar: View {
    let selection: Tab
    /// Tap handler — the parent owns the page slide and the haptic, and ignores a
    /// release on the tab that is already selected.
    var onSelect: (Tab) -> Void
    /// The signed-in neighbour's photo for the You tab; nil draws the person icon.
    var avatarURL: String? = nil
    /// The feed is reading down (its top bar is away): the bar rests small. A touch
    /// brings it back to full size while the finger is down.
    var compact = false

    /// The finger while it is down, capsule-local. `@GestureState` resets itself
    /// when the system cancels the touch, so the Lens can never stay stuck up.
    @GestureState private var touch: Touch?
    /// After the finger lifts, the Lens keeps its look until the bubble lands, as
    /// Apple's does: to the end of a tap's travel, or a short collapse after a drag.
    @State private var landing = false
    @State private var landingTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Touch: Equatable {
        var x: CGFloat
        /// Past the first 4pt of travel (GUESSED threshold) the Lens tracks the
        /// finger tightly; before that, it springs over from the selected tab.
        var moved: Bool
    }

    var body: some View {
        GeometryReader { capsule in
            let width = capsule.size.width
            // Reduce Motion: no Lens, no growth, no magnification, no swell; a change
            // crossfades the bubble (see `BubbleGeometry`).
            let lens = reduceMotion ? nil : touch
            let held = lens != nil || (landing && !reduceMotion)
            let bubbleX = lens.map { TabBarMetric.lensCentreX(fingerX: $0.x, capsuleWidth: width) }
                ?? TabBarMetric.centreX(of: selection, capsuleWidth: width)
            let geometry = BubbleGeometry(x: bubbleX,
                                          size: TabBarMetric.bubbleSize(capsuleWidth: width, held: held),
                                          held: held, following: lens?.moved == true,
                                          selection: selection, reduceMotion: reduceMotion)
            ZStack(alignment: .topLeading) {
                // Under a finger the grey bubble gives way to a clear glass Lens, as
                // Instagram's does. The glass is placed straight at the finger, never
                // animated there (glass draws at its final position), and swapped with
                // the bubble in one frame, never faded. It stays mounted at zero size
                // between touches: inserted fresh, it drew two frames late and left
                // the touch-down with neither Lens nor bubble (eyes sim, 2026-09-27).
                bubble
                    .modifier(geometry)
                    .opacity(lens == nil ? 1 : 0)
                    .animation(nil, value: lens == nil)
                lensGlass
                    .frame(width: lens == nil ? 0 : geometry.size.width,
                           height: lens == nil ? 0 : geometry.size.height)
                    .position(x: bubbleX, y: TabBarMetric.height / 2)
                    .transaction { $0.animation = nil }
                Items(selection: selection, capsuleWidth: width, onSelect: onSelect,
                      avatarURL: avatarURL, lensX: lens == nil ? nil : bubbleX)
            }
            .contentShape(Rectangle())
            .gesture(
                // Read in screen space and mapped onto the bar at its PRESSED size. In
                // the bar's own space a still finger kept the x it touched down at on
                // the shrunk bar, so the Lens slid off the finger as the bar grew
                // back (review, 2026-09-27). The bar scales about its centre, so its
                // centre is the same at any scale.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touch) { value, state, _ in
                        state = Touch(x: pressedX(value.location.x, capsule: capsule),
                                      moved: state?.moved == true || abs(value.translation.width) > 4)
                    }
                    .onEnded { value in
                        land(after: abs(value.translation.width) > 4
                             ? TabBarMetric.collapseAfterDrag : TabBarMetric.landingAfterTap)
                        onSelect(TabBarMetric.tab(atX: pressedX(value.location.x, capsule: capsule),
                                                  capsuleWidth: width))
                    }
            )
        }
        .frame(height: TabBarMetric.height)
        // Real Liquid Glass, untinted: near-white over paper, mid-grey over dark
        // photos — the same response the Reference measures (§1.6, §1.13).
        // Interactive, Apple's own pressed look: Instagram's bar lightens under a
        // finger (206–239 over a near-black photo, against 192 at rest; MEASURED).
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        // Keeps the glass in its LIGHT state. Over a near-black feed card the glass
        // flipped to its dark state (measured 2026-09-26, Town at
        // `-feed-scrolled-y 1200`: glass 23/255, ink invisible), and no colour-scheme
        // pin stopped it. A white layer BEHIND the glass lifts what it samples: at
        // 20% it still flipped (40/255), at 30% it held (178/255). It sits at 30%, the
        // value that held, to match Instagram's grey (`TabBarMetric.glassUnderlay`).
        // Pressed, it thickens: the interactive glass alone lightened the bar only
        // +13 (198 → 211), the bottom of Instagram's +14 to +47.
        .background {
            Capsule(style: .continuous)
                .fill(Hue.surface.onLightCanvas.opacity(touch != nil && !reduceMotion
                    ? TabBarMetric.pressedUnderlay : TabBarMetric.glassUnderlay))
                .animation(reduceMotion ? nil : TabBarMetric.growth, value: touch != nil)
                .allowsHitTesting(false)
        }
        // The Reference's brighter 1pt rim (§1.9: +60–75 over the glass). Opacity
        // tuned on the eyes sim: 0.6 read +56 over the dark card.
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Hue.surface.onLightCanvas.opacity(0.75), lineWidth: 1)
                .allowsHitTesting(false)
        }
        // No hand-made swell: the interactive glass swells the bar itself, and the
        // two together pressed it to ~1.08x, past Instagram's 1.044x (eyes sim).
        // Instagram's shrink while reading down, around the bar's own centre. A
        // finger on the bar (or its landing) holds it at full size. Under Reduce
        // Motion it still shrinks, without the spring.
        .scaleEffect(compact && touch == nil && !landing ? TabBarMetric.compactScale : 1)
        .animation(reduceMotion ? nil : TabBarMetric.compaction, value: compact && touch == nil && !landing)
        .padding(.horizontal, TabBarMetric.margin)
    }

    /// A finger's screen x, in capsule points on the bar at its pressed size (the
    /// swell; 1x under Reduce Motion, which has none).
    private func pressedX(_ screenX: CGFloat, capsule: GeometryProxy) -> CGFloat {
        let scale = reduceMotion ? 1 : TabBarMetric.swell
        return capsule.size.width / 2 + (screenX - capsule.frame(in: .global).midX) / scale
    }

    private func land(after delay: Duration) {
        guard !reduceMotion else { return }
        landingTask?.cancel()
        landing = true
        landingTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            landing = false
        }
    }

    /// The Selection bubble: translucent black at Instagram's measured shade
    /// (`TabBarMetric.bubbleShade`). It does all the sliding; under a finger the
    /// glass Lens stands in for it (`lensGlass`).
    private var bubble: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(TabBarMetric.bubbleShade))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The held Lens: real Liquid Glass on the same white layer as the bar, so it
    /// reads lighter than the bar and cannot flip dark over a dark photo either.
    private var lensGlass: some View {
        Capsule(style: .continuous)
            .fill(Hue.surface.onLightCanvas.opacity(TabBarMetric.glassUnderlay))
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where the bubble is and how it moves. Size and look ride the measured growth
    /// spring; position rides the travel spring (or tracks the finger). Scoped this
    /// way because one `.animation` over both let the travel spring win the growth.
    struct BubbleGeometry: ViewModifier {
        var x: CGFloat
        var size: CGSize
        var held: Bool
        var following: Bool
        var selection: Tab
        var reduceMotion: Bool

        func body(content: Content) -> some View {
            if reduceMotion {
                // No travel: the old bubble fades out where it was and the new one
                // fades in, on the parent's 0.2s ease.
                content
                    .frame(width: size.width, height: size.height)
                    .position(x: x, y: TabBarMetric.height / 2)
                    .id(selection)
                    .transition(.opacity)
            } else {
                content
                    .frame(width: size.width, height: size.height)
                    .animation(TabBarMetric.growth, value: held)
                    .position(x: x, y: TabBarMetric.height / 2)
                    .animation(following ? TabBarMetric.growth : TabBarMetric.travel, value: x)
            }
        }
    }

    /// The four items, placed from `TabBarMetric`. No glass, so a test can render
    /// them alone.
    struct Items: View {
        let selection: Tab
        let capsuleWidth: CGFloat
        var onSelect: (Tab) -> Void
        /// The signed-in neighbour's photo, drawn on the You tab in place of its icon.
        var avatarURL: String? = nil
        /// The Lens centre while held; icons near it magnify.
        var lensX: CGFloat? = nil

        var body: some View {
            ZStack(alignment: .topLeading) {
                // Instagram's bar: icons only, all one ink, the selected one filled.
                // Ink is the LIGHT-canvas value, fixed: glass that flips hands its
                // items a dark trait, and adaptive `Hue.ink` then drew white
                // (measured 2026-09-26).
                ForEach(Tab.allCases) { tab in
                    icon(tab)
                        .scaleEffect(magnification(tab))
                        .position(x: centreX(tab), y: TabBarMetric.iconCentreY)
                }
                .animation(TabBarMetric.growth, value: lensX)
                .accessibilityHidden(true)
                // Frozen chrome owes the reader another way in: the glyph never
                // grows, so a long press at an accessibility text size has to
                // enlarge it (docs/rules/architecture.md).
                ForEach(Tab.allCases) { tab in
                    Color.clear
                        .frame(width: TabBarMetric.pitch(capsuleWidth: capsuleWidth), height: TabBarMetric.height)
                        .contentShape(Rectangle())
                        .accessibilityShowsLargeContentViewer {
                            Label(tab.title, systemImage: selection == tab ? tab.selectedSymbol : tab.symbol)
                        }
                        .position(x: centreX(tab), y: TabBarMetric.height / 2)
                }
            }
            .frame(width: capsuleWidth, height: TabBarMetric.height, alignment: .topLeading)
            // VoiceOver sees exactly four tabs, named, not the drawing: the tab
            // elements are synthetic children laid over the slots.
            .accessibilityChildren {
                ZStack(alignment: .topLeading) {
                    ForEach(Tab.allCases) { tab in
                        accessibilityElement(tab)
                    }
                }
                .frame(width: capsuleWidth, height: TabBarMetric.height, alignment: .topLeading)
            }
            .accessibilityAddTraits(.isTabBar)
        }

        @ViewBuilder
        private func icon(_ tab: Tab) -> some View {
            let selected = selection == tab
            if tab == .you, let avatarURL, let url = URL(string: avatarURL) {
                TabAvatar(url: url, selected: selected, placeholder: symbol(tab, selected: selected))
            } else {
                symbol(tab, selected: selected)
            }
        }

        private func symbol(_ tab: Tab, selected: Bool) -> some View {
            Group {
                if tab == .search {
                    MagnifierGlyph(size: TabBarMetric.searchGlyphSize, bold: selected)
                } else {
                    Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                        .font(.glyph(TabBarMetric.iconSize))
                }
            }
            .foregroundStyle(Hue.ink.onLightCanvas)
            // Swapped, not crossfaded: under the tab switch's spring the outline
            // and the filled symbol blended into a grey blob for ~3 frames, and
            // `.contentTransition(.identity)` did not stop it.
            .transaction { $0.animation = nil }
        }

        /// One VoiceOver element per tab, over its slot, with the tab's action.
        private func accessibilityElement(_ tab: Tab) -> some View {
            let selected = selection == tab
            return Color.clear
                .frame(width: TabBarMetric.pitch(capsuleWidth: capsuleWidth), height: TabBarMetric.height)
                .position(x: centreX(tab), y: TabBarMetric.height / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect(tab) }
        }

        private func centreX(_ tab: Tab) -> CGFloat {
            TabBarMetric.centreX(of: tab, capsuleWidth: capsuleWidth)
        }

        private func magnification(_ tab: Tab) -> CGFloat {
            guard let lensX else { return 1 }
            return TabBarMetric.magnification(itemX: centreX(tab), lensX: lensX, capsuleWidth: capsuleWidth)
        }
    }
}

/// The You tab's photo, as Instagram's profile tab draws it: a plain circle, with an
/// ink ring when selected (GUESSED ring: the recording never selects that tab). The
/// person icon stands in while it loads or when it fails, so the slot is never blank.
private struct TabAvatar<Placeholder: View>: View {
    let url: URL
    let selected: Bool
    let placeholder: Placeholder

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
                    .frame(width: TabBarMetric.avatarSize, height: TabBarMetric.avatarSize)
                    .clipShape(Circle())
                    .padding(3)
                    .overlay {
                        if selected {
                            Circle().strokeBorder(Hue.ink.onLightCanvas, lineWidth: 1.5)
                        }
                    }
            } else {
                placeholder
            }
        }
    }
}

/// The Town feed's "reading down" signal, carried up to the shell so the tab bar can
/// shrink with the top bar. Absent (false) on every other tab.
struct TabBarCompactKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
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

/// The stack's swipe back, kept alive while the bar is hidden. With the event page
/// hiding the bar as well, UIKit refused every swipe back (recorded 2026-09-26; with the
/// bar shown it followed the finger). Two recognizers do that swipe on iOS 26:
/// `interactivePopGestureRecognizer` from the leading edge, and
/// `interactiveContentPopGestureRecognizer` anywhere else on the page. This delegate lets
/// both begin whenever there is a page to go back to and no push or pop is running; at
/// the root they stay off, as UIKit leaves them. That is a defensive guard against the
/// known root-pop freeze, which did not reproduce here on iOS 26.5. With a page to go back
/// to, the edge one also beats a horizontal scroll under the finger, so an edge swipe on the
/// photo carousel pops the page (`EventCardPhotoTapTests`), while a swipe that starts on a
/// photo away from the edge still pages or rubber-bands the carousel. Vertical scrolls, and
/// every scroll at the root, never wait on it.
private struct SwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactiveContentPopGestureRecognizer?.delegate = self
        }

        /// Both swipes begin only with a page to go back to. Off at the root is a guard
        /// against the known root-pop freeze; it did not reproduce on iOS 26.5.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation = navigationController else { return false }
            return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
        }

        /// With a page to go back to, the edge swipe beats a horizontal scroll under the finger
        /// (the photo carousel): its pan waits for the edge swipe to fail, which it does at
        /// once off the edge. A vertical scroll (the page, the feed) never waits, and nothing
        /// waits at the root, where the edge swipe can't begin.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            guard let navigation = navigationController,
                  gestureRecognizer === navigation.interactivePopGestureRecognizer,
                  navigation.viewControllers.count > 1,
                  other is UIPanGestureRecognizer,
                  let scroll = other.view as? UIScrollView
            else { return false }
            // A point of slack: the event page's vertical scroll measures a fraction of a
            // point off its own width (420.17 in 420.33 on iPhone Air).
            return scroll.isPagingEnabled || scroll.contentSize.width > scroll.bounds.width + 1
        }
    }
}
