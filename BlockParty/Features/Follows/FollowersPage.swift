//
//  FollowersPage.swift
//  Block Party — the people following you, from your Profile's followers count (BP app backlog 34,
//  references/followers-count).
//
//  The Your friends page's bar over Search's result rows: a face, the name and mutual friends, and
//  Add friend or Friends under it. A face or name opens their Profile. Newest first. Only your own:
//  a neighbour's followers count opens nothing (Jesse, 2026-11-17).
//

import SwiftUI

struct FollowersPage: View {
    @State private var rows: [Neighbor]?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let rows {
                        ForEach(rows) { ResultRow(person: $0) }
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
                .padding(.top, PageMetric.bar + FriendsMetric.resultsTop)
            }
            .refreshable { await load() }
            // Apple's empty page, once a read has said so: the one who followed may have left since.
            .overlay {
                if rows?.isEmpty == true {
                    ContentUnavailableView("No followers yet", systemImage: "person.2")
                        .allowsHitTesting(false)
                }
            }
            FriendsTitleBar(title: "Followers", titleUnder: true).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        do {
            rows = try await Self.read()
            failed = false
        } catch {
            failed = rows == nil
        }
    }

    /// `my_followers`; under DEBUG `-town-samples` the sample neighbours, and `-town-offline` a failed read.
    private static func read() async throws -> [Neighbor] {
        switch LaunchFlags.backend {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).myFollowers()
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples: return Array(Neighbor.samples.prefix(3))
        }
    }
}
