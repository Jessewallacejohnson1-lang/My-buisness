//
//  TownNewsCard.swift
//  Block Party — town news in the Town feed (BP app docs/plans/town-feed, ticket 35).
//
//  A Town card that says News, the short white card (BP app references/no-photo-cards): the place's
//  logo on the left, else its first letter with its name starting the facts; the headline, "News · 2d"
//  under it in plain words, and the facts beside them. Nothing under it: held, it opens a Town card's menu (`TownCardHold`,
//  inside-cards 24), Share, then Not interested and Mute its place (news-menu), no Report. The heart in its bottom right
//  corner, signed in only (inside-cards 22). Never its place's cover (Jesse, 2026-11-04, BP app town-feed 40); its post's
//  own photo, when the photo step kept one, puts it on the Town photo card with that card's grey glass heart (Jesse,
//  2026-11-08, town-feed 53). A tap opens its News page when its post is the place's own and its words are read
//  (`NewsPage`, town-feed 65); else the post in Instagram or Facebook when that app is on the phone, else in Apple's
//  in-app browser. The card sinks the instant a finger lands, as an event card's does.
//

import SwiftUI

struct TownNewsCard: View {
    let news: TownNews
    /// Its sides' room: the Town feed's, or none where the page already keeps it (Liked).
    var inset: CGFloat = TownFeedMetric.contentInset

    /// The headline keeps 26 pt clear on its right for the heart: 242 pt of a 402 pt phone's 268 (BP app
    /// inside-cards SPEC.md, "The Town cards").
    static let heartRoom: CGFloat = 26

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The shell's stack, where its News page goes; nil where nothing can push.
    @Environment(\.hostOpener) private var opener
    private var words: NewsPostWords { .shared }
    @State private var pressed = false
    @State private var link: SafariLink?
    /// The card's size, so the heart on its corner sinks in with it.
    @State private var size: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                face(heart: actions.canAct)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .scaleEffect(FeedMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
                    .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
                    .animation(Press.animation(down: pressed, reduceMotion: reduceMotion), value: pressed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FeedCardLinkStyle())
            .gesture(FeedTouchDownTracker(isPressed: $pressed))
            .accessibilityElement(children: .ignore)
            // The title first, then when, as on an Event card.
            .accessibilityLabel([news.place.isEmpty ? "News" : "News from \(news.place)", news.headline, news.facts,
                                 news.published?.formatted(.relative(presentation: .named))]
                .compactMap { $0 }.joined(separator: ". "))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(opensPage ? "Opens the story" : "Opens the post")
            // The heart in the card's bottom right corner, its own button over the post's, riding the corner
            // in as the card sinks, as an Event card's does.
            .overlay(alignment: .bottomTrailing) {
                if actions.canAct {
                    let scale = FeedMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion)
                    TownCardHeart(news: news, onWhite: news.photoSource == nil)
                        .padding(TownCardHeart.inset)
                        .offset(x: -size.width * (1 - scale) / 2, y: -size.height * (1 - scale) / 2)
                        .animation(Press.animation(down: pressed, reduceMotion: reduceMotion), value: pressed)
                }
            }
            .modifier(TownCardHold(id: news.id, hostName: news.place, why: news.why, share: { Self.share(news) }))
            .padding(.horizontal, inset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only while it's on screen does a heart the server turns back shake here.
        .onAppear {
            actions.cardOpened(news.id)
            // Its post's words, read with the other cards on screen, so a tap finds them (town-feed 65).
            words.want(news.id)
        }
        .onDisappear { actions.cardClosed(news.id) }
        .sheet(item: $link) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    /// Its post's own photo on the Town photo card (town-feed 53), else the white card. `heart`: one sits in its corner.
    @ViewBuilder
    private func face(heart: Bool) -> some View {
        if let photo = news.photoSource {
            // The words keep clear of the heart as an Event photo card's do.
            NewsPhotoFace(news: news, photo: photo, heartRoom: heart ? TownCardHeart.side + TownCardHeart.inset - 8 : 0)
                // A new photo for this News starts over: not failed, its credit waiting for it.
                .id(photo.url)
        } else {
            whiteFace(room: heart ? Self.heartRoom : 0)
        }
    }

    /// With no second line, its two lines go to the headline (BP app inside-cards 12). `room` is the heart's. Shared as
    /// this, photo or not: the share window draws at once, before any photo could load.
    private func whiteFace(room: CGFloat) -> some View {
        Self.whiteFace(news, room: room)
    }

    private static func whiteFace(_ news: TownNews, room: CGFloat) -> some View {
        NoPhotoCard(logo: news.logo, name: news.place, when: news.when(),
                    title: news.headline, titleLines: news.facts == nil ? 4 : 2, facts: news.cardFacts, factsLines: 2,
                    trailingRoom: room)
    }

    /// Its own words are read and the shell can push: a tap opens its News page.
    private var opensPage: Bool { opener != nil && words.words[news.id] != nil }

    /// The post in its own app, Instagram or Facebook, when that app is on the phone; else in
    /// Apple's in-app browser. Jesse at Check-in 2, after Instagram's web page showed "Watch this
    /// reel in the app" instead of the reel: "open the post in the Instagram or Facebook app when
    /// it's on the phone, else the in-app browser".
    private func open() {
        if opensPage, let opener {
            opener.push(NewsRoute(news: news))
            return
        }
        let post = news.post
        Task {
            if await !UIApplication.shared.open(post, options: [.universalLinksOnly: true]) {
                link = SafariLink(url: post)
            }
        }
    }

    /// The share window, from its hold menu and its News page's send: the white card alone, no heart.
    static func share(_ news: TownNews) {
        ShareCenter.shared.present(
            SharePayload(title: news.place,
                         shareText: "\(news.place): \(news.words) \(news.post.absoluteString)",
                         includesImage: false) {
                // The card alone, no heart: the share window has none of the app's environment its hold reads.
                whiteFace(news, room: 0)
                    .padding(.horizontal, TownFeedMetric.contentInset)
                    .frame(width: 320)
                    .padding(.vertical, 16)
                    .background(Hue.surface)
            }
        )
    }
}

/// A News with its post's own photo (town-feed 53): an Event photo card's face (`FeedEventCard`), the photo in its own
/// shape known before it loads (square at accessibility sizes), its shade, the headline, "News · 2d" and its words over
/// it, the place's mark with the photo's credit on its top right once the photo is on screen; the heart is the card's. A photo that
/// can't load keeps the frame, as ink, so the feed never jumps.
private struct NewsPhotoFace: View {
    let news: TownNews
    let photo: FeedCardImageSource
    /// The heart's room on the right of the words, none signed out.
    let heartRoom: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Group {
                    if !failed, let url = photo.url {
                        FeedCardURLPhoto(url: url, onReady: { shown = true }, onFailure: { failed = true })
                    } else {
                        Hue.ink
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                FeedCardPhotoScrim(imageHeight: proxy.size.height)
            }
        }
        .aspectRatio(dynamicTypeSize.isAccessibilitySize ? 1 : photo.cardAspect, contentMode: .fit)
        .overlay(alignment: .bottomLeading) { words }
        .overlay(alignment: .topTrailing) { mark }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// As an Event's over its photo: the headline, 4 pt under it when, then its words (2 lines; Jesse at town-feed 53's
    /// Check-in 1), clear of the heart in the bottom right corner.
    private var words: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(news.headline)
                .font(.eventDisplay(28))
                .lineSpacing(-2)
                .foregroundStyle(.white)
                .lineLimit(!dynamicTypeSize.isAccessibilitySize && photo.cardAspect > 1.5 ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
            CardTime(text: news.when(), color: .white)
            if let facts = news.facts {
                Text(facts)
                    .font(.sans(13))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .padding(.trailing, heartRoom)
        .feedCardPhotoTypeShadow()
    }

    /// The photo's credit (its place) once the photo is on screen, then the place's mark: its logo, else its first
    /// letter, never its cover. It only shows; the whole card opens the post.
    private var mark: some View {
        HStack(spacing: HostMarkDisc.gap) {
            PhotoCredit(names: shown ? photo.attribution.map { [$0] } ?? [] : [], spoken: false)
                .padding(-PhotoCredit.edgeInset)
                .animation(reduceMotion ? nil : Motion.smooth, value: shown)
            if !news.place.isEmpty {
                HostMarkDisc(picture: news.picture?.kind == .logo ? news.picture : nil, name: news.place)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            }
        }
        .frame(minHeight: PhotoChip.height)
        .padding(PhotoChip.inset)
    }
}

extension TownNews {
    /// The place's logo; a photo is its cover, which News never shows (BP app town-feed 40).
    var logo: URL? { picture?.kind == .logo ? picture?.url : nil }

    /// Its post's own photo as a Town card shows one, credited to its place (town-feed 53).
    var photoSource: FeedCardImageSource? {
        photo.map { .placePhoto($0, credit: place.isEmpty ? nil : place, aspect: photoAspect) }
    }

    /// The card's small line. A first letter doesn't say whose post it is, so with no logo the place's
    /// name starts it, unless the card already names it (Jesse at town-feed 40's Check-in 2). "St." and
    /// "Saint" are one name: "St. John's Prep" is in "Saint John's Prep girls won".
    var cardFacts: String? {
        let saint = { (text: String) in text.replacing("Saint ", with: "St. ") }
        guard logo == nil, !place.isEmpty, !saint(facts ?? "").localizedCaseInsensitiveContains(saint(place)),
              !saint(headline).localizedCaseInsensitiveContains(saint(place)) else { return facts }
        return [place, facts].compactMap { $0 }.joined(separator: " · ")
    }

    /// "News · 2d" under the headline, in a neighbour's post's short form, from when Block Party found it
    /// (not when the place posted it); "News" with no date. Replaces NEW (Jesse, 2026-11-06, BP app
    /// inside-cards 12), and left its pill for plain words (inside-cards 26).
    func when(now: Date = .now) -> String {
        published.map { "News · \(PostingCard.relativeLabel(for: $0, now: now))" } ?? "News"
    }
}
