//
//  FeedPostCard.swift
//  Block Party — a neighbour's post in the Town feed (BP app docs/plans/town-feed, ticket 29).
//
//  Facebook's post, picked at post-screen's Check-in 1 (Jesse: "A yes"; mock
//  https://claude.ai/artifact/9M6EyMvnwRZk8d1AGL8vjD, BP app references/post-screen/checkin1.py, card A):
//  their picture, the name line and when, then the words, then the photo edge to edge in its own shape,
//  then the heart and send, with a light grey band before the next card. The ••• is Report for someone
//  else's post and Delete for your own.
//

import SwiftUI

struct FeedPostCard: View {
    let post: TownPost
    /// Off in the share sheet's picture, which draws the post without its controls.
    var sendable = true

    @Environment(RealLifeActions.self) private var actions: RealLifeActions?
    @Environment(TownFeed.self) private var feed: TownFeed?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var menuPresented = false
    @State private var deleting = false
    @State private var expanded = false
    /// `heartFailureCount` at the last tap: a tap mid-shake stills it.
    @State private var heartTappedAt = 0

    /// Card A's measurements (checkin1.py `.fb`): 16 pt sides, a 40 pt picture 10 pt from the name, words
    /// 16 on 22 with 10 above and 12 below, the row 14 pt in, an 8 pt band.
    private enum Metric {
        static let side: CGFloat = 16
        static let picture: CGFloat = 40
        static let pictureGap: CGFloat = 10
        static let wordsTop: CGFloat = 10
        static let wordsBottom: CGFloat = 12
        static let rowSide: CGFloat = 14
        static let band: CGFloat = 8
        /// Facebook's See more: past six lines.
        static let lines = 6
    }

    private var mine: Bool { AuthStore.shared.userId?.lowercased() == post.poster.id.lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Metric.side)
            if !post.words.isEmpty {
                words
                    .padding(.horizontal, Metric.side)
                    .padding(.top, Metric.wordsTop)
                    .padding(.bottom, post.photo == nil ? 0 : Metric.wordsBottom)
            }
            if let url = post.photo {
                photo(url)
                    .padding(.top, post.words.isEmpty ? Metric.wordsTop : 0)
            }
            if sendable, let actions {
                actionRow(actions)
                    .padding(.horizontal, Metric.rowSide)
            }
            Rectangle()
                .fill(Hue.fill)
                .frame(height: Metric.band)
                .padding(.top, sendable ? 0 : Metric.wordsBottom)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Metric.pictureGap) {
            HStack(spacing: Metric.pictureGap) {
                Avatar(post.posterPhoto, size: Metric.picture)
                VStack(alignment: .leading, spacing: 0) {
                    Text(nameLine)
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subLine)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if sendable {
                FeedCardMenuButton { if mine { deleting = true } else { menuPresented = true } }
                    .modifier(FeedCardMenuSheet(isPresented: $menuPresented, post: post))
                    // Your own post: Delete, Apple's sheet asking first (the `isPresented` form 26.5 has).
                    .confirmationDialog("Delete post?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            Haptics.light()
                            Task { await feed?.delete(post) }
                        }
                    } message: {
                        Text("You can't undo this.")
                    }
            }
        }
    }

    /// "**Jesse** is with **Sam Lee** at **Sal's**.": the names and the Place in semibold, as Facebook's.
    private var nameLine: AttributedString {
        var line = AttributedString(post.line)
        line.font = .sans(15)
        let tagged = post.tagged.count > 2 ? [post.tagged[0].name, "\(post.tagged.count - 1) others"] : post.tagged.map(\.name)
        for bold in [post.poster.name] + tagged + [post.place ?? ""] where !bold.isEmpty {
            if let range = line.range(of: bold) { line[range].font = .sansSemibold(15) }
        }
        return line
    }

    /// "2h · St. Joseph", or "· Friends" when only friends see it.
    private var subLine: String {
        PostingCard.relativeLabel(for: post.posted) + " · " + (post.friendsOnly ? "Friends" : Town.everyday)
    }

    // MARK: - Words and photo

    private var words: some View {
        Text(post.words)
            .font(.sans(16))
            .lineSpacing(3)
            .foregroundStyle(Hue.ink)
            .lineLimit(expanded || dynamicTypeSize.isAccessibilitySize ? nil : Metric.lines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? nil : Motion.snappy) { expanded.toggle() }
            }
            .accessibilityAddTraits(.isStaticText)
    }

    /// Edge to edge in its own shape (4:5 to 1.91:1), known before it loads.
    private func photo(_ url: URL) -> some View {
        FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
            .aspectRatio(CGFloat(post.photoAspect), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel(post.words.isEmpty ? "Photo from \(post.poster.name)" : "Photo")
    }

    // MARK: - Heart and send

    private func actionRow(_ actions: RealLifeActions) -> some View {
        FeedEventCardActionRow(
            kind: .event,
            showsHeart: actions.canAct,
            showsSave: false,
            heartFailures: actions.heartFailureCount(post.id),
            state: Binding {
                let heart = actions.heart(post)
                return FeedCardActionState(likeCount: heart.count, isLiked: heart.isHearted, isSaved: false)
            } set: { new in
                if new.isLiked != actions.heart(post).isHearted { actions.toggleHeart(post) }
            },
            reduceMotion: reduceMotion,
            autoplayStep: 0,
            onLike: nil,
            onSave: nil,
            onComment: {},
            onShare: share
        )
    }

    private func share() {
        let name = post.poster.name
        ShareCenter.shared.present(
            SharePayload(title: name,
                         shareText: post.words.isEmpty ? "\(name) posted on Block Party." : "\(name): \(post.words)",
                         includesImage: false) {
                FeedPostCard(post: post, sendable: false)
                    .frame(width: 320)
                    .padding(.vertical, 16)
                    .background(Hue.surface)
            }
        )
    }
}
