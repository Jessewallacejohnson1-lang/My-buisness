//
//  RootView.swift
//  Block Party — the account gate over the tab shell: no account → onboarding's Welcome; an account → tabs.
//

import SwiftUI

/// The five destinations, in bar order (2026-09-18; Search took Business's slot on
/// 2026-09-29, Jesse; Friends came into the middle on 2026-11-01, BP app docs/plans/five-tabs).
/// `Int`-backed because the page
/// slide derives its direction from the order: moving right through the bar slides
/// the content the way a thumb expects.
enum Tab: Int, CaseIterable, Identifiable {
    /// The town feed — everything happening on the block, for everyone.
    case town
    /// The Block Party tab (Daily until five-tabs 04): the neighbour's own paper, the town feed
    /// crossed with what they follow.
    case blockParty
    /// Friends, in the middle: neighbours, requests, what friends are going to, and Groups.
    /// It was a page pushed from the Town bar's friends mark until 2026-11-01.
    case friends
    /// Search: the magnifier that sat at the Town bar's leading edge until 2026-09-29.
    case search
    /// Their own profile.
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .town:     return "Town"
        case .blockParty:    return "Block Party"
        case .friends:  return "Friends"
        case .search:   return "Search"
        case .you:      return "You"
        }
    }

    /// The resting glyph, drawn as an ink outline. The selected tab shows the filled
    /// `selectedSymbol` in the same ink, as Instagram's bar does. Search draws BP's own
    /// traced magnifier instead (`MagnifierGlyph`), and Town BP's own rounder house
    /// (`HouseGlyph`, 2026-10-30); their names are only large-content stand-ins.
    /// Daily's is not an SF Symbol: it names the `DailyMark` asset, the app
    /// icon's own Bp! letters (Jesse, 2026-10-29). Friends is Apple's two people, the mark that
    /// led the Town bar, as Facebook's Friends tab draws them.
    var symbol: String {
        switch self {
        case .town:     return "house"
        case .blockParty:    return "DailyMark"
        case .friends:  return "person.2"
        case .search:   return "magnifyingglass"
        case .you:      return "person"
        }
    }

    /// A magnifier has no fill: selected, it thickens instead (`MagnifierGlyph.bold`).
    /// Daily's Bp! is a logo with no outline form, so it stays solid and the grey
    /// bubble alone shows it's picked (Jesse, 2026-10-29).
    var selectedSymbol: String { self == .search || self == .blockParty ? symbol : symbol + ".fill" }

    /// One line on what the slot is for — shown by the placeholder screens, so an
    /// unbuilt tab reads as reserved rather than broken.
    var promise: String {
        switch self {
        case .town:     return "Everything happening on the block."
        case .blockParty:    return "Your paper — the town, filtered to what you follow."
        case .friends:  return "Your neighbors, and what they're going to."
        case .search:   return "Find a place, a happening, or someone on the block."
        case .you:      return "Your three weeks, and your profile."
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    /// Your profile (BP app codebase-health-2 09): made here, where it reads while onboarding is up,
    /// and handed to the shell's `AppSession`; every screen finds it in the environment.
    @State private var profile = ProfileModel()

    /// The neighbour's System / Light / Dark choice (its switch went with the town
    /// menu on 2026-10-25; a saved choice still applies). Held
    /// here because THIS is the root of the presentation `.preferredColorScheme`
    /// acts on — the request has to be made once, at the top, or a sheet and the
    /// screen behind it can disagree about what appearance they are in.
    @StateObject private var appearance = AppearanceStore.shared

    var body: some View {
        Group {
            #if DEBUG
            if LaunchFlags.has(.feedCardGallery) {
                // Preview the static feed-card states full-screen (bypassing the auth
                // gate) so the component can be verified headlessly.
                FeedCardGallery()
            } else if LaunchFlags.has(.townFeedPreview) {
                // The Town feed over fixtures, without auth or network, so
                // both card shapes and the ranked order can be screenshotted.
                TownFeedPreview()
            } else if LaunchFlags.has(.reviewQueuePreview) {
                // The admin Review queue over made-up and real items, without auth or
                // network. Its only real entry is the admin's profile, which a clean
                // simulator can't reach. Add `-review-queue-fail` to make every decision
                // fail, so the row coming back with a shake can be recorded. An item's
                // Event page reads the shell's actions, so the preview gets its own.
                ModerationView(preview: true)
                    .environment(RealLifeActions.preview)
            } else if LaunchFlags.has(.showSkeletons) {
                // Preview the per-tab shimmer skeletons (bypassing the auth gate).
                SkeletonGalleryPreview()
            } else {
                gate
            }
            #else
            gate
            #endif
        }
        // THE APPEARANCE SWITCH, APPLIED ONCE, HERE — on the ROOT of the window's
        // content, not on `gate` below. `gate` is only the auth branch: every DEBUG
        // preview root above bypasses it, and a preference attached there would
        // silently do nothing on exactly the screens used to verify it.
        //
        // `.system` resolves to no request, so the app keeps following the phone —
        // except while the Town feed holds the clock (`AppearanceStore.holdsClock`),
        // when it requests the phone's own scheme: with no request iOS 26 inks the
        // clock from whatever scrolls under it, white over every dark photo.
        // `.light` / `.dark` turn the hosting window's interface style over, which is
        // why every `Hue` token, every `.glassEffect` surface and every presented
        // sheet move together.
        //
        // NOT `.environment(\.colorScheme, …)`: that forces a value into the SwiftUI
        // tree only, leaving the UIKit-backed materials resolving the device's
        // appearance underneath the ink drawn on them. It was removed a commit ago
        // (see the note further down this file) and must not come back.
        .preferredColorScheme(appearance.requestedScheme)
        // Above the shell, its sheets and covers, and the DEBUG preview roots: Edit interests and
        // the name sheet open from all of them.
        .environment(profile)
        #if DEBUG
        // The preview roots above show cards without the shell; the shell sets its own.
        .environment(RealLifeActions.preview)
        #endif
        .onAppear {
            // ponytail: the first window scene; per-scene following if iPad
            // multi-window ever matters.
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
                appearance.followPhone(on: scene.screen)
            }
        }
        #if DEBUG
        // `-appearance <state>` / `-appearance-demo` set an appearance for screenshots;
        // nothing in the app sets one since the town menu went (2026-10-25).
        .task { appearance.applyDebugLaunchArguments() }
        #endif
    }

    /// Only an account someone made or logged into gets past the Welcome (Jesse, 2026-11-02: "dont
    /// allow people in app without logged in", BP app onboarding 27). Screenshot runs
    /// (`-skip-onboarding`, or `-onboarding` opening one step) and UI tests reinstall with no
    /// account, so DEBUG lets those in without one; a launch with none of them meets the gate.
    private var hasAccount: Bool {
        #if DEBUG
        if LaunchFlags.has(.skipOnboarding) || LaunchFlags.has(.uiTests) || LaunchFlags.has(.onboarding) {
            return true
        }
        #endif
        return auth.hasAccount
    }

    /// No account on the phone, once the launch has looked for a kept one.
    private var signedOut: Bool { !auth.booting && !hasAccount }

    /// Onboarding is up: the Welcome with no account, else until the flow is done.
    private var flowUp: Bool { !Self.tabsUp(hasAccount: hasAccount, onboardingUp: onboardingUp) }

    /// The tabs come up only with an account and with onboarding done.
    nonisolated static func tabsUp(hasAccount: Bool, onboardingUp: Bool) -> Bool { hasAccount && !onboardingUp }

    /// A neighbour's code from the iPhone camera (friends 07). The tabs open it (`MainTabsView.openCode`)
    /// but it's caught here, above the gate, so it's known whether it came with no account and it's
    /// let go when an account ends. Left to SwiftUI, a link opened behind the Welcome waits for the
    /// next `onOpenURL` to appear, whoever's account that is.
    @State private var code = WaitingCode()

    /// Onboarding's steps and answers on the phone; its finish hands them to Your profile, which
    /// stamps and saves them once an account exists (BP app codebase-health-2 10).
    @State private var onboarding = OnboardingStore()

    /// A first launch shows onboarding (BP app docs/plans/onboarding, on since ticket 24). Every
    /// screenshot run reinstalls the app, so DEBUG `-skip-onboarding` skips it for other screens'
    /// proofs (eyes.py adds it), and so does `-ui-tests` without `-onboarding`.
    private var onboardingUp: Bool {
        #if DEBUG
        if LaunchFlags.has(.skipOnboarding) || (LaunchFlags.has(.uiTests) && !LaunchFlags.has(.onboarding)) {
            return false
        }
        #endif
        // Finished here, the last screen stays up under the Done island till the answers land.
        return !onboarding.finished || (onboarding.finishedHere && !profile.answersLanded)
    }

    private var gate: some View {
        // Onboarding (the Welcome, Log in and Create account with no account), then the tabs.
        Group {
            if flowUp {
                // Finished, the last screen waits under the island for the answers: nothing on it answers.
                OnboardingFlow(store: onboarding)
                    .allowsHitTesting(!onboarding.finished || !hasAccount)
                    .transition(.opacity)
            } else {
                MainTabsView(profile: profile, code: $code, welcoming: onboarding.welcoming).transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: flowUp)
        .onOpenURL { code.opened($0, signedOut: signedOut) }
        .overlay {
            if onboarding.welcoming {
                OnboardingDone(name: onboarding.displayName ?? "") { onboarding.welcoming = false }
            }
        }
        // The launch's account, or a new one: your profile's read, and what onboarding owes it.
        .task(id: auth.userId) { await profile.arrived(onboarding) }
        // Signed out, or a token the server turned down: the next account starts on a clean Welcome.
        .onChange(of: signedOut, initial: true) { _, out in
            guard out else { return }
            onboarding.reset()
            profile.forgetOnboarding()
            code.foundNoAccount()
        }
        // An account ended (under-13's Close, a token the server turned down): a code still waiting
        // isn't the next person's. Not on `signedOut`, which fires as the launch finishes looking.
        .onChange(of: auth.userId) { old, new in if old != nil, new == nil { code.forget() } }
        .onChange(of: onboarding.finished) { _, done in
            guard done, onboarding.finishedHere else { return }
            // Here, before the tabs come up, so the hello pill doesn't say a second welcome.
            HelloDrop.saidWelcome()
            profile.finished(onboarding)
        }
    }
}

/// The authed shell: the five tabs and the sheets and covers they open.
struct MainTabsView: View {
    /// View on Map from a held Town card (inside-cards 24): today's Event with a spot opens our map on
    /// its bubble; any other, Apple Maps at its place (`EventMapRoute`). Its spot is read for a second at
    /// most, so a slow network still answers the tap; today's with no place either way, our map.
    private func viewOnMap(_ event: FeedCardItem) {
        Task {
            let now = TodayBubbleClock.now()
            var spot = false
            if EventMapRoute.today(event, now: now) {
                let auth = auth
                let reading = Task { try? await CommunityAPI(auth: auth).eventSpots([event.id]) }
                let timeout = Task {
                    try? await Task.sleep(for: HostOpener.readWait)
                    reading.cancel()
                }
                spot = await reading.value?[event.id] != nil
                timeout.cancel()
            }
            switch EventMapRoute.route(event, now: now, spot: spot) {
            case .appleMaps(let url):
                await UIApplication.shared.open(url)
            case .ourMap, nil:
                mapOpener?.eventID = event.id
                showMap = true
            }
        }
    }

    /// In its own app when that's on the phone, else in the in-app browser.
    private func openLink(_ url: URL) {
        Task {
            if await !UIApplication.shared.open(url, options: [.universalLinksOnly: true]) {
                InAppBrowser.open(url)
            }
        }
    }

    /// A website stays inside Block Party, as Instagram's do, so the tap can't lose your place
    /// (Jesse, 2026-11-06, BP app backlog 21). Mail, Settings and Apple Maps go as ever.
    private var opensLinks: OpenURLAction {
        OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased()),
                  url.host()?.lowercased() != "maps.apple.com" else { return .systemAction }
            openLink(url)
            return .handled
        }
    }

    /// Where a tap on the hello pill goes.
    @MainActor
    private func openHello(_ target: HelloDrop.Target) {
        switch target {
        case .event(let card): path.append(card)
        case .group(let group): path.append(group)
        case .person(let person): path.append(person)
        case .town: if tab != .town { select(.town) }
        // An Event from something you follow (hello-drop 07): its page while the feed has it, else Town.
        case .eventID(let id):
            if let card = townFeed.cards.first(where: { $0.id == id }) {
                path.append(card)
            } else if tab != .town {
                select(.town)
            }
        // As the news card: the post's own app when it's on the phone, else the in-app browser.
        case .news(let post):
            openLink(post.post)
        }
    }

    @State private var tab: Tab
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    /// A neighbour's code waiting for these tabs (`RootView`).
    @Binding private var code: WaitingCode
    /// Onboarding's Done island is up.
    private let welcoming: Bool
    private let launch = LaunchStage.shared

    init(profile: ProfileModel, code: Binding<WaitingCode>, welcoming: Bool) {
        _code = code
        self.welcoming = welcoming
        // Town, or a DEBUG `-open-tab` override.
        _tab = State(initialValue: MainTabsView.initialTab())
        // `-open-map` raises the map on launch, for screenshots: its real way in is a tap.
        _showMap = State(initialValue: LaunchFlags.has(.openMap))
        let session = AppSession(profile: profile)
        _session = State(initialValue: session)
        // Back after iOS shut the app down: the feed you left, and the Event page on top while the
        // feed still has it (`LeftOff`).
        if let left = LeftOff.claim() {
            session.townFeed.resume(left)
            session.eventOfTheDay.showKept()
            if let tab = Tab(rawValue: left.tab) { _tab = State(initialValue: tab) }
            if let id = left.event, let card = session.townFeed.cards.first(where: { $0.id == id }) {
                _path = State(initialValue: NavigationPath([card]))
                _reopened = State(initialValue: id)
                LeftOff.pageToReopen = id
            }
        }
    }

    /// DEBUG-only: `-open-tab town|daily|friends|search|you` launch argument selects
    /// the starting tab, so simulator verification can screenshot any tab
    /// without UI driving. No effect in release builds or without the flag.
    private static func initialTab() -> Tab {
        #if DEBUG
        // Your Profile is the You tab now (five-tabs 03); the old flag still lands there.
        if LaunchFlags.has(.openProfile) { return .you }
        if let tab = LaunchFlags.value(.openTab) {
            switch tab {
            case "town":     return .town
            case "daily", "blockparty": return .blockParty
            case "friends":  return .friends
            case "search":   return .search
            case "you":      return .you
            default:         break
            }
        }
        #endif
        return .town
    }

    /// The models every tab shares, and what an account change, coming back and going away do
    /// to them (BP app codebase-health 22).
    @State private var session: AppSession
    private var searchModel: SearchModel { session.searchModel }
    private var townFeed: TownFeed { session.townFeed }
    private var actions: RealLifeActions { session.actions }
    private var friendsBook: FriendsBook { session.friendsBook }
    private var chats: ChatBook { session.chats }
    private var you: YouModel { session.you }
    private var saves: YouModel { session.saves }
    private var eventOfTheDay: EventOfTheDay { session.eventOfTheDay }
    private var dayPicks: DailyDayPicks { session.dayPicks }
    private var followingNews: FollowingNews { session.followingNews }
    private var notices: Notices { session.notices }
    /// The day picked in Daily's week (daily-tab 16), nil for today: kept here so it stays while
    /// you switch tabs, and a new launch opens on today.
    @State private var dailyDay: String?
    /// Your Going in your iPhone Calendar, kept up to date from here while its switch in
    /// Profile is on (BP app docs/plans/you-tab, ticket 05).
    @State private var calendarSync = CalendarSync()
    /// The shell stack's path: the bell, a neighbour's code and a followed row push onto it.
    @State private var path = NavigationPath()
    /// The Event page back on top after a restart: it's the same open, so it isn't counted again.
    @State private var reopened: String?
    /// A Place's business page from a host row (follows 08), over the whole shell as Search's is
    /// over its tab.
    @State private var placeOpener = BusinessOpener()
    /// Made once, so the cards it reaches don't redraw each time the shell does.
    @State private var hostOpener: HostOpener?
    /// The map, presented full-screen from the map disc in the Town bar rather than
    /// living in the tab bar. Its own state belongs to `SJMapView`.
    @State private var showMap = false
    /// Made once, as `hostOpener` is.
    @State private var mapOpener: EventMapOpener?
    /// New post, from the Town bar's + (BP app references/post-screen).
    @State private var creating = false
    /// Direction of the last tab change — whether the incoming screen slides in
    /// from the trailing edge (moving *forward* through the tab order) or the
    /// leading edge (moving back). Set in `select(_:)` right before the animation.
    @State private var slideForward = true
    /// The Town feed is reading down (`TabBarCompactKey`): the tab bar rests small.
    @State private var tabBarCompact = false
    /// Your profile: the You tab's photo in the bar, and New post's name line.
    private var profile: ProfileModel { session.profile }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What a host row opens (follows 08): a person's page, a team's, a page, a board's meetings, or
    /// a Place's business page flying out of its picture, as Search opens it; a Place Search can't
    /// open (no logo) opens nothing.
    private func makeHostOpener() -> HostOpener {
        HostOpener(
            opens: { row in
                switch row.targetType {
                case .profile, .team, .page, .board: true
                case .place: placeItem(row) != nil
                default: false
                }
            },
            open: { row, picture in
                switch row.targetType {
                case .profile: path.append(FollowedPersonRoute(row: row))
                case .team: path.append(Game.Team(followed: row))
                case .page: path.append(TownPageKind.of(row))
                case .board:
                    path.append(TownBoardRoute(board: .init(id: row.targetId, name: row.name,
                                                            following: actions.follow(row.target).isFollowing, next: nil),
                                               city: row.kind ?? Town.cityPage))
                case .place:
                    guard let item = placeItem(row), let logo = item.logo else { return }
                    placeOpener.open(item, from: .init(logo: picture, box: picture, radius: picture.width / 2,
                                                       shadow: logo.shadow, fades: row.pictureKind != "logo"))
                default: break
                }
            },
            group: { id in searchModel.groups.lazy.compactMap(\.townGroup).first { $0.id == id } },
            push: { path.append($0) })
    }

    /// A Place's page as Search has it; nil for one Search can't open.
    private func placeItem(_ row: FollowRow) -> SearchItem? {
        searchModel.items.first { $0.placeID == row.targetId && $0.opens }
    }

    /// One stack over the whole shell, so a pushed event page covers the tab bar
    /// and the edge swipe brings the town back under the finger. The shell draws
    /// its own chrome, so the system bar is hidden with `.toolbar(.hidden)` —
    /// never `navigationBarBackButtonHidden`, which kills the swipe back.
    /// `SwipeBack` keeps that swipe alive once the pushed page hides the bar too.
    var body: some View {
        NavigationStack(path: $path) {
            shell
                .toolbar(.hidden, for: .navigationBar)
                .background { SwipeBack().frame(width: 0, height: 0) }
                .navigationDestination(for: FeedCardItem.self) { item in
                    EventPage(item: item)
                        // Its menu's Not interested and Report.
                        .environment(townFeed)
                        // An open, for popularity (ticket 20): only from the Town feed,
                        // not Daily, which pushes the same page.
                        .onAppear {
                            if reopened == item.id {
                                reopened = nil
                            } else if tab == .town {
                                townFeed.views.opened(item.id)
                            }
                        }
                }
                // Messages and a chat (five-tabs 05).
                .navigationDestination(for: ChatRoute.self) { route in
                    switch route {
                    case .messages: MessagesPage()
                    case .requests: RequestsPage()
                    case .chat(let chat): ChatPage(chat: chat)
                    case .person(let person): ChatPage(chat: nil, person: person)
                    case .group(let id, let others, let name):
                        ChatPage(chat: nil, groupID: id, groupOthers: others, groupName: name)
                    case .going(let card, let isHost):
                        ChatPage(chat: nil, event: card, eventHost: isHost)
                    case .groupChat(let group):
                        ChatPage(chat: nil, club: group)
                    }
                }
                .navigationDestination(for: FriendsRoute.self) { route in
                    switch route {
                    case .contacts: FriendsContactsPage()
                    case .allFriends: FriendsAllPage(groups: false)
                    case .groups: FriendsAllPage(groups: true)
                    }
                }
                // A neighbour's page, from any name or face: the Friends page or Search.
                .navigationDestination(for: Neighbor.self) { NeighborPage(neighbor: $0) }
                // A local team's page, from its picture on a game card (hello-drop 03).
                .navigationDestination(for: Game.Team.self) { TeamPage(team: $0) }
                // A group's page, from Search's Groups shelf (rsvp-and-groups 05).
                .navigationDestination(for: TownGroup.self) { GroupPage(group: $0) }
                // The Town's own page or its City's, from the Town bar's wordmark menu or Daily's
                // Town logo, and a board's, from its row (follows 04).
                .navigationDestination(for: TownPageKind.self) { TownPageView(shown: $0) }
                .navigationDestination(for: TownBoardRoute.self) { TownBoardPage(route: $0) }
                // A person's page from a host row (follows 08).
                .navigationDestination(for: FollowedPersonRoute.self) { FollowedNeighborPage(row: $0.row) }
                // The bell's page (school-activities 04).
                .navigationDestination(for: NotificationsRoute.self) { _ in NotificationsPage().environment(townFeed) }
                .navigationDestination(for: NoticeEventRoute.self) { route in
                    EventPage(item: route.item).environment(townFeed)
                }
        }
        // A host's name on a card or an Event page opens its own page (follows 08).
        .environment(\.hostOpener, hostOpener)
        .environment(\.viewOnMap, mapOpener)
        // A neighbour's code from the iPhone camera (friends 07): their page once the launch and the
        // Done island are over, so it opens where it can be seen (Jesse, 2026-11-06).
        .onChange(of: code.id, initial: true) { openWaitingCode() }
        .onChange(of: codeReady) { openWaitingCode() }
        .sheet(isPresented: $creating) {
            NewPostSheet(places: NewEventPlaces.ordered(searchModel.items), me: profile, onShared: shared, onPosted: posted)
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        // `-new-post`: New post open at launch; `-new-post-state <state>`: the faded card on Town.
        .task {
            if let state = LaunchFlags.value(.newPostState) { PostOutbox.shared.sample(state) }
            if LaunchFlags.has(.newPost) { creating = true }
        }
        #endif
        .overlay { BusinessPage().environment(placeOpener) }
        .onAppear {
            placeOpener.reduceMotion = reduceMotion
            if hostOpener == nil { hostOpener = makeHostOpener() }
            if mapOpener == nil { mapOpener = EventMapOpener(viewOnMap) }
        }
        // The day's first open says hello, then one thing about the town (hello-drop 01).
        .overlay(alignment: .top) {
            HelloDropView(pill: session.helloPill, open: openHello)
        }
        // The iPhone Calendar follows the Going (ticket 05).
        .background { CalendarFollower(sync: calendarSync) }
        // An Event's "Send in a chat" (`ShareCenter`).
        .sheet(item: Bindable(chats).sending) { ChatPicker(card: $0) }
        // Outside the stack, so pushed pages and sheets read the same one.
        .environment(actions)
        // A game's newest score, on whichever page shows it (codebase-health-2 08).
        .environment(session.liveGames)
        // The bell's dot and its page.
        .environment(notices)
        .environment(friendsBook)
        .environment(chats)
        .onAppear {
            ShareCenter.shared.sendInChat = { chats.sending = $0 }
            // The pencil's sheet and a Profile open a chat on the shell's stack.
            chats.push = { path.append($0) }
        }
        // A neighbour's page lays their groups and your shared plans over the You tab's reads.
        .environment(you)
        // The friend sheet and its refusals (follows 05).
        .friendSurfaces(friendsBook, actions: actions)
        // Each list the Town feed lands, kept or read: Events of what you follow found since the
        // last look go to the hello pill and the bell (hello-drop 07).
        .onChange(of: townFeed.entries?.map(\.id)) {
            HelloInbox.shared.look(at: townFeed.entries?.compactMap(\.card) ?? [])
        }
        // Another account, none, or the same one logged in for real: the session resets every
        // model, then reads for this one, so Join comes up at once even on an event page already
        // open. Here, not on the stack's root, which a pushed page covers. The key's first part
        // is the account's id, "" for none.
        .onChange(of: auth.accountKey) { old, _ in
            session.accountChanged(from: old[0].isEmpty ? nil : old[0], to: auth.userId,
                                   signedIn: auth.isSignedIn)
        }
        // Onboarding's answers landed after the tabs opened: the feed reads again, sorted to them.
        .onChange(of: profile.lateLandings) { Task { await townFeed.reload() } }
        .task { await session.launched() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.wentAway() }
            if phase == .active { session.cameForward(on: tab) }
        }
        // The notification, not `scenePhase`: that waits on a redraw, and on a busy phone iOS can
        // suspend the app first (measured, 2026-11-06).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            session.keepSpot(on: tab)
        }
        .onAppear { openLaunchPages() }
        .environment(\.openURL, opensLinks)
    }

    /// The pages DEBUG launch flags open (`-open-friends`, `-open-team` and the rest). Its own
    /// function, out of `body`: Xcode 26.6 couldn't type-check the body with it inside in time.
    private func openLaunchPages() {
        // DEBUG: `-open-friends` lands on the Friends tab.
        if LaunchFlags.has(.openFriends) { tab = .friends }
        if LaunchFlags.has(.openNotifications) { path.append(NotificationsRoute()) }
        #if DEBUG
        // `-open-team <uuid>` pushes that local school's page (school-activities 02).
        if let id = LaunchFlags.value(.openTeam),
           let team = try? JSONDecoder().decode(Game.Team.self, from: Data(
               #"{"name":"","id":"\#(id)","local":true}"#.utf8)) {
            path.append(team)
        }
        // `-open-page town|city` pushes that Town page (follows 04).
        if let kind = LaunchFlags.value(.openPage).flatMap({ TownPageKind(slug: $0) }) {
            path.append(kind)
        }
        // `-open-event <id>` pushes that Event's page once the Town feed has it (e1 to e7
        // under `-town-samples`, or a live id), so a photo check needn't scroll for it.
        if let id = LaunchFlags.value(.openEvent) {
            Task {
                for _ in 0..<120 {
                    if let card = townFeed.entries?.lazy.compactMap(\.card).first(where: { $0.id == id }) {
                        path.append(card)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        #endif
    }

    /// The friends going each day under Daily's week: the Town feed's, or under DEBUG
    /// `-daily-samples` the sample faces.
    private var dailyFriends: [String: [FeedFriend]] {
        #if DEBUG
        if DailySamples.on { return DailyWeek.sampleFriends(from: DailyClock.now(Date())) }
        #endif
        return DailyWeek.friendsGoing(in: townFeed.cards)
    }

    /// The Town bar's +: New post, for a real account (Jesse, 2026-11-01: "anyone signed in").
    private func create() {
        guard auth.hasAccount else { return }
        creating = true
    }

    /// A post New post saved: faded on Town until the check answers; a yes reads Town again.
    private func posted(_ sent: PostOutbox.Sent) {
        PostOutbox.shared.check(sent, api: CommunityAPI(auth: AuthStore.shared)) { await townFeed.reload() }
    }

    /// What New post's Event shared: the pill says it at once, and Town reads again so it's there.
    private func shared(_ posted: HelloItem.Posted) {
        HelloInbox.shared.add(.posted(posted))
        Task { await townFeed.reload() }
    }

    private var codeReady: Bool { launch.finished && !welcoming }

    private func openWaitingCode() {
        if let taken = code.take(ready: codeReady) { openCode(taken.id, addFriend: taken.addFriend) }
    }

    /// A neighbour's code (friends 07): their page on the shell's stack, over the map, once
    /// `get_neighbor` answers; your own opens your Profile, the You tab. With no signal then, nothing
    /// opens and they scan again (Jesse, 2026-11-06). `addFriend`: the request goes first, so the
    /// page opens on Cancel request.
    private func openCode(_ id: String, addFriend: Bool) {
        showMap = false
        if id == auth.userId?.lowercased() {
            path = NavigationPath()
            tab = .you
            return
        }
        guard auth.hasAccount else { return }
        Task {
            guard let neighbor = try? await Neighbor.read(id) else { return }
            if addFriend { friendsBook.requestFromCode(neighbor) }
            path.append(neighbor)
        }
    }

    private var shell: some View {
        ZStack(alignment: .bottom) {
            Hue.paper.ignoresSafeArea()

            // Tab content only — the tab BAR lives OUTSIDE this GlassEffectContainer,
            // deliberately. When the two shared one (2026-07-19 "one continuous bottom
            // glass"), the map sheet's glass metaball-merged with the bar into a single
            // tall panel on the Map tab ONLY, so switching tabs visibly swapped between
            // "one attached panel" and "a lone floating capsule" — two different bars
            // (Jesse's round-2 ask 6). Out here the bar's silhouette can never fuse
            // with anything: one identical capsule on every tab.
            GlassEffectContainer(spacing: 22) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .town:
                            TownView(
                                onOpenMap: { showMap = true },
                                onOpenNotifications: { path.append(NotificationsRoute()) },
                                onCreate: create,
                                onOpenPage: { path.append($0) },
                                townFeed: townFeed,
                                eventOfTheDay: eventOfTheDay,
                                places: searchModel.place
                            )
                        // Daily shows paper while its first read is out, then its page: the week
                        // on top, and under it the picked day, or the named, reserved slot on a
                        // day with nothing in it.
                        case .blockParty:
                            Group {
                                if DailySpotlight.today != nil || eventOfTheDay.events != nil {
                                    DailyPage(spotlight: DailySpotlight.today, events: eventOfTheDay.events ?? [],
                                              picked: $dailyDay, dayPicks: dayPicks, friends: dailyFriends,
                                              cards: townFeed.cards, posts: townFeed.posts,
                                              // A story you hid or whose place you muted goes here too.
                                              news: followingNews.items.filter { !townFeed.hides.isHidden(id: $0.id, host: $0.place) })
                                        // Following's post and News cards (daily-tab 23): the •••'s Delete and
                                        // the hold's Not interested and Mute.
                                        .environment(townFeed)
                                } else {
                                    Hue.paper.ignoresSafeArea()
                                }
                            }
                            .task { await eventOfTheDay.refresh() }
                            .task { await followingNews.refresh() }
                        // Neighbours and Groups (five-tabs 02): the Friends page as a tab, the
                        // Town feed's cards for what friends are going to.
                        case .friends:
                            FriendsHomePage(tab: true, cards: townFeed.cards)
                                // The Town tab reads the feed; a launch straight onto Friends reads it here.
                                .task { if townFeed.entries == nil { await townFeed.refresh() } }
                        // Places, businesses and the Town feed's Events (five-tabs 04).
                        case .search:
                            // A failed read with nothing kept is no Events, not a shimmer for good.
                            SearchPage(model: searchModel,
                                       cards: townFeed.entries == nil ? (townFeed.failed ? [] : nil) : townFeed.cards)
                                // The Town tab reads the feed; a launch straight onto Search reads it here.
                                .task { if townFeed.entries == nil { await townFeed.refresh() } }
                        // Your Profile, with your full Calendar and Agenda (five-tabs 03).
                        case .you:
                            ProfileView(model: session.profile, saves: saves)
                                // Settings' Calendar switch, and what Muted and Following read.
                                .environment(calendarSync)
                                .environment(townFeed)
                                .environment(searchModel)
                        }
                    }
                    // Identity keyed on the tab so a switch is an insertion+removal that
                    // the page transition can animate: the outgoing screen slides off one
                    // edge while the incoming slides in from the other, in lockstep — a
                    // swipe to the new tab rather than a flat swap.
                    .id(tab)
                    .transition(pageTransition)
                    // NO LOADING COVER. A tab that is still fetching renders its own
                    // skeleton in its own layout (Features/Components/Skeleton.swift);
                    // nothing is ever hidden behind a full-screen cover. The dark
                    // rainbow-wave cover that used to sit here was deleted 2026-09-21 —
                    // it had begun covering content that was already on screen.

                }
            }
            .onPreferenceChange(TabBarCompactKey.self) { tabBarCompact = $0 }

            BlockPartyTabBar(selection: tab, onSelect: select,
                             avatarURL: profile.avatarUrl, compact: tabBarCompact,
                             friendsDot: friendsBook.dot || chats.unread,
                             friendsLabel: friendsBook.dot ? "Friends, new friend request"
                                 : chats.unread ? "Friends, unread message" : nil)
                // Apple's measured spot: 21pt above the PHYSICAL bottom edge, not
                // above the home-indicator safe area. The full-height frame is what
                // lets `ignoresSafeArea` reach the edge: on the fixed-height bar alone
                // it moved nothing, and the capsule sat 34pt too high (measured).
                .padding(.bottom, TabBarMetric.margin)
                // It dips as the launch's Bp! lands in it (Jesse, 2026-11-02).
                .launchCatch()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .zIndex(10)
            // THE `.environment(\.colorScheme, .light)` THAT USED TO BE HERE IS GONE.
            //
            // It existed because the app was light-only BY CONSTRUCTION — every `Hue`
            // token was a fixed light hex — while `.glassEffect` (the tab bar AND the
            // map sheet) was the one appearance-ADAPTIVE surface in the tree. Under
            // iOS Dark Mode the glass resolved charcoal and everything drawn on it
            // stayed light, so the peek line and the tab labels fell to ~1:1: the
            // primary navigation, unreadable. Its own comment named the exit — "a full
            // dark ramp + a dark basemap palette" — and that is what has now been
            // built: `Hue` carries both appearances, so ink on charcoal glass is
            // near-white and the contrast runs the right way round.
            //
            // The basemap did NOT get a dark palette, and deliberately: Mapbox renders
            // light-v11 cartography in both modes, so map INK is pinned to its light
            // value instead (`Color.onLightCanvas`). See `BlockPartyColor`.
        }
        // The map is a destination, not a tab: full screen, with its own close, and its card
        // opens the Event page on the map's own stack (BP app references/map-reset).
        .fullScreenCover(isPresented: $showMap, onDismiss: { mapOpener?.eventID = nil }) {
            SJMapView(onClose: { showMap = false }, request: mapOpener)
                .environment(\.hostOpener, nil)
                .environment(actions)
                .environment(friendsBook)
                .environment(townFeed)
                .environment(session.liveGames)
        }
        #if DEBUG
        .onAppear {
            // `-tab-cycle` walks the bar end to end on a loop so the bubble travel, the
            // icon swap and the page slide can be recorded headlessly — there is no
            // tap automation in this setup, and motion is the whole point of the bar.
            if LaunchFlags.has(.tabCycle) {
                cycleTabs(from: 1)
            }
            if LaunchFlags.has(.shareDemo) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    ShareCenter.shared.present(.event(title: "Farmers Market",
                                                      dateLabel: "Saturday, Jul 12",
                                                      time: "9:00 AM",
                                                      location: "College Ave"))
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// Walks forward through the bar, one tab every 1.4s, wrapping at the end. Each
    /// step goes through `switchTab`, so what gets recorded is the real transition,
    /// not a preview of it.
    private func cycleTabs(from index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            let all = Tab.allCases
            switchTab(to: all[index % all.count])
            cycleTabs(from: index + 1)
        }
    }
    #endif

    /// A tab-bar tap. The haptic lives here (not the button) so it fires once per
    /// real change — re-tapping the current tab is a no-op.
    private func select(_ newTab: Tab) {
        guard newTab != tab else { return }
        Haptics.selection()
        switchTab(to: newTab)
    }

    /// The tab change itself, with its horizontal page slide. Direction is derived
    /// from the tab order (`Tab: Int`), so moving right through the bar slides content
    /// the way your thumb expects. The bar's bubble rides its own fitted spring
    /// (`TabBarMetric.travel`); Reduce Motion swaps both for a short crossfade.
    /// Shared, so a route-driven change feels exactly like a tapped one.
    private func switchTab(to newTab: Tab) {
        slideForward = newTab.rawValue > tab.rawValue
        withAnimation(reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.44, dampingFraction: 0.86)) {
            tab = newTab
        }
        if newTab == .town { Task { await friendsBook.refreshDot() } }
    }

    /// The coupled slide: incoming enters from the edge you're travelling toward,
    /// outgoing exits the opposite edge (pure `.move`, no fade, so the two full-
    /// bleed screens tile seamlessly). Reduce Motion → crossfade, no positional
    /// motion.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading),
            removal:   .move(edge: slideForward ? .leading  : .trailing)
        )
    }
}

/// The stack's swipe back, kept alive while the bar is hidden. With the event page
/// hiding the bar as well, UIKit refused every swipe back (recorded 2026-09-26; with the
/// bar shown it followed the finger). Two recognizers do that swipe on iOS 26:
/// `interactivePopGestureRecognizer` from the leading edge, and
/// `interactiveContentPopGestureRecognizer` anywhere else on the page. This delegate lets
/// both begin whenever there is a page to go back to and no push or pop is running; at
/// the root they stay off, as UIKit leaves them. That is a defensive guard against the
/// known root-pop freeze, which did not reproduce here on iOS 26.5. With a page to go back
/// to, the edge one also beats a horizontal scroll under the finger, so an edge swipe on the
/// photo carousel pops the page (`EventCardPhotoTapTests`), while a swipe that starts on a
/// photo away from the edge still pages or rubber-bands the carousel. Vertical scrolls, and
/// every scroll at the root, never wait on it.
struct SwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactiveContentPopGestureRecognizer?.delegate = self
        }

        /// Both swipes begin only with a page to go back to. Off at the root is a guard
        /// against the known root-pop freeze; it did not reproduce on iOS 26.5.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation = navigationController else { return false }
            return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
        }

        /// With a page to go back to, the edge swipe beats a horizontal scroll under the finger
        /// (the photo carousel): its pan waits for the edge swipe to fail, which it does at
        /// once off the edge. A vertical scroll (the page, the feed) never waits, and nothing
        /// waits at the root, where the edge swipe can't begin.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            guard let navigation = navigationController,
                  gestureRecognizer === navigation.interactivePopGestureRecognizer,
                  navigation.viewControllers.count > 1,
                  other is UIPanGestureRecognizer,
                  let scroll = other.view as? UIScrollView
            else { return false }
            // A point of slack: the event page's vertical scroll measures a fraction of a
            // point off its own width (420.17 in 420.33 on iPhone Air).
            return scroll.isPagingEnabled || scroll.contentSize.width > scroll.bounds.width + 1
        }
    }
}
