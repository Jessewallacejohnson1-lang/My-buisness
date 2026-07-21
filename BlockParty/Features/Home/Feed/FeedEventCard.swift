//
//  FeedEventCard.swift
//  Block Party — reusable static visual for a normalized feed event.
//

import SwiftUI
import UIKit

struct FeedEventCard: View {
    let item: FeedCardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection

            socialRow
                .padding(.top, 10)

            actionRow
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                HStack(spacing: 5) {
                    actionIcon(item.isLiked ? "heart.fill" : "heart", active: item.isLiked)

                    if item.likeCount > 0 {
                        Text("\(item.likeCount)")
                            .font(.mono(13))
                            .monospacedDigit()
                            .foregroundStyle(Hue.ink.opacity(0.45))
                    }
                }

                actionIcon("bubble.right")
                actionIcon("square.and.arrow.up")
            }

            Spacer()

            actionIcon(item.isSaved ? "bookmark.fill" : "bookmark", active: item.isSaved)
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    private func actionIcon(_ name: String, active: Bool = false) -> some View {
        // SF Symbols does not expose a 1.75pt stroke; regular approximates the spec.
        Image(systemName: name)
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Hue.ink.opacity(active ? 1 : 0.45))
            .frame(width: 22, height: 44)
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
