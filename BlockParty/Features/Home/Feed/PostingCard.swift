//
//  PostingCard.swift
//  Block Party — a neighbour's post in the Daily feed.
//
//  Instagram proportions on purpose: a 4:5 portrait frame is what a phone camera
//  hands you and what everyone's thumb already knows how to read. The chrome around
//  it stays ink on paper, so the photo is the only colour on the card.
//
//  Shares the event card's image loader, action state and comment sheet — the two
//  cards differ in shape and in which verbs they offer, not in machinery.
//

import SwiftUI

struct PostingCard: View {
    let posting: PostingItem
    var onLike: ((Bool) -> Void)?
    var onSave: ((Bool) -> Void)?
    var onShare: (() -> Void)?
    var onFollow: ((Bool) -> Void)?
    var onLoadComments: (() async throws -> [EventComment])?
    var onComment: ((String) async throws -> EventComment)?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var actionState: FeedCardActionState
    /// Local so the button leaves the moment it is tapped. The feed's copy of the
    /// posting catches up on the next refresh; waiting for it would leave a button
    /// sitting there that you have already used.
    @State private var isFollowing: Bool
    @State private var commentState: FeedCommentState
    @State private var commentsPresented = false
    @State private var captionExpanded = false
    @State private var likeBurst = FeedLikeBurst()

    init(
        posting: PostingItem,
        comments: [EventComment] = [],
        onLike: ((Bool) -> Void)? = nil,
        onSave: ((Bool) -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onFollow: ((Bool) -> Void)? = nil,
        onLoadComments: (() async throws -> [EventComment])? = nil,
        onComment: ((String) async throws -> EventComment)? = nil
    ) {
        self.posting = posting
        self.onLike = onLike
        self.onSave = onSave
        self.onShare = onShare
        self.onFollow = onFollow
        self.onLoadComments = onLoadComments
        self.onComment = onComment
        _actionState = State(initialValue: FeedCardActionState(posting: posting))
        _isFollowing = State(initialValue: posting.signals.isFollowed)
        _commentState = State(initialValue: FeedCommentState(comments: comments))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The photo is the one thing that runs to both screen edges, and the
            // author rides ON it rather than above it (Jesse, 2026-09-20 — the
            // Reels header). Everything below keeps `contentInset` so the copy is
            // not reading off the bezel.
            imageSection

            FeedEventCardActionRow(
                kind: .posting,
                commentCount: posting.commentCount,
                state: $actionState,
                reduceMotion: motionIsReduced,
                autoplayStep: 0,
                onLike: onLike,
                onSave: onSave,
                onComment: { commentsPresented = true },
                onShare: onShare
            )
            .padding(.top, 2)
            .padding(.horizontal, DailyFeedMetric.contentInset)

            caption
                .padding(.horizontal, DailyFeedMetric.contentInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .sheet(isPresented: $commentsPresented) {
            FeedCommentSheet(
                commentState: $commentState,
                onLoad: onLoadComments,
                onSend: onComment
            )
        }
        .onChange(of: posting) { _, updated in actionState.sync(with: updated) }
    }

    // MARK: - Header

    /// Instagram's header, measured off a capture (Jesse, 2026-09-20): a 32pt round
    /// avatar, 8pt of air, the name at 13pt semibold with the age trailing it in the
    /// same line, and the follow control at the far edge.
    private enum Metric {
        static let avatarSide: CGFloat = 32
        static let avatarGap: CGFloat = 8
        static let followHeight: CGFloat = 30
        static let followInset: CGFloat = 12
        static let followRadius: CGFloat = 8
        /// The header's inset from the photo's own edges. Tighter than the card's
        /// `contentInset`, the way a floating header always is — it is sitting on
        /// the picture, not in the column.
        static let overlayInset: CGFloat = 12
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: Metric.avatarGap) {
                avatar

                Text(posting.authorName)
                    .font(.sansSemibold(13))
                    .foregroundStyle(.white)
                    // One line is the Instagram header; at accessibility sizes a
                    // name that long has nowhere to go but a second line, and a
                    // clipped name is worse than a taller header.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                // The age rides with the name rather than holding the trailing edge —
                // that edge is the follow button's now. At accessibility sizes there
                // is no room for both on one line, and the name is the one that has
                // to survive, so the age drops out rather than clipping the header
                // (caught by the Dynamic Type audit at AX3).
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("· " + Self.relativeLabel(for: posting.createdAt))
                        .font(.sans(13))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if !isFollowing {
                followButton
            }
        }
        // The scrim does most of the work; this catches a bright patch landing
        // under a letterform, same as the event card's title.
        .feedCardPhotoTypeShadow()
    }

    private var avatar: some View {
        FeedAuthorAvatar(
            url: posting.authorAvatar,
            name: posting.authorName,
            side: Metric.avatarSide
        )
    }

    /// Only here while you are not following. Following is the end of this button's
    /// job — an "Following" state would just be a second thing to tap by accident,
    /// and unfollowing belongs on the profile, not in the middle of a feed.
    private var followButton: some View {
        Button {
            withAnimation(motionIsReduced ? nil : Motion.snappy) { isFollowing = true }
            onFollow?(true)
        } label: {
            Text("Follow")
                .font(.sansSemibold(13))
                .foregroundStyle(.white)
                .padding(.horizontal, Metric.followInset)
                .frame(height: Metric.followHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Metric.followRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follow \(posting.authorName)")
    }

    // MARK: - Image

    /// Instagram's feed frame, edge to edge: a 4:5 portrait at the full screen width
    /// (Jesse, 2026-09-20). A posting is somebody's camera roll and is the BIG card —
    /// an event is the small, inset, cut one.
    private var imageSection: some View {
        imageContent
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    FeedCardPhotoScrim(imageHeight: proxy.size.height, edge: .top)
                        .frame(width: proxy.size.width)
                        .allowsHitTesting(false)
                }
            }
            // INSIDE the clip: the heart's exit is this edge cutting it off, and
            // being under the header overlay means it slides beneath the avatar row
            // on its way out rather than colliding with the Follow button.
            .feedCardLikeBurst(likeBurst, reduceMotion: motionIsReduced)
            .clipShape(RoundedRectangle(cornerRadius: DailyFeedMetric.mediaRadius, style: .continuous))
            .overlay(alignment: .top) {
                header
                    .padding(.horizontal, Metric.overlayInset)
                    .padding(.top, Metric.overlayInset)
            }
            .contentShape(Rectangle())
            // Spatial, not a plain `TapGesture`: the heart has to land under the
            // finger, which means knowing where the finger was.
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { performImageLike(at: $0.location) }
            )
    }

    @ViewBuilder
    private var imageContent: some View {
        GeometryReader { proxy in
            Group {
                switch posting.image {
                case .eventPhoto(let url), .placesPhoto(let url, _):
                    FeedCardURLPhoto(url: url)
                case .venueLookup, .fallback:
                    // Ink, matching the event card's undownloaded state — a pale box
                    // would read as a broken image rather than as the card's own
                    // fallback treatment.
                    Rectangle().fill(Hue.ink)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    // MARK: - Copy

    @ViewBuilder
    private var caption: some View {
        if !posting.caption.isEmpty {
            Text(posting.caption)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(captionExpanded || dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(motionIsReduced ? nil : Motion.snappy) {
                        captionExpanded.toggle()
                    }
                }
                .accessibilityHint(captionExpanded ? "Collapse caption" : "Expand caption")
        }
    }

    // MARK: - Behaviour

    private var motionIsReduced: Bool { accessibilityReduceMotion }

    /// Double-tap the photo to like it. Idempotent — a second double-tap re-plays
    /// the burst without taking the heart back, because an accidental un-like is a
    /// worse outcome than an accidental repeat.
    private func performImageLike(at point: CGPoint?) {
        let changed = !actionState.isLiked

        withAnimation(motionIsReduced ? .easeInOut(duration: 0.15) : Motion.snappy) {
            _ = actionState.like()
        }
        likeBurst.fire(at: point)

        if changed { onLike?(true) }
    }

    /// "now" / "4h" / "3d" / "2w". Deliberately not `RelativeDateTimeFormatter`,
    /// which says "4 hours ago" and wraps the header at Dynamic Type sizes.
    static func relativeLabel(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        return "\(days / 7)w"
    }
}

extension FeedCardActionState {
    init(posting: PostingItem) {
        self.init(
            likeCount: posting.likeCount,
            isLiked: posting.isLiked,
            isSaved: posting.isSaved
        )
    }

    mutating func sync(with posting: PostingItem) {
        self = FeedCardActionState(posting: posting)
    }
}
