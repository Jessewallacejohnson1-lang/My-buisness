//
//  DayScheduleLogic.swift
//  Block Party — everything the day sheet decides before it draws anything.
//
//  Pure, `nonisolated`, and clock-injected, so the interesting rules — which stat
//  columns survive, where the now line goes, what the gutter says — are testable
//  without a view.
//
//  THE HOUSE RULE THROUGHOUT: a column, a line, or a label appears only when the
//  data behind it is real. Nothing renders a dash, a "TBD", or a zero. That is not
//  an edge case here, it is the common path — see `stats(...)`.
//

import Foundation

/// Where an item sits relative to now. Drives which three stat labels apply and
/// whether the row is dimmed.
nonisolated enum DayRowState: Hashable {
    case upcoming
    case inProgress
    case completed
}

/// One column of the stat row. Built only when there is a value; the absence of a
/// `DayStat` IS the suppression.
nonisolated struct DayStat: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label }
}

/// The clock scale in the left gutter. `meridiem` is split off so the column reads
/// as a timetable rather than repeating the card's eyebrow sentence.
nonisolated struct DayGutterTime: Hashable {
    let value: String
    let meridiem: String?

    var spoken: String {
        guard let meridiem else { return value }
        return "\(value) \(meridiem)"
    }
}

nonisolated enum DayScheduleLogic {

    // MARK: - Row state

    static func state(for item: DayItem, now: Date, isComplete: Bool) -> DayRowState {
        if isComplete { return .completed }
        return now >= item.start ? .inProgress : .upcoming
    }

    // MARK: - The stat row

    /// The three columns for a state, minus every one with nothing real behind it.
    ///
    /// What actually survives today, and why:
    ///   * `DISTANCE` — never. Events carry no coordinates; there is no distance
    ///     source to ask. See `distance(for:)`.
    ///   * `ENDS IN` — never, until `club_events.end_at` ships. The two-hour
    ///     assumption `completionInstant` makes is good enough to grey a card out
    ///     and nowhere near good enough to print as a number.
    ///   * `DURATION` — same reason.
    ///   * `GOING` — only above zero. "0 going" is a fact about our database, not
    ///     about the town.
    ///
    /// So an in-progress item usually renders ONE column, and sometimes none, in
    /// which case the caller drops the divider too.
    static func stats(for item: DayItem, state: DayRowState, now: Date) -> [DayStat] {
        switch state {
        case .upcoming:
            return [
                startsIn(item, now: now).map { DayStat(label: "STARTS", value: $0) },
                distance(for: item).map { DayStat(label: "DISTANCE", value: $0) },
                going(item).map { DayStat(label: "GOING", value: $0) },
            ].compactMap { $0 }

        case .inProgress:
            return [
                endsIn(item, now: now).map { DayStat(label: "ENDS IN", value: $0) },
                distance(for: item).map { DayStat(label: "DISTANCE", value: $0) },
                going(item).map { DayStat(label: "GOING", value: $0) },
            ].compactMap { $0 }

        case .completed:
            return [
                went(item).map { DayStat(label: "WENT", value: $0) },
                duration(item).map { DayStat(label: "DURATION", value: $0) },
                going(item).map { DayStat(label: "GOING", value: $0) },
            ].compactMap { $0 }
        }
    }

    /// Reuses the rail's countdown vocabulary rather than inventing a second one,
    /// so "in 25 mins" means the same thing in both views.
    static func startsIn(_ item: DayItem, now: Date) -> String? {
        YourDayLogic.countdownText(eventStart: item.start, now: now)
    }

    static func endsIn(_ item: DayItem, now: Date) -> String? {
        guard let end = item.end else { return nil }
        return YourDayLogic.countdownText(eventStart: end, now: now)
    }

    /// The clock time it happened — only when the row actually stated one. An
    /// all-day or still-running multi-day item has no "went at".
    static func went(_ item: DayItem) -> String? {
        gutterTime(for: item).flatMap { time in
            time.meridiem == nil ? nil : time.spoken
        }
    }

    static func duration(_ item: DayItem) -> String? {
        guard let end = item.end else { return nil }
        let minutes = Int((end.timeIntervalSince(item.start) / 60).rounded())
        guard minutes > 0 else { return nil }
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        let rounded = (hours * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) hr"
            : String(format: "%.1f hr", rounded)
    }

    static func going(_ item: DayItem) -> String? {
        item.goingCount > 0 ? "\(item.goingCount)" : nil
    }

    /// THE MISSING SOURCE, stated explicitly rather than hidden in an if.
    /// `club_events` has no coordinates and `DayItem` carries a free-text
    /// `location`, so there is nothing to measure from. When venues resolve to
    /// coordinates this becomes the only function that changes.
    static func distance(for _: DayItem) -> String? { nil }

    // MARK: - The gutter

    /// The left clock scale. Derived from the contract's documented `eyebrow`
    /// vocabulary — `"6:30 PM"` · `"Today · ongoing"` · `"Today · all day"` ·
    /// `"Today"` — with the structural flags taking precedence, so nothing here
    /// re-parses the event row.
    ///
    /// Nil for `"Today"`: the organiser never said a time, and 11:59 PM (where the
    /// data layer parks an unparseable one so it sorts last) is a sort key, not a
    /// fact to print.
    static func gutterTime(for item: DayItem) -> DayGutterTime? {
        if item.isAllDay { return DayGutterTime(value: "all day", meridiem: nil) }
        if item.isMultiDay { return DayGutterTime(value: "ongoing", meridiem: nil) }

        let eyebrow = item.eyebrow.trimmingCharacters(in: .whitespaces)
        guard let separator = eyebrow.range(of: " ", options: .backwards) else {
            return nil
        }

        let meridiem = String(eyebrow[separator.upperBound...])
        guard meridiem.caseInsensitiveCompare("AM") == .orderedSame
                || meridiem.caseInsensitiveCompare("PM") == .orderedSame
        else { return nil }

        return DayGutterTime(
            value: String(eyebrow[..<separator.lowerBound]),
            meridiem: meridiem
        )
    }

    // MARK: - Subtitle

    /// `category · location`, minus whatever is missing.
    ///
    /// `.other` is dropped rather than printed: it is the fallback for a null
    /// column, so today EVERY row would read "Other · somewhere", which tells a
    /// neighbour nothing and reads like a bug.
    ///
    /// The one `@MainActor` member here: `EventCategory.label` is part of the
    /// design system and is main-actor isolated with it. Reaching for it from a
    /// `nonisolated` context trips the 0-warning bar, and copying the ten labels
    /// into this file to avoid that would fork the taxonomy.
    @MainActor
    static func subtitle(for item: DayItem) -> String? {
        let category = item.event.category == .other ? nil : item.event.category.label
        let parts = [category, item.location].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - The now line

    /// `[first start, last ending]`. Nil for an empty day.
    static func span(of items: [DayItem]) -> (start: Date, end: Date)? {
        guard let first = items.map(\.start).min() else { return nil }
        let last = items
            .map { YourDayLogic.completionInstant(for: $0.event, span: ($0.start, $0.end)) }
            .max() ?? first
        return (first, max(first, last))
    }

    /// Only while the day is actually underway. Before the first thing starts the
    /// line would just sit at the top restating "nothing yet", and after the last
    /// one ends it would sit at the bottom restating "that was the day".
    static func showsNowLine(items: [DayItem], now: Date) -> Bool {
        guard let span = span(of: items) else { return false }
        return now >= span.start && now <= span.end
    }

    /// How many rows precede the line. Everything already started sits above it.
    static func nowLineIndex(items: [DayItem], now: Date) -> Int? {
        guard showsNowLine(items: items, now: now) else { return nil }
        return items.filter { $0.start <= now }.count
    }

    // MARK: - Copy

    /// `Monday, August 10`, in town time — the same day the rail was built for.
    static func headerDate(_ date: Date) -> String {
        townFormatter("EEEE, MMMM d").string(from: date)
    }

    /// `3 things today`. Singular at one, and an invitation at zero.
    static func headerCount(_ count: Int) -> String {
        switch count {
        case 0: "Nothing today"
        case 1: "1 thing today"
        default: "\(count) things today"
        }
    }

    /// `now 9:23` — the line's own label, no meridiem, because it sits beside a
    /// gutter that already reads AM/PM.
    static func nowLabel(_ date: Date) -> String {
        "now \(townFormatter("h:mm").string(from: date))"
    }

    /// The unambiguous version, for VoiceOver.
    static func nowSpoken(_ date: Date) -> String {
        "Now, \(townFormatter("h:mm a").string(from: date))"
    }

    private static func townFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
