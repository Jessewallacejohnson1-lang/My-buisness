//
//  FollowingPage.swift
//  Block Party — Profile's Following list and an Event page's host line (BP app docs/plans/follows,
//  ticket 02).
//
//  Following: everyone and everything you follow, A to Z, each with its Following button, as
//  Instagram's list (60 pt pictures, 76 pt rows, its 104 x 32 pt button). One tap unfollows; the
//  row stays, as Follow, until you leave, so a slip is one tap to undo (Jesse's pick at Check-in
//  1). Pushed from the Profile sheet's Following row, under Blocked's top. Groups aren't listed:
//  the You tab's Groups row holds them.
//
//  The host line: Eventbrite's "Organized by", under where an Event is: the Place or person who
//  hosts it, "Host · 128 followers", and Follow.
//

import SwiftUI

struct FollowingPage: View {
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [FollowRow]?
    @State private var failed = false

    /// Saved's sheet edge to its top bar (`SavedPage`, as `BlockedPage`).
    private static let barTop: CGFloat = 20

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let rows {
                    ForEach(rows) { row($0) }
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
            } + [FollowRow(targetType: .place, targetId: "sample-krewe", name: "Krewe", kind: "cajun_restaurant",
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

    private func row(_ row: FollowRow) -> some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            FollowPicture(row: row, size: FriendsMetric.neighborFace)
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
            FollowButton(target: row.target, name: row.name, size: .row, minWidth: FollowMetric.listWidth)
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
    }
}

/// A Place's or person's round picture: a person's photo (their initial without one), a Place's
/// photo, or its logo inset on white, as the mock draws a Place with no photo.
struct FollowPicture: View {
    let row: FollowRow
    let size: CGFloat

    var body: some View {
        let url = row.picture.flatMap(URL.init)
        if row.pictureKind == "logo", let url {
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
        row.targetType == .profile ? "Neighbor" : row.kind.flatMap(SearchModel.label)
    }
}

/// An Event page's host line, under where it is. Reads who hosts it when the page opens; draws
/// nothing until then, or for an Event with no host to follow.
struct EventHostRow: View {
    let item: FeedCardItem
    /// Paper above it once it shows; none while it doesn't.
    var top: CGFloat = 0
    /// The place's name is on the photo above: a Place hosting doesn't say it again here.
    var placeNamed = false
    @Environment(RealLifeActions.self) private var actions
    @State private var host: FollowRow?

    static let picture: CGFloat = 44
    static let smallPicture: CGFloat = 32
    static let gap: CGFloat = 12

    var body: some View {
        // Always something on screen, even before the read, so the read starts.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
            if let host {
                HStack(spacing: Self.gap) {
                    // Smaller under a named photo: the name has already been said (Jesse's pick).
                    FollowPicture(row: host, size: placeNamed && host.targetType == .place ? Self.smallPicture : Self.picture)
                    VStack(alignment: .leading, spacing: 2) {
                        if !(placeNamed && host.targetType == .place) {
                            Text(host.name)
                                .font(.sansSemibold(15))
                                .foregroundStyle(Hue.ink)
                                .lineLimit(1)
                        }
                        // `host-line`: "Host · 128 followers"; a person shows no count.
                        Text(["Host", FollowWords.count(actions.follow(host.target).count)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.sans(13))
                            .foregroundStyle(Hue.inkSecondary)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    // A friend you follow reads Following; one you unfollowed can follow again here.
                    FollowButton(target: host.target, name: host.name, size: .row)
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

    /// `event_host`; under DEBUG `-town-samples` its Place, by the card's own words.
    private static func read(_ item: FeedCardItem) async throws -> FollowRow? {
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
