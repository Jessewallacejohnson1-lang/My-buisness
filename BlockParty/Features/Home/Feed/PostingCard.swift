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
    var onLoadComments: (() async throws -> [EventComment])?
    var onComment: ((String) async throws -> EventComment)?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var actionState: FeedCardActionState
    @State private var commentState: FeedCommentState
    @State private var commentsPresented = false
    @State private var captionExpanded = false
    @State private var burstScale: CGFloat = 0
    @State private var burstOpacity: Double = 0
    @State private var burstGeneration = 0

    init(
        posting: PostingItem,
        comments: [EventComment] = [],
        onLike: ((Bool) -> Void)? = nil,
        onSave: ((Bool) -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onLoadComments: (() async throws -> [EventComment])? = nil,
        onComment: ((String) async throws -> EventComment)? = nil
    ) {
        self.posting = posting
        self.onLike = onLike
        self.onSave = onSave
        self.onShare = onShare
        self.onLoadComments = onLoadComments
        self.onComment = onComment
        _actionState = State(initialValue: FeedCardActionState(posting: posting))
        _commentState = State(initialValue: FeedCommentState(comments: comments))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            imageSection
                .padding(.top, 10)

            FeedEventCardActionRow(
                kind: .posting,
                state: $actionState,
                reduceMotion: motionIsReduced,
                autoplayStep: 0,
                onLike: onLike,
                onSave: onSave,
                onComment: { commentsPresented = true },
                onShare: onShare
            )
            .padding(.top, 2)

            caption

            if posting.commentCount > 0 {
                commentsLink
                    .padding(.top, 4)
            }
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

    private var header: some View {
        HStack(spacing: 10) {
            avatar

            Text(posting.authorName)
                .font(.sansSemibold(14))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(Self.relativeLabel(for: posting.createdAt))
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var avatar: some View {
        // A square-framed mark on an inert fill, never an emoji and never a coloured
        // illustration — the brand's photo-less rule.
        if let url = posting.authorAvatar {
            FeedCardURLPhoto(url: url)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            BlockPartyGlyph(side: 32)
                .frame(width: 32, height: 32)
        }
    }

    // MARK: - Image

    private var imageSection: some View {
        imageContent
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 84, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .scaleEffect(motionIsReduced ? 1 : burstScale)
                    .opacity(burstOpacity)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .simultaneousGesture(TapGesture(count: 2).onEnded(performImageLike))
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
                .lineLimit(captionExpanded ? nil : 2)
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

    private var commentsLink: some View {
        Button { commentsPresented = true } label: {
            Text(posting.commentCount == 1 ? "View 1 note" : "View all \(posting.commentCount) notes")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behaviour

    private var motionIsReduced: Bool { accessibilityReduceMotion }

    /// Double-tap the photo to give a thumbs-up. Idempotent — a second double-tap
    /// re-plays the burst without taking the thumb back, because an accidental
    /// un-like is a worse outcome than an accidental repeat.
    private func performImageLike() {
        burstGeneration += 1
        let generation = burstGeneration
        let changed = !actionState.isLiked

        if motionIsReduced {
            burstScale = 1
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = actionState.like()
                burstOpacity = 1
            }
        } else {
            burstScale = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                _ = actionState.like()
                burstScale = 1.15
                burstOpacity = 1
            }
        }

        if changed { onLike?(true) }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard generation == burstGeneration else { return }

            if !motionIsReduced {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                    burstScale = 1
                }
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard generation == burstGeneration else { return }
            withAnimation(.linear(duration: motionIsReduced ? 0.15 : 0.2)) {
                burstOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard generation == burstGeneration else { return }
            burstScale = 0
        }
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
