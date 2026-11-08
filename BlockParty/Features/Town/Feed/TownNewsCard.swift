//
//  TownNewsCard.swift
//  Block Party — town news in the Town feed (BP app docs/plans/town-feed, ticket 35).
//
//  A Town card that says News, the short white card (BP app references/no-photo-cards): the place's
//  logo on the left, else its first letter with its name starting the facts; the headline, "News · 2d"
//  under it in plain words, and the facts beside them. Nothing under it: held, it opens a Town card's menu (`TownCardHold`,
//  inside-cards 24), Share, then Not interested and Mute its place (news-menu), no Report. The heart in its bottom right
//  corner, the white card's ink one, signed in only (inside-cards 22). Never a photo: a post has no Event, so the only photo it could show is its place's cover
//  (Jesse, 2026-11-04, BP app town-feed 40). A tap opens the post in Instagram or Facebook when that app is on the phone,
//  else in Apple's in-app browser; the card sinks the instant a finger lands, as an event card's does.
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
    @State private var pressed = false
    @State private var link: SafariLink?
    /// The card's size, so the heart on its corner sinks in with it.
    @State private var size: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                face(room: actions.canAct ? Self.heartRoom : 0)
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
            .accessibilityHint("Opens the post")
            // The heart in the card's bottom right corner, its own button over the post's, riding the corner
            // in as the card sinks, as an Event card's does.
            .overlay(alignment: .bottomTrailing) {
                if actions.canAct {
                    let scale = FeedMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion)
                    TownCardHeart(news: news)
                        .padding(TownCardHeart.inset)
                        .offset(x: -size.width * (1 - scale) / 2, y: -size.height * (1 - scale) / 2)
                        .animation(Press.animation(down: pressed, reduceMotion: reduceMotion), value: pressed)
                }
            }
            .modifier(TownCardHold(id: news.id, hostName: news.place, why: news.why, share: share))
            .padding(.horizontal, inset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only while it's on screen does a heart the server turns back shake here.
        .onAppear { actions.cardOpened(news.id) }
        .onDisappear { actions.cardClosed(news.id) }
        .sheet(item: $link) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    /// With no second line, its two lines go to the headline (BP app inside-cards 12). `room` is the heart's.
    private func face(room: CGFloat) -> some View {
        NoPhotoCard(logo: news.logo, name: news.place, when: news.when(),
                    title: news.headline, titleLines: news.facts == nil ? 4 : 2, facts: news.cardFacts, factsLines: 2,
                    trailingRoom: room)
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
                // The card alone, no heart: the share window has none of the app's environment its hold reads.
                face(room: 0)
                    .padding(.horizontal, TownFeedMetric.contentInset)
                    .frame(width: 320)
                    .padding(.vertical, 16)
                    .background(Hue.surface)
            }
        )
    }
}

extension TownNews {
    /// The place's logo; a photo is its cover, which News never shows (BP app town-feed 40).
    var logo: URL? { picture?.kind == .logo ? picture?.url : nil }

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
