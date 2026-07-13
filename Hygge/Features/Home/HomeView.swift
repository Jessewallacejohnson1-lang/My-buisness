//
//  HomeView.swift
//  Hygge — Home / Timeline. Masthead, almanac, today's events, around town.
//

import SwiftUI

struct HomeView: View {
    var onCompose: (() -> Void)?
    /// The single top-right button → the town menu drawer (a corner "genie"
    /// reveal owned by MainTabsView so it can sit above the tab bar).
    var onMenu: (() -> Void)?
    /// Mirrors the drawer's presented state so the masthead's dots restore on close.
    var menuOpen: Bool = false
    /// Mirrors the profile sheet's presented state so the greeting refreshes when
    /// it closes (a name edit writes Interests.displayName synchronously).
    var profileShown: Bool = false
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = HomeModel()

    /// Drives the staggered spring entrance. Starts hidden, springs in on appear
    /// (app open / switching back to Today) and again after a pull-to-refresh.
    @State private var revealed = false
    /// False only during a refresh collapse, so the reset is instant (see refresh).
    @State private var revealAnimated = true

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Masthead(onMenu: onMenu, menuOpen: menuOpen)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .springReveal(0, revealed: revealed, animated: revealAnimated)

                // Weather in its own little bar, with the weather-reactive
                // background brought back — sits right above the almanac.
                WeatherBar()
                    .padding(.horizontal, 18)
                    .springReveal(1, revealed: revealed, animated: revealAnimated)

                // The daily almanac — a warm time-of-day greeting over the read-of-
                // the-day, in a white card with the coral accent border. On the first
                // open of the day it writes itself in (greeting types, read follows).
                AlmanacSection(name: model.name)
                    .padding(.horizontal, 18)
                    .springReveal(2, revealed: revealed, animated: revealAnimated)

                // Real, actionable "today" — the one section a neighbor opens for.
                todaySection
                    .padding(.horizontal, 18)
                    .springReveal(3, revealed: revealed, animated: revealAnimated)

                AroundTownCarousel(expanded: $expandedPlace, ns: cardNS)
                    .springReveal(4, revealed: revealed, animated: revealAnimated)

                Color.clear.frame(height: 96)
            }
        }
        .background(Hue.canvas)
        .refreshable {
            // Collapse instantly (animated: false → no reverse cascade), load,
            // then spring it all back in — the reference's "reload → springs out" beat.
            revealAnimated = false
            revealed = false
            await model.load(api)
            revealAnimated = true
            revealed = true
        }
        .task { await model.load(api) }
        // Springs in when Today first appears and each time it's returned to.
        .onAppear { revealed = true }
        // A name edit in the profile writes Interests.displayName synchronously;
        // pick it up when the genie closes so the greeting stays in sync.
        .onChange(of: profileShown) { _, shown in
            if !shown { model.name = Interests.displayName ?? firstNameFromEmail(auth.email) }
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        if model.loading && !model.loaded {
            TodayLoadingCard()
        } else if model.today.isEmpty {
            TodayCard(onAdd: onCompose)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today")
                        .font(.displaySemi(22))
                        .foregroundStyle(Hue.ink)
                    Spacer()
                    Text("\(model.today.count) thing\(model.today.count == 1 ? "" : "s")")
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
                ForEach(model.today) { event in
                    EventRow(event: event, date: DateHelpers.localDate()) {
                        Task { await model.toggleRsvp(api, event) }
                    }
                }
            }
        }
    }
}

/// Subtle placeholder while today's events load.
struct TodayLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(Hue.paper200).frame(width: 80, height: 12)
            RoundedRectangle(cornerRadius: 6).fill(Hue.paper200).frame(width: 200, height: 20)
            RoundedRectangle(cornerRadius: 6).fill(Hue.paper200).frame(maxWidth: .infinity).frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 18)
        .redacted(reason: .placeholder)
    }
}
