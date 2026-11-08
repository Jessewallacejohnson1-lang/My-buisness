//
//  TownNewsCard.swift
//  Block Party — town news in the Town feed (BP app docs/plans/town-feed, ticket 35).
//
//  A Town card that says News, the short white card (BP app references/no-photo-cards): the place's
//  logo on the left, else its first letter with its name starting the facts; "News · 2d" in the grey pill; the
//  headline and the facts beside them. Nothing under it: held, it opens a Town card's menu (`TownCardHold`,
//  inside-cards 24), Share, then Not interested and Mute its place (news-menu), no Report. Never a photo: a post has no Event, so the only photo it could show is its place's cover
//  (Jesse, 2026-11-04, BP app town-feed 40). A tap opens the post in Instagram or Facebook when that app is on the phone,
//  else in Apple's in-app browser; the card sinks the instant a finger lands, as an event card's does.
//

import SwiftUI

struct TownNewsCard: View {
    let news: TownNews

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var link: SafariLink?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            // The title first, then when, as on an Event card.
            .accessibilityLabel([news.place.isEmpty ? "News" : "News from \(news.place)", news.headline, news.facts,
                                 news.published?.formatted(.relative(presentation: .named))]
                .compactMap { $0 }.joined(separator: ". "))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the post")
            .modifier(TownCardHold(id: news.id, hostName: news.place, why: news.why, share: share))
            .padding(.horizontal, TownFeedMetric.contentInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $link) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    /// With no second line, its two lines go to the headline (BP app inside-cards 12).
    private var face: some View {
        NoPhotoCard(logo: news.logo, name: news.place, pill: news.pill(),
                    title: news.headline, titleLines: news.facts == nil ? 4 : 2, facts: news.cardFacts, factsLines: 2)
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
                // The card alone: the share window has none of the app's environment its hold reads.
                face
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

    /// "News · 2d", in a neighbour's post's short form, from when Block Party found it (not when the
    /// place posted it); "News" with no date. Replaces NEW (Jesse, 2026-11-06, BP app inside-cards 12).
    func pill(now: Date = .now) -> String {
        published.map { "News · \(PostingCard.relativeLabel(for: $0, now: now))" } ?? "News"
    }
}
