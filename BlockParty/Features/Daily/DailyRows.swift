//
//  DailyRows.swift
//  Block Party — Daily's sideways rows of Town cards: Friends are going and Suggestions
//  ("For you today"), in the Town tab's look, the words over the photo (BP app docs/plans/daily-tab,
//  tickets 20 and 21; Check-in 1 https://claude.ai/artifact/3xQgvR2fLR2bKTp6ErQhwv).
//

import SwiftUI

/// Sizes from the Check-in 1 page Jesse said yes to (BP app `references/daily-rows/mock.html`),
/// drawn after the Daily inspo board's Town cards.
nonisolated enum DailyRowMetric {
    /// Friends are going's cards, and Suggestions' smaller ones.
    static let friendsSize = CGSize(width: 280, height: 300)
    static let suggestionSize = CGSize(width: 200, height: 250)
    static let gap: CGFloat = 12
    static let side: CGFloat = 16
    /// The Town card's corner and its fade: clear to 45% of the way down, then to black 62%.
    static let radius: CGFloat = 20
    static let shadeFrom: Double = 0.45
    static let shade: Double = 0.62
    /// The words, 14 in from the card's sides and 12 over its bottom.
    static let wordsInset: CGFloat = 14
    static let wordsBottom: CGFloat = 12
    static let wordsGap: CGFloat = 5
    /// From the friends' faces to their words, as on the Town card.
    static let facesGap: CGFloat = 7
    static let friendsTitle: CGFloat = 21
    static let suggestionTitle: CGFloat = 18
    /// The row's title, in the logo's face as "Spotlight" is, 18 in and 10 over the cards.
    static let titleSize: CGFloat = 24
    static let titleInset: CGFloat = 18
    static let titleToCards: CGFloat = 10
    /// Most cards in a row.
    static let limit = 10
    /// How far ahead Friends are going looks from today (Daily plan, ticket 15).
    static let friendsDays = 7
}

extension DailyEvent {
    /// The shown day's events that match your interests, from the Town feed's cards, in the feed
    /// recipe's order (Town feed ticket 14). With no interests (signed out, or none picked), the
    /// day's top. Never what's over, your Event of the day, or what you're Going to or saved:
    /// `without` and `left` say which.
    static func suggestions(from cards: [FeedCardItem], day: String, interests: [String], now: Date,
                            without shown: [DailyEvent], left: (FeedCardItem) -> Bool) -> [DailyEvent] {
        let shownIDs = Set(shown.map(\.id))
        let mine = cards.filter { card in
            card.eventDate == day && left(card) && !shownIDs.contains(card.id)
                && (interests.isEmpty || interests.contains { DailyTopic.matches(card, $0) })
        }
        return Array(mine.compactMap { YouCalendar.event(from: $0) }.filter { $0.ends > now }
            .prefix(DailyRowMetric.limit))
    }

    /// Events with friends Going on `days` (today: the next seven; a day picked in the week: that
    /// day), most friends first, then soonest (Jesse at daily-tab 21's Check-in 1). Event-centred:
    /// never one friend's list of plans; a friend's "Show my plans to friends" off already keeps
    /// them out of the Town feed's `friends_going`.
    static func friendsGoing(from cards: [FeedCardItem], days: Set<String>, now: Date,
                             without shown: [DailyEvent]) -> [DailyEvent] {
        let shownIDs = Set(shown.map(\.id))
        return Array(cards.filter { card in
            !card.friendsGoing.isEmpty && card.eventDate.map(days.contains) == true && !shownIDs.contains(card.id)
        }
        .compactMap { YouCalendar.event(from: $0) }
        .filter { $0.ends > now }
        .sorted { ($0.item.friendsGoing.count, $1.starts) > ($1.item.friendsGoing.count, $0.starts) }
        .prefix(DailyRowMetric.limit))
    }
}

/// A row's title in the logo's face, as "Spotlight" is set (Jesse at Check-in 1). Working words.
struct DailyRowTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.logoSerif(DailyRowMetric.titleSize))
            .foregroundStyle(Hue.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DailyRowMetric.titleInset)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled row of Town cards the finger slides sideways, each stopping at the margin.
struct DailyCardRow: View {
    let title: String
    let events: [DailyEvent]
    let size: CGSize
    let titleSize: CGFloat
    let showsFriends: Bool
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DailyRowMetric.titleToCards) {
            DailyRowTitle(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DailyRowMetric.gap) {
                    ForEach(events) { event in
                        DailyTownCard(event: event, size: size, titleSize: titleSize,
                                      showsFriends: showsFriends, now: now)
                    }
                }
                .scrollTargetLayout()
                // A finished event's card closes up instead of vanishing.
                .animation(reduceMotion ? nil : Motion.smooth, value: events.map(\.id))
            }
            .contentMargins(.horizontal, DailyRowMetric.side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

/// One Town card, the photo alone with the words over its bottom fade: the time chip at the top
/// left, the title, then the friends going (their faces and Facebook's words) or who hosts it.
/// It opens the Event page, as every Town card does.
struct DailyTownCard: View {
    let event: DailyEvent
    let size: CGSize
    let titleSize: CGFloat
    let showsFriends: Bool
    let now: Date

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DailyRowMetric.radius, style: .continuous) }

    var body: some View {
        NavigationLink(value: event.item) {
            Hue.ink
                .frame(width: size.width, height: size.height)
                .overlay { if let url = event.photo { FeedCardURLPhoto(url: url) } }
                .overlay {
                    LinearGradient(stops: [.init(color: .black.opacity(0), location: DailyRowMetric.shadeFrom),
                                           .init(color: .black.opacity(DailyRowMetric.shade), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    PhotoChip(text: when, dot: event.isOn(now) ? Hue.now : nil).padding(PhotoChip.inset)
                }
                .overlay(alignment: .bottomLeading) { words }
                .clipShape(shape)
                .modifier(CardShadow())
                .contentShape(shape)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([event.item.title, when, line].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    /// "7 PM", "Now", or on another day "Fri · 7 PM".
    private var when: String { event.dayLine(now: now) ?? event.startTime(now: now) }

    private var friendNames: [String] { event.item.friendsGoing.map(\.name) }

    /// "Kim and 2 friends are going", or who hosts it.
    private var line: String? {
        if showsFriends { return RSVPWords.friendsLine(friendNames, bar: false) }
        let host = event.item.hostName
        return host.isEmpty ? event.item.location : host
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: DailyRowMetric.wordsGap) {
            Text(event.item.title)
                .font(.eventDisplay(titleSize))
                .lineSpacing(-2)
                .lineLimit(2)
                .foregroundStyle(.white)
            HStack(spacing: DailyRowMetric.facesGap) {
                if showsFriends { FriendFaces(friends: event.item.friendsGoing, ring: .white) }
                if let line {
                    Text(line)
                        .font(.sans(13))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .feedCardPhotoTypeShadow()
        .padding(.horizontal, DailyRowMetric.wordsInset)
        .padding(.bottom, DailyRowMetric.wordsBottom)
    }
}
