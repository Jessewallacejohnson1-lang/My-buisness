//
//  NoPhotoCard.swift
//  Block Party — a Town card with no photo (BP app references/no-photo-cards, Jesse 2026-10-30).
//
//  A card with no photo of its own or its place's used to spend a whole photo-sized frame on the
//  place's logo over its backdrop, or on ink. It is a short white card now, Meetup's and Luma's
//  event rows in the white game card's edge and shadow: the place's logo on the left, the day (or
//  NEW for News) in a light grey pill, the title and its facts beside it. Jesse picked it over a
//  post card, a logo tile, a logo watermark and a yellow pill ("that looks harsh"). The heart and
//  the row under the card stay the Event card's own.
//

import SwiftUI

struct NoPhotoCard: View {
    /// The place's logo; without one, `photo` round, else the first letter of `name`.
    let logo: URL?
    /// A neighbour host's photo.
    var photo: URL? = nil
    let name: String
    /// The day and time, or NEW; nil leaves the pill out.
    let pill: String?
    var pillSpoken: String? = nil
    /// "Now" behind Apple's green, as the photo chip has it (event-card 04).
    var pillDot: Color? = nil
    let title: String
    let facts: String?
    var factsLines = 1
    /// Room kept on the right for a control laid over the card: the Event card's heart.
    var trailingRoom: CGFloat = 0

    /// The round 7 mock's measures.
    enum Metric {
        static let mark: CGFloat = 56
        static let gap: CGFloat = 14
        static let vertical: CGFloat = 14
        static let horizontal: CGFloat = 16
        static let pillHeight: CGFloat = 22
        static let pillPadding: CGFloat = 9
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Metric.gap) {
            mark
            VStack(alignment: .leading, spacing: 0) {
                if let pill, !pill.isEmpty {
                    pillView(pill)
                        .padding(.bottom, 6)
                }
                Text(title)
                    .font(.eventDisplay(19))
                    .lineSpacing(-1)
                    .foregroundStyle(Hue.ink.onLightCanvas)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let facts, !facts.isEmpty {
                    Text(facts)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary.onLightCanvas)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : factsLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Metric.vertical)
        .padding(.leading, Metric.horizontal)
        .padding(.trailing, Metric.horizontal + trailingRoom)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Hue.surface.onLightCanvas))
        // The white game card's hairline and soft shadow, so it stands off the paper.
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 10, y: 6)
    }

    /// Clear, with no disc or tile of its own (Jesse: "dont put logo in its own card").
    @ViewBuilder
    private var mark: some View {
        if let logo {
            LogoDisc(logo: logo, initial: initial, logoSide: Metric.mark, letter: .sansSemibold(22), fits: true, disc: false)
                .frame(width: Metric.mark, height: Metric.mark)
                .accessibilityHidden(true)
        } else {
            Avatar(photo, size: Metric.mark, blank: .initial(name, font: 22))
                .accessibilityHidden(true)
        }
    }

    private var initial: String {
        name.first(where: \.isLetter).map { String($0).uppercased() } ?? ""
    }

    /// Light grey, easy on the eyes (Jesse, turning down BP yellow).
    private func pillView(_ text: String) -> some View {
        HStack(spacing: PhotoChip.dotGap) {
            if let pillDot {
                Circle().fill(pillDot).frame(width: PhotoChip.dotSide, height: PhotoChip.dotSide)
            }
            Text(text)
                .font(.sansBold(12))
                .foregroundStyle(Hue.ink.onLightCanvas.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, Metric.pillPadding)
        .frame(minHeight: Metric.pillHeight)
        .background(Capsule().fill(Hue.fill.onLightCanvas))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pillSpoken ?? text)
    }
}

extension FeedCardItem {
    /// No photo of its own or its place's, and not a game: the short white card. A photo that fails
    /// to load keeps its photo card, as ink, so the feed never jumps (Jesse at Check-in 1).
    var isPhotoless: Bool { game == nil && !image.isPhoto }
}

extension TownNews {
    /// Only its place's logo, or nothing: the short white card.
    var isPhotoless: Bool { picture?.kind != .photo }
}
