//
//  TownPage.swift
//  Block Party — the Town's two public pages, its own (Joetown) and its City's (BP app
//  docs/plans/follows, ticket 04). Pushed from the Town bar's wordmark menu and Daily's Town logo.
//  Apple's segmented switch at the top picks the other page without going back. Any other page (a
//  campus calendar's, follows 08) opens from its host alone, with no switch, on the photo its read
//  brings. Each page: its
//  picture and name, "City government · 312 followers", the friends who follow it and Follow, then
//  what's coming up. The City's then lists its boards, each with its next meeting and its own
//  Follow; a row pushes that board's meetings.
//
//  Sizes off the approved Figma frames (`references/follows/figma/build.js`, `civicPage`): 20 pt
//  sides, 13 pt kind line, 17 pt section titles, 44 pt tiles and pictures in rows 64 pt apart, the
//  row's 32 pt Follow pill. The photo up top, its sheet and its round Back are the Group page's.
//

import SwiftUI

/// Which page: the Town's own or its City's (`town_pages.slug`), or any other by its id, a campus
/// calendar's (follows 08).
enum TownPageKind: Hashable, Codable {
    case town, city
    /// Another page, and its name until its read says it.
    case page(id: String, name: String)

    /// The two the switch picks between.
    static let switchable: [TownPageKind] = [.town, .city]

    /// "town" or "city"; nil for any other slug.
    init?(slug: String) {
        switch slug {
        case "town": self = .town
        case "city": self = .city
        default: return nil
        }
    }

    /// The page a host or Following row names: the Town's two by their names, any other by its id.
    static func of(_ row: FollowRow) -> TownPageKind {
        switch row.name {
        case Town.townPage: .town
        case Town.cityPage: .city
        default: .page(id: row.targetId, name: row.name)
        }
    }

    var name: String {
        switch self {
        case .town: Town.townPage
        case .city: Town.cityPage
        case .page(_, let name): name
        }
    }

    /// The Town's two pages' photos, in the app; another page's comes with its read.
    var photo: (name: String, credit: String)? {
        switch self {
        case .town: Town.townPagePhoto
        case .city: Town.cityPagePhoto
        case .page: nil
        }
    }
}

/// One page as `town_page` reads it.
struct TownPageInfo: Decodable, Hashable {
    let id: String
    let name: String
    /// The kind line's first words: "City government".
    let kind: String
    let picture: String?
    let pictureKind: String?
    /// Whose photo it is, for one from the web: "csbsju.edu" (follows 08). Optional, so a read from
    /// before it still decodes.
    var pictureCredit: String? = nil
    let events: [Event]
    /// A City's boards, A to Z; none for the Town's own page.
    let boards: [Board]

    var target: FollowTarget { FollowTarget(type: .page, id: id) }

    /// One coming Event, or one of a board's meetings (`board_meetings`).
    struct Event: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
        let date: String
        let time: String?
        let location: String?
    }

    struct Board: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
        let following: Bool
        /// Its next meeting; nil with none set.
        let next: Next?

        struct Next: Decodable, Hashable {
            let date: String
            let time: String?
        }

        var target: FollowTarget { FollowTarget(type: .board, id: id) }
    }
}

/// Coming up with nothing in it.
private struct TownNothingYet: View {
    var body: some View {
        Text("Nothing coming up")
            .font(.sans(15))
            .foregroundStyle(Hue.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A board's own page, pushed from its row.
struct TownBoardRoute: Hashable {
    let board: TownPageInfo.Board
    /// Its City's name, for its kind line.
    let city: String
}

/// What the page shows and which one: each page read once and kept, so the switch flips back at
/// once. The reads are injected: live, DEBUG samples, or a test's.
@MainActor
@Observable
final class TownPageModel {
    var shown: TownPageKind
    private(set) var pages: [TownPageKind: TownPageInfo] = [:]
    /// Read and failed, with nothing kept to show.
    private(set) var failed: Set<TownPageKind> = []

    private let read: (TownPageKind) async throws -> TownPageInfo?

    /// `read`: nil reads `town_page` (`live`).
    init(shown: TownPageKind, read: ((TownPageKind) async throws -> TownPageInfo?)? = nil) {
        self.shown = shown
        self.read = read ?? { try await TownPageModel.live($0) }
    }

    var page: TownPageInfo? { pages[shown] }
    var boards: [TownPageInfo.Board] { page?.boards ?? [] }

    /// Reads the shown page; its boards' Follow comes from the read. A failed read keeps the last.
    func load(_ actions: RealLifeActions) async {
        let kind = shown
        do {
            guard let info = try await read(kind) else { failed.insert(kind); return }
            pages[kind] = info
            failed.remove(kind)
            actions.read(boards: info.boards)
        } catch {
            if pages[kind] == nil { failed.insert(kind) }
        }
    }

    /// `board-next-meeting`: "Next meeting Tue, Oct 28 · 6 PM"; nil with none set.
    static func nextMeeting(_ next: TownPageInfo.Board.Next?) -> String? {
        next.map { "Next meeting " + when(date: $0.date, time: $0.time) }
    }

    /// "Tue, Oct 28 · 6 PM": the day, and its time when it has one.
    static func when(date: String, time: String?) -> String {
        var parts: [String] = []
        if let day = Town.midnight(date) { parts.append(Town.format(day, "EEEMMMd")) }
        if let minutes = EventWhen.minutes(time) { parts.append(Town.clock(minutes: minutes)) }
        return parts.joined(separator: " · ")
    }

    /// A board's tile: "City Council" is "CC", "Economic Development Authority" "EDA".
    static func initials(_ name: String) -> String {
        String(name.split(separator: " ").compactMap(\.first).filter(\.isUppercase).prefix(3))
    }

    /// `town_page`; under DEBUG `-town-samples` the samples, and `-town-offline` a failed read.
    static func live(_ kind: TownPageKind) async throws -> TownPageInfo? {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).townPage(kind)
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples: return sample(kind)
        }
    }

    /// `board_meetings`, the same way.
    static func meetings(_ board: String) async throws -> [TownPageInfo.Event] {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).boardMeetings(board)
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples: return sample(.city).events.filter { $0.title.hasPrefix("City Council") }
        }
    }

    /// Sample pages, dated from today, for previews and the Eyes pass.
    static func sample(_ kind: TownPageKind) -> TownPageInfo {
        let day = { (ahead: Int) in Town.day(Date().addingTimeInterval(Double(ahead) * 86_400)) }
        let event = { (n: Int, title: String, ahead: Int, time: String) in
            TownPageInfo.Event(id: "sample-\(kind.name)-\(n)", title: title, date: day(ahead), time: time, location: nil)
        }
        let board = { (n: Int, name: String, ahead: Int?) in
            TownPageInfo.Board(id: "sample-board-\(n)", name: name, following: false,
                               next: ahead.map { .init(date: day($0), time: "18:00") })
        }
        switch kind {
        case .page(let id, let name):
            return TownPageInfo(id: id, name: name, kind: "College",
                                picture: "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/csbsju-events/photo-774a7306de.webp",
                                pictureKind: "photo", pictureCredit: "csbsju.edu",
                                events: [event(1, "Fix-It Clinic", 1, "15:00"), event(2, "Bones & Brushes", 3, "17:00")],
                                boards: [])
        case .town:
            return TownPageInfo(id: "sample-town", name: kind.name, kind: "Town events", picture: nil, pictureKind: "town",
                                events: [event(1, "Shop Small Crawl", 3, "10:00"), event(2, "Winterwalk", 8, "17:00")],
                                boards: [])
        case .city:
            return TownPageInfo(id: "sample-city", name: kind.name, kind: "City government", picture: nil, pictureKind: nil,
                                events: [event(1, "City Council Meeting", 1, "18:00"), event(2, "Park Board Meeting", 6, "18:00")],
                                boards: [board(1, "City Council", 1), board(2, "Economic Development Authority", nil),
                                         board(3, "Park Board", 6), board(4, "Planning Commission", 13)])
        }
    }
}

nonisolated enum TownPageMetric {
    static let side: CGFloat = 20
    static let pictureGap: CGFloat = 14
    /// The switch on the photo: Figma's 280 pt, clear of Back on a narrower phone.
    static let switchWidth: CGFloat = 280
    static let switchClear: CGFloat = 64
    static let headerTop: CGFloat = 26
    static let followTop: CGFloat = 16
    static let sectionTop: CGFloat = 28
    static let rowsTop: CGFloat = 12
    /// A row's tile or picture, and the gap to its words (the mock's 44 and 56 − 44).
    static let tile: CGFloat = 44
    static let tileCorner: CGFloat = 10
    static let tileGap: CGFloat = 12
    static let row: CGFloat = 64
    static let loadingRows = 3
}

/// The two pages behind one switch.
struct TownPageView: View {
    @State private var model: TownPageModel
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Scrolled up past the photo: the top turns paper, so the words never run under the clock.
    @State private var pastPhoto = false

    init(shown: TownPageKind) {
        _model = State(initialValue: TownPageModel(shown: shown))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                TownPagePhoto(kind: model.shown, page: model.page)
                VStack(alignment: .leading, spacing: 0) {
                    TownPageHeader(model: model)
                        .padding(.top, TownPageMetric.headerTop)
                    TownPageLists(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TownPageMetric.side)
                .padding(.bottom, 40)
                .background(Hue.paper, in: UnevenRoundedRectangle(topLeadingRadius: Event.sheetCorner,
                                                                 topTrailingRadius: Event.sheetCorner, style: .continuous))
            }
        }
        .refreshable { await model.load(actions) }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > geo.containerSize.width / GroupPage.Metric.heroAspect - 80
        } action: { _, past in
            pastPhoto = past
        }
        // The photo runs up under the status bar, as the Group page's.
        .ignoresSafeArea(edges: .top)
        .background(Hue.paper.ignoresSafeArea())
        .overlay(alignment: .top) { top }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.shown) { await model.load(actions) }
        .sensoryFeedback(.selection, trigger: model.shown)
    }

    private typealias Event = FeedEventDetailDestination.Metric

    /// Back, and the switch centred on the photo; outside the scroll, so they stay put.
    private var top: some View {
        HStack(spacing: 0) {
            FeedEventDetailDestination.circleButton(glyph: Image(systemName: "arrow.left"), label: "Back",
                                                    reduceMotion: reduceMotion) { dismiss() }
            Spacer(minLength: 0)
        }
        .overlay {
            // The switch, between the Town's own two only.
            if TownPageKind.switchable.contains(model.shown) {
                picker
                    .frame(maxWidth: TownPageMetric.switchWidth)
                    .padding(.horizontal, TownPageMetric.switchClear)
            }
        }
        .padding(.horizontal, Event.inset - (Event.tapBox - Event.button) / 2)
        .padding(.top, Event.buttonTop - (Event.tapBox - Event.button) / 2)
        .padding(.bottom, 4)
        .background { Hue.paper.ignoresSafeArea(edges: .top).opacity(pastPhoto ? 1 : 0) }
        .animation(Motion.smooth, value: pastPhoto)
    }

    private var picker: some View {
        Picker("Page", selection: $model.shown) {
            ForEach(TownPageKind.switchable, id: \.self) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        .background(Hue.paper.opacity(0.94), in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

/// The page's photo, the Group page's size: it stretches when the page is pulled down, and its
/// credit sits bottom left. Switching pages fades one into the other. The Town's two are in the app;
/// another page's is its read's.
private struct TownPagePhoto: View {
    let kind: TownPageKind
    let page: TownPageInfo?

    private var url: URL? {
        if let name = kind.photo?.name { return Bundle.main.url(forResource: name, withExtension: "jpg") }
        return page?.picture.flatMap(URL.init(string:))
    }

    private var credit: String? { kind.photo?.credit ?? page?.pictureCredit }

    private typealias Event = FeedEventDetailDestination.Metric

    var body: some View {
        Color.clear
            .aspectRatio(GroupPage.Metric.heroAspect, contentMode: .fit)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    if let url {
                        FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                            .frame(width: proxy.size.width, height: proxy.size.height + Event.heroUnderlap)
                            .clipped()
                            .id(kind)
                            .transition(.opacity)
                    }
                }
            }
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                PhotoCredit(names: credit.map { [$0] } ?? [])
                    .padding(.leading, Event.inset - PhotoCredit.edgeInset)
                    .padding(.bottom, Event.counterBottom - PhotoCredit.edgeInset)
                    .id(kind)
                    .transition(.opacity)
            }
            .animation(Motion.smooth, value: kind)
            .accessibilityHidden(true)
    }
}

/// A pushed page's bar: Back at the leading edge, as Following's.
private struct TownPageBar: View {
    let back: () -> Void

    var body: some View {
        HStack {
            FriendsBackButton(action: back)
            Spacer()
        }
        .padding(.leading, SearchMetric.pageBackLead)
        .frame(height: SearchMetric.pageBar)
        .background(Hue.paper)
    }
}

/// The page's name, kind line with its count, and its follow line. The name is known before the
/// read; the rest waits for it.
private struct TownPageHeader: View {
    let model: TownPageModel
    @Environment(RealLifeActions.self) private var actions

    var body: some View {
        let page = model.page
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page?.name ?? model.shown.name)
                    .font(.eventDisplay(28))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                kindLine(page)
            }
            if let page {
                FollowLine(target: page.target, name: page.name)
                    .padding(.top, TownPageMetric.followTop)
                    .transition(.opacity)
            } else if !model.failed.contains(model.shown) {
                HStack {
                    Spacer()
                    SkeletonBlock(cornerRadius: Radius.button)
                        .frame(width: FollowMetric.pageWidth, height: FollowMetric.pageHeight)
                }
                .padding(.top, TownPageMetric.followTop)
                .shimmering()
                .accessibilityHidden(true)
            }
        }
        .animation(Motion.smooth, value: page)
    }

    @ViewBuilder
    private func kindLine(_ page: TownPageInfo?) -> some View {
        if let page {
            // "City government · 312 followers" (follows 02's count).
            Text([page.kind, FollowWords.count(actions.follow(page.target).count)].compactMap { $0 }
                .joined(separator: " · "))
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .contentTransition(.numericText())
                .animation(Motion.smooth, value: actions.follow(page.target).count)
        } else if !model.failed.contains(model.shown) {
            SkeletonLine(widthFraction: 0.6, height: 13)
                .shimmering()
                .accessibilityHidden(true)
        }
    }
}

/// Coming up, and the City's boards; their rows' shapes while the page reads.
private struct TownPageLists: View {
    let model: TownPageModel

    var body: some View {
        if let page = model.page {
            TownPageSection(title: "Coming up")
            if page.events.isEmpty {
                TownNothingYet()
            } else {
                ForEach(page.events) { TownEventRow(event: $0) }
            }
            if !page.boards.isEmpty {
                TownPageSection(title: "Boards")
                ForEach(page.boards) { TownBoardRow(board: $0, city: page.name) }
            }
        } else if model.failed.contains(model.shown) {
            Text("Check your connection and try again.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, TownPageMetric.sectionTop)
        } else {
            TownPageSection(title: "Coming up")
            TownRowsLoading()
        }
    }
}

private struct TownPageSection: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.sansSemibold(17))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, TownPageMetric.sectionTop)
            .padding(.bottom, TownPageMetric.rowsTop - (TownPageMetric.row - TownPageMetric.tile) / 2)
    }
}

/// Rows in their own shape while they read.
private struct TownRowsLoading: View {
    var body: some View {
        ForEach(0..<TownPageMetric.loadingRows, id: \.self) { _ in
            HStack(spacing: TownPageMetric.tileGap) {
                SkeletonBlock(cornerRadius: TownPageMetric.tileCorner)
                    .frame(width: TownPageMetric.tile, height: TownPageMetric.tile)
                SkeletonLine(widthFraction: 0.55, height: 15)
            }
            .frame(height: TownPageMetric.row)
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// A date tile ("NOV" over "29"), then what it is and when: "Sat, Nov 29 · 10 AM".
struct TownEventRow: View {
    let event: TownPageInfo.Event
    @Environment(TownFeed.self) private var feed: TownFeed?

    var body: some View {
        // Opens its Event page, as a Town card does; the route Notifications uses, so an open from
        // here doesn't count toward the Town feed's popularity.
        NavigationLink(value: NoticeEventRoute(item: item)) { row }
            .buttonStyle(PressableStyle(scale: 0.98))
    }

    /// The Town feed's own card when it has this Event (its photo, Going and the rest); else the
    /// row's few facts.
    private var item: FeedCardItem {
        feed?.cards.first { $0.id == event.id }
            ?? FeedCardItem(UpcomingEvent(id: event.id, title: event.title, eventDate: event.date,
                                          startTime: event.time, location: event.location, goingCount: 0,
                                          createdAt: ""))
    }

    @ViewBuilder private var row: some View {
        let tile = GroupPage.tile(event.date)
        HStack(spacing: TownPageMetric.tileGap) {
            VStack(spacing: 0) {
                Text(tile.month)
                    .font(.sansSemibold(9))
                    .foregroundStyle(Hue.inkSecondary)
                Text(tile.day)
                    .font(.sansBold(17))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
            }
            .frame(width: TownPageMetric.tile, height: TownPageMetric.tile)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: TownPageMetric.tileCorner, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(2)
                Text([TownPageModel.when(date: event.date, time: event.time), event.location]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: TownPageMetric.row)
        .accessibilityElement(children: .combine)
    }
}

/// A board: its initials, its name and next meeting, which push its meetings, and its own Follow.
private struct TownBoardRow: View {
    let board: TownPageInfo.Board
    let city: String

    var body: some View {
        HStack(spacing: TownPageMetric.tileGap) {
            NavigationLink(value: TownBoardRoute(board: board, city: city)) {
                HStack(spacing: TownPageMetric.tileGap) {
                    TownBoardTile(name: board.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(board.name)
                            .font(.sansSemibold(15))
                            .foregroundStyle(Hue.ink)
                            .multilineTextAlignment(.leading)
                        if let next = TownPageModel.nextMeeting(board.next) {
                            Text(next)
                                .font(.sans(13))
                                .foregroundStyle(Hue.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: TownPageMetric.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows its meetings")
            FollowButton(target: board.target, name: board.name, size: .row)
        }
    }
}

/// A board's initials on the rows' grey tile.
private struct TownBoardTile: View {
    let name: String

    var body: some View {
        Text(TownPageModel.initials(name))
            .font(.sansSemibold(12))
            .foregroundStyle(Hue.inkSecondary)
            .frame(width: TownPageMetric.tile, height: TownPageMetric.tile)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: TownPageMetric.tileCorner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One board's page: its name, "City of St. Joseph · 41 followers", its follow line, and its coming
/// meetings.
struct TownBoardPage: View {
    let route: TownBoardRoute
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var meetings: [TownPageInfo.Event]?
    @State private var failed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, TownPageMetric.headerTop)
                FollowLine(target: route.board.target, name: route.board.name)
                    .padding(.top, TownPageMetric.followTop)
                list
            }
            .padding(.horizontal, TownPageMetric.side)
            .padding(.bottom, 40)
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .top, spacing: 0) { TownPageBar { dismiss() } }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: TownPageMetric.pictureGap) {
            TownBoardTile(name: route.board.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.board.name)
                    .font(.eventDisplay(28))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text([route.city, FollowWords.count(actions.follow(route.board.target).count)].compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .contentTransition(.numericText())
                    .animation(Motion.smooth, value: actions.follow(route.board.target).count)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if let meetings {
            TownPageSection(title: "Coming up")
            if meetings.isEmpty {
                TownNothingYet()
            } else {
                ForEach(meetings) { TownEventRow(event: $0) }
            }
        } else if failed {
            Text("Check your connection and try again.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, TownPageMetric.sectionTop)
        } else {
            TownPageSection(title: "Coming up")
            TownRowsLoading()
        }
    }

    private func load() async {
        do {
            meetings = try await TownPageModel.meetings(route.board.id)
            failed = false
        } catch {
            failed = meetings == nil
        }
    }
}
