//
//  LikedPage.swift
//  Block Party — You's Liked (BP app inside-cards 16, which took over you-tab 04's Saved): every
//  Event you hearted, not over or called off, soonest first, as the You tab's Agenda cards, each
//  saying its day; then the stories you hearted while the Town feed keeps them, newest first, as the
//  Town feed's News card (inside-cards 22). Pushed from ☰'s Liked row, under Instagram's Saved top: a back chevron and
//  the title in the middle (BP app references/saved-in-profile), drawn as Search's shelf
//  pages draw it, since Apple's bar dropped the page 20pt at the end of the push.
//
//  The read (`get_my_likes`, kept in the shell's `YouModel.likes(supabase:)`) gives the list; a heart
//  given or taken back anywhere since, a double tap included, comes from `RealLifeActions`, so the
//  list matches without a refresh and a heart that turns back never shows.
//

import SwiftUI

struct LikedPage: View {
    let model: YouModel
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The event page a card opened. Held here, outside the list, so unhearting the last
    /// Event on its own page empties the list without closing the page.
    @State private var pushed: FeedCardItem?

    var body: some View {
        ScrollView(showsIndicators: false) {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
                    // The page's width whatever it holds: the retry alone left the paper a strip.
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, YouMetric.side)
                    .padding(.top, AgendaMetric.rowGap)
                    .padding(.bottom, YouMetric.emptyLine)
            }
        }
        // Instagram's word for what you hearted. The cards pass under it.
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Liked") { dismiss() } }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushed) { EventPage(item: $0) }
        // On every visit, the list on screen staying meanwhile; no account, nothing to read.
        .task { if actions.canAct { await refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, actions.canAct { Task { await refresh() } }
        }
    }

    /// The stories' hearts go to `actions` too, so a tap on one here starts from what the read said.
    private func refresh() async {
        await model.refresh()
        actions.read(news: model.news)
    }

    private func list(now: Date) -> some View {
        // No account can't have hearted anything: the empty line, never the retry.
        let read = actions.canAct ? model.going : []
        let liked = read.map {
            YouCalendar.liked(read: $0, tapped: Array(actions.likedTapped.values),
                              isLiked: { actions.heart($0).isHearted }, now: now)
        }
        let stories = actions.canAct && read != nil
            ? YouCalendar.likedNews(read: model.news, tapped: Array(actions.likedNews.values),
                                    isLiked: { actions.heart($0).isHearted }, now: now)
            : []
        return VStack(spacing: AgendaMetric.rowGap) {
            // With stories, no Events is no empty line: the stories are what's liked.
            if stories.isEmpty || liked?.isEmpty == false {
                AgendaList(events: liked, failed: model.failed, empty: "Nothing liked yet",
                           loading: "Loading your liked Events", now: now, withDay: true,
                           retry: { Task { await refresh() } }, open: { pushed = $0 })
            }
            ForEach(stories) { TownNewsCard(news: $0, inset: 0) }
        }
    }
}
