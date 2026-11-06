//
//  AppSession.swift
//  Block Party — the models every tab shares, and what happens to them when the shell comes up,
//  the account changes, the app comes back or it goes away (BP app codebase-health 22). The shell
//  holds one.
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
    /// Every game's newest score while it's played, for the Town feed's cards, an Event page from any
    /// tab and the map, on the app's one `club_events` connection (BP app codebase-health-2 08).
    let liveGames: LiveGames
    /// Search's places and recents, kept so the tab doesn't fetch the Town's places again each
    /// time it comes back. Its groups reads tell `actions`.
    let searchModel: SearchModel
    /// Friend requests, friends and the dot on the Friends tab, so a row and a person's page
    /// agree (BP app docs/plans/friends, ticket 03).
    let friendsBook: FriendsBook
    /// Your chats, the unread dot and their live updates (BP app five-tabs 05).
    let chats: ChatBook
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
    /// Your profile (codebase-health-2 09): the You tab, the tab bar's photo, New post's name line.
    /// The root view makes it, since it reads while onboarding is up, before the shell exists.
    let profile: ProfileModel
    /// What the hello pill says next, and its reads (codebase-health-2 14). No line in `accountChanged`:
    /// it keeps no account's data, only when it last read and the phone's own cut-offs.
    let helloPill: HelloPill
    private let hello: HelloInbox
    /// Saves this phone kept before they moved to the server.
    private let saved: SavedStore
    private let supabase: Supabase
    private let phone: UserDefaults

    init(actions: RealLifeActions, townFeed: TownFeed, searchModel: SearchModel, friendsBook: FriendsBook,
         you: YouModel, saves: YouModel, eventOfTheDay: EventOfTheDay, dayPicks: DailyDayPicks,
         notices: Notices, profile: ProfileModel, hello: HelloInbox,
         saved: SavedStore, supabase: Supabase, liveGames: LiveGames? = nil, chats: ChatBook? = nil,
         phone: UserDefaults = .standard) {
        self.actions = actions
        self.townFeed = townFeed
        self.liveGames = liveGames ?? LiveGames(listen: { _ in })
        let chats = chats ?? ChatBook(supabase: supabase)
        self.chats = chats
        actions.memberWritten = { Task { await chats.refresh() } }
        self.searchModel = searchModel
        self.friendsBook = friendsBook
        self.you = you
        self.saves = saves
        self.eventOfTheDay = eventOfTheDay
        self.dayPicks = dayPicks
        self.notices = notices
        self.profile = profile
        self.hello = hello
        helloPill = HelloPill(reads: .live(you: you, townFeed: townFeed, friendsBook: friendsBook, actions: actions,
                                           supabase: supabase),
                              inbox: hello, phone: phone)
        self.saved = saved
        self.supabase = supabase
        self.phone = phone
    }

    /// The live models, or the DEBUG samples each one's launch flags pick. Every one reads and
    /// writes through `supabase`, the app's one client (`Supabase.app`) unless a test hands it a
    /// fake, so none of them can go around the account the session is on. `phone` and `saved`
    /// are where the models keep what stays on the phone; a test hands its own.
    convenience init(profile: ProfileModel, supabase: Supabase? = nil, phone: UserDefaults? = nil,
                     saved: SavedStore? = nil) {
        let supabase = supabase ?? .app
        let actions = RealLifeActions(supabase: supabase)
        let live = LiveGames(token: { try? await supabase.auth.validAccessToken() })
        self.init(actions: actions, townFeed: TownFeed(supabase: supabase, actions: actions, live: live),
                  searchModel: SearchModel(supabase: supabase, defaults: phone ?? .standard, actions: actions),
                  friendsBook: FriendsBook(supabase: supabase), you: YouModel(supabase: supabase),
                  saves: YouModel.saves(supabase: supabase), eventOfTheDay: EventOfTheDay(supabase: supabase),
                  dayPicks: DailyDayPicks(supabase: supabase),
                  notices: Notices(supabase: supabase, keep: phone ?? .standard),
                  profile: profile,
                  hello: phone.map { HelloInbox(keep: $0) } ?? .shared, saved: saved ?? .shared,
                  supabase: supabase, liveGames: live, chats: ChatBook(supabase: supabase, sockets: true),
                  phone: phone ?? .standard)
    }

    /// The shell came up: today's open and onboarding's follows, then its reads side by side, so a
    /// slow one holds up nothing. Runs for as long as the shell is up: the Town feed's views and
    /// opens go up every 30 seconds, on any tab and under a pushed page (ticket 20), and the shell
    /// going cancels the lot. The DEBUG demo screens outside the shell never send.
    func launched(sendEvery: Duration = .seconds(TownFeed.sendEvery)) async {
        recordOpen()
        takeFollows()
        await withDiscardingTaskGroup { jobs in
            // Search's places, so a Place host opens its page from the first tap.
            jobs.addTask { @MainActor in if !self.searchModel.placesLoaded { await self.searchModel.load() } }
            jobs.addTask { await self.friendsBook.refreshDot() }
            // Event saves this phone kept before they moved to the server go up once, at launch
            // with an account or when one arrives (`accountChanged`).
            jobs.addTask { await self.actions.moveUp(self.saved) }
            // Canceled or moved since you last looked.
            jobs.addTask { await self.notices.refresh() }
            jobs.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: sendEvery)
                    await self.townFeed.send()
                }
            }
        }
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
            // Only lets go: the root view's read is the one for each new account (it runs while
            // onboarding is up too, before this shell exists).
            profile.accountChanged()
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
        // So are chats: nothing of the last account's stays, and this one's go live.
        chats.accountChanged()
        chats.start()
        reads.append(Task { await chats.refresh() })
        // After `actions` let the last account go; the same one logging in for real can take them.
        takeFollows()
        return Task { for read in reads { await read.value } }
    }

    /// Back to the app: today's open, the friends dot and the bell, and on Daily today's picks.
    func cameForward(on tab: Tab) {
        LeftOff.clear()
        liveGames.away(false)
        recordOpen()
        Task { await friendsBook.refreshDot() }
        Task { await notices.refresh() }
        chats.start()
        Task { await chats.refresh() }
        // Back the next morning on Daily: today's picks, not yesterday's.
        if tab == .blockParty { Task { await eventOfTheDay.refresh() } }
        // Back the next day on Search: today's Events, not yesterday's (five-tabs 04).
        if tab == .search { Task { await townFeed.refresh() } }
    }

    /// Off to the background: the Town feed's views and opens go up now.
    func wentAway() {
        liveGames.away(true)
        chats.stop()
        Task { await townFeed.send(always: true) }
    }

    /// Where you were stays on the phone, in case iOS shuts the app down while it's away (`LeftOff`).
    func keepSpot(on tab: Tab) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene })?
            .session.persistentIdentifier else { return }
        let spot = townFeed.spot
        LeftOff.save(LeftOff(at: Date(), scene: scene, tab: tab.rawValue,
                             event: LeftOff.page, eventY: LeftOff.page.flatMap { LeftOff.pageY[$0] } ?? 0,
                             feed: spot.feed, top: spot.top, feedY: spot.y, poster: spot.poster))
    }

    /// Today's open, for the weekly numbers' reach (town-feed 26); a failed one is dropped.
    private func recordOpen() {
        guard supabase.auth.userId != nil else { return }
        let api = CommunityAPI(supabase)
        Task { try? await api.recordOpen() }
    }

    /// Onboarding's Follow 3 picks wait on the phone until a signed-up account can take them (BP
    /// app onboarding 22): at launch, and when one arrives.
    private func takeFollows() {
        guard actions.hasAccount else { return }
        for target in OnboardingStore.takeFollows(phone) { actions.followOn(target) }
    }
}
