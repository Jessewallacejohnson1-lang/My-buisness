//
//  SchoolEvents.swift
//  Block Party — a school's events on its page (BP app school-search 05): Apple Sports' Yesterday,
//  Today and Upcoming card, opening on Upcoming when today has none (Jesse, 2026-11-11), and the page's
//  top folding into its bar as it scrolls. Mock (version 2): https://claude.ai/artifact/LeS4sSai7DLT7qTqGgTYx5.
//

import SwiftUI

/// One of the school's events: an activity's, with that activity's symbol.
nonisolated struct SchoolEvent: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    /// Its Town day, "2026-11-12".
    let date: String
    let time: String?
    let location: String?
    let symbol: String
}

/// The card's three segments.
nonisolated enum SchoolDay: CaseIterable, Hashable, Sendable {
    case yesterday, today, upcoming

    var word: String {
        switch self {
        case .yesterday: "Yesterday"
        case .today: "Today"
        case .upcoming: "Upcoming"
        }
    }

    /// Apple Sports' words for a segment with nothing in it.
    var empty: String {
        switch self {
        case .yesterday: "No Events Yesterday"
        case .today: "No Events Today"
        case .upcoming: "No Upcoming Events"
        }
    }
}

nonisolated enum SchoolEvents {
    /// Every activity's events as one list: an event two activities share once, soonest first, one
    /// with no time it can read last on its day.
    static func merged(_ lists: [[SchoolEvent]]) -> [SchoolEvent] {
        var seen = Set<String>()
        let all = lists.joined().filter { seen.insert($0.id).inserted }
        return all.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return (EventWhen.minutes(a.time) ?? .max) < (EventWhen.minutes(b.time) ?? .max)
        }
    }

    /// The segment the card opens on: Today, or Upcoming when today has none.
    static func opening(_ events: [SchoolEvent], now: Date) -> SchoolDay {
        let today = Town.day(now)
        return events.contains { $0.date == today } ? .today : .upcoming
    }

    /// How many Upcoming shows: the mock's five, so search and the activities stay near the top. Every
    /// event is still on its activity's row.
    static let upcomingShown = 5

    /// What a segment shows, a heading's day with its events, in the order given.
    static func days(_ events: [SchoolEvent], on segment: SchoolDay, now: Date) -> [(date: String, events: [SchoolEvent])] {
        let today = Town.day(now)
        let yesterday = Town.day(Town.gregorian.date(byAdding: .day, value: -1, to: now) ?? now)
        var shown = events.filter {
            switch segment {
            case .yesterday: $0.date == yesterday
            case .today: $0.date == today
            case .upcoming: $0.date > today
            }
        }
        if segment == .upcoming { shown = Array(shown.prefix(upcomingShown)) }
        var days: [(date: String, events: [SchoolEvent])] = []
        for event in shown {
            if days.last?.date == event.date { days[days.count - 1].events.append(event) } else { days.append((event.date, [event])) }
        }
        return days
    }
}

/// How far the page's top has folded into its bar, 0 at rest to 1, from the scroll's offset: the mock's
/// 90 pt. The logo and name shrink to 75% toward their foot and fade; the bar's title comes in over the
/// last 30%, following the finger both ways.
nonisolated enum SchoolFold {
    static let distance: CGFloat = 90

    static func progress(_ offset: CGFloat) -> CGFloat { min(1, max(0, offset / distance)) }

    static func topScale(_ progress: CGFloat) -> CGFloat { 1 - 0.25 * progress }

    static func titleOpacity(_ progress: CGFloat) -> CGFloat { min(1, max(0, (progress - 0.7) / 0.3)) }
}

/// The fold, in a box of its own so the scroll can write it every frame and only the top and the bar
/// read it (the Town bar's `BarTravel`).
@Observable
final class SchoolFoldBox {
    var progress: CGFloat = 0
}

/// The school's events: Yesterday, Today and Upcoming over the day's events, in Apple Sports' card.
struct SchoolEventsCard: View {
    /// nil while they load.
    let events: [SchoolEvent]?
    let failed: Bool

    /// The segment picked; nil until a tap, while the card opens where `SchoolEvents.opening` says.
    @State private var picked: SchoolDay?

    var body: some View {
        let now = Date()
        let segment = picked ?? SchoolEvents.opening(events ?? [], now: now)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SchoolDay.allCases, id: \.self) { day in
                    Button { picked = day } label: {
                        Text(day.word)
                            .font(.displaySemi(17))
                            .foregroundStyle(Hue.nameOnDark.opacity(day == segment ? 1 : 0.5))
                            .frame(maxWidth: .infinity, minHeight: TeamPage.rowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityAddTraits(day == segment ? .isSelected : [])
                }
            }
            .overlay(alignment: .bottom) { hairline }
            .padding(.horizontal, 9)
            if let events {
                let days = SchoolEvents.days(events, on: segment, now: now)
                if days.isEmpty {
                    Text(segment.empty)
                        .font(.displaySemi(20))
                        .foregroundStyle(Hue.nameOnDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                }
                ForEach(days, id: \.date) { day in
                    Text(TeamPage.day(day.date) ?? day.date)
                        .font(.sansSemibold(13))
                        .foregroundStyle(Hue.nameOnDark.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TeamPage.rowPad)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(day.events) { row($0) }
                }
            } else if failed {
                Text("Check your connection and try again.")
                    .font(.sans(15))
                    .foregroundStyle(Hue.nameOnDark.opacity(0.6))
                    .padding(.vertical, 24)
            } else {
                // Rows in the card's own shape while they load.
                VStack(alignment: .leading, spacing: 16) {
                    SkeletonLine(widthFraction: 0.3, height: 12)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 12) {
                            SkeletonCircle(diameter: TeamPage.icon)
                            SkeletonLine(widthFraction: 0.65, height: 16)
                        }
                    }
                }
                .padding(.horizontal, TeamPage.rowPad)
                .padding(.vertical, 16)
                .opacity(0.25)
                .shimmering()
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .schoolCard()
    }

    private var hairline: some View {
        Rectangle().fill(Hue.nameOnDark.opacity(0.12)).frame(height: 0.5)
    }

    private func row(_ event: SchoolEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.symbol)
                .font(.glyph(17, weight: .regular))
                .foregroundStyle(Hue.nameOnDark)
                .frame(width: TeamPage.icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.sansSemibold(16))
                    .foregroundStyle(Hue.nameOnDark)
                    .lineLimit(1)
                if let location = event.location {
                    Text(location)
                        .font(.sans(13))
                        .foregroundStyle(Hue.nameOnDark.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let time = event.time {
                Text(time)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.nameOnDark)
                    .fixedSize()
            }
        }
        .padding(.horizontal, TeamPage.rowPad)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A card on a school's page: Apple Sports' dark see-through card with 30 pt corners over the
    /// school's colour, a hairline of light round its edge (the mock's).
    func schoolCard() -> some View {
        background(Hue.nameShadow.opacity(0.42), in: RoundedRectangle(cornerRadius: Radius.schoolCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.schoolCard, style: .continuous)
                .strokeBorder(Hue.nameOnDark.opacity(0.1), lineWidth: 0.5))
    }
}
