//
//  NoPhotoCard.swift
//  Block Party — a Town card with no photo (BP app references/no-photo-cards, Jesse 2026-10-30).
//
//  A card with no photo of the Event used to spend a whole photo-sized frame on the place's logo
//  over its backdrop, on ink, or on the place's cover (town-feed 40). It is a short white card now, Meetup's and Luma's
//  event rows in the white game card's edge and shadow: the place's logo on the left, the title,
//  when (or "News · 2d" for News) and its facts beside it. Jesse picked it over a post card, a logo
//  tile, a logo watermark and a yellow pill ("that looks harsh"). When was in a light grey pill over
//  the title until it moved under it in plain words, as on every Town card (Jesse, 2026-11-07, BP app
//  inside-cards 26). The heart and the row under the card stay the Event card's own.
//

import SwiftUI

struct NoPhotoCard: View {
    /// The place's logo; without one, `photo` round, else the first letter of `name`.
    let logo: URL?
    /// A neighbour host's photo.
    var photo: URL? = nil
    let name: String
    /// The day and time under the title, or "News · 2d"; nil leaves the line out.
    let when: String?
    var whenSpoken: String? = nil
    /// On right now: "Now" behind Apple's green dot in its place (event-card 04).
    var now = false
    /// A long Event's part on now: "Now · Artist talk" (happening-now 04).
    var part: String? = nil
    let title: String
    var titleLines = 2
    var facts: String? = nil
    var factsLines = 1
    /// An Event's small line, in place of `facts`.
    var factsTries: [String] = []
    /// Room kept on the right for a control laid over the card: the Event card's heart.
    var trailingRoom: CGFloat = 0
    /// Off when the Event card lays the mark over the card as its own button (the host's page),
    /// leaving its room here.
    var drawsMark = true

    /// The round 7 mock's measures.
    enum Metric {
        static let mark: CGFloat = 56
        static let gap: CGFloat = 14
        static let vertical: CGFloat = 14
        static let horizontal: CGFloat = 16
        /// Between the title, when and the small line (the inside-cards 25 page's 3 pt).
        static let lineGap: CGFloat = 3
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Metric.gap) {
            if drawsMark {
                NoPhotoCardMark(logo: logo, photo: photo, name: name)
            } else {
                Color.clear.frame(width: Metric.mark, height: Metric.mark)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.eventDisplay(19))
                    .lineSpacing(-1)
                    .foregroundStyle(Hue.ink.onLightCanvas)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : titleLines)
                    .fixedSize(horizontal: false, vertical: true)
                // In the small line's grey, read after the title as on a photo card.
                if now || !(when ?? "").isEmpty {
                    CardTime(text: when ?? "", spoken: whenSpoken, now: now, part: part, color: Hue.inkSecondary.onLightCanvas, lines: 2)
                        .padding(.top, Metric.lineGap)
                }
                if !factsTries.isEmpty {
                    SmallLine(tries: factsTries, wraps: true)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary.onLightCanvas)
                        .padding(.top, Metric.lineGap)
                } else if let facts, !facts.isEmpty {
                    Text(facts)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary.onLightCanvas)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : factsLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Metric.lineGap)
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
}

/// The white card's mark: the place's logo, clear, with no disc or tile of its own (Jesse: "dont put
/// logo in its own card"), else a neighbour's photo, else the first letter on the light fill. Read as
/// whose it is.
struct NoPhotoCardMark: View {
    let logo: URL?
    var photo: URL? = nil
    let name: String

    var body: some View {
        Group {
            if let logo {
                LogoDisc(logo: logo, initial: initial, logoSide: NoPhotoCard.Metric.mark, letter: .sansSemibold(22),
                         fits: true, disc: false, blank: Hue.fill)
            } else {
                Avatar(photo, size: NoPhotoCard.Metric.mark, blank: .initial(name, font: 22))
            }
        }
        .frame(width: NoPhotoCard.Metric.mark, height: NoPhotoCard.Metric.mark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    private var initial: String {
        name.first(where: \.isLetter).map { String($0).uppercased() } ?? ""
    }
}

extension FeedCardItem {
    /// No photo of the Event, and not a game: the short white card. Its place's cover doesn't count
    /// (Jesse, 2026-11-04: "only photos of the event", BP app town-feed 40). A photo that fails to load
    /// keeps its photo card, as ink, so the feed never jumps (Jesse at Check-in 1).
    var isPhotoless: Bool { game == nil && (!image.isPhoto || coverOnly) }
}
