//
//  TownNewsCard.swift
//  Block Party — town news in the Town feed (BP app docs/plans/town-feed, ticket 35).
//
//  A Town card that says News, the short white card (BP app references/no-photo-cards): the place's
//  logo on the left, else its first letter with its name starting the facts; NEW in the grey pill; the
//  headline and the facts beside them; the send and the ••• under it (news-menu: Not interested and Mute its place, as an Event
//  card's). Never a photo: a post has no Event, so the only photo it could show is its place's cover
//  (Jesse, 2026-11-04, BP app town-feed 40). No time: Block Party knows when it saved a post, not when
//  the place posted it. A tap opens the post in Instagram or Facebook when that app is on the phone,
//  else in Apple's in-app browser; the card sinks the instant a finger lands, as an event card's does.
//

import SwiftUI

struct TownNewsCard: View {
    let news: TownNews
    /// Off in the share reveal's picture, which draws the post without its controls.
    var sendable = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var link: SafariLink?
    /// The •••'s sheet, an Event card's: Not interested and Mute its place (news-menu).
    @State private var menuPresented = false

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
                    onShare: share,
                    onMenu: { menuPresented = true }
                )
                .padding(.top, 2)
                .padding(.horizontal, DailyFeedMetric.contentInset)
                .modifier(FeedCardMenuSheet(isPresented: $menuPresented, news: news))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $link) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    private var face: some View {
        NoPhotoCard(logo: news.logo, name: news.place, pill: "NEW",
                    title: news.headline, facts: news.cardFacts, factsLines: 2)
            .padding(.horizontal, DailyFeedMetric.contentInset)
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

extension TownNews {
    /// The place's logo; a photo is its cover, which News never shows (BP app town-feed 40).
    var logo: URL? { picture?.kind == .logo ? picture?.url : nil }

    /// The card's small line. A first letter doesn't say whose post it is, so with no logo the place's
    /// name starts it, unless the words already name it (Jesse at town-feed 40's Check-in 2).
    var cardFacts: String? {
        guard logo == nil, !place.isEmpty, !words.localizedCaseInsensitiveContains(place),
              !headline.localizedCaseInsensitiveContains(place) else { return facts }
        return [place, facts].compactMap { $0 }.joined(separator: " · ")
    }
}
