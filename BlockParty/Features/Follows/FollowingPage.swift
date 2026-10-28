//
//  FollowingPage.swift
//  Block Party — Profile's Following list and an Event page's host line (BP app docs/plans/follows,
//  ticket 02).
//
//  Following: everyone and everything you follow, A to Z, each with its Following button, as
//  Instagram's list (60 pt pictures, 76 pt rows, its 104 x 32 pt button). One tap unfollows; the
//  row stays, as Follow, until you leave, so a slip is one tap to undo (Jesse's pick at Check-in
//  1). Pushed from the Profile sheet's Following row, under Blocked's top. Groups aren't listed:
//  the You tab's Groups row holds them. A row opens what it follows, as Instagram's list does
//  (ticket 05): a person's page, a Place's business page as Search opens it, a team's page, the
//  City's or Joetown's page, a board's meetings (follows 04); a
//  Place Search can't open (no logo) doesn't open here either.
//
//  The host line: Eventbrite's "Organized by", under where an Event is: the Place or person who
//  hosts it, "Host · 128 followers", and Follow. Its picture and name open the host's own page, as an
//  Instagram name opens its profile (follows 08): a person's, a page's, a board's meetings, a team's,
//  or a Place's business page flying out of its picture (`HostOpener`, the shell's).
//

import SwiftUI

struct FollowingPage: View {
    @Environment(RealLifeActions.self) private var actions
    @Environment(SearchModel.self) private var places
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rows: [FollowRow]?
    @State private var failed = false
    @State private var opener = BusinessOpener()
    @State private var person: FollowRow?
    @State private var team: Game.Team?
    @State private var page: TownPageKind?
    @State private var board: TownBoardRoute?

    /// Saved's sheet edge to its top bar (`SavedPage`, as `BlockedPage`).
    private static let barTop: CGFloat = 20

    var body: some View {
        ZStack {
            list
            BusinessPage()
        }
        .environment(opener)
        // Open over the sheet, a business closes by its own drag, not the sheet's.
        .interactiveDismissDisabled(opener.isOpen)
        .navigationDestination(item: $person) { FollowedNeighborPage(row: $0) }
        .navigationDestination(item: $team) { TeamPage(team: $0) }
        .navigationDestination(item: $page) { TownPageView(shown: $0) }
        .navigationDestination(item: $board) { TownBoardPage(route: $0) }
        .onAppear { opener.reduceMotion = reduceMotion }
        // Search's places, for a Place's page, read here when Search hasn't been opened yet.
        .task { if !places.placesLoaded { await places.load() } }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let rows {
                    ForEach(rows) { row in
                        FollowingRow(row: row, item: item(row)) { open(row, item: $0, from: $1) }
                    }
                } else if failed {
                    // The Town feed's words for a read that failed.
                    Text("Check your connection and try again.")
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .padding(.horizontal, FriendsMetric.side)
                        .padding(.top, FriendsMetric.noteTop)
                } else {
                    ForEach(0..<FriendsMetric.loadingRows, id: \.self) { _ in
                        HStack(spacing: FriendsMetric.avatarGap) {
                            SkeletonBlock(cornerRadius: FriendsMetric.neighborFace / 2)
                                .frame(width: FriendsMetric.neighborFace, height: FriendsMetric.neighborFace)
                            SkeletonBlock(cornerRadius: FriendsMetric.loadingLine / 2)
                                .frame(width: FriendsMetric.loadingName, height: FriendsMetric.loadingLine)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, FriendsMetric.side)
                        .frame(height: FriendsMetric.row)
                        .shimmering()
                        .accessibilityHidden(true)
                    }
                }
            }
            .padding(.top, FriendsMetric.resultsTop)
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        // `following-empty`: Apple's empty page, in the middle, once a read has said so.
        .overlay {
            if rows?.isEmpty == true {
                ContentUnavailableView("You're not following anyone yet", systemImage: "person.2")
                    .allowsHitTesting(false)
            }
        }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        do {
            let read = try await Self.read()
            actions.read(following: read.map(\.target))
            rows = read
            failed = false
        } catch {
            failed = rows == nil
        }
    }

    /// `my_follows`; under DEBUG `-town-samples` a few samples, and `-town-offline` a failed read.
    private static func read() async throws -> [FollowRow] {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).myFollows()
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples:
            return Neighbor.samples.filter { $0.relation == .friends }.prefix(2).map {
                FollowRow(targetType: .profile, targetId: $0.id, name: $0.displayName, kind: nil,
                          picture: $0.avatarUrl, pictureKind: "photo")
            } + [FollowRow(targetType: .team, targetId: "d2d14f41-35bc-4b0c-bc03-680f28de7674", name: "Cathedral",
                           kind: "team", picture: "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/cathedral/logo-160e29d911.png",
                           pictureKind: "logo"),
                 // Krewe's real place id, so its row opens the page Search reads for it.
                 FollowRow(targetType: .place, targetId: "02280501-5d7d-4c2b-8a6b-2ec671ce9c7c", name: "Krewe",
                           kind: "cajun_restaurant", picture: nil, pictureKind: nil),
                 FollowRow(targetType: .page, targetId: "sample-city", name: Town.cityPage, kind: "City government",
                           picture: nil, pictureKind: nil),
                 FollowRow(targetType: .board, targetId: "sample-board-1", name: "City Council", kind: nil,
                           picture: nil, pictureKind: nil)]
        }
    }

    private var bar: some View {
        ZStack {
            // `following-row`
            Text("Following")
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                FriendsBackButton { dismiss() }
                Spacer()
            }
            .padding(.leading, SearchMetric.pageBackLead)
        }
        .frame(height: SearchMetric.pageBar)
        .padding(.top, Self.barTop)
        .frame(maxWidth: .infinity)
        .background(Hue.paper)
    }

    /// A Place's page as Search has it; nil for anyone else, or a Place Search can't open.
    private func item(_ row: FollowRow) -> SearchItem? {
        guard row.targetType == .place else { return nil }
        return places.items.first { $0.placeID == row.targetId && $0.opens }
    }

    private func open(_ row: FollowRow, item: SearchItem?, from picture: CGRect) {
        switch row.targetType {
        case .profile: person = row
        case .team: team = Game.Team(followed: row)
        case .page: page = TownPageKind.of(row)
        case .board:
            board = TownBoardRoute(board: .init(id: row.targetId, name: row.name, following: true, next: nil),
                                   city: Town.cityPage)
        default:
            guard let item, let logo = item.logo else { return }
            // From its round picture: a logo flies out of it; a photo lets the logo fade in, as a
            // Search photo card does.
            opener.open(item, from: .init(logo: picture, box: picture, radius: picture.width / 2, shadow: logo.shadow,
                                          fades: row.pictureKind != "logo"))
        }
    }
}

/// One Following row: its picture and name open what it follows, pressed with the Friends rows'
/// grey; its Following button keeps its own tap. The row's press is a button behind it all, so the
/// row draws one Following button and its picture and words let the finger through to it.
private struct FollowingRow: View {
    let row: FollowRow
    let item: SearchItem?
    let open: (SearchItem?, CGRect) -> Void
    @State private var picture = FrameBox()

    /// A person, a team, the Town's pages and boards, or a Place Search can open. Anything else (an
    /// activity) has no page here.
    private var opens: Bool {
        switch row.targetType {
        case .profile, .team, .page, .board: true
        case .place: item != nil
        default: false
        }
    }

    var body: some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            Group {
                FollowPicture(row: row, size: FriendsMetric.neighborFace)
                    .trackFrame(picture)
                VStack(alignment: .leading, spacing: FriendsMetric.lineGap) {
                    Text(row.name)
                        .font(.sansSemibold(17))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    if let what = FollowPicture.what(row) {
                        Text(what)
                            .font(.sans(15))
                            .foregroundStyle(Hue.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // VoiceOver presses the row here; the button behind is for fingers.
                .accessibilityAddTraits(opens ? .isButton : [])
                .accessibilityAction { if opens { open(item, picture.rect) } }
            }
            .allowsHitTesting(false)
            FollowButton(target: row.target, name: row.name, size: .row, minWidth: FollowMetric.listWidth)
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
        .background {
            if opens {
                Button { open(item, picture.rect) } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A person's page from their Following row or a host row, which know only who they are: it opens at
/// once on their photo and name, and its pill waits for `get_neighbor` to say where you stand, so a
/// friend never flashes Add friend. A failed read shows the pill as the Friends book has it; nobody
/// found (they blocked you since) shows none.
struct FollowedNeighborPage: View {
    let row: FollowRow
    @Environment(FriendsBook.self) private var book
    @State private var read: Neighbor?
    @State private var settled = false

    var body: some View {
        NeighborPage(neighbor: read ?? standIn, settled: settled)
            .task {
                do {
                    read = try await Self.read(row.targetId)
                    settled = read != nil
                } catch {
                    settled = true
                }
            }
    }

    private var standIn: Neighbor {
        Neighbor(userId: row.targetId, displayName: row.name, avatarUrl: row.picture, since: nil,
                 relation: book.friends.first { $0.id == row.targetId }?.relation ?? .stranger, mutualFriends: 0)
    }

    /// `get_neighbor`; under DEBUG `-town-samples` the sample by that id.
    private static func read(_ id: String) async throws -> Neighbor? {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).getNeighbor(id)
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples: return Neighbor.samples.first { $0.id == id }
        }
    }
}

/// A Place's or person's round picture: a person's photo (their initial without one), a Place's
/// photo, or its logo inset on white, as the mock draws a Place with no photo. The Town's own page
/// draws the app's Town logo (follows 04).
struct FollowPicture: View {
    let row: FollowRow
    let size: CGFloat

    /// `picture_kind` for the Town's own logo, bundled in the app (`Town.logo`).
    static let townKind = "town"

    var body: some View {
        let url = row.picture.flatMap(URL.init)
        if row.pictureKind == Self.townKind {
            Image(Town.logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if row.pictureKind == "logo", let url {
            Circle()
                .fill(Hue.surface)
                .overlay { FeedCardURLPhoto(url: url, loadingFill: Hue.surface).padding(size * 0.16) }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Hue.hairline, lineWidth: FriendsMetric.hairline))
                .accessibilityHidden(true)
        } else {
            FeedAuthorAvatar(url: url, name: row.name, side: size, initialSize: size * 0.4)
                .accessibilityHidden(true)
        }
    }

    /// What it is, under its name: "Neighbor", or a Place's kind ("Cajun").
    static func what(_ row: FollowRow) -> String? {
        switch row.targetType {
        case .profile: "Neighbor"
        case .team: "Team"
        // "City government"; a board, its City's name.
        case .page, .board: row.kind
        default: row.kind.flatMap(SearchModel.label)
        }
    }
}

/// A person's page pushed from a host row (follows 08).
struct FollowedPersonRoute: Hashable {
    let row: FollowRow
}

/// What a host row opens (follows 08), set by the shell's stack: nil anywhere it can't push, where a
/// host opens nothing of its own.
@MainActor
struct HostOpener {
    /// Whether `open` takes this host anywhere: a Place only when Search can open it.
    let opens: (FollowRow) -> Bool
    /// Pushes its page, or flies a Place's business page out of `picture` (its frame on screen).
    let open: (_ host: FollowRow, _ picture: CGRect) -> Void
    /// A Group from Search's read, by id, and pushing it.
    let group: (String) -> TownGroup?
    let pushGroup: (TownGroup) -> Void
    /// A local school's page, from a game card's host (hello-drop 03).
    let pushTeam: (Game.Team) -> Void
    /// The Event's own page: where a card's host goes when it has no page of its own.
    let pushEvent: (FeedCardItem) -> Void
}

extension EnvironmentValues {
    @Entry var hostOpener: HostOpener? = nil
}

/// An Event page's host line, under where it is. Reads who hosts it when the page opens; draws
/// nothing until then, or for an Event with no host to follow. Its picture and name open the host's
/// page, pressed with a list row's grey; Follow keeps its own tap.
struct EventHostRow: View {
    let item: FeedCardItem
    /// Paper above it once it shows; none while it doesn't.
    var top: CGFloat = 0
    /// The place's name is on the photo above: a Place hosting doesn't say it again here.
    var placeNamed = false
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.hostOpener) private var opener
    @State private var host: FollowRow?
    @State private var picture = FrameBox()

    static let picture: CGFloat = 44
    static let smallPicture: CGFloat = 32
    static let gap: CGFloat = 12

    var body: some View {
        // Always something on screen, even before the read, so the read starts.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
            if let host {
                let opens = opener?.opens(host) == true
                HStack(spacing: Self.gap) {
                    Group {
                        // Smaller under a named photo: the name has already been said (Jesse's pick).
                        FollowPicture(row: host, size: placeNamed && host.targetType == .place ? Self.smallPicture : Self.picture)
                            .trackFrame(picture)
                        VStack(alignment: .leading, spacing: 2) {
                            if !(placeNamed && host.targetType == .place) {
                                Text(host.name)
                                    .font(.sansSemibold(15))
                                    .foregroundStyle(Hue.ink)
                                    .lineLimit(1)
                            }
                            // `host-line`: "Host · 128 followers"; a person shows no count. A City
                            // meeting's board: "City of St. Joseph · 41 followers" (follows 04).
                            Text([Self.hostWord(host), FollowWords.count(actions.follow(host.target).count)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.sans(13))
                                .foregroundStyle(Hue.inkSecondary)
                                .contentTransition(.numericText())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        // VoiceOver presses the row here; the button behind is for fingers.
                        .accessibilityAddTraits(opens ? .isButton : [])
                        .accessibilityAction { if opens { opener?.open(host, picture.rect) } }
                    }
                    .allowsHitTesting(false)
                    // A friend you follow reads Following; one you unfollowed can follow again here.
                    FollowButton(target: host.target, name: host.name, size: .row)
                }
                .background {
                    if opens {
                        Button { opener?.open(host, picture.rect) } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(RowPressStyle())
                            .accessibilityHidden(true)
                    }
                }
                .animation(Motion.smooth, value: actions.follow(host.target).count)
                .padding(.top, top)
                .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: host)
        .task(id: item.id) {
            guard let found = try? await Self.read(item) else { return }
            host = found
            await actions.refreshFollow(found.target)
        }
    }

    /// "Host", or a page's or board's own kind: "City government", "City of St. Joseph".
    static func hostWord(_ host: FollowRow) -> String {
        [.page, .board].contains(host.targetType) ? host.kind ?? "Host" : "Host"
    }

    /// `event_host`; under DEBUG `-town-samples` its Place, by the card's own words.
    static func read(_ item: FeedCardItem) async throws -> FollowRow? {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).eventHost(item.id)
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples:
            guard let place = item.whereLine else { return nil }
            return FollowRow(targetType: .place, targetId: "sample-\(item.id)", name: place, kind: "restaurant",
                             picture: nil, pictureKind: nil)
        }
    }
}
