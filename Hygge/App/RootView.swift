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

/// Custom frosted tab bar — three content tabs + map.
struct HyggeTabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Hue.hairline).frame(height: 1), alignment: .top)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        let selected = selection == tab
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = tab }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Hue.ink : Hue.ink3)
                    .frame(height: 24)
                Text(tab.title)
                    .font(.sansMedium(11))
                    .foregroundStyle(selected ? Hue.ink : Hue.ink3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
