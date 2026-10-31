//
//  SavedPage.swift
//  Block Party — Profile's Saved (BP app docs/plans/you-tab, ticket 04): every saved Event
//  not over yet, soonest first, as the You tab's Agenda cards, each saying its day. Pushed
//  from Profile's Saved row inside the sheet, under Instagram's Saved top: a back chevron and
//  the title in the middle (BP app references/saved-in-profile), drawn as Search's shelf
//  pages draw it, since Apple's bar dropped the page 20pt at the end of the push.
//
//  The read (`get_my_saves`, kept in the shell's `YouModel.saves()`) gives the list; a save
//  or unsave made anywhere since comes from `RealLifeActions`, so the list matches without a
//  refresh and a save that turns back never shows.
//

import SwiftUI

struct SavedPage: View {
    let model: YouModel
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The event page a card opened. Held here, outside the list, so unsaving the last
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
        // "Saved" from the words page. The cards pass under it.
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Saved") { dismiss() } }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushed) { FeedEventDetailDestination(item: $0) }
        // On every visit, the list on screen staying meanwhile; no account, nothing to read.
        .task { if actions.canAct { await model.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, actions.canAct { Task { await model.refresh() } }
        }
    }

    private func list(now: Date) -> some View {
        // No account can't have saved anything: the empty line, never the retry.
        let read = actions.canAct ? model.going : []
        let saved = read.map {
            YouCalendar.saved(read: $0, tapped: Array(actions.savedTapped.values),
                              isSaved: { actions.saved($0) }, now: now)
        }
        // "Nothing saved yet" from the words page.
        return AgendaList(events: saved, failed: model.failed, empty: "Nothing saved yet",
                          loading: "Loading your saved Events", now: now, withDay: true,
                          retry: { Task { await model.refresh() } }, open: { pushed = $0 })
    }
}
