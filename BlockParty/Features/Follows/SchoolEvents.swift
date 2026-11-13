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
    /// Its Town day, at the Town's midnight.
    let day: Date
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
    /// What the page says when its read failed (offline), and what to do about it.
    static let tryAgain = "Couldn't load right now. Pull down to try again."

    /// The school's events soonest first, one with no time it can read last on its day, two at one time in the
    /// order given (the server's: the activities' order).
    static func sorted(_ events: [SchoolEvent]) -> [SchoolEvent] {
        // Swift's sort promises no order for ties.
        events.enumerated().sorted { a, b in
            let at = { (e: SchoolEvent) in (e.day, EventWhen.minutes(e.time) ?? .max) }
            return at(a.element) != at(b.element) ? at(a.element) < at(b.element) : a.offset < b.offset
        }
        .map(\.element)
    }

    /// A title as the card says it: the middle-school tag dropped, as the mock does, since a school's own page
    /// says its level. Every other level's tag stays.
    static func title(_ title: String) -> String {
        title.hasSuffix(" · MS") ? String(title.dropLast(5)) : title
    }

    /// The segment an event is in, by Town days from `now`; nil for one before yesterday.
    static func segment(_ event: SchoolEvent, now: Date) -> SchoolDay? {
        switch Town.days(from: now, to: event.day) {
        case -1: .yesterday
        case 0: .today
        case 1...: .upcoming
        default: nil
        }
    }

    /// The segment the card opens on: Today, or Upcoming when today has none.
    static func opening(_ events: [SchoolEvent], now: Date) -> SchoolDay {
        events.contains { segment($0, now: now) == .today } ? .today : .upcoming
    }

    /// What a segment shows, a heading's day with its events, in the order given.
    static func days(_ events: [SchoolEvent], on segment: SchoolDay, now: Date) -> [(day: Date, events: [SchoolEvent])] {
        var days: [(day: Date, events: [SchoolEvent])] = []
        for event in events where self.segment(event, now: now) == segment {
            if days.last?.day == event.day { days[days.count - 1].events.append(event) } else { days.append((event.day, [event])) }
        }
        return days
    }

    /// The events before "See all" (Jesse, 2026-11-12), so search and the activities stay near the top.
    static let shown = 5

    /// The first `count` events of `days`, each with its day's heading; a day cut short keeps the ones that fit.
    static func first(_ count: Int, of days: [(day: Date, events: [SchoolEvent])]) -> [(day: Date, events: [SchoolEvent])] {
        var left = count
        var kept: [(day: Date, events: [SchoolEvent])] = []
        for day in days where left > 0 {
            kept.append((day.day, Array(day.events.prefix(left))))
            left -= min(left, day.events.count)
        }
        return kept
    }
}

/// How far the page's top has folded into its bar, 0 at rest to 1, from the scroll's offset: the top's own height
/// and 6 pt, as the mock's 90 pt was for its 84 pt top, so the name reaches the bar as it fades. The logo and name
/// shrink to 75% toward their foot and fade; the bar's title comes in over the last 30%, following the finger both
/// ways.
nonisolated enum SchoolFold {
    static let distance: CGFloat = SchoolMetric.top + 6

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

    /// The segment picked; nil until a tap, while the card opens where `SchoolEvents.opening` says.
    @State private var picked: SchoolDay?
    /// Every event of the segment, after "See all"; its first `SchoolEvents.shown` before.
    @State private var all = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Each minute, so a card left open past midnight moves its days along.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let segment = picked ?? SchoolEvents.opening(events ?? [], now: now)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(SchoolDay.allCases, id: \.self) { day in
                        Button { picked = day; all = false } label: {
                            Text(day.word)
                                .font(.displaySemi(17))
                                .foregroundStyle(Hue.nameOnDark.opacity(day == segment ? 1 : 0.5))
                                .frame(maxWidth: .infinity, minHeight: SchoolMetric.rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.press(.squish))
                        .accessibilityAddTraits(day == segment ? .isSelected : [])
                    }
                }
                .overlay(alignment: .bottom) { SchoolRule() }
                .padding(.horizontal, SchoolMetric.segmentInset)
                content(segment, now: now)
            }
        }
        .padding(.vertical, SchoolMetric.cardPad)
        .schoolCard()
        // The skeleton cross-fades into what was read (design.md, Loading).
        .animation(Motion.smooth, value: events == nil)
    }

    @ViewBuilder
    private func content(_ segment: SchoolDay, now: Date) -> some View {
        if let events {
            let days = SchoolEvents.days(events, on: segment, now: now)
            VStack(spacing: 0) {
                if days.isEmpty {
                    Text(segment.empty)
                        .font(.displaySemi(20))
                        .foregroundStyle(Hue.nameOnDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                }
                ForEach(all ? days : SchoolEvents.first(SchoolEvents.shown, of: days), id: \.day) { day in
                    Text(TeamPage.day(day.day))
                        .font(.sansSemibold(13))
                        .foregroundStyle(Hue.nameOnDark.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SchoolMetric.rowPad)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(day.events) { row($0) }
                }
                if days.flatMap(\.events).count > SchoolEvents.shown {
                    Button(all ? "Show less" : "See all") {
                        withAnimation(reduceMotion ? nil : Motion.smooth) { all.toggle() }
                    }
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.nameOnDark)
                    .frame(maxWidth: .infinity, minHeight: MeetupPillStyle.minTarget, alignment: .leading)
                    .padding(.horizontal, SchoolMetric.rowPad)
                    .buttonStyle(.press(.squish))
                }
            }
            .transition(.opacity)
        } else {
            // Rows in the card's own shape while they load.
            VStack(alignment: .leading, spacing: 16) {
                SkeletonLine(widthFraction: 0.3, height: 12)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SkeletonCircle(diameter: SchoolMetric.icon)
                        SkeletonLine(widthFraction: 0.65, height: 16)
                    }
                }
            }
            .padding(.horizontal, SchoolMetric.rowPad)
            .padding(.vertical, 16)
            .opacity(0.25)
            .shimmering()
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private func row(_ event: SchoolEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.symbol)
                .font(.glyph(17, weight: .regular))
                .foregroundStyle(Hue.nameOnDark)
                .frame(width: SchoolMetric.icon)
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
        .padding(.horizontal, SchoolMetric.rowPad)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The school page's one hairline: between the segments and the days, and between an activity's rows (the mock's
/// 0.5 pt of light at 12%).
struct SchoolRule: View {
    var body: some View {
        Rectangle().fill(Hue.nameOnDark.opacity(0.12)).frame(height: SchoolMetric.hairline)
    }
}

extension View {
    /// A card on a school's page: Apple Sports' dark see-through card with 30 pt corners over the
    /// school's colour, a hairline of light round its edge (the mock's). Not `shown`, its ground fades away.
    func schoolCard(shown: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.schoolCard, style: .continuous)
        return background(Hue.nameShadow.opacity(shown ? 0.42 : 0), in: shape)
            .overlay(shape.strokeBorder(Hue.nameOnDark.opacity(shown ? 0.1 : 0), lineWidth: SchoolMetric.hairline))
    }
}
