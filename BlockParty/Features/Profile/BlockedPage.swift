//
//  BlockedPage.swift
//  Block Party — Profile's Blocked list (BP app docs/plans/friends, ticket 04): the people you
//  blocked, newest first, each with Unblock. Unblocking takes them off the list at once and
//  gives back only being findable: no friendship, no request. Pushed from Profile's Blocked
//  row inside the sheet, under Saved's top (a back chevron, the title in the middle).
//
//  Reference: Instagram's Blocked accounts (BP app references/unfriend-block/ig-blocked-1.jpg),
//  with the Friends page's 60pt row and its grey 36pt button. Mock Jesse said yes to on
//  2026-10-13: https://claude.ai/artifact/RUmoV1bdCGHEnFhh97kykH
//

import SwiftUI

struct BlockedPage: View {
    @Environment(FriendsBook.self) private var book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Saved's sheet edge to its top bar (`SavedPage`).
    private static let barTop: CGFloat = 20

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !book.blockedLoaded {
                    if book.blockedFailed {
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
                } else {
                    ForEach(book.blocked) { row($0) }
                }
            }
            .padding(.top, FriendsMetric.resultsTop)
        }
        // A read that failed is tried again by pulling down.
        .refreshable { await book.refreshBlocked() }
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        // `blocked-empty`: Apple's empty page, in the middle, once a read has said so.
        .overlay {
            if book.blockedLoaded, book.blocked.isEmpty {
                ContentUnavailableView("You haven't blocked anyone", systemImage: "hand.raised")
                    .allowsHitTesting(false)
            }
        }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await book.refreshBlocked() }
        .onAppear { book.screenOpened() }
        .onDisappear { book.screenClosed() }
    }

    private var bar: some View {
        ZStack {
            // `blocked-row`
            Text("Blocked")
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

    /// Instagram's row: the face, the name, Unblock at the right. A failed Unblock comes back
    /// and shakes.
    private func row(_ person: Neighbor) -> some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            Avatar(avatarUrl: person.avatarUrl, size: FriendsMetric.neighborFace, outlined: true)
            Text(person.displayName)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { book.act(.unblock, person) } label: {
                // `blocked-unblock`
                Text("Unblock")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, FriendsMetric.buttonPad)
                    .frame(minHeight: FriendsMetric.button)
                    .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    // 36pt drawn, 44pt to the finger.
                    .contentShape(Rectangle().inset(by: (FriendsMetric.button - SearchMetric.tapMin) / 2))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Unblock, \(person.displayName)")
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
        .turnBackShake(failures: book.failures[person.id] ?? 0, shakes: !reduceMotion)
        // Fades where it is while the rows below close up, as a friend's row does on Unfriend.
        .transition(.opacity)
    }
}
