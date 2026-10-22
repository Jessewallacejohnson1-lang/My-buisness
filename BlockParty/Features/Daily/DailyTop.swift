//
//  DailyTop.swift
//  Block Party — the top of Daily, as Apple News lays out Discover: the Block Party wordmark at the
//  left where News+ sits, the Town's round logo at the right where News has its Subscriber Edition
//  seal, and under the week a row of topics in place of Best of News+ / My Magazines / Downloaded
//  (BP app docs/plans/daily-tab, ticket 19; take 11 on Figma "BP · Daily tab inspo").
//

import SwiftUI

/// Sizes from take 11, the mock Jesse picked (BP app `references/daily-news/mock.html`), drawn
/// over Apple News' Discover (`references/daily-news/refs/news-discover.jpg`).
nonisolated enum DailyTopMetric {
    static let side: CGFloat = 20
    /// The wordmark's height, and the Town logo's circle: News' seal is about 60pt.
    static let wordmark: CGFloat = 38
    static let logo: CGFloat = 60
    /// From the logo row to the week, and from the week's faces to the topics.
    static let toWeek: CGFloat = 4
    static let toTopics: CGFloat = 12
    /// A topic: News' 34pt pill, 15pt in from its ends, 8pt apart. It grows with the text size,
    /// and its tap area reaches 5pt above and below it, for 44.
    static let topicHeight: CGFloat = 34
    static let topicTapExtra: CGFloat = 5
    static let topicPadding: CGFloat = 15
    static let topicGap: CGFloat = 8
    /// At most this many topics after "Best of".
    static let topics = 6
}

/// Daily's topics: the interests (`Interests`) that have something on the day shown. Picking one
/// turns the page to the events that match it, by the same keyword match "Suggested for you" uses.
enum DailyTopic {
    /// The words an event is matched on.
    static func text(_ item: FeedCardItem) -> String {
        [item.title, item.hostName, item.metaLine, item.location ?? "", item.description ?? ""]
            .joined(separator: " ")
    }

    static func matches(_ item: FeedCardItem, _ topic: String) -> Bool {
        matches(text: text(item), topic)
    }

    static func matches(_ row: DailyFollowing, _ topic: String) -> Bool {
        if let event = row.event { return matches(event.item, topic) }
        return matches(text: "\(row.name) \(row.what)", topic)
    }

    /// The interest's keywords, each from the start of a word: "art" finds "artists" but not
    /// "Party", where `Interests.matches` (any part of a word) would.
    static func matches(text: String, _ topic: String) -> Bool {
        guard let interest = Interests.all.first(where: { $0.id == topic }) else { return false }
        return interest.keywords.contains { keyword in
            text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: keyword),
                       options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// Your own interests that have something that day, in your order; signed out or with none
    /// picked, the day's busiest interests. A topic with nothing that day isn't offered.
    static func topics(for items: [FeedCardItem], mine: [String],
                       limit: Int = DailyTopMetric.topics) -> [String] {
        let texts = items.map(text)
        let counts = Dictionary(uniqueKeysWithValues: Interests.all.map { interest in
            (interest.id, texts.filter { matches(text: $0, interest.id) }.count)
        })
        let offered = mine.isEmpty
            ? Interests.all.map(\.id).enumerated()
                .sorted { (counts[$0.element] ?? 0, -$0.offset) > (counts[$1.element] ?? 0, -$1.offset) }
                .map(\.element)
            : mine
        return Array(offered.filter { (counts[$0] ?? 0) > 0 }.prefix(limit))
    }

    static func label(_ topic: String) -> String {
        Interests.all.first { $0.id == topic }?.label ?? topic
    }
}

/// The wordmark and the Town's logo on one line. The logo is art for now: the Joetown page it
/// will open is Follows ticket 04 (Jesse, daily-tab 19).
struct DailyMasthead: View {
    var body: some View {
        HStack(alignment: .center) {
            BlockPartyWordmark(height: DailyTopMetric.wordmark)
                .foregroundStyle(Hue.ink)
            Spacer(minLength: 0)
            Image(Town.logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: DailyTopMetric.logo, height: DailyTopMetric.logo)
                .accessibilityLabel("\(Town.name) logo")
        }
        .padding(.horizontal, DailyTopMetric.side)
    }
}

/// "Best of St. Joe" and the day's topics, News' pills: the picked one ink, which slides to the
/// one you tap, as the week's black bubble does; the rest white with the one soft lift.
struct DailyTopicRow: View {
    let topics: [String]
    /// nil is "Best of": everything.
    let picked: String?
    let pick: (String?) -> Void
    @Namespace private var pill

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DailyTopMetric.topicGap) {
                chip(nil, "Best of \(Town.nickname)")
                ForEach(topics, id: \.self) { chip($0, DailyTopic.label($0)) }
            }
            .padding(.horizontal, DailyTopMetric.side)
        }
        // The pills' lift reaches past the row.
        .scrollClipDisabled()
    }

    private func chip(_ topic: String?, _ title: String) -> some View {
        let isPicked = topic == picked
        return Button { pick(topic) } label: {
            Text(title)
                .font(.sansMedium(15))
                .lineLimit(1)
                .foregroundStyle(isPicked ? Hue.surface : Hue.ink)
                .padding(.horizontal, DailyTopMetric.topicPadding)
                .frame(minHeight: DailyTopMetric.topicHeight)
                .background {
                    if isPicked {
                        Capsule().fill(Hue.ink).matchedGeometryEffect(id: "picked", in: pill)
                    } else {
                        Capsule().fill(Hue.surface)
                            .overlay { Capsule().strokeBorder(Hue.hairline, lineWidth: 0.5) }
                            .modifier(CardShadow())
                    }
                }
                .padding(.vertical, DailyTopMetric.topicTapExtra)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
    }
}
