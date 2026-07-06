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
    @State private var needsOnboarding = !Interests.isOnboarded()

    var body: some View {
        Group {
            if auth.booting {
                ZStack {
                    Hue.canvas.ignoresSafeArea()
                    Text("Hygge")
                        .font(.display(34))
                        .foregroundStyle(Hue.ink)
                }
            } else if auth.isSignedIn {
                if needsOnboarding {
                    OnboardingView { needsOnboarding = false }
                } else {
                    MainTabsView()
                }
            } else {
                LoginView()
            }
        }
    }
}

/// The authed shell: four tabs + global "+" composer sheet.
struct MainTabsView: View {
    @State private var tab: Tab = MainTabsView.initialTab()

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
                    HomeView(
                        onCompose: { composing = true },
                        expandedPlace: $expandedPlace,
                        cardNS: cardNS
                    )
                case .activities: ActivitiesView()
                case .calendar:   CalendarView()
                case .map:        SJMapView()
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
    }
}

/// Floating frosted tab bar — a rounded glass pill with a gray selection
/// highlight that matched-geometry-slides to whichever tab is active. Selected
/// state reads charcoal-on-gray (no accent tint); each switch fires a haptic.
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
            .foregroundStyle(selected ? Hue.ink : Hue.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
