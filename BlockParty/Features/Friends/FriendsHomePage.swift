//
//  FriendsHomePage.swift
//  Block Party — the Friends page and a neighbour's page (BP app docs/plans/friends, ticket
//  02). The Town bar's friends mark pushes the Friends page: a large title and Search's field,
//  under the sample inbox's own top. Typing finds neighbours by name; a name opens their page.
//  Requests and Your friends join it in ticket 03.
//
//  Reference: Facebook's Friends screens (BP app references/friends): the friends-list row
//  measured at a 60pt photo, 12pt gap, 17pt semibold name, 76pt apart. Mock Jesse said yes
//  to on 2026-10-13: https://claude.ai/artifact/YW9WezLabBwQDBmmUKW8wN
//

import SwiftUI

extension FriendsMetric {
    /// Facebook's friends-list row, measured.
    static let neighborRow: CGFloat = 76
    static let neighborFace: CGFloat = 60
    static let resultsTop: CGFloat = 8
    /// The neighbour's page: its head starts this far under the bar. (guessed)
    static let headTop: CGFloat = 20
    static let noteTop: CGFloat = 18
}

struct FriendsHomePage: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var search = NeighborSearch()
    @State private var words = Self.debugWords
    /// The large title has gone under the bar: the bar shows the small one.
    @State private var titleUnder = false
    @State private var signingIn = false

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
                    results
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
        // Nothing typed, or nobody found: Apple's empty page, in the middle of the screen.
        .overlay {
            switch search.state {
            case .idle:
                ContentUnavailableView("No friends yet", systemImage: "person.2",
                                       description: Text("Search for neighbors you know and add them."))
                    .allowsHitTesting(false)
            case .none:
                ContentUnavailableView("No results found", systemImage: "magnifyingglass")
                    .allowsHitTesting(false)
            default:
                EmptyView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: words, initial: true) { search.search(words) }
        // Logging in from the line below asks again, as the account that now asks.
        .onChange(of: auth.accountKey) { search.search(words) }
        .signInSheet(isPresented: $signingIn)
    }

    @ViewBuilder private var results: some View {
        switch search.state {
        case .found(let people):
            ForEach(people) { person in
                NavigationLink(value: person) { NeighborRow(neighbor: person) }
                    .buttonStyle(RowPressStyle())
            }
        case .needsAccount:
            LogInToFindRow { signingIn = true }
        case .failed:
            // The Town feed's words for a read that failed.
            Text("Check your connection and try again.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.horizontal, FriendsMetric.side)
                .padding(.top, FriendsMetric.noteTop)
        case .idle, .loading, .none:
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

/// A neighbour's page: their photo, name and Neighbor since, under the same head as your own
/// Profile (Jesse, 2026-10-13), never their plans. Add friend joins it in ticket 03.
struct NeighborPage: View {
    let neighbor: Neighbor

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ProfileAvatar(url: neighbor.avatarUrl, size: 104)
                        .accessibilityHidden(true)
                    Text(neighbor.displayName)
                        .font(.display(26))
                        .foregroundStyle(Hue.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 12)
                        .accessibilityAddTraits(.isHeader)
                    if let since = neighbor.sinceLine {
                        Text(since)
                            .font(.sans(13))
                            .foregroundStyle(Hue.inkSecondary)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, FriendsMetric.side)
                .padding(.top, SearchMetric.pageBar + FriendsMetric.headTop)
            }
            FriendsTitleBar(title: neighbor.displayName, titleUnder: false).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A neighbour in a list: their face and name. The Friends page's is Facebook's row; Search
/// passes its own smaller sizes.
struct NeighborRow: View {
    let neighbor: Neighbor
    var face: CGFloat = FriendsMetric.neighborFace
    var nameFont: Font = .sansSemibold(17)
    var height: CGFloat = FriendsMetric.neighborRow

    var body: some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            NeighborFace(url: neighbor.avatarUrl, size: face)
            Text(neighbor.displayName)
                .font(nameFont)
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: height)
        .contentShape(Rectangle())
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

extension AuthStore {
    /// Changes when the account does: a new one, or the same one turned real by logging in.
    var accountKey: [String] { [userId ?? "", isAnonymous ? "anonymous" : "real"] }
}
