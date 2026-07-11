//
//  HomeView.swift
//  Hygge — Home / Timeline. Masthead, weather, today's events, around town, quest.
//

import SwiftUI

struct HomeView: View {
    var onCompose: (() -> Void)?
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = HomeModel()

    /// Drives the staggered spring entrance. Starts hidden, springs in on appear
    /// (app open / switching back to Today) and again after a pull-to-refresh.
    @State private var revealed = false
    /// False only during a refresh collapse, so the reset is instant (see refresh).
    @State private var revealAnimated = true
    /// The community profile sheet (opened from the Masthead's person button).
    @State private var showProfile = HomeView.debugOpenProfile()

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    /// DEBUG-only: `-open-profile` presents the profile sheet on launch so it can
    /// be screenshotted headlessly. No effect in release or without the flag.
    private static func debugOpenProfile() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-open-profile")
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Masthead(name: model.name, onAdd: onCompose, onProfile: { showProfile = true })
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .springReveal(0, revealed: revealed, animated: revealAnimated)

                TodayInStJoeCard(content: model.board)
                    .padding(.horizontal, 18)
                    .springReveal(1, revealed: revealed, animated: revealAnimated)

                // Real, actionable "today" sits directly under the hero — the one
                // section a neighbor opens for. (The almanac's day-nudge now lives
                // inside the hero above, so the day is read once, not twice.)
                todaySection
                    .padding(.horizontal, 18)
                    .springReveal(2, revealed: revealed, animated: revealAnimated)

                AroundTownCarousel(expanded: $expandedPlace, ns: cardNS)
                    .springReveal(3, revealed: revealed, animated: revealAnimated)

                // Gated on `loaded`: a fresh HomeModel (every return to the Today tab
                // recreates it) starts weekGoing=0 / quest=nil, so rendering these
                // before the first fetch resolves would flash a false "Quiet week" /
                // "no quest" every visit. Hold until real data has arrived.
                if model.loaded {
                    RollCallSection(count: model.weekGoing)
                        .padding(.horizontal, 18)
                        .springReveal(4, revealed: revealed, animated: revealAnimated)

                    QuestSection(quest: model.quest, count: model.questCount, done: model.questDone) {
                        Task { await model.completeQuest(api) }
                    }
                    .padding(.horizontal, 18)
                    .springReveal(5, revealed: revealed, animated: revealAnimated)
                }

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
        .sheet(isPresented: $showProfile) { ProfileView() }
        // A name edit in the profile writes Interests.displayName synchronously;
        // pick it up when the sheet closes so the greeting stays in sync.
        .onChange(of: showProfile) { _, shown in
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
