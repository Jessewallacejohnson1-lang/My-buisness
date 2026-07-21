//
//  FeedEventCard.swift
//  Block Party — reusable static visual for a normalized feed event.
//

import SwiftUI
import UIKit

struct FeedEventCard: View {
    let item: FeedCardItem
    let comments: [EventComment]
    let onLike: ((Bool) -> Void)?
    let onSave: ((Bool) -> Void)?
    let onComment: (() -> Void)?
    let onShare: (() -> Void)?
    let debugAutoplay: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var actionState: FeedCardActionState
    @State private var commentState: FeedCommentState
    @State private var commentsPresented = false
    @State private var burstScale: CGFloat = 0
    @State private var burstOpacity: Double = 0
    @State private var burstGeneration = 0
    @State private var autoplayStep = 0

    init(
        item: FeedCardItem,
        comments: [EventComment] = [],
        onLike: ((Bool) -> Void)? = nil,
        onSave: ((Bool) -> Void)? = nil,
        onComment: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        debugAutoplay: Bool = false
    ) {
        self.item = item
        self.comments = comments
        self.onLike = onLike
        self.onSave = onSave
        self.onComment = onComment
        self.onShare = onShare
        self.debugAutoplay = debugAutoplay
        _actionState = State(initialValue: FeedCardActionState(item: item))
        _commentState = State(initialValue: FeedCommentState(comments: comments))
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
        .sheet(isPresented: $commentsPresented) {
            FeedCommentSheet(commentState: $commentState, onSend: onComment)
        }
        .task { await runDebugAutoplay() }
    }

    private var imageSection: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                imageContent
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if item.image.isPhoto {
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.4)
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
            if let attribution = item.image.attribution {
                Text(attribution)
                    .font(.sans(10))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    // Keep the required caption legible beside the overlapping join block.
                    .padding(.trailing, 52)
                    .padding(.bottom, 8)
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
        switch item.image {
        case .eventPhoto(let url), .placesPhoto(let url, _):
            FeedCardURLPhoto(url: url)
        case .fallback:
            Rectangle().fill(Hue.ink)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(item.dateChip)
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
        switch item.image {
        case .fallback:
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
        }
    }

    private var joinBlock: some View {
        Image(systemName: "plus")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                Hue.ink,
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var socialRow: some View {
        HStack(spacing: 8) {
            if !facepileSlots.isEmpty {
                FeedCardFacepile(slots: facepileSlots)
            }

            Text(item.goingSummary)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(minHeight: 24)
    }

    private var facepileSlots: [URL?] {
        guard !item.goingAvatars.isEmpty else { return [] }
        let count = min(3, max(item.goingAvatars.count, item.goingCount))
        return (0..<count).map { index in
            index < item.goingAvatars.count ? item.goingAvatars[index] : nil
        }
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
        #if DEBUG
        accessibilityReduceMotion && !debugAutoplay
        #else
        accessibilityReduceMotion
        #endif
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
            withAnimation(.linear(duration: 0.2)) { burstOpacity = 0 }

            try? await Task.sleep(for: .milliseconds(200))
            guard generation == burstGeneration else { return }
            burstScale = 0
        }
    }

    /// DEBUG-only gallery driver: like → image burst → save → unlike.
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
        #endif
    }
}

private struct FeedCardFacepile: View {
    let slots: [URL?]
    private let placeholderInitials = ["A", "M", "S"]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, url in
                avatar(url: url, index: index)
                    .zIndex(Double(index))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func avatar(url: URL?, index: Int) -> some View {
        ZStack {
            Circle().fill(Hue.fill)

            if let url {
                FeedCardURLPhoto(url: url)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } else {
                Text(placeholderInitials[index % placeholderInitials.count])
                    .font(.sansSemibold(10))
                    .foregroundStyle(Hue.ink)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Hue.paper, lineWidth: 1.5))
    }
}

private struct FeedCardURLPhoto: View {
    let url: URL

    var body: some View {
        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            configured(Image(uiImage: image))
        } else {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    configured(image)
                } else {
                    Rectangle().fill(Hue.fill)
                }
            }
        }
    }

    private func configured(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
    }
}

private extension FeedCardImageSource {
    var isPhoto: Bool {
        switch self {
        case .eventPhoto, .placesPhoto: true
        case .fallback: false
        }
    }

    var attribution: String? {
        if case .placesPhoto(_, let attribution) = self { attribution } else { nil }
    }
}
