//
//  FeedEventCard.swift
//  Block Party — reusable static visual for a normalized feed event.
//

import SwiftUI
import UIKit

struct FeedEventCard: View {
    let item: FeedCardItem
    let comments: [EventComment]
    let onJoin: ((Bool) -> Void)?
    let onLike: ((Bool) -> Void)?
    let onSave: ((Bool) -> Void)?
    let onLoadComments: (() async throws -> [EventComment])?
    let onComment: ((String) async throws -> EventComment)?
    let onShare: (() -> Void)?
    let debugAutoplay: Bool

    /// Horizontal room the overlapping join block needs, so the ToS attribution
    /// caption stays fully legible beside it.
    private static let joinBlockClearance: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var resolvedVenuePhoto: ResolvedVenuePhoto?
    @State private var actionState: FeedCardActionState
    @State private var joinState: FeedCardJoinState
    @State private var commentState: FeedCommentState
    @State private var showsCurrentUserAvatar: Bool
    @State private var commentsPresented = false
    @State private var burstScale: CGFloat = 0
    @State private var burstOpacity: Double = 0
    @State private var burstGeneration = 0
    @State private var autoplayStep = 0
    @State private var autoplayJoinPressed = false
    @GestureState private var cardIsPressed = false

    init(
        item: FeedCardItem,
        comments: [EventComment] = [],
        onJoin: ((Bool) -> Void)? = nil,
        onLike: ((Bool) -> Void)? = nil,
        onSave: ((Bool) -> Void)? = nil,
        onLoadComments: (() async throws -> [EventComment])? = nil,
        onComment: ((String) async throws -> EventComment)? = nil,
        onShare: (() -> Void)? = nil,
        debugAutoplay: Bool = false
    ) {
        self.item = item
        self.comments = comments
        self.onJoin = onJoin
        self.onLike = onLike
        self.onSave = onSave
        self.onLoadComments = onLoadComments
        self.onComment = onComment
        self.onShare = onShare
        self.debugAutoplay = debugAutoplay
        _actionState = State(initialValue: FeedCardActionState(item: item))
        let initialJoinState = FeedCardJoinState(item: item)
        _joinState = State(initialValue: initialJoinState)
        _commentState = State(initialValue: FeedCommentState(comments: comments))
        _showsCurrentUserAvatar = State(
            initialValue: initialJoinState.hasCurrentUserAvatar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection

            socialRow
                .padding(.top, 10)

            actionRow
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .scaleEffect(motionIsReduced ? 1 : (cardIsPressed ? 0.98 : 1))
        .animation(
            motionIsReduced
                ? nil
                : .spring(response: 0.3, dampingFraction: 0.7),
            value: cardIsPressed
        )
        .simultaneousGesture(cardPressGesture)
        .sheet(isPresented: $commentsPresented) {
            FeedCommentSheet(
                commentState: $commentState,
                onLoad: onLoadComments,
                onSend: onComment
            )
        }
        .onChange(of: item) { _, updatedItem in
            actionState.sync(with: updatedItem)
            joinState.sync(with: updatedItem)
            showsCurrentUserAvatar = updatedItem.isJoined
        }
        .task(id: item.image) { await resolveVenuePhoto() }
        .task { await runDebugAutoplay() }
    }

    /// A resolved venue photo, tagged with the lookup that produced it — so a card
    /// whose item changed under it can tell "already resolved" from "someone else's
    /// photo" without ever flashing the wrong venue.
    private struct ResolvedVenuePhoto {
        let lookup: FeedCardImageSource
        let image: FeedCardImageSource
    }

    /// What the card renders right now. A `venueLookup` shows the fallback treatment
    /// until it resolves into a `.placesPhoto`; every other source is already final.
    private var displayImage: FeedCardImageSource {
        guard case .venueLookup = item.image else { return item.image }
        guard let resolved = resolvedVenuePhoto, resolved.lookup == item.image
        else { return .fallback }
        return resolved.image
    }

    /// The one place the feed spends a billed Google call. It runs from `.task`, so a
    /// card that never scrolls into view never costs anything, and `GooglePlacesService`
    /// caches + coalesces, so cards sharing a venue share one round-trip. A venue that
    /// can't be confidently identified simply stays on the fallback — no gray box, no
    /// spinner, no retry loop.
    private func resolveVenuePhoto() async {
        guard case .venueLookup(let name, let hint) = item.image else { return }
        // Same venue as the last appearance — displayImage is already showing it, so
        // don't drop it and re-render the fallback for a frame on the way back in.
        guard resolvedVenuePhoto?.lookup != item.image else { return }

        let lookup = item.image
        let resolved = await FeedCardVenuePhoto.resolve(name: name, hint: hint)
        guard !Task.isCancelled, let resolved else { return }

        withAnimation(motionIsReduced ? nil : .easeOut(duration: 0.25)) {
            resolvedVenuePhoto = ResolvedVenuePhoto(lookup: lookup, image: resolved)
        }
    }

    private var imageSection: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                imageContent
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if displayImage.isPhoto {
                    FeedCardPhotoScrim(imageHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(5.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 84, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .scaleEffect(motionIsReduced ? 1 : burstScale)
                .opacity(burstOpacity)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            chipRow
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            imageCopy
                .padding(16)
                .padding(.trailing, 60)
        }
        .overlay(alignment: .bottomTrailing) {
            if let attribution = displayImage.attribution {
                FeedCardPhotoAttribution(attribution: attribution)
                    .padding(.trailing, Self.joinBlockClearance)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            joinBlock
                .offset(y: 22)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .gesture(TapGesture(count: 2).onEnded(performImageLike))
        // Reserve the lower half of the overlapping join block before the social row.
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var imageContent: some View {
        switch displayImage {
        case .eventPhoto(let url), .placesPhoto(let url, _):
            FeedCardURLPhoto(url: url)
        case .venueLookup, .fallback:
            Rectangle().fill(Hue.ink)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            if !item.dateChip.isEmpty {
                chip(item.dateChip)
            }
            if let recurrence = item.recurrence {
                chip(recurrence)
            }
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.sansSemibold(11))
            .tracking(0.8)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
    }

    @ViewBuilder
    private var imageCopy: some View {
        switch displayImage {
        case .venueLookup, .fallback:
            Text(item.title)
                .font(.display(32))
                .foregroundStyle(.white)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
        case .eventPhoto, .placesPhoto:
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.display(22))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.metaLine)
                    .font(.sans(13))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .feedCardPhotoTypeShadow()
        }
    }

    private var joinBlock: some View {
        FeedEventCardJoinButton(
            isJoined: joinState.isJoined,
            isFallback: displayImage.isFallback,
            reduceMotion: motionIsReduced,
            autoplayPressed: autoplayJoinPressed,
            onToggle: performJoinTap
        )
    }

    private var socialRow: some View {
        HStack(spacing: 8) {
            if showsCurrentUserAvatar || !item.goingAvatars.isEmpty {
                FeedCardFacepile(
                    neighborAvatars: item.goingAvatars,
                    goingCount: joinState.goingCount,
                    includesCurrentUser: showsCurrentUserAvatar,
                    reduceMotion: motionIsReduced
                )
            }

            goingSummaryText
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var goingSummaryText: some View {
        if let summary = numericGoingSummary {
            HStack(spacing: 0) {
                Text(summary.prefix)
                animatedGoingCount(summary.count)
                Text(summary.suffix)
            }
            .accessibilityElement(children: .combine)
        } else if joinState.goingCount == item.goingCount {
            Text(item.goingSummary)
        } else {
            HStack(spacing: 0) {
                animatedGoingCount(joinState.goingCount)
                Text(joinState.goingCount == 1 ? " neighbor is going" : " neighbors are going")
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var numericGoingSummary: (prefix: String, count: Int, suffix: String)? {
        guard let range = item.goingSummary.range(
            of: #"[0-9]+"#,
            options: .regularExpression
        ), let initialCount = Int(item.goingSummary[range]) else {
            return nil
        }

        let delta = joinState.goingCount - item.goingCount
        return (
            String(item.goingSummary[..<range.lowerBound]),
            max(0, initialCount + delta),
            String(item.goingSummary[range.upperBound...])
        )
    }

    private func animatedGoingCount(_ count: Int) -> some View {
        Text("\(count)")
            .monospacedDigit()
            .contentTransition(motionIsReduced ? .opacity : .numericText())
            .animation(
                motionIsReduced
                    ? .easeInOut(duration: 0.15)
                    : .easeOut(duration: 0.35),
                value: count
            )
    }

    private var actionRow: some View {
        FeedEventCardActionRow(
            state: $actionState,
            reduceMotion: motionIsReduced,
            autoplayStep: autoplayStep,
            onLike: onLike,
            onSave: onSave,
            onComment: { commentsPresented = true },
            onShare: onShare
        )
    }

    private var motionIsReduced: Bool {
        accessibilityReduceMotion
    }

    private var cardPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0, maximumDistance: 16)
            .updating($cardIsPressed) { isPressing, state, _ in
                state = isPressing
            }
    }

    private func performJoinTap() {
        let joined = joinState.toggleJoin()

        if motionIsReduced {
            showsCurrentUserAvatar = joined
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                showsCurrentUserAvatar = joined
            }
        }

        if joined {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // Phase 4: onJoin → schedule/cancel 1h reminder
        onJoin?(joined)
    }

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
            withAnimation(
                .linear(duration: motionIsReduced ? 0.15 : 0.2)
            ) {
                burstOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard generation == burstGeneration else { return }
            burstScale = 0
        }
    }

    /// DEBUG-only gallery driver: like → image burst → save → unlike → join → leave.
    private func runDebugAutoplay() async {
        #if DEBUG
        guard debugAutoplay, autoplayStep == 0 else { return }

        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        autoplayStep = 1

        try? await Task.sleep(for: .milliseconds(1_200))
        guard !Task.isCancelled else { return }
        autoplayStep = 2
        performImageLike()

        try? await Task.sleep(for: .milliseconds(1_800))
        guard !Task.isCancelled else { return }
        autoplayStep = 3

        try? await Task.sleep(for: .milliseconds(1_400))
        guard !Task.isCancelled else { return }
        autoplayStep = 4

        try? await Task.sleep(for: .milliseconds(1_500))
        guard !Task.isCancelled else { return }
        autoplayStep = 5
        autoplayJoinPressed = true

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        autoplayJoinPressed = false
        autoplayStep = 6
        performJoinTap()

        try? await Task.sleep(for: .milliseconds(1_500))
        guard !Task.isCancelled else { return }
        autoplayStep = 7
        autoplayJoinPressed = true

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        autoplayJoinPressed = false
        autoplayStep = 8
        performJoinTap()
        #endif
    }
}
