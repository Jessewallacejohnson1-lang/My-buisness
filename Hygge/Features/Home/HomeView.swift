//
//  HomeView.swift
//  Hygge — Today. Three zones: the living almanac, today's agenda, and the
//  komoot-style interest feed. Staggered spring entrance; pull-to-refresh.
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
    /// The feed posting whose notes (comments) sheet is open, if any.
    @State private var commentPosting: FeedPosting?

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var social: SocialAPI { SocialAPI(auth: auth) }

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

                // Zone 1 — the living almanac (weather + sun + moon + on-this-day +
                // the daily-quest momentum ring). Reads `auth` from the environment.
                AlmanacHeader(quest: model.quest,
                              questCount: model.questCount,
                              questDone: model.questDone,
                              onCompleteQuest: { Task { await model.completeQuest(api) } })
                    .padding(.horizontal, 18)
                    .springReveal(1, revealed: revealed, animated: revealAnimated)

                // Zone 2 — today's agenda (the one section a neighbor opens for).
                agendaSection
                    .padding(.horizontal, 18)
                    .springReveal(2, revealed: revealed, animated: revealAnimated)

                // Zone 3 — the komoot-style interest feed, gated on `loaded` so a
                // fresh HomeModel (recreated on every return to the tab) doesn't
                // flash an empty "New in town" before the first fetch resolves.
                if model.loaded {
                    FeedSection(
                        postings: model.feed,
                        onLike:    { id in withPosting(id) { p in Task { await model.toggleLike(social, p) } } },
                        onFollow:  { id in withPosting(id) { p in Task { await model.toggleFollow(social, p) } } },
                        onSave:    { _ in },                       // card owns the local saved mark
                        onShare:   { _ in },                       // TODO: share sheet (polish pass)
                        onComment: { id in withPosting(id) { p in commentPosting = p } },
                        onOpen:    { id in withPosting(id) { p in commentPosting = p } }
                    )
                    .padding(.horizontal, 18)
                    .springReveal(3, revealed: revealed, animated: revealAnimated)
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
            await model.load(api, social)
            revealAnimated = true
            revealed = true
        }
        .task { await model.load(api, social) }
        // Springs in when Today first appears and each time it's returned to.
        .onAppear { revealed = true }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .sheet(item: $commentPosting) { posting in
            CommentSheet(eventId: posting.id, eventTitle: posting.title)
        }
        // A name edit in the profile writes Interests.displayName synchronously;
        // pick it up when the sheet closes so the greeting stays in sync.
        .onChange(of: showProfile) { _, shown in
            if !shown { model.name = Interests.displayName ?? firstNameFromEmail(auth.email) }
        }
    }

    /// Resolve a feed callback's posting id back to the live posting before acting.
    private func withPosting(_ id: String, _ body: (FeedPosting) -> Void) {
        if let posting = model.feed.first(where: { $0.id == id }) { body(posting) }
    }

    // MARK: - Zone 2 — today's agenda

    @ViewBuilder
    private var agendaSection: some View {
        if model.loading && !model.loaded {
            TodayLoadingCard()
        } else if model.today.isEmpty {
            TodayCard(onAdd: onCompose)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today's agenda")
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
