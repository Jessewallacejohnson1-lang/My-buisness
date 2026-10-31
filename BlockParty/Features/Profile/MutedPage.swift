//
//  MutedPage.swift
//  Block Party — Profile's Muted list (BP app docs/plans/town-feed, ticket 21): the hosts you
//  muted from a Town card's •••, newest first, each with Unmute. Unmuting takes the host off
//  the list at once and brings its Events back to the Town feed. Blocked's page, row for row
//  (`BlockedPage`), with the host's mark for a face.
//
//  Mock Jesse said yes to on 2026-10-22: https://claude.ai/artifact/HAJWN4Zj2Xh4wAeJA5UNcg
//

import SwiftUI

struct MutedPage: View {
    @Environment(TownFeed.self) private var feed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let muted = feed.muted {
                    ForEach(muted) { row($0) }
                } else if feed.mutedFailed {
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
            .animation(Motion.smooth, value: feed.muted)
        }
        // A read that failed is tried again by pulling down.
        .refreshable { await feed.refreshMuted() }
        // `muted-row`
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Muted") { dismiss() } }
        .overlay {
            if feed.muted?.isEmpty == true {
                ContentUnavailableView("You haven't muted anyone", systemImage: "speaker.slash")
                    .allowsHitTesting(false)
            }
        }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await feed.refreshMuted() }
    }

    /// Blocked's row: the host's mark, its name, Unmute at the right. A failed Unmute comes back
    /// and shakes.
    private func row(_ host: MutedHost) -> some View {
        ListRow(leading: { Avatar(nil, size: FriendsMetric.neighborFace, blank: .initial(host.name, font: 20)) },
                title: host.name) {
            // `muted-undo`
            RowButton("Unmute") { Task { await feed.unmute(host) } }
                .accessibilityLabel("Unmute, \(host.name)")
        }
        .turnBackShake(failures: feed.unmuteFailures[host.host] ?? 0, shakes: !reduceMotion)
        .transition(.opacity)
    }
}
