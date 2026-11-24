//
//  GroupPage.swift
//  Block Party — a group's own page (BP app docs/plans/rsvp-and-groups, ticket 05), pushed from
//  Search's Groups shelf onto the shell's stack like the Event page. Drawn to the Figma frame
//  "Group page" (page "Meetup depth", approved by Jesse on 2026-10-17) with the changes he took
//  at Check-in 1 on 2026-10-18: the group's own photos (else its logo) at the top under the
//  Event page's round back and share buttons; a sheet over their bottom edge with the name, what
//  kind of group and the town, when and where it meets, its members (from one up), About, its
//  next get-togethers and its own website; and Meetup's charcoal Join group pill floating at the
//  bottom, which joins in one tap (ticket 06, `RealLifeActions`).
//
//  PRODUCT RULE: never a zero count or a placeholder. Every row is absent when its data is.
//

import SwiftUI

struct GroupPage: View {
    /// As opened, then as its Admin saves it (start-a-group 04).
    @State private var group: TownGroup
    /// False inside Start a group's sheet, whose stack can't open the chat (as the map's Event page's Going chat).
    private let groupChat: Bool

    init(group: TownGroup, groupChat: Bool = true) {
        _group = State(initialValue: group)
        self.groupChat = groupChat
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Being in the group, shared with every screen that shows it (`RealLifeActions`).
    @Environment(RealLifeActions.self) private var actions
    /// `actions.memberFailureCount` at the last tap: a tap mid-shake stills it (as `RSVPArea`'s).
    @State private var tappedAt = 0
    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen: until then a photo shimmers, and its credit waits.
    @State private var shownPhotos: Set<URL> = []
    /// Photos that could not be loaded leave the pager, so a failure never holds a skeleton.
    @State private var failedPhotos: Set<URL> = []
    /// The Calendar (start-a-group 05): the Group's Events (`get_group_events`), its get-togethers 4 months ahead,
    /// whether you may add, its rule and the Events its Admin may take off (`get_group_calendar`).
    @State private var events: [FeedCardItem] = []
    @State private var calendar = GroupCalendar.Read()
    @State private var newEvent = false
    @State private var settingMeets = false
    /// An Event opens on the stack this page is on: the shell's (architecture.md, The shell), or Start a group's sheet's.
    @Environment(\.hostOpener) private var opener
    @Environment(SearchModel.self) private var search: SearchModel?
    @Environment(ProfileModel.self) private var profile: ProfileModel?
    /// Private Groups (start-a-group 03): who asked, shared with Groups to join; the Admin's waiting asks.
    private var asks: GroupAsks { GroupAsks.shared }
    @State private var waiting: Int?
    @State private var showingRequests = false
    /// Edit group, the Admin's, from the ••• (start-a-group 04).
    @State private var editing = false
    /// Leave group? on a Group that asks first (`GroupAsks.asksToLeave`).
    @State private var leaving = false
    @Environment(YouModel.self) private var you: YouModel?

    /// A private Group you aren't in: Ask to join, and none of its time, place, members or chat.
    private var locked: Bool { GroupAsks.locked(group, member: actions.member(group).isMember) }

    /// One still waiting on its checks that you left: nothing here to join or ask for, and no longer yours to see.
    private var shut: Bool {
        group.status == "pending" && !group.isAdmin && group.invitedBy == nil && !actions.member(group).isMember
    }

    /// The Figma frame's sizes, on a 420 pt phone. The round buttons, the sheet's corner, its
    /// side inset and the title's rhythm are the Event page's (`EventPage.Metric`).
    enum Metric {
        /// The sheet's edge 256 pt down a 420 pt phone; other widths keep the ratio.
        static let heroAspect: CGFloat = 420.0 / 256.0
        static let kindTop: CGFloat = 6
        static let whenTop: CGFloat = 2
        static let membersTop: CGFloat = 16
        static let sectionTop: CGFloat = 24
        static let sectionBodyTop: CGFloat = 6
        /// The old Coming up's rows, kept by You's Coming up: a 64 pt date tile with 12 pt corners, the words 12 pt
        /// beside it, rows 12 pt apart.
        static let tile: CGFloat = 64
        static let tileCorner: CGFloat = 12
        static let rowGap: CGFloat = 12
        static let rowTop: CGFloat = 12
        static let linkTop: CGFloat = 24
        /// Join group, as Meetup's measures off its iOS screen at 3x: 54 pt tall, 24 pt in from each
        /// side, its bottom 35 pt above the screen's (1 pt over the 34 pt home-bar inset; Jesse took
        /// Meetup's own spot over the Figma page's 74 pt, 2026-10-18). The page fades to paper under
        /// it from 23 pt above its top, as under the Event page's bar.
        static let pillHeight: CGFloat = 54
        static let pillSide: CGFloat = 24
        static let pillBottom: CGFloat = 1
        static let fadeAbovePill: CGFloat = 23
    }

    private typealias Event = EventPage.Metric

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                sheet
            }
        }
        // The photo runs up under the status bar; with none the page starts below it.
        .ignoresSafeArea(edges: hasHero ? .top : [])
        .background(Hue.paper.ignoresSafeArea())
        // Outside the scroll, so the buttons stay put; read first by VoiceOver, as they sit.
        .overlay(alignment: .top) {
            topButtons
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
        // An inset, so the page scrolls under the pill and its last line stops clear of it. Only
        // for someone who may act, as the Event page's RSVP bar: it comes up when the quiet
        // account arrives.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // A turned-down Group has nothing to join or invite to (start-a-group 02).
            if actions.canAct, group.status != "rejected", !shut {
                joinBar
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(Motion.smooth, value: actions.canAct)
        .animation(reduceMotion ? nil : Motion.smooth, value: shut)
        // Hidden, never `navigationBarBackButtonHidden`: `SwipeBack` (RootView) keeps the swipe.
        .toolbar(.hidden, for: .navigationBar)
        // A failed join shakes and buzzes only while the page is open.
        .onAppear { actions.pageOpened(group.id) }
        .onDisappear { actions.pageClosed(group.id) }
        .navigationDestination(isPresented: $showingRequests) {
            JoinRequestsPage(group: group, waiting: Binding { waiting ?? 0 } set: { waiting = $0 })
        }
        .sheet(isPresented: $editing) {
            EditGroupSheet(group: group) { group = $0; refresh() } handedOver: {
                group.requests = nil
                refresh()
            } closed: {
                refresh()
                dismiss()
            }
        }
        .sheet(isPresented: $newEvent) {
            if let profile {
                NewPostSheet(places: places, me: profile, onShared: {
                    HelloInbox.shared.add(.posted($0))
                    Task { await loadCalendar() }
                }, group: group)
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $settingMeets) {
            GroupMeetsSheet(group: group, rule: calendar.rule, places: places) { schedule, place in
                group.schedule = schedule
                group.location = place
                Task { await loadCalendar() }
                refresh()
            }
        }
        .modifier(LeaveGroupQuestion(group: group, asking: $leaving, edit: { editing = true }, leave: flip))
        // Its checks end while this is open; or, left, the Groups were read again without it.
        .onChange(of: you?.groups.map { all in all.first { $0.id == group.id }?.status ?? "" }) { _, status in
            guard let status else { return }
            if !status.isEmpty { group.status = status } else if shut { dismiss() }
        }
        #if DEBUG
        // `-group-admin edit|hand|close`: Edit group open at launch.
        .task { if ["edit", "hand", "close"].contains(LaunchFlags.value(.groupAdmin) ?? "") { editing = true } }
        // `-group-admin event|meets`: New event with the Group as host, or Add when you meet, open at launch.
        .task {
            switch LaunchFlags.value(.groupAdmin) {
            case "event": newEvent = true
            case "meets": settingMeets = true
            default: break
            }
        }
        #endif
    }

    /// New event's Place list, and Add when you meet's: Search's places.
    private var places: [SearchItem] { NewEventPlaces.ordered(search?.items ?? []) }

    /// The Calendar's two reads at once. A failed or cut-off read keeps what's shown.
    private func loadCalendar() async {
        #if DEBUG
        if group.id == "sample-group" {
            let sample = GroupCalendar.sample(now: .now)
            events = sample.events
            calendar.meetings = sample.meetings
            calendar.adds = group.isAdmin
            calendar.rule = group.isAdmin ? sample.rule : nil
            calendar.takesOff = group.isAdmin ? Set(sample.events.map(\.id)) : []
            return
        }
        #endif
        let api = CommunityAPI(auth: AuthStore.shared)
        async let found = api.groupEvents(group.id)
        async let read = api.groupCalendar(group.id)
        if let found = try? await found { events = found }
        if let read = try? await read { calendar = read }
    }

    /// The Admin's take-off (SPEC decision 8): it leaves the Calendar at once; a refused or lost write puts it back.
    private func takeOff(_ event: FeedCardItem) {
        let kept = events
        events.removeAll { $0.id == event.id }
        #if DEBUG
        if group.id == "sample-group" { return }
        #endif
        Task {
            do {
                try await CommunityAPI(auth: AuthStore.shared).takeOffGroupEvent(event.id)
                calendar.takesOff.remove(event.id)
            } catch {
                Haptics.error()
                events = kept
            }
        }
    }

    /// Every list that shows the Group reads it again.
    private func refresh() {
        Task { if let groups = await you?.refreshGroups() { actions.read(groups) } }
    }

    // MARK: Pictures

    private var photos: [PlacePicture] { group.photos.filter { !failedPhotos.contains($0.url) } }

    /// No photo: its logo on its Search backdrop, as an Event page draws a place it has no photo of.
    private var heroLogo: SearchLogo? {
        photos.isEmpty ? group.logo.flatMap { FeedCardImageSource($0).logo } : nil
    }

    private var hasHero: Bool { !photos.isEmpty || heroLogo != nil }

    @ViewBuilder
    private var hero: some View {
        if hasHero {
            Color.clear
                .aspectRatio(Metric.heroAspect, contentMode: .fit)
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        Group {
                            if let logo = heroLogo {
                                FeedCardPlaceLogo(logo: logo, topShare: 0.29, sideShare: 0.43)
                            } else {
                                PhotoPager(urls: photos.map(\.url), page: $photoPage, shown: $shownPhotos,
                                           value: photoValue, onFailure: drop)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height + Event.heroUnderlap)
                    }
                }
                // Pulling the page down past its top stretches the picture from its bottom edge.
                .visualEffect { content, proxy in
                    let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                    return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
                }
                .overlay(alignment: .bottomLeading) { credit }
                .overlay(alignment: .bottomTrailing) { counter }
        }
    }

    /// The photo on screen's credit, once it is drawn: the group's own site. A tap on it reports
    /// the photo (BP app place-photos 06).
    @ViewBuilder private var credit: some View {
        let index = photoPage ?? 0
        if photos.indices.contains(index), PhotoPager.isShown(photos[index].url, in: shownPhotos),
           let credit = photos[index].creditLine {
            PhotoCredit(names: [credit], report: PhotoReport(place: group.name, photo: photos[index].url),
                        spoken: photos.count < 2)
                .padding(.leading, Event.inset - PhotoCredit.edgeInset)
                .padding(.bottom, Event.counterBottom - PhotoCredit.edgeInset)
        }
    }

    @ViewBuilder private var counter: some View {
        if let text = EventPage.counterText(page: photoPage ?? 0, count: photos.count) {
            PhotoCounter(text: text)
                .padding(.trailing, Event.inset)
                .padding(.bottom, Event.counterBottom)
        }
    }

    private var photoValue: String {
        let index = photoPage ?? 0
        let credit = photos.indices.contains(index) ? photos[index].creditLine : nil
        return "Photo \(index + 1) of \(photos.count)" + (credit.map { ", by \($0)" } ?? "")
    }

    private func drop(_ url: URL) {
        failedPhotos.insert(url)
        photoPage = min(photoPage ?? 0, max(photos.count - 1, 0))
    }

    // MARK: Buttons

    private var topButtons: some View {
        HStack(spacing: 0) {
            EventPage.circleButton(glyph: Image(systemName: "arrow.left"), label: "Back") { dismiss() }
            Spacer(minLength: 0)
            // The Admin's alone (start-a-group 04), beside Share as the Event page's heart is.
            if group.isAdmin {
                EventPage.circleButton(glyph: Image(systemName: "ellipsis"), label: "Edit group") { editing = true }
            }
            EventPage.circleButton(
                glyph: Image(systemName: "square.and.arrow.up").font(.sansSemibold(15)), label: "Share"
            ) {
                ShareCenter.shared.present(.group(group))
            }
        }
        .padding(.horizontal, Event.inset - (Event.tapBox - Event.button) / 2)
        .padding(.top, Event.buttonTop - (Event.tapBox - Event.button) / 2)
    }

    // MARK: The sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.name)
                .font(.display(28))
                .lineSpacing(Event.nameLineSpacing)
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Event.titleTop)

            if locked {
                // Mock frame 7: the lock and the count on one line, in the kind line's place.
                Label(Self.privateLine(actions.member(group).count), systemImage: "lock")
                    .labelStyle(PrivateLineStyle())
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, Metric.kindTop)
            } else {
                Text(Self.kindLine(group))
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, Metric.kindTop)
            }

            // Both checks said no (start-a-group 02): only its starter sees it, and this.
            if group.status == "rejected" {
                Label("Couldn't start this group", systemImage: "exclamationmark.circle")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, Metric.whenTop)
            }

            if !locked, let when = Self.whenLine(group) {
                Text(when)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metric.whenTop)
            }

            // Counts you the instant you join: the line fades in and the number rolls.
            if !locked, let members = Self.membersText(actions.member(group).count) {
                Text(members)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, Metric.membersTop)
                    .transition(.opacity)
            }

            // The Admin's asks waiting on a private Group (start-a-group 03).
            if group.isPrivate, let count = waiting ?? group.requests {
                requestsRow(count)
            }

            // Once you're in. The count is right above, so with nothing said it has no second line.
            if groupChat, !locked {
            ChatRoomRow(title: "Group chat", isIn: actions.member(group).isMember && group.status != "rejected",
                        listed: { [id = group.id] in $0.chat(forGroup: id) },
                        ruled: false, access: { [id = group.id] in try await $0.groupAccess(id) },
                        route: { [group] _ in .groupChat(group) })
            }

            if let about = Self.nonempty(group.about) {
                section("About")
                Text(about)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metric.sectionBodyTop)
            }

            if locked {
                MembersOnlyBox().padding(.top, Metric.sectionTop)
            }

            // The Calendar, in Coming up's place (start-a-group 05): with something on it, or for whoever adds to it.
            let plans = locked ? [] : GroupCalendar.plans(group, meetings: calendar.meetings, events: events)
            if !locked, !plans.isEmpty || calendar.adds || group.isAdmin {
                GroupCalendarView(plans: plans, adds: calendar.adds, admin: group.isAdmin,
                                  meets: group.schedule != nil || calendar.rule != nil, takesOff: calendar.takesOff,
                                  add: { newEvent = true }, setMeets: { settingMeets = true },
                                  open: { opener?.push($0) }, takeOff: takeOff)
            }

            if let page = group.pageUrl, let row = BusinessPage.rows([PlaceLink(kind: "website", url: page)]).first {
                InfoPill(glyph: row.glyph, text: row.text, url: row.url, hint: "Opens the link",
                         glyphBox: SearchMetric.bizGlyphBox)
                    .padding(.top, Metric.linkTop)
            }
        }
        .padding(.horizontal, Event.inset)
        .padding(.bottom, Event.contentBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: actions.member(group).count)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: events)
        .task(id: group.id) { await loadCalendar() }
        .background(Hue.paper, in: UnevenRoundedRectangle(topLeadingRadius: Event.sheetCorner,
                                                         topTrailingRadius: Event.sheetCorner, style: .continuous))
        .padding(.top, hasHero ? 0 : Event.buttonTop + Event.button + Event.noPhotoGap)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.displaySemi(17))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Metric.sectionTop)
    }

    // MARK: Join group

    /// Meetup's charcoal pill over a fade to the page. One tap joins: "You're in!" at once, the pill
    /// shrinks into Invite at the right and the Event page's glass bar comes up around it, with
    /// "Leave group?" under the words (Jesse, 2026-10-18: inside the group you can leave), over the
    /// RSVP pill's 0.18 s, both ways. It stays one button, so VoiceOver keeps its place. A join
    /// the server refuses holds, turns back, then shakes.
    @ViewBuilder private var joinBar: some View {
        if locked { askBar } else { memberBar }
    }

    /// A private Group you aren't in (mock frame 7): Ask to join, then Asked in the light face, as Join's
    /// Joined; a tap on Asked takes it back.
    private var askBar: some View {
        let asked = asks.isAsked(group)
        return Button {
            Task { await asks.toggle(group) }
        } label: {
            ZStack {
                Text("Ask to join").opacity(asked ? 0 : 1)
                Text("Asked").opacity(asked ? 1 : 0)
            }
            .font(.displaySemi(RSVPArea.Size.page.top))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MeetupPillStyle(height: Metric.pillHeight, minWidth: 0, light: asked))
        .turnBackShake(failures: asks.failures[group.id] ?? 0, shakes: !reduceMotion)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: asked)
        .accessibilityLabel(asked ? "Asked to join" : "Ask to join")
        .accessibilityHint(asked ? "Takes your ask back" : "")
        .padding(.horizontal, Metric.pillSide)
        .padding(.bottom, Metric.pillBottom)
        .background {
            LinearGradient(colors: [Hue.paper.opacity(0), Hue.paper], startPoint: .top, endPoint: .bottom)
                .padding(.top, -Metric.fadeAbovePill)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Requests, the Group chat row's own look (`FactRow`): how many wait, and it opens them.
    private func requestsRow(_ count: Int) -> some View {
        FactRow(glyph: "person.badge.plus",
                lines: EventPage.FactLines(first: "Requests", second: count > 0 ? "\(count) waiting" : nil),
                end: .opens, hint: "Opens the requests") { showingRequests = true }
            .padding(.top, Metric.membersTop)
    }

    private var memberBar: some View {
        let isMember = actions.member(group).isMember
        let failures = actions.memberFailureCount(group.id)
        let size = RSVPArea.Size.page
        return HStack(spacing: 0) {
            if isMember {
                VStack(alignment: .leading, spacing: 1) {
                    Text("You're in!")
                        .font(.display(size.top))
                        .foregroundStyle(Hue.ink)
                    RSVPArea.leave("Leave group?", size: size, hint: "Takes you out of the group",
                                   action: toggle)
                }
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .layoutPriority(1)
                .transition(.opacity)
                Spacer(minLength: 12)
            }
            Button {
                if isMember { ShareCenter.shared.present(.group(group)) } else { toggle() }
            } label: {
                // Both faces stay inside the pill and cross-fade as it shrinks; a face swapped
                // out stayed where the wide pill had been, outside the small one.
                ZStack {
                    Text("Join group")
                        .opacity(isMember ? 0 : 1)
                    HStack(spacing: RSVPArea.glyphGap) { RSVPArea.invite(size) }
                        .opacity(isMember ? 1 : 0)
                }
                .font(.displaySemi(size.top))
                .frame(maxWidth: isMember ? nil : .infinity)
            }
            .buttonStyle(MeetupPillStyle(height: isMember ? size.pillHeight : Metric.pillHeight,
                                         minWidth: size.pillMinWidth))
            .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
            .accessibilityLabel(isMember ? "Invite" : "Join group")
            .accessibilityValue(isMember ? "Joined" : "")
        }
        // In the group: the Event page's capsule (`EventPage.rsvpBar`), the words 24 pt
        // in, the pill 5.5 pt from its end, 57 pt tall, a little glass over a white layer.
        .padding(.leading, isMember ? Event.barWordsInset : 0)
        .padding(.trailing, isMember ? Event.barPillInset : 0)
        .padding(.vertical, isMember ? Event.barPillInset : 0)
        .frame(minHeight: isMember ? Event.barHeight : nil)
        // The whole capsule takes a touch: a tap between the words and the pill once opened the
        // group's website, under the bar.
        .contentShape(Capsule())
        .glassEffect(isMember ? .regular : .identity, in: Capsule())
        .background {
            Capsule()
                .fill(Hue.surface.opacity(isMember ? Event.barWhite : 0))
                .allowsHitTesting(false)
        }
        .padding(.horizontal, isMember ? Event.inset : Metric.pillSide)
        // Reduce Motion: shorter, as the RSVP pill (`RSVPArea`); swapping the bar for a cross-fade
        // would rebuild the button and lose VoiceOver's place.
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: isMember)
        .padding(.bottom, Metric.pillBottom)
        .background {
            LinearGradient(colors: [Hue.paper.opacity(0), Hue.paper], startPoint: .top, endPoint: .bottom)
                .padding(.top, -Metric.fadeAbovePill)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Join group and "Leave group?" both flip being in it; a write the server refuses turns back
    /// and shakes the pill.
    private func toggle() {
        // The Admin hands over or closes first (start-a-group 04); the server won't let them leave either.
        if actions.member(group).isMember, GroupAsks.asksToLeave(group) {
            leaving = true
        } else {
            flip()
        }
    }

    private func flip() {
        tappedAt = actions.memberFailureCount(group.id)
        let joining = !actions.member(group).isMember
        actions.toggleMember(group)
        // Joined: the toast asks whether its get-togethers go on your Agenda (rsvp-and-groups 09).
        if joining, actions.member(group).isMember { GroupAgenda.shared.joined(group) }
        // The invite that let you in goes as you leave (`leaving_ends_invite`): Ask to join, not a Join that's refused.
        if !joining { group.invitedBy = nil }
    }

    // MARK: Words (SearchModelTests)

    /// "Private group · 12 members", mock frame 7; "Private group" before anyone is in it.
    static func privateLine(_ members: Int) -> String {
        ["Private group", membersText(members)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Book club · St. Joseph": the town alone when the group doesn't say what kind it is.
    static func kindLine(_ group: TownGroup) -> String {
        return [nonempty(group.kind), Town.everyday].compactMap { $0 }.joined(separator: " · ")
    }

    /// "1st Tuesdays at 9:30 AM · Fireside Room, Resurrection Lutheran"; nil with neither.
    static func whenLine(_ group: TownGroup) -> String? {
        let parts = [nonempty(group.schedule), nonempty(group.location)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Never "0 members".
    static func membersText(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 member"
        default: "\(count) members"
        }
    }

    /// "Tue, Oct 20 · 6 PM", with its place when it isn't the group's usual one.
    static func meetingLine(_ meeting: TownGroup.Meeting) -> String {
        var parts: [String] = []
        if let day = Town.midnight(meeting.day) { parts.append(Town.format(day, "EEEMMMd")) }
        if let minutes = EventWhen.minutes(meeting.time) { parts.append(Town.clock(minutes: minutes)) }
        if let place = nonempty(meeting.place) { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    /// The date tile's words: "OCT" and "20".
    static func tile(_ day: String) -> (month: String, day: String) {
        guard let date = Town.midnight(day) else { return ("", "") }
        return (Town.format(date, "MMM").uppercased(), Town.format(date, "d"))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// The lock glyph a little closer to its words than a Label's, as the mock's 6 pt.
private struct PrivateLineStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.glyph(13, weight: .semibold))
            configuration.title
        }
        .accessibilityElement(children: .combine)
    }
}
