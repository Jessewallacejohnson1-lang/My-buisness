//
//  TownNewsCard.swift
//  Block Party — town news in the Town feed (BP app docs/plans/town-feed, ticket 35).
//
//  Threads' text post in the event card's own sizes (Reference: BP app references/town-news/):
//  the place's logo where a host's photo goes, its name, its one line of facts beside the
//  avatar from 58 pt in, and the send under them. No time: Block Party knows when it saved a
//  post, not when the place posted it. A tap opens the post in Apple's in-app browser; the card
//  squishes the instant a finger lands, as an event card does.
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

    /// The event card's host avatar and its gap to the name (`FeedEventCard.hostRow`), so the
    /// words start where an event's host name does.
    private static let avatarSide: CGFloat = 32
    private static let avatarGap: CGFloat = 10
    /// The send's glyph sits 2 pt inside its 28 pt target: this lines it up under the words.
    private static let sendInset: CGFloat = avatarSide + avatarGap - 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { link = SafariLink(url: news.post) } label: {
                HStack(alignment: .top, spacing: Self.avatarGap) {
                    // The name says whose post it is: VoiceOver skips the avatar's letter.
                    avatar.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(news.place)
                            .font(.sansSemibold(14))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        Text(news.words)
                            .font(.sans(15))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Hue.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedCardLinkStyle())
            .gesture(FeedTouchDownTracker(isPressed: $pressed))
            .accessibilityElement(children: .combine)
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
                .padding(.leading, Self.sendInset)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, DailyFeedMetric.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(FeedMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
        .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
        .animation(FeedMotion.pressAnimation(reduceMotion: reduceMotion), value: pressed)
        .sheet(item: $link) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    /// The place's logo on a white disc, as Search shows it, else its photo; with neither, its
    /// first letter, as a neighbour with no photo gets.
    @ViewBuilder
    private var avatar: some View {
        if let picture = news.picture, picture.kind == .logo {
            LogoDisc(logo: picture.url, initial: initial, logoSide: Self.avatarSide * 0.75, letter: .sansSemibold(14))
                .frame(width: Self.avatarSide, height: Self.avatarSide)
                .overlay(Circle().strokeBorder(Hue.hairline.onLightCanvas, lineWidth: 0.5))
        } else {
            FeedAuthorAvatar(url: news.picture?.url, name: news.place, side: Self.avatarSide)
        }
    }

    private var initial: String {
        news.place.first(where: \.isLetter).map { String($0).uppercased() } ?? ""
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
