//
//  FriendsHomePage.swift
//  Block Party — the Friends page and a neighbour's page (BP app docs/plans/friends, tickets
//  02, 03 and 04). The Town bar's friends mark pushes the Friends page: a large title and Search's
//  field, under the sample inbox's own top, then the accepted lines, Requests and Your friends.
//  Typing finds neighbours by name; a name opens their page; one button on every row and
//  page follows where the two of you stand (`FriendsBook`).
//
//  Reference: Facebook's Friends screens (BP app references/friends): the friends-list row
//  measured at a 60pt photo, 12pt gap, 17pt semibold name, 76pt apart. Mock Jesse said yes
//  to on 2026-10-13: https://claude.ai/artifact/YW9WezLabBwQDBmmUKW8wN
//

import SwiftUI

extension FriendsMetric {
    /// Facebook's friends-list photo, measured; its row is the inbox's 76 (`row`).
    static let neighborFace: CGFloat = 60
    static let resultsTop: CGFloat = 8
    /// The neighbour's page: the photo starts this far under the bar, Instagram's 11 (±1)
    /// on someone else's profile (BP app references/friends/ig-person-private.jpg).
    static let headTop: CGFloat = 11
    static let noteTop: CGFloat = 18
    /// Stand-in rows while a search is asked, and how wide their name bar is.
    static let loadingRows = 3
    static let loadingName: CGFloat = 140
    static let loadingLine: CGFloat = 14

    // Ticket 03, off Facebook's Find friends and people search (BP app references/friends,
    // 375pt frames at 1:1): a 92pt request photo, 36pt buttons 8pt apart, 20pt bold section
    // titles, a 28pt face on the accepted line.
    static let requestFace: CGFloat = 92
    static let requestPad: CGFloat = 8
    static let button: CGFloat = 36
    static let buttonGap: CGFloat = 8
    static let buttonTop: CGFloat = 6
    static let buttonPad: CGFloat = 14
    static let resultPad: CGFloat = 10
    static let resultNameTop: CGFloat = 4
    static let sectionTop: CGFloat = 16
    static let sectionBottom: CGFloat = 8
    static let acceptedFace: CGFloat = 28
    static let acceptedPad: CGFloat = 12
    /// A person's page: its button sits where Edit profile sits on your own Profile, at
    /// least the mock's 132pt wide.
    static let pageButtonTop: CGFloat = 14
    static let pageButton: CGFloat = 132
    /// Ticket 04: Facebook's ••• on a friend's row ends 20pt from the screen's edge
    /// (fb-requests-4, 375pt at 1:1); its 44pt target leaves this much past it.
    static let moreTrail: CGFloat = 7
    /// The check before "Friends" on its button. (picked)
    static let iconGap: CGFloat = 6
}

struct FriendsHomePage: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(FriendsBook.self) private var book
    @State private var search = NeighborSearch()
    @State private var words = Self.debugWords
    /// The large title has gone under the bar: the bar shows the small one.
    @State private var titleUnder = false
    @State private var signingIn = false

    private var typing: Bool { !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// What the search found, less anyone you just blocked.
    private var found: NeighborSearch.State { book.visible(search.state) }

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Friends")
                        .font(.sansBold(34))
                        .foregroundStyle(Hue.ink)
                        .frame(height: FriendsMetric.titleLine)
                        .padding(.horizontal, FriendsMetric.side)
                        .accessibilityAddTraits(.isHeader)
                    FriendsSearchField(words: $words)
                        .padding(.horizontal, FriendsMetric.side)
                        .padding(.top, FriendsMetric.titleToField)
                        .padding(.bottom, FriendsMetric.resultsTop)
                    if typing { results } else { home }
                }
                .padding(.top, SearchMetric.pageBar)
            }
            .scrollDismissesKeyboard(.immediately)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > FriendsMetric.titleLine
            } action: { _, under in
                titleUnder = under
            }
            // Drawn last so it sits over the rows, read first so Back comes first.
            FriendsTitleBar(title: "Friends", titleUnder: titleUnder).accessibilitySortPriority(1)
        }
        // Nobody found, or no friends after a read that worked: Apple's empty page, in the
        // middle of the screen.
        .overlay {
            if typing, found == .none {
                ContentUnavailableView("No results found", systemImage: "magnifyingglass")
                    .allowsHitTesting(false)
            } else if !typing, search.state != .needsAccount, book.loaded, book.isEmpty {
                ContentUnavailableView("No friends yet", systemImage: "person.2",
                                       description: Text("Search for neighbors you know and add them."))
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: words, initial: true) { search.search(words) }
        // Logging in from the line below asks again, as the account that now asks.
        .onChange(of: auth.accountKey) {
            search.search(words)
            Task { await book.refresh() }
        }
        // Read on every visit; once drawn, the dot clears and accepted lines count as seen.
        .task {
            await book.refresh()
            await book.seen()
        }
        .onAppear { book.screenOpened() }
        .onDisappear { book.screenClosed() }
        .signInSheet(isPresented: $signingIn)
    }

    /// Nothing typed: the accepted lines, Requests and Your friends, in one list keyed by
    /// person, so a confirmed request slides down into Your friends.
    @ViewBuilder private var home: some View {
        if search.state == .needsAccount {
            LogInToFindRow { signingIn = true }
        } else if !book.loaded {
            if book.failed { FailedLine() } else { LoadingRows() }
        } else {
            ForEach(rows) { row in
                switch row {
                case .accepted(let person): AcceptedLine(person: person)
                case .title(let title): FriendsSectionTitle(text: title)
                case .person(let person, let waiting): PersonRow(person: person, waiting: waiting) { signingIn = true }
                }
            }
        }
    }

    private enum Row: Identifiable {
        /// A request (`waiting`) or a friend: one case, so a confirmed request is the same view
        /// with the same id in its new place, and SwiftUI moves it rather than swapping it.
        case accepted(Neighbor), title(String), person(Neighbor, waiting: Bool)

        var id: String {
            switch self {
            case .accepted(let person): "accepted:" + person.id
            case .title(let title): "title:" + title
            case .person(let person, _): person.id
            }
        }
    }

    private var rows: [Row] {
        // `friends-sections`
        var rows = book.accepted.map(Row.accepted)
        let requests = book.requests, friends = book.friends
        if !requests.isEmpty { rows += [.title("Requests")] + requests.map { .person($0, waiting: true) } }
        if !friends.isEmpty { rows += [.title("Your friends")] + friends.map { .person($0, waiting: false) } }
        return rows
    }

    @ViewBuilder private var results: some View {
        switch found {
        case .found(let people):
            ForEach(people) { ResultRow(person: $0) { signingIn = true } }
        case .needsAccount:
            LogInToFindRow { signingIn = true }
        case .failed:
            FailedLine()
        case .loading:
            LoadingRows()
        case .idle, .none:
            EmptyView()
        }
    }

    /// DEBUG `-friends-words <text>`: opens with those words typed, as Search's flag does.
    private static var debugWords: String {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-friends-words"), i + 1 < args.count { return args[i + 1] }
        #endif
        return ""
    }
}

/// The Town feed's words for a read that failed.
private struct FailedLine: View {
    var body: some View {
        Text("Check your connection and try again.")
            .font(.sans(15))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.horizontal, FriendsMetric.side)
            .padding(.top, FriendsMetric.noteTop)
    }
}

/// Nothing read yet: the rows' own shape, shimmering.
private struct LoadingRows: View {
    var body: some View {
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

/// Facebook's section title on its Friends page: 20pt bold.
private struct FriendsSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.sansBold(20))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, FriendsMetric.side)
            .padding(.top, FriendsMetric.sectionTop)
            .padding(.bottom, FriendsMetric.sectionBottom)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `friend-accepted`, Facebook's line: a small face, then "Sam Rivera accepted your friend
/// request." It shows on the visit after they confirm, once.
private struct AcceptedLine: View {
    let person: Neighbor

    var body: some View {
        NavigationLink(value: person) {
            HStack(spacing: FriendsMetric.avatarGap) {
                NeighborFace(url: person.avatarUrl, size: FriendsMetric.acceptedFace)
                Text("\(Text(person.displayName).font(.sansSemibold(15))) accepted your friend request.")
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, FriendsMetric.side)
            .padding(.vertical, FriendsMetric.acceptedPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline)
                .padding(.horizontal, FriendsMetric.side)
        }
    }
}

/// A request or a friend: one view for both, so Confirm moves the row down into Your friends
/// and shrinks it from Facebook's 92pt request photo to the friends list's 60pt, rather than
/// fading one row out and another in. Waiting, it carries Confirm and Delete. The face and
/// the name open their page; the buttons sit beside those links, not in them.
private struct PersonRow: View {
    let person: Neighbor
    let waiting: Bool
    let logIn: () -> Void
    @Environment(FriendsBook.self) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            NavigationLink(value: person) {
                NeighborFace(url: person.avatarUrl, size: waiting ? FriendsMetric.requestFace : FriendsMetric.neighborFace)
            }
            .buttonStyle(DimStyle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FriendsMetric.lineGap) {
                NavigationLink(value: person) { NameAndMutual(person: person) }
                    .buttonStyle(DimStyle())
                if waiting {
                    RelationButtons(person: person, logIn: logIn)
                        .padding(.top, FriendsMetric.buttonTop)
                        .transition(.opacity)
                }
            }
            if !waiting {
                MoreButton(person: person).transition(.opacity)
            }
        }
        .padding(.leading, FriendsMetric.side)
        .padding(.trailing, waiting ? FriendsMetric.side : FriendsMetric.moreTrail)
        .padding(.vertical, waiting ? FriendsMetric.requestPad : 0)
        .frame(minHeight: waiting ? nil : FriendsMetric.row)
        // An Unfriend that turns back shakes the row it came back to.
        .turnBackShake(failures: waiting ? 0 : book.failures[person.id] ?? 0, shakes: !reduceMotion)
    }
}

/// Facebook's ••• on a friend: opens the friend sheet (ticket 04).
struct MoreButton: View {
    let person: Neighbor
    @Environment(FriendsBook.self) private var book

    var body: some View {
        Button { book.menu = person } label: {
            Image(systemName: "ellipsis")
                .font(.glyph(17, weight: .bold))
                .foregroundStyle(Hue.ink)
                .frame(width: SearchMetric.tapMin, height: SearchMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(DimStyle())
        .accessibilityLabel("More options, \(person.displayName)")
    }
}

/// A search result, Facebook's: the face, the name, and the button under the name. Search
/// passes its own smaller sizes.
struct ResultRow: View {
    let person: Neighbor
    var face: CGFloat = FriendsMetric.neighborFace
    var nameFont: Font = .sansSemibold(17)
    let logIn: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: FriendsMetric.avatarGap) {
            NavigationLink(value: person) { NeighborFace(url: person.avatarUrl, size: face) }
                .buttonStyle(DimStyle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FriendsMetric.lineGap) {
                NavigationLink(value: person) { NameAndMutual(person: person, nameFont: nameFont) }
                    .buttonStyle(DimStyle())
                RelationButtons(person: person, logIn: logIn)
                    .padding(.top, FriendsMetric.buttonTop)
            }
            .padding(.top, FriendsMetric.resultNameTop)
        }
        .padding(.horizontal, FriendsMetric.side)
        .padding(.vertical, FriendsMetric.resultPad)
    }
}

/// The name, and under it the friends you share, or "Request sent" in that place once you
/// asked (Facebook's), so the row doesn't grow a line.
private struct NameAndMutual: View {
    let person: Neighbor
    var nameFont: Font = .sansSemibold(17)
    @Environment(FriendsBook.self) private var book

    var body: some View {
        VStack(alignment: .leading, spacing: FriendsMetric.lineGap) {
            Text(person.displayName)
                .font(nameFont)
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            // `friend-request-sent`
            if let mutual = book.relation(person) == .sent ? "Request sent" : person.mutualLine {
                Text(mutual)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The one button that follows where you two stand (ticket 03): Add friend; Request sent
/// with Cancel; Confirm and Delete when they asked you; Friends, which opens the friend
/// sheet (ticket 04). Facebook's shape, black for blue (Jesse, 2026-10-13). On a row the
/// buttons fill the row; on a person's page they sit centred.
struct RelationButtons: View {
    let person: Neighbor
    var onPage = false
    let logIn: () -> Void
    @Environment(FriendsBook.self) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let relation = book.relation(person)
        Group {
            switch relation {
            case .stranger:
                face("Add friend", ink: true) { tap(.add) }
            case .sent:
                // `friend-request-sent`: a row says Request sent over Cancel; a page, Cancel request.
                face(onPage ? "Cancel request" : "Cancel", ink: false, spoken: "Cancel request") { tap(.cancel) }
            case .received:
                // `friend-respond`
                HStack(spacing: FriendsMetric.buttonGap) {
                    face("Confirm", ink: true) { tap(.confirm) }
                    face("Delete", ink: false) { tap(.delete) }
                }
            case .friends:
                // `friends-button`
                face("Friends", ink: false, icon: "checkmark") { book.menu = person }
            case .blocked:
                EmptyView()
            }
        }
        .turnBackShake(failures: book.failures[person.id] ?? 0, shakes: !reduceMotion)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: relation)
    }

    /// One button. VoiceOver hears whose it is: "Confirm, Sarah Lindgren".
    private func face(_ title: String, ink: Bool, spoken: String? = nil, icon: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: FriendsMetric.iconGap) {
                if let icon { Image(systemName: icon).font(.glyph(13, weight: .bold)) }
                Text(title)
            }
                .font(.sansSemibold(15))
                .foregroundStyle(ink ? Hue.surface : Hue.ink)
                .lineLimit(1)
                .padding(.horizontal, FriendsMetric.buttonPad)
                .frame(maxWidth: onPage ? nil : .infinity, minHeight: FriendsMetric.button)
                .frame(minWidth: onPage ? FriendsMetric.pageButton : nil)
                .background(ink ? Hue.ink : Hue.fill,
                            in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                // 36pt drawn, 44pt to the finger.
                .contentShape(Rectangle().inset(by: (FriendsMetric.button - SearchMetric.tapMin) / 2))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(spoken ?? title), \(person.displayName)")
    }

    private func tap(_ action: FriendsBook.Action) {
        guard !book.isAnonymous() else { logIn(); return }
        book.act(action, person)
    }
}

/// A neighbour's page: their photo, name, Neighbor since and the friends you share, under
/// the same head as your own Profile (Jesse, 2026-10-13), and the one button. Never their
/// plans.
struct NeighborPage: View {
    let neighbor: Neighbor
    @Environment(FriendsBook.self) private var book
    @Environment(\.dismiss) private var dismiss
    @State private var signingIn = false

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ProfileHead(url: neighbor.avatarUrl, name: neighbor.displayName,
                                line: [neighbor.sinceLine, neighbor.mutualLine].compactMap { $0 }
                                    .joined(separator: "  ·  "))
                    RelationButtons(person: neighbor, onPage: true) { signingIn = true }
                        .padding(.top, FriendsMetric.pageButtonTop)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, FriendsMetric.side)
                .padding(.top, SearchMetric.pageBar + FriendsMetric.headTop)
            }
            FriendsTitleBar(title: neighbor.displayName, titleUnder: false) {
                MoreButton(person: neighbor)
            }
            .accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Blocked: back to where you came from, as on Facebook (ticket 04).
        .onChange(of: book.relation(neighbor) == .blocked) { _, blocked in
            if blocked { dismiss() }
        }
        .onAppear { book.screenOpened() }
        .onDisappear { book.screenClosed() }
        .signInSheet(isPresented: $signingIn)
    }
}

/// A neighbour's round photo, or the person icon your own Profile shows without one.
struct NeighborFace: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Hue.surface)
            .overlay {
                if let url, let photo = URL(string: url) {
                    FeedCardURLPhoto(url: photo, loadingFill: Hue.fill)
                } else {
                    Image(systemName: "person.fill")
                        .font(.glyph(size * 0.42))
                        .foregroundStyle(Hue.inkSecondary.opacity(0.5))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Hue.ink.opacity(0.16), lineWidth: FriendsMetric.ring))
            .accessibilityHidden(true)
    }
}

/// `people-login`: an Anonymous account finds nobody, and this opens Log in.
struct LogInToFindRow: View {
    var font: Font = .sansSemibold(17)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Log in to find neighbors")
                    .font(font)
                    .foregroundStyle(Hue.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.glyph(14, weight: .semibold))
                    .foregroundStyle(Hue.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, FriendsMetric.side)
            .frame(height: SearchMetric.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// Edit profile for a neighbour asked for their name before a request goes
/// (`friend-name-needed`). It opens once their profile has loaded, so saving can't wipe
/// interests it never read.
struct AddNameSheet: View {
    @StateObject private var model = ProfileModel()

    var body: some View {
        Group {
            if model.loaded {
                EditProfileView(model: model)
            } else {
                // The edit form's own shapes while the profile loads: the photo, the name.
                VStack(spacing: FriendsMetric.loadingLine) {
                    SkeletonBlock(cornerRadius: FriendsMetric.requestFace / 2)
                        .frame(width: FriendsMetric.requestFace, height: FriendsMetric.requestFace)
                    SkeletonBlock(cornerRadius: FriendsMetric.loadingLine / 2)
                        .frame(width: FriendsMetric.loadingName, height: FriendsMetric.loadingLine)
                }
                .shimmering()
                .padding(.top, FriendsMetric.requestFace)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Hue.paper.ignoresSafeArea())
                .accessibilityHidden(true)
            }
        }
        .task { await model.load() }
    }
}

extension AuthStore {
    /// Changes when the account does: a new one, or the same one turned real by logging in.
    var accountKey: [String] { [userId ?? "", isAnonymous ? "anonymous" : "real"] }
}
