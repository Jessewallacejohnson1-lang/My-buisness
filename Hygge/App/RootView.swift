//
//  RootView.swift
//  Hygge — auth gate over the tab shell. Signed-out → Login; signed-in → tabs.
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
            if ProcessInfo.processInfo.arguments.contains("-show-splash") {
                SplashView()
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
        _tab = State(initialValue: startTab ?? MainTabsView.initialTab())
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
    @State private var expandedPlace: Place?
    @State private var composing = false
    @Namespace private var cardNS

    var body: some View {
        ZStack(alignment: .bottom) {
            Hue.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    // Home carries the brand in its own "Hygge" masthead — a second
                    // coral badge would be redundant, so Home is the one tab without it.
                    HomeView(
                        onCompose: { composing = true },
                        expandedPlace: $expandedPlace,
                        cardNS: cardNS
                    )
                // No brand badge on these tabs — the top-right corner carries
                // screen chrome now (the map's compose "+" etc.).
                case .activities: ActivitiesView(onCompose: { composing = true })
                case .calendar:   CalendarView(onCompose: { composing = true })
                case .map:        SJMapView(onCompose: { composing = true })
                }
            }

            HyggeTabBar(selection: $tab)
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
        // Global compose sheet — triggered by "+" anywhere in the app
        .sheet(isPresented: $composing) {
            AddView()
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-share-demo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    ShareCenter.shared.present(
                        SharePayload(title: "SHARE THIS EVENT",
                                     shareText: "Come to Farmers Market with me — Sat 9am. (via Hygge)",
                                     includesImage: true) {
                            InviteCard(title: "Farmers Market",
                                       dateLabel: "Saturday, Jul 12",
                                       time: "9:00 AM",
                                       location: "College Ave")
                        })
                }
            }
        }
        #endif
    }
}

/// Floating frosted tab bar — a rounded glass pill with a coral-tinted selection
/// highlight that matched-geometry-slides to whichever tab is active. Selected
/// state reads coral-on-soft-coral (matches the map's Life360 look); each switch
/// fires a haptic.
struct HyggeTabBar: View {
    @Binding var selection: Tab
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
            Haptics.selection()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selection = tab }
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
