//
//  AppSession.swift
//  Block Party — the models every tab shares, and what happens to them when the account changes,
//  the app comes back or it goes away (BP app codebase-health 22). The shell holds one.
//
//  A model that keeps an account's state joins here: a property, its line in `accountChanged`,
//  and its check in `AppSessionTests`, so the last account's Going or Saved never shows under
//  the next one.
//

import SwiftUI

@MainActor
final class AppSession {
    /// Each Event's Going, Heart and Save for the session, which the Town feed's reads set and
    /// every card and event page reads, so they agree (BP app docs/plans/real-life-actions).
    let actions: RealLifeActions
    /// The Town feed's events, kept here so coming back to Town shows the list it left while
    /// it reads again behind it.
    let townFeed: TownFeed
    /// Search's places and recents, kept so the tab doesn't fetch the Town's places again each
    /// time it comes back. Its groups reads tell `actions`.
    let searchModel: SearchModel
    /// Friend requests, friends and the dot on the friends mark, so a row and a person's page
    /// agree (BP app docs/plans/friends, ticket 03).
    let friendsBook: FriendsBook
    /// The You tab's three weeks of Going, kept like the Town feed's.
    let you: YouModel
    /// Profile's Saved list (you-tab 04), kept the same way.
    let saves: YouModel
    /// Daily's Event of the day (daily-tab 14), and the Town feed's top (event-card 03).
    let eventOfTheDay: EventOfTheDay
    /// The other days' picks in Daily's week (daily-tab 16).
    let dayPicks: DailyDayPicks
    /// What the bell holds: Events you follow or are Going to that were canceled or moved (BP app
    /// docs/plans/school-activities, ticket 04).
    let notices: Notices
    private let hello: HelloInbox
    /// Saves this phone kept before they moved to the server.
    private let saved: SavedStore
    private let supabase: Supabase

    init(actions: RealLifeActions, townFeed: TownFeed, searchModel: SearchModel, friendsBook: FriendsBook,
         you: YouModel, saves: YouModel, eventOfTheDay: EventOfTheDay, dayPicks: DailyDayPicks,
         notices: Notices, hello: HelloInbox, saved: SavedStore, supabase: Supabase) {
        self.actions = actions
        self.townFeed = townFeed
        self.searchModel = searchModel
        self.friendsBook = friendsBook
        self.you = you
        self.saves = saves
        self.eventOfTheDay = eventOfTheDay
        self.dayPicks = dayPicks
        self.notices = notices
        self.hello = hello
        self.saved = saved
        self.supabase = supabase
    }

    /// The live models, or the DEBUG samples each one's launch flags pick.
    convenience init() {
        let actions = RealLifeActions()
        self.init(actions: actions, townFeed: TownFeed(actions: actions), searchModel: SearchModel(actions: actions),
                  friendsBook: FriendsBook(), you: YouModel(), saves: YouModel.saves(),
                  eventOfTheDay: EventOfTheDay(), dayPicks: DailyDayPicks(), notices: Notices(),
                  hello: .shared, saved: .shared, supabase: Supabase(auth: AuthStore.shared))
    }

    /// The account changed (`AuthStore.accountKey`): another one, none, or the same one logged in
    /// for real. Every model lets go of the last account here, in this turn, before anything is
    /// read for the new one. Answers once the new account's reads are done, for tests.
    @discardableResult
    func accountChanged(from old: String?, to new: String?, signedIn: Bool) -> Task<Void, Never> {
        var reads: [Task<Void, Never>] = []
        if old != new {
            // The last one's acceptances leave the hello pill and the bell (hello-drop 06); the
            // launch's saved account coming in is not another one.
            if old != nil { hello.forgetAccount() }
            // First, and animated, so the heart and the going line come in rather than pop.
            withAnimation(Motion.snappy) { actions.accountChanged(signedIn: signedIn) }
            // Views made before the first quiet account go up under it; another account's never do.
            if old != nil { townFeed.accountChanged() }
            you.accountChanged()
            saves.accountChanged()
            eventOfTheDay.accountChanged()
            dayPicks.accountChanged()
            notices.reset()
            // A first launch makes its account after the shell appears: today's open.
            if old == nil, signedIn { recordOpen() }
            // The feed reads again for who's going as this account sees it.
            reads.append(Task { await townFeed.reload() })
            // Whether you're in each group is this account's, once Search has read them.
            if searchModel.groupsLoaded { reads.append(Task { await searchModel.readGroupsAgain() }) }
            reads.append(Task { await you.refresh() })
            // The You row's groups, this account's.
            reads.append(Task { if let groups = await you.refreshGroups() { actions.read(groups) } })
            reads.append(Task { await eventOfTheDay.refresh() })
            reads.append(Task { await actions.moveUp(saved) })
            reads.append(Task { await notices.refresh() })
        }
        // Friends are a real account's, so the same one logging in for real starts them over too.
        friendsBook.reset()
        reads.append(Task { await friendsBook.refreshDot() })
        return Task { for read in reads { await read.value } }
    }

    /// Back to the app: today's open, the friends dot and the bell, and on Daily today's picks.
    func cameForward(on tab: Tab) {
        recordOpen()
        Task { await friendsBook.refreshDot() }
        Task { await notices.refresh() }
        // Back the next morning on Daily: today's picks, not yesterday's.
        if tab == .daily { Task { await eventOfTheDay.refresh() } }
    }

    /// Off to the background: the Town feed's views and opens go up now.
    func wentAway() {
        Task { await townFeed.send(always: true) }
    }

    /// Today's open, for the weekly numbers' reach (town-feed 26); a failed one is dropped.
    func recordOpen() {
        guard supabase.auth.userId != nil else { return }
        let api = CommunityAPI(auth: supabase.auth, send: supabase.send)
        Task { try? await api.recordOpen() }
    }
}
