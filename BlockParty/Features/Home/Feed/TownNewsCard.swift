//
//  TownNewsCard.swift
//  Block Party — town news in the Town feed (BP app docs/plans/town-feed, ticket 35).
//
//  A Town card that says News (Jesse, 2026-10-29: "similar format to cards just news", BP app
//  references/found-posts): the place's photo in its own shape, else its logo on its Search
//  backdrop, else ink; a white "News" chip where an event's day and time go; the headline over
//  it as an event's title, the facts under that; the send under the picture. No place name and no
//  picture beside one: a found post carries only the place's own mark. No time: Block Party knows
//  when it saved a post, not when the place posted it. A tap opens the post in Instagram or
//  Facebook when that app is on the phone, else in Apple's in-app browser; the picture sinks the
//  instant a finger lands, as an event card's does.
//

import SwiftUI

struct TownNewsCard: View {
    let news: TownNews
    /// Off in the share reveal's picture, which draws the post without its controls.
    var sendable = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pressed = false
    @State private var link: SafariLink?
    /// The photo once its bitmap is on screen: its credit waits for it.
    @State private var shown: Set<URL> = []
    /// A photo that couldn't load: the card turns to ink, keeping its shape.
    @State private var failed = false
    /// The words' height over the picture, so a logo stays in the room above them.
    @State private var copyHeight: CGFloat = 0

    /// The place's picture, which also sets the card's shape, failed or not.
    private var source: FeedCardImageSource { news.picture.map(FeedCardImageSource.init) ?? .fallback }
    private var image: FeedCardImageSource { failed ? .fallback : source }
    /// Ink words over a logo's light backdrop, white over a photo or ink.
    private var onLogo: Bool { image.logo != nil }

    private var credit: [String] {
        guard let url = image.url, PhotoPager.isShown(url, in: shown), let credit = image.attribution else { return [] }
        return [credit]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                picture
                    .scaleEffect(FeedMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
                    .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
                    .animation(FeedMotion.pressAnimation(reduceMotion: reduceMotion), value: pressed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FeedCardLinkStyle())
            .gesture(FeedTouchDownTracker(isPressed: $pressed))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([news.place.isEmpty ? "News" : "News from \(news.place)", news.headline, news.facts]
                .compactMap { $0 }.joined(separator: ". "))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the post")

            if sendable {
                FeedEventCardActionRow(
                    kind: .event,
                    showsHeart: false,
                    showsSave: false,
                    state: .constant(FeedCardActionState(likeCount: 0, isLiked: false, isSaved: false)),
                    reduceMotion: reduceMotion,
                    autoplayStep: 0,
                    onLike: nil,
                    onSave: nil,
                    onComment: {},
                    onShare: share
                )
                .padding(.top, 2)
                .padding(.horizontal, DailyFeedMetric.contentInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $link) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    /// The event card's picture (`FeedEventCard.imageSection`): the photo's own shape, 20 pt
    /// corners, the chip along the top with the photo's credit at the right, the words off the
    /// bottom left.
    private var picture: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                pictureContent
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
        .overlay(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                PhotoChip(text: "News")
                Spacer(minLength: 0)
                PhotoCredit(names: credit)
                    .padding(-PhotoCredit.edgeInset)
                    .animation(reduceMotion ? nil : Motion.smooth, value: credit)
                placeMark
            }
            .frame(minHeight: PhotoChip.height)
            .padding(PhotoChip.inset)
        }
        .overlay(alignment: .bottomLeading) {
            copy.padding(16)
        }
        .padding(.horizontal, DailyFeedMetric.contentInset)
    }

    /// Whose post it is, on the picture's top right, as an Event's host rides it (Jesse, 2026-10-29:
    /// "water marks for businesses or people"): the place's logo on a white disc, else its first
    /// letter, since the feed sends no logo beside a photo. None over its own logo.
    @ViewBuilder
    private var placeMark: some View {
        if !onLogo, !news.place.isEmpty {
            Group {
                if let picture = news.picture, picture.kind == .logo {
                    LogoDisc(logo: picture.url, initial: String(news.place.prefix(1)).uppercased(),
                             logoSide: PhotoChip.height * 0.875, letter: .sansSemibold(14), fits: true)
                        .frame(width: PhotoChip.height, height: PhotoChip.height)
                } else {
                    FeedAuthorAvatar(url: nil, name: news.place, side: PhotoChip.height)
                }
            }
            .overlay(Circle().strokeBorder(Hue.surface, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private var pictureContent: some View {
        if let url = image.url {
            PhotoPager(urls: [url], page: .constant(0), shown: $shown, value: "",
                       onFailure: { _ in failed = true }, skeleton: false, bounces: true)
        } else if let logo = image.logo {
            FeedCardPlaceLogo(logo: logo, topClear: PhotoChip.inset + PhotoChip.height, bottomClear: copyHeight + 16)
        } else {
            Rectangle().fill(Hue.ink)
        }
    }

    /// The headline as an event's title (`FeedEventCard.imageCopy`), the facts in its place line's
    /// type, two lines at most: news facts run a sentence where an event's place is a few words.
    private var copy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(news.headline)
                .font(.eventDisplay(28))
                .lineSpacing(-2)
                .foregroundStyle(onLogo ? Hue.ink : .white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let facts = news.facts {
                Text(facts)
                    .font(.sans(13))
                    .foregroundStyle(onLogo ? Hue.inkSecondary : .white.opacity(0.85))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .feedCardPhotoTypeShadow(onLogo ? 0 : 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 }
        .allowsHitTesting(false)
    }

    /// The post in its own app, Instagram or Facebook, when that app is on the phone; else in
    /// Apple's in-app browser. Jesse at Check-in 2, after Instagram's web page showed "Watch this
    /// reel in the app" instead of the reel: "open the post in the Instagram or Facebook app when
    /// it's on the phone, else the in-app browser".
    private func open() {
        let post = news.post
        Task {
            if await !UIApplication.shared.open(post, options: [.universalLinksOnly: true]) {
                link = SafariLink(url: post)
            }
        }
    }

    private func share() {
        ShareCenter.shared.present(
            SharePayload(title: news.place,
                         shareText: "\(news.place): \(news.words) \(news.post.absoluteString)",
                         includesImage: false) {
                TownNewsCard(news: news, sendable: false)
                    .frame(width: 320)
                    .padding(.vertical, 16)
                    .background(Hue.surface)
            }
        )
    }
}
