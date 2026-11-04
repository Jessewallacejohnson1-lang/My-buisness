//
//  AfterTheBest.swift
//  Block Party — what the Town feed shows once its ranked list runs out (BP app docs/plans/town-feed,
//  ticket 23; Jesse, 2026-10-08 in ticket 10, and at Check-in 1 on 2026-11-01): Instagram's "You're
//  all caught up" with no checkmark, then later Events, then places to try, then rounds of places
//  again with recent Events and News mixed back in. What comes and in what order is the database's
//  (`get_town_more`); this draws the line and a place's card, and remembers which places were opened.
//

import SwiftUI

/// Where the ranked list ends: the words between two hairlines, quiet, and nothing stops the scroll.
struct CaughtUpLine: View {
    var body: some View {
        HStack(spacing: 12) {
            hairline
            Text("You're all caught up")
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.inkSecondary.onLightCanvas)
                .fixedSize()
            hairline
        }
        .padding(.horizontal, DailyFeedMetric.contentInset)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var hairline: some View {
        Rectangle().fill(Hue.hairline.onLightCanvas).frame(height: 1).frame(maxWidth: .infinity)
    }
}

/// A place to try: its cover photo in the Town card's frame with its name and kind over it and its
/// logo at the top right, or with no photo the short white card with its logo on the left. Nothing
/// under it (Jesse at Check-in 1). A tap opens its business page as Search does, flying from the
/// logo on the white card and fading in over the photo.
struct PlaceCard: View {
    let place: SearchItem

    @Environment(\.hostOpener) private var opener
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pressed = false
    @State private var frame = FrameBox()
    /// The photo once its bitmap is on screen: its credit waits for it.
    @State private var shown: Set<URL> = []
    @State private var failed = false

    private var cover: FeedCardImageSource? {
        place.photos.first { $0.kind == .photo }.map(FeedCardImageSource.init)
    }

    var body: some View {
        Button(action: open) {
            face
                .scaleEffect(FeedMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
                .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
                .animation(Press.animation(down: pressed, reduceMotion: reduceMotion), value: pressed)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardLinkStyle())
        .gesture(FeedTouchDownTracker(isPressed: $pressed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([place.name, place.sub].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens its page")
    }

    @ViewBuilder
    private var face: some View {
        if let cover {
            picture(cover)
        } else {
            NoPhotoCard(logo: place.logo?.url, name: place.name, pill: nil, title: place.name, facts: place.sub,
                        drawsMark: false)
                .overlay(alignment: .leading) {
                    NoPhotoCardMark(logo: place.logo?.url, name: place.name)
                        .trackFrame(frame)
                        .padding(.leading, NoPhotoCard.Metric.horizontal)
                }
                .padding(.horizontal, DailyFeedMetric.contentInset)
        }
    }

    /// The Town news card's picture (`TownNewsCard.picture`) with no chip: the photo's own shape, its
    /// credit, the logo, the words off the bottom left.
    private func picture(_ source: FeedCardImageSource) -> some View {
        let image = failed ? FeedCardImageSource.fallback : source
        let credit = image.url.flatMap { PhotoPager.isShown($0, in: shown) ? image.attribution : nil }
        return GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Group {
                    if let url = image.url {
                        PhotoPager(urls: [url], page: .constant(0), shown: $shown,
                                   value: "", onFailure: { _ in failed = true }, skeleton: false, bounces: true)
                    } else {
                        Rectangle().fill(Hue.ink)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Hue.ink)
                .clipped()
                if image.isPhoto {
                    FeedCardPhotoScrim(imageHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(dynamicTypeSize.isAccessibilitySize ? 1 : CGFloat(source.cardAspect), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .trackFrame(frame)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                PhotoCredit(names: credit.map { [$0] } ?? [])
                    .padding(-PhotoCredit.edgeInset)
                    .animation(reduceMotion ? nil : Motion.smooth, value: credit)
                if let logo = place.logo?.url {
                    LogoDisc(logo: logo, initial: String(place.name.prefix(1)), logoSide: PhotoChip.height * 0.875,
                             letter: .sansSemibold(14), fits: true)
                        .frame(width: PhotoChip.height, height: PhotoChip.height)
                        .overlay(Circle().strokeBorder(Hue.surface, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                }
            }
            .frame(minHeight: PhotoChip.height)
            .padding(PhotoChip.inset)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.eventDisplay(28))
                    .lineSpacing(-2)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let kind = place.sub {
                    Text(kind)
                        .font(.sans(13))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .feedCardPhotoTypeShadow()
            .allowsHitTesting(false)
            .padding(16)
        }
        .padding(.horizontal, DailyFeedMetric.contentInset)
    }

    /// Its business page, through the shell's opener, as a host's logo opens it.
    private func open() {
        guard let opener, let id = place.placeID, let logo = place.logo else { return }
        let row = FollowRow(targetType: .place, targetId: id, name: place.name, kind: nil,
                            picture: logo.url.absoluteString, pictureKind: cover == nil ? "logo" : "photo")
        if opener.opens(row) { opener.open(row, frame.rect) }
    }
}

/// The places whose page this phone opened, newest last: a round of places to try puts them after the
/// rest (town-feed 23). Kept on the phone only.
/// ponytail: per phone; a table of opens when a second phone or Android needs the same order.
enum OpenedPlaces {
    private static let key = "openedPlaces"
    private static let keep = 200

    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ id: String?) {
        guard let id else { return }
        let ids = (ids.filter { $0 != id } + [id]).suffix(keep)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
