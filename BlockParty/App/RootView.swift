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
            } else if LaunchFlags.has(.dailyFeedPreview) {
                // The Daily social feed over fixtures, without auth or network, so
                // both card shapes and the ranked order can be screenshotted.
                DailyFeedPreview()
            } else if LaunchFlags.has(.reviewQueuePreview) {
                // The admin Review queue over the City's real found events, without
                // auth or network. Its only real entry is the admin's profile, which a
                // clean simulator can't reach. Add `-review-queue-fail` to make every
                // decision fail, so the row coming back with a shake can be recorded.
                ModerationView(preview: true)
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
    private var flowUp: Bool { onboardingUp || !hasAccount }

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
                MainTabsView(profile: profile).transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: flowUp)
        .overlay {
            if onboarding.welcoming {
                OnboardingDone(name: onboarding.displayName ?? "") { onboarding.welcoming = false }
            }
        }
        // The launch's account, or a new one: your profile's read, and what onboarding owes it.
        .task(id: auth.userId) { await profile.arrived(onboarding) }
        // Signed out, or a token the server turned down: the next account starts on a clean Welcome.
        .onChange(of: signedOut, initial: true) { _, out in if out { onboarding.reset(); profile.forgetOnboarding() } }
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
    /// The hello pill's news post, when its app isn't on the phone.
    @State private var helloLink: SafariLink?

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
            Task {
                if await !UIApplication.shared.open(post.post, options: [.universalLinksOnly: true]) {
                    helloLink = SafariLink(url: post.post)
                }
            }
        }
    }

    @State private var tab: Tab
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase

    init(profile: ProfileModel) {
        // Town, or a DEBUG `-open-tab` override.
        _tab = State(initialValue: MainTabsView.initialTab())
        // `-open-map` raises the map on launch, for screenshots: its real way in is a tap.
        _showMap = State(initialValue: LaunchFlags.has(.openMap))
        _session = State(initialValue: AppSession(profile: profile))
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
    private var notices: Notices { session.notices }
    /// The day picked in Daily's week (daily-tab 16), nil for today: kept here so it stays while
    /// you switch tabs, and a new launch opens on today.
    @State private var dailyDay: String?
    /// Your Going in your iPhone Calendar, kept up to date from here while its switch in
    /// Profile is on (BP app docs/plans/you-tab, ticket 05).
    @State private var calendarSync = CalendarSync()
    /// The shell stack's path: the bell, a neighbour's code and a followed row push onto it.
    @State private var path = NavigationPath()
    /// A Place's business page from a host row (follows 08), over the whole shell as Search's is
    /// over its tab.
    @State private var placeOpener = BusinessOpener()
    /// Made once, so the cards it reaches don't redraw each time the shell does.
    @State private var hostOpener: HostOpener?
    /// The map, presented full-screen from the map disc in the Town bar rather than
    /// living in the tab bar. Its own state belongs to `SJMapView`.
    @State private var showMap = false
    /// Log in, for an Anonymous account that opened a neighbour's code.
    @State private var signingIn = false
    /// That code's neighbour, opened once the login lands.
    @State private var codeAfterLogin: String?
    /// New post, from the Town bar's + (BP app references/post-screen).
    @State private var creating = false
    /// The + asked for an account first: New post opens once the login lands.
    @State private var createAfterLogin = false
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
                    FeedEventDetailDestination(item: item)
                        // Its menu's Not interested and Report.
                        .environment(townFeed)
                        // An open, for popularity (ticket 20): only from the Town feed,
                        // not Daily, which pushes the same page.
                        .onAppear { if tab == .town { townFeed.opened(item.id) } }
                }
                .navigationDestination(for: PostingItem.self) { posting in
                    DailyPostPage(posting: posting)
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
                    FeedEventDetailDestination(item: route.item).environment(townFeed)
                }
        }
        // A host's name on a card or an Event page opens its own page (follows 08).
        .environment(\.hostOpener, hostOpener)
        // A neighbour's code from the iPhone camera (friends 07): their page once it's read. An
        // Anonymous account logs in first, as Add friend asks; your own code opens your Profile.
        .onOpenURL { url in
            if let id = YourCode.userID(from: url) { openCode(id) }
        }
        .signInSheet(isPresented: $signingIn) {
            if createAfterLogin, auth.isSignedIn, !auth.isAnonymous { creating = true }
            createAfterLogin = false
        }
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
        // Logged in from that ask: the neighbour whose code it was.
        .onChange(of: auth.accountKey) {
            if let id = codeAfterLogin, auth.isSignedIn, !auth.isAnonymous {
                codeAfterLogin = nil
                openCode(id)
            }
        }
        .overlay { BusinessPage().environment(placeOpener) }
        .onAppear {
            placeOpener.reduceMotion = reduceMotion
            if hostOpener == nil { hostOpener = makeHostOpener() }
        }
        // Search's places, so a Place host opens its page from the first tap.
        .task { if !searchModel.placesLoaded { await searchModel.load() } }
        // The day's first open says hello, then one thing about the town (hello-drop 01).
        .overlay(alignment: .top) {
            HelloDropView(pill: session.helloPill, open: openHello)
            .sheet(item: $helloLink) { link in SafariView(url: link.url).ignoresSafeArea() }
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
        // The dot: read at launch and on coming back to the app (and on each visit to Town),
        // and again for another account, or the same one logged in for real.
        .task { await friendsBook.refreshDot() }
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
        // Onboarding's Follow 3 picks wait on the phone until a signed-up account can take them
        // (BP app onboarding 22): at launch, and when one arrives.
        .task(id: auth.accountKey) {
            guard !actions.needsSignUp else { return }
            for target in OnboardingStore.takeFollows() { actions.followOn(target) }
        }
        // Onboarding's answers landed after the tabs opened: the feed reads again, sorted to them.
        .onChange(of: profile.lateLandings) { Task { await townFeed.reload() } }
        // Event saves this phone kept before they moved to the server go up once, at
        // launch with an account or when one arrives (above).
        .task { await actions.moveUp(.shared) }
        // Canceled or moved since you last looked: at launch, on coming back, and for a new account.
        .task { await notices.refresh() }
        // The Town feed's views and opens go up every 30 seconds, from the shell so it
        // runs on any tab and under a pushed page (ticket 20); the DEBUG demo screens
        // outside the shell never send.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TownFeed.sendEvery))
                await townFeed.send()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.wentAway() }
            if phase == .active { session.cameForward(on: tab) }
        }
        .onAppear {
            session.recordOpen()
            openLaunchPages()
        }
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

    /// The Town bar's +: New post for a real account; anyone else signs in first (Jesse,
    /// 2026-11-01: "anyone signed in"), and New post opens once they have.
    private func create() {
        guard auth.isSignedIn, !auth.isAnonymous else {
            createAfterLogin = true
            signingIn = true
            return
        }
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

    /// A neighbour's code (friends 07): their page on the shell's stack, over the map, once
    /// `get_neighbor` answers; your own opens your Profile, the You tab.
    private func openCode(_ id: String) {
        showMap = false
        if id == auth.userId?.lowercased() {
            path = NavigationPath()
            tab = .you
            return
        }
        guard auth.isSignedIn, !auth.isAnonymous else {
            codeAfterLogin = id
            signingIn = true
            return
        }
        Task { if let neighbor = try? await Neighbor.read(id) { path.append(neighbor) } }
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
                            HomeView(
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
                                              cards: townFeed.cards)
                                } else {
                                    Hue.paper.ignoresSafeArea()
                                }
                            }
                            .task { await eventOfTheDay.refresh() }
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
        .fullScreenCover(isPresented: $showMap) {
            SJMapView(onClose: { showMap = false })
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

/// The tab bar's measured geometry, in CAPSULE-LOCAL points: x = 0 at the capsule's
/// leading edge, y = 0 at its top. One set of numbers places the items and the
/// bubble, and will hit-test the finger. Source: Instagram's iOS 26 bar, measured
/// from Jesse's recording (`/Users/owner/BP app/references/instagram-tab-bar/`,
/// 2026-09-27), where it sets a value; Apple's own bar (`references/tab-bar/`)
/// where Instagram's recording cannot.
///
/// `nonisolated`: constants and pure arithmetic, callable from any context.
nonisolated enum TabBarMetric {
    /// Capsule height, and its gap to the screen's sides and physical bottom edge.
    /// Height: Instagram's capsule is 0.167x its width, 60pt at 360 (MEASURED as a
    /// ratio, so the recording's scale drops out). Gaps: 21pt, Apple's MEASURED
    /// value; Instagram's side gap matches it, its bottom gap is outside the crop.
    static let height: CGFloat = 60
    static let margin: CGFloat = 21
    /// The Selection bubble: 50pt tall, so 5pt inside the capsule top and bottom,
    /// and as wide as one tab's slot. The slots split the capsule evenly inside a
    /// 9pt side inset, so the end bubbles sit 9pt in. MEASURED on Instagram's five
    /// slots (69.4pt bubble, 68.5pt slot, first centre 43pt in); four here.
    static let sideInset: CGFloat = 9
    static let bubbleHeight: CGFloat = 50
    /// Icon point size, centred up and down: Instagram's glyph boxes are 22pt and
    /// its strokes ~1.6pt (MEASURED). At 23 the house drew 26.7pt wide on the eyes
    /// sim; 19.5 brings the widest glyph to ~22.5pt.
    static let iconSize: CGFloat = 19.5
    /// Search's traced magnifier fills its own box: Instagram's search mark, 22pt
    /// (66px @3x, MEASURED on Mobbin's Instagram tab bar, 2026-09-29).
    static let searchGlyphSize: CGFloat = 22
    /// Daily's Bp!: letters at the size Jesse picked at Check-in 1 (38pt for Bp.,
    /// 2026-10-29), 22pt tall, about Instagram's 22pt glyph box. `DailyMark.svg`'s own width.
    static let dailyMarkWidth: CGFloat = 39.15
    static let iconCentreY: CGFloat = height / 2
    /// The You tab's photo: a 25pt circle (MEASURED on Instagram's profile tab).
    static let avatarSize: CGFloat = 25
    /// How far the Friends icon's frame runs past its ink on the right and top, so its dot
    /// sits on the ink's corner: the Town bar's measure for the same symbol at 19pt (2026-10-13).
    /// MEASURED at 19.5 on BP Build (2026-11-01): the dot's centre lands at 220.5, 853.8 against
    /// the rule's 220.7, 853.7 (the ink's top right, 2pt in).
    static let friendsInkRight: CGFloat = 3.3
    static let friendsInkTop: CGFloat = 1.5
    /// How far past the first and last centres the Lens may travel. MEASURED at the
    /// right end on Apple's bar (§3.5); the left end mirrors it, GUESSED.
    static let lensOvershoot: CGFloat = 9

    /// One tab's share of the capsule, and the bubble's width.
    static func bubbleWidth(capsuleWidth: CGFloat) -> CGFloat {
        (capsuleWidth - 2 * sideInset) / CGFloat(Tab.allCases.count)
    }

    /// The Lens while held: 1.20x the bubble's width and 1.30x its height, so it
    /// stands ~4pt proud of the capsule. MEASURED on TabProbe (Air, hold (d)).
    static let lensScale = CGSize(width: 1.20, height: 1.30)
    /// Apple's whole bar swells while pressed. MEASURED 1.042x peak, 1.039x held
    /// (Instagram's 1.044x). The interactive glass draws it; this maps the finger.
    static let swell: CGFloat = 1.04
    /// Icons under the Lens centre magnify 1.2x (MEASURED §3.7), falling off
    /// linearly to 1.0 one tab away (GUESSED method: no jump between tabs).
    static let magnificationPeak: CGFloat = 0.2

    static func bubbleSize(capsuleWidth: CGFloat, held: Bool) -> CGSize {
        let rest = CGSize(width: bubbleWidth(capsuleWidth: capsuleWidth), height: bubbleHeight)
        guard held else { return rest }
        return CGSize(width: rest.width * lensScale.width, height: rest.height * lensScale.height)
    }

    /// The distance between neighbouring tab centres.
    static func pitch(capsuleWidth: CGFloat) -> CGFloat {
        centreX(of: .blockParty, capsuleWidth: capsuleWidth) - centreX(of: .town, capsuleWidth: capsuleWidth)
    }

    static func magnification(itemX: CGFloat, lensX: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        1 + magnificationPeak * max(0, 1 - abs(lensX - itemX) / pitch(capsuleWidth: capsuleWidth))
    }

    /// The Lens growing on touch-down and the bar's swell: 89% there at 37ms, 96%
    /// at 70ms, no overshoot. MEASURED; fitted as a critically damped spring.
    static let growth = Animation.spring(response: 0.06, dampingFraction: 1)
    /// The bubble travelling between tabs (a tap, a touch-down away from the
    /// selected tab, a release). MEASURED target: Apple's arrives ~270–280ms after a
    /// tap (its centre 96.5% of the way at +272ms, TabProbe) and does not overshoot.
    /// Critically damped at 0.33 matches that point; 0.45/0.8 arrived at ~350ms and
    /// overshot 2.5pt, and 0.27 read as early on the eyes sim. Fitted, not measured.
    static let travel = Animation.spring(response: 0.33, dampingFraction: 1)

    /// How long the Lens keeps its look after the finger lifts. After a tap it lasts
    /// to the end of the travel (Apple's re-forms its grey bubble ~323–353ms after
    /// touch-down); after a drag it collapses in ~76ms (MEASURED §3.6). The tap
    /// value is GUESSED from those, counted from lift rather than touch-down.
    static let landingAfterTap: Duration = .milliseconds(260)
    static let collapseAfterDrag: Duration = .milliseconds(70)

    /// The white layer behind the bar's glass that holds it in its light state.
    /// MEASURED threshold: 20% flipped, 30% held. 35% read 202–208 over a near-black
    /// photo (2026-09-27), lighter than Instagram's 192 over black, so it sits at the
    /// threshold that held.
    static let glassUnderlay: Double = 0.30
    /// The same layer under a finger, so the pressed bar lightens by Instagram's
    /// middling amount (~+30 over a dark photo, with the interactive glass's own).
    static let pressedUnderlay: Double = 0.40
    /// The Selection bubble's black: Instagram's reads 0.87x the glass on any
    /// ground (168 on 192 over black, 221 on 255 over white; MEASURED).
    static let bubbleShade: Double = 0.13

    /// While the feed reads down, the whole bar rests at 0.84x (Instagram's
    /// 462×78px against 550×92px, MEASURED), and gets there with no overshoot: half
    /// way at ~80ms, 98% at ~250ms. Fitted as a critically damped spring; the way
    /// back is GUESSED to mirror it (the recording never scrolls up).
    static let compactScale: CGFloat = 0.84
    static let compaction = Animation.spring(response: 0.3, dampingFraction: 1)

    /// A tab's centre: the middle of its slot.
    static func centreX(of tab: Tab, capsuleWidth: CGFloat) -> CGFloat {
        sideInset + bubbleWidth(capsuleWidth: capsuleWidth) * (CGFloat(tab.rawValue) + 0.5)
    }

    /// The tab a release picks: the centre nearest the finger's x. Its height does
    /// not matter — Apple's bar switches on a release 150pt above it (MEASURED on
    /// the Air probe, 2026-09-25), so there is no cancel zone.
    static func tab(atX x: CGFloat, capsuleWidth: CGFloat) -> Tab {
        Tab.allCases.min {
            abs(centreX(of: $0, capsuleWidth: capsuleWidth) - x) < abs(centreX(of: $1, capsuleWidth: capsuleWidth) - x)
        } ?? .town
    }

    /// Where the Lens sits under a finger: on it, clamped `lensOvershoot` past the
    /// end centres.
    static func lensCentreX(fingerX: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        let first = centreX(of: .town, capsuleWidth: capsuleWidth) - lensOvershoot
        let last = centreX(of: .you, capsuleWidth: capsuleWidth) + lensOvershoot
        return min(max(fingerX, first), last)
    }
}

/// The global bottom shell: one floating Liquid Glass capsule, a copy of Instagram's
/// iOS 26 bar with BP's icons (Jesse, 2026-09-27). It mounts on every tab and never
/// hides; while the Town feed reads down it shrinks, as Instagram's does.
///
/// One touch drives it, the way Apple's own bar works (TabProbe, 2026-09-25): the
/// Selection bubble lifts into a Lens under the finger on touch-down (a plain tap
/// included), follows the finger, and the tab nearest the finger's x on release is
/// picked, however far above the bar the finger ends.
struct BlockPartyTabBar: View {
    let selection: Tab
    /// Tap handler — the parent owns the page slide and the haptic, and ignores a
    /// release on the tab that is already selected.
    var onSelect: (Tab) -> Void
    /// The signed-in neighbour's photo for the You tab; nil draws the person icon.
    var avatarURL: String? = nil
    /// The feed is reading down (its top bar is away): the bar rests small. A touch
    /// brings it back to full size while the finger is down.
    var compact = false
    /// A new friend request: the quiet yellow dot on the Friends tab (`FriendsBook.dot`), as
    /// it sat on the Town bar's friends mark until 2026-11-01.
    var friendsDot = false
    /// What VoiceOver reads for Friends when the dot says something.
    var friendsLabel: String? = nil

    /// The finger while it is down, capsule-local. `@GestureState` resets itself
    /// when the system cancels the touch, so the Lens can never stay stuck up.
    @GestureState private var touch: Touch?
    /// After the finger lifts, the Lens keeps its look until the bubble lands, as
    /// Apple's does: to the end of a tap's travel, or a short collapse after a drag.
    @State private var landing = false
    @State private var landingTask: Task<Void, Never>?
    /// Taps on Daily, each one a hop of its ! (`DailyMarkGlyph`).
    @State private var dailyHops = 0
    /// Taps on Search, each one a swoop of the magnifier's shine (`MagnifierGlyph`).
    @State private var searchSwoops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Touch: Equatable {
        var x: CGFloat
        /// Past the first 4pt of travel (GUESSED threshold) the Lens tracks the
        /// finger tightly; before that, it springs over from the selected tab.
        var moved: Bool
    }

    var body: some View {
        GeometryReader { capsule in
            let width = capsule.size.width
            // Reduce Motion: no Lens, no growth, no magnification, no swell; a change
            // crossfades the bubble (see `BubbleGeometry`).
            let lens = reduceMotion ? nil : touch
            let held = lens != nil || (landing && !reduceMotion)
            let bubbleX = lens.map { TabBarMetric.lensCentreX(fingerX: $0.x, capsuleWidth: width) }
                ?? TabBarMetric.centreX(of: selection, capsuleWidth: width)
            let geometry = BubbleGeometry(x: bubbleX,
                                          size: TabBarMetric.bubbleSize(capsuleWidth: width, held: held),
                                          held: held, following: lens?.moved == true,
                                          selection: selection, reduceMotion: reduceMotion)
            ZStack(alignment: .topLeading) {
                // Under a finger the grey bubble gives way to a clear glass Lens, as
                // Instagram's does. The glass is placed straight at the finger, never
                // animated there (glass draws at its final position), and swapped with
                // the bubble in one frame, never faded. It stays mounted at zero size
                // between touches: inserted fresh, it drew two frames late and left
                // the touch-down with neither Lens nor bubble (eyes sim, 2026-09-27).
                bubble
                    .modifier(geometry)
                    .opacity(lens == nil ? 1 : 0)
                    .animation(nil, value: lens == nil)
                lensGlass
                    .frame(width: lens == nil ? 0 : geometry.size.width,
                           height: lens == nil ? 0 : geometry.size.height)
                    .position(x: bubbleX, y: TabBarMetric.height / 2)
                    .transaction { $0.animation = nil }
                Items(selection: selection, capsuleWidth: width, onSelect: onSelect,
                      avatarURL: avatarURL, lensX: lens == nil ? nil : bubbleX, dailyHops: dailyHops,
                      searchSwoops: searchSwoops, friendsDot: friendsDot, friendsLabel: friendsLabel)
            }
            .contentShape(Rectangle())
            .gesture(
                // Read in screen space and mapped onto the bar at its PRESSED size. In
                // the bar's own space a still finger kept the x it touched down at on
                // the shrunk bar, so the Lens slid off the finger as the bar grew
                // back (review, 2026-09-27). The bar scales about its centre, so its
                // centre is the same at any scale.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touch) { value, state, _ in
                        state = Touch(x: pressedX(value.location.x, capsule: capsule),
                                      moved: state?.moved == true || abs(value.translation.width) > 4)
                    }
                    .onEnded { value in
                        land(after: abs(value.translation.width) > 4
                             ? TabBarMetric.collapseAfterDrag : TabBarMetric.landingAfterTap)
                        let tab = TabBarMetric.tab(atX: pressedX(value.location.x, capsule: capsule),
                                                   capsuleWidth: width)
                        // Every tap on Daily hops its !, and every tap on Search swoops
                        // its shine, already-picked included.
                        if tab == .blockParty && !reduceMotion { dailyHops += 1 }
                        if tab == .search && !reduceMotion { searchSwoops += 1 }
                        onSelect(tab)
                    }
            )
        }
        .frame(height: TabBarMetric.height)
        // Real Liquid Glass, untinted: near-white over paper, mid-grey over dark
        // photos — the same response the Reference measures (§1.6, §1.13).
        // Interactive, Apple's own pressed look: Instagram's bar lightens under a
        // finger (206–239 over a near-black photo, against 192 at rest; MEASURED).
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        // Keeps the glass in its LIGHT state. Over a near-black feed card the glass
        // flipped to its dark state (measured 2026-09-26, Town at
        // `-feed-scrolled-y 1200`: glass 23/255, ink invisible), and no colour-scheme
        // pin stopped it. A white layer BEHIND the glass lifts what it samples: at
        // 20% it still flipped (40/255), at 30% it held (178/255). It sits at 30%, the
        // value that held, to match Instagram's grey (`TabBarMetric.glassUnderlay`).
        // Pressed, it thickens: the interactive glass alone lightened the bar only
        // +13 (198 → 211), the bottom of Instagram's +14 to +47.
        .background {
            Capsule(style: .continuous)
                .fill(Hue.surface.onLightCanvas.opacity(touch != nil && !reduceMotion
                    ? TabBarMetric.pressedUnderlay : TabBarMetric.glassUnderlay))
                .animation(reduceMotion ? nil : TabBarMetric.growth, value: touch != nil)
                .allowsHitTesting(false)
        }
        // The Reference's brighter 1pt rim (§1.9: +60–75 over the glass). Opacity
        // tuned on the eyes sim: 0.6 read +56 over the dark card.
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Hue.surface.onLightCanvas.opacity(0.75), lineWidth: 1)
                .allowsHitTesting(false)
        }
        // No hand-made swell: the interactive glass swells the bar itself, and the
        // two together pressed it to ~1.08x, past Instagram's 1.044x (eyes sim).
        // Instagram's shrink while reading down, around the bar's own centre. A
        // finger on the bar (or its landing) holds it at full size. Under Reduce
        // Motion it still shrinks, without the spring.
        .scaleEffect(compact && touch == nil && !landing ? TabBarMetric.compactScale : 1)
        .animation(reduceMotion ? nil : TabBarMetric.compaction, value: compact && touch == nil && !landing)
        .padding(.horizontal, TabBarMetric.margin)
    }

    /// A finger's screen x, in capsule points on the bar at its pressed size (the
    /// swell; 1x under Reduce Motion, which has none).
    private func pressedX(_ screenX: CGFloat, capsule: GeometryProxy) -> CGFloat {
        let scale = reduceMotion ? 1 : TabBarMetric.swell
        return capsule.size.width / 2 + (screenX - capsule.frame(in: .global).midX) / scale
    }

    private func land(after delay: Duration) {
        guard !reduceMotion else { return }
        landingTask?.cancel()
        landing = true
        landingTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            landing = false
        }
    }

    /// The Selection bubble: translucent black at Instagram's measured shade
    /// (`TabBarMetric.bubbleShade`). It does all the sliding; under a finger the
    /// glass Lens stands in for it (`lensGlass`).
    private var bubble: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(TabBarMetric.bubbleShade))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The held Lens: real Liquid Glass on the same white layer as the bar, so it
    /// reads lighter than the bar and cannot flip dark over a dark photo either.
    private var lensGlass: some View {
        Capsule(style: .continuous)
            .fill(Hue.surface.onLightCanvas.opacity(TabBarMetric.glassUnderlay))
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where the bubble is and how it moves. Size and look ride the measured growth
    /// spring; position rides the travel spring (or tracks the finger). Scoped this
    /// way because one `.animation` over both let the travel spring win the growth.
    struct BubbleGeometry: ViewModifier {
        var x: CGFloat
        var size: CGSize
        var held: Bool
        var following: Bool
        var selection: Tab
        var reduceMotion: Bool

        func body(content: Content) -> some View {
            if reduceMotion {
                // No travel: the old bubble fades out where it was and the new one
                // fades in, on the parent's 0.2s ease.
                content
                    .frame(width: size.width, height: size.height)
                    .position(x: x, y: TabBarMetric.height / 2)
                    .id(selection)
                    .transition(.opacity)
            } else {
                content
                    .frame(width: size.width, height: size.height)
                    .animation(TabBarMetric.growth, value: held)
                    .position(x: x, y: TabBarMetric.height / 2)
                    .animation(following ? TabBarMetric.growth : TabBarMetric.travel, value: x)
            }
        }
    }

    /// The five items, placed from `TabBarMetric`. No glass, so a test can render
    /// them alone.
    struct Items: View {
        let selection: Tab
        let capsuleWidth: CGFloat
        var onSelect: (Tab) -> Void
        /// The signed-in neighbour's photo, drawn on the You tab in place of its icon.
        var avatarURL: String? = nil
        /// The Lens centre while held; icons near it magnify.
        var lensX: CGFloat? = nil
        /// Taps on Daily so far; each one hops the Bp!'s !.
        var dailyHops = 0
        /// Taps on Search so far; each one swoops the magnifier's shine.
        var searchSwoops = 0
        /// A new friend request's dot on the Friends icon.
        var friendsDot = false
        var friendsLabel: String? = nil
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack(alignment: .topLeading) {
                // Instagram's bar: icons only, all one ink, the selected one filled.
                // Ink is the LIGHT-canvas value, fixed: glass that flips hands its
                // items a dark trait, and adaptive `Hue.ink` then drew white
                // (measured 2026-09-26).
                ForEach(Tab.allCases) { tab in
                    icon(tab)
                        .scaleEffect(magnification(tab))
                        .position(x: centreX(tab), y: TabBarMetric.iconCentreY)
                }
                .animation(TabBarMetric.growth, value: lensX)
                .accessibilityHidden(true)
                // Frozen chrome owes the reader another way in: the glyph never
                // grows, so a long press at an accessibility text size has to
                // enlarge it (docs/rules/architecture.md).
                ForEach(Tab.allCases) { tab in
                    Color.clear
                        .frame(width: TabBarMetric.pitch(capsuleWidth: capsuleWidth), height: TabBarMetric.height)
                        .contentShape(Rectangle())
                        .accessibilityShowsLargeContentViewer {
                            if tab == .blockParty {
                                Label(tab.title, image: tab.symbol)
                            } else {
                                Label(tab.title, systemImage: selection == tab ? tab.selectedSymbol : tab.symbol)
                            }
                        }
                        .position(x: centreX(tab), y: TabBarMetric.height / 2)
                }
            }
            .frame(width: capsuleWidth, height: TabBarMetric.height, alignment: .topLeading)
            // VoiceOver sees exactly five tabs, named, not the drawing: the tab
            // elements are synthetic children laid over the slots.
            .accessibilityChildren {
                ZStack(alignment: .topLeading) {
                    ForEach(Tab.allCases) { tab in
                        accessibilityElement(tab)
                    }
                }
                .frame(width: capsuleWidth, height: TabBarMetric.height, alignment: .topLeading)
            }
            .accessibilityAddTraits(.isTabBar)
        }

        @ViewBuilder
        private func icon(_ tab: Tab) -> some View {
            let selected = selection == tab
            if tab == .you, let avatarURL {
                TabAvatar(url: avatarURL, selected: selected)
            } else {
                symbol(tab, selected: selected)
                    // Outside the symbol's no-animation transaction, so the dot grows in.
                    .overlay(alignment: .topTrailing) {
                        if tab == .friends, friendsDot {
                            UnreadDot(ring: Hue.surface.onLightCanvas,
                                      inkRight: TabBarMetric.friendsInkRight, inkTop: TabBarMetric.friendsInkTop)
                        }
                    }
                    .animation(reduceMotion ? nil : Motion.smooth, value: friendsDot)
            }
        }

        private func symbol(_ tab: Tab, selected: Bool) -> some View {
            Group {
                if tab == .search {
                    MagnifierGlyph(size: TabBarMetric.searchGlyphSize, bold: selected, swoops: searchSwoops)
                } else if tab == .town {
                    HouseGlyph(filled: selected)
                } else if tab == .blockParty {
                    DailyMarkGlyph(hops: dailyHops)
                        .frame(width: TabBarMetric.dailyMarkWidth)
                        // The launch's Bp! lands here: hidden till it does (`LaunchBall`).
                        .launchLanding()
                } else {
                    Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                        .font(.glyph(TabBarMetric.iconSize))
                }
            }
            .foregroundStyle(Hue.ink.onLightCanvas)
            // Swapped, not crossfaded: under the tab switch's spring the outline
            // and the filled symbol blended into a grey blob for ~3 frames, and
            // `.contentTransition(.identity)` did not stop it.
            .transaction { $0.animation = nil }
        }

        /// One VoiceOver element per tab, over its slot, with the tab's action.
        private func accessibilityElement(_ tab: Tab) -> some View {
            let selected = selection == tab
            return Color.clear
                .frame(width: TabBarMetric.pitch(capsuleWidth: capsuleWidth), height: TabBarMetric.height)
                .position(x: centreX(tab), y: TabBarMetric.height / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab == .friends ? friendsLabel ?? tab.title : tab.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect(tab) }
        }

        private func centreX(_ tab: Tab) -> CGFloat {
            TabBarMetric.centreX(of: tab, capsuleWidth: capsuleWidth)
        }

        private func magnification(_ tab: Tab) -> CGFloat {
            guard let lensX else { return 1 }
            return TabBarMetric.magnification(itemX: centreX(tab), lensX: lensX, capsuleWidth: capsuleWidth)
        }
    }
}

/// The You tab's photo, as Instagram's profile tab draws it: a plain circle, with an ink ring when
/// selected (GUESSED ring: the recording never selects that tab). Without a photo the tab keeps the
/// person icon, ink like every icon (taste.md 2026-09-27).
private struct TabAvatar: View {
    let url: String
    let selected: Bool

    var body: some View {
        Avatar(avatarUrl: url, size: TabBarMetric.avatarSize)
            .padding(3)
            .overlay {
                if selected {
                    Circle().strokeBorder(Hue.ink.onLightCanvas, lineWidth: 1.5)
                }
            }
    }
}

/// The Town feed's "reading down" signal, carried up to the shell so the tab bar can
/// shrink with the top bar. Absent (false) on every other tab.
struct TabBarCompactKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// What a reserved tab shows until its screen is built: the slot's name and the one
/// line describing what will live there. Deliberately quiet — a named, empty room
/// reads as reserved, where a bare screen reads as broken.
struct BlankTab: View {
    let tab: Tab

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(tab.title)
                    .font(.display(22))
                    .foregroundStyle(Hue.ink)
                Text(tab.promise)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }
            .accessibilityElement(children: .combine)
        }
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
