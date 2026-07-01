//
//  RootView.swift
//  Hygge — auth gate over the tab shell. Signed-out → Login; signed-in → tabs.
//

import SwiftUI

enum Tab: Int, CaseIterable, Identifiable {
    case home, activities, calendar, add
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Today"
        case .activities: return "Activities"
        case .calendar: return "Calendar"
        case .add: return "Add"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .activities: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .add: return "plus"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

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
                MainTabsView()
            } else {
                LoginView()
            }
        }
    }
}

/// The authed shell: four screens under the custom frosted tab bar.
struct MainTabsView: View {
    @State private var tab: Tab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Hue.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .home: HomeView()
                case .activities: ActivitiesView()
                case .calendar: CalendarView()
                case .add: AddView()
                }
            }

            HyggeTabBar(selection: $tab)
        }
    }
}

/// Custom frosted tab bar over four screens. Add is the accented action.
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
                if tab == .add {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Hue.paper)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Hue.moss700))
                } else {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 19, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Hue.ink : Hue.ink3)
                        .frame(height: 24)
                }
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
