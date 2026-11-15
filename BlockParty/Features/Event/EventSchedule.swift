//
//  EventSchedule.swift
//  Block Party — a long Event's parts on its page (BP app happening-now 06; Jesse picked mock A, 2026-11-10):
//  "Schedule" under the Map button, Bloomberg's schedule rows, the time in its own column ("Thu 3 PM") and the
//  name beside it. "Now" behind the green dot beside a live part on, as the cards say it (`CardTime`); "In 20 min"
//  beside the next one in its last hour when it is live (happening-now 01's words). The first 4 are the part on and
//  the next; parts that ended today fade and fill only the places left; "See all" for the rest. One that ended before
//  today drops off. No parts left, no Schedule. The words tick on the minute, in place.
//

import SwiftUI

enum EventSchedule {
    /// What sits beside a part's name.
    enum Mark: Equatable {
        case now
        case soon(FeedWhenLine)
    }

    struct Row: Equatable {
        let part: EventPart
        /// Ended today, wherever it started: it stays, faded.
        let past: Bool
        let mark: Mark?

        /// "Thu 3 PM", in the Town's time.
        var time: String { "\(Town.format(part.start, "EEE")) \(Town.clock(part.start))" }

        /// "Thursday 3 PM, Artist talk, starts in 20 minutes": one element per row for VoiceOver.
        var spoken: String {
            let mark: String? = switch self.mark {
            case .now: "happening now"
            case .soon(let line): line.spoken.lowercased()
            case nil: nil
            }
            return ["\(Town.format(part.start, "EEEE")) \(Town.clock(part.start))", part.title, mark]
                .compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The rows before "See all".
    static let shown = 4

    /// Every part as "See all" lists it at `now`, by start: those still to end, and those that ended today, faded. Only a
    /// live part (`get_event_parts`: a real happening under 12 hours) says "Now" or counts down.
    static func rows(_ parts: [EventPart], at now: Date) -> [Row] {
        let kept = parts
            .filter { $0.end > now || Town.days(from: $0.end, to: now) == 0 }
            .sorted { $0.start < $1.start }
        let next = kept.first { $0.start > now }
        return kept.map { part in
            let mark: Mark? = if !part.live { nil }
                else if part.start <= now, now < part.end { .now }
                else if part == next, let soon = FeedWhenLine.countdown(to: part.start, at: now) { .soon(soon) }
                else { nil }
            return Row(part: part, past: part.end <= now, mark: mark)
        }
    }

    /// The first `shown` rows: the part on and the next ones; when fewer are left, the latest to have ended fill the
    /// places left, above them in time order.
    static func visible(_ rows: [Row]) -> [Row] {
        let ahead = rows.filter { !$0.past }.prefix(shown)
        let room = shown - ahead.count
        let ended = rows.filter(\.past).sorted { $0.part.end > $1.part.end }.prefix(room).sorted { $0.part.start < $1.part.start }
        return Array(ended) + ahead
    }

    // MARK: The day row (BP app event-schedule 02; mock B beside Apple Store Upcoming)

    /// One day of the day row.
    struct Day: Equatable, Identifiable {
        /// "2026-11-14", the Town day.
        let id: String
        /// Town midnight that day.
        let start: Date
        /// Parts that day.
        let count: Int
        let today: Bool

        /// "S", over the number.
        var letter: String { Town.format(start, "EEEEE") }
        /// "14".
        var number: String { Town.format(start, "d") }
        /// "Saturday, November 14, today, 3 planned": one button for VoiceOver.
        var spoken: String {
            [Town.format(start, "EEEEMMMMd"), today ? "today" : nil, count == 0 ? "nothing planned" : "\(count) planned"]
                .compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The Town day a row sits under: its start's, or today's for one that began on an earlier day and runs on.
    static func day(of row: Row, at now: Date) -> String {
        Town.day(max(row.part.start, Town.gregorian.startOfDay(for: now)))
    }

    /// The day row when the rows left fall on two or more Town days: every day from the first to the last, gaps
    /// included, each with its count. Empty when they fall on one day: the list (A) shows them.
    static func days(_ rows: [Row], at now: Date) -> [Day] {
        let counts = Dictionary(grouping: rows) { day(of: $0, at: now) }.mapValues(\.count)
        guard counts.count > 1, let first = counts.keys.min().flatMap(Town.midnight),
              let last = counts.keys.max().flatMap(Town.midnight) else { return [] }
        let today = Town.day(now)
        return (0...Town.days(from: first, to: last)).compactMap { offset in
            // By calendar day, not 24 hours, so the days stay midnights across a clock change.
            guard let start = Town.gregorian.date(byAdding: .day, value: offset, to: first) else { return nil }
            let id = Town.day(start)
            return Day(id: id, start: start, count: counts[id] ?? 0, today: id == today)
        }
    }

    /// The day shown: the one picked while it's still in the row, else today, else the first day.
    static func shown(picked: String?, in days: [Day]) -> String? {
        if let picked, days.contains(where: { $0.id == picked }) { return picked }
        return (days.first(where: \.today) ?? days.first)?.id
    }

    /// One day's rows, by start.
    static func rows(_ rows: [Row], onDay day: String, at now: Date) -> [Row] {
        rows.filter { Self.day(of: $0, at: now) == day }
    }

    /// "3 – 4 PM", "11 AM – 1 PM": a part's hours under its name in the day row.
    static func span(_ part: EventPart) -> String {
        let start = Town.gregorian.component(.hour, from: part.start) * 60 + Town.gregorian.component(.minute, from: part.start)
        let length = Int(part.end.timeIntervalSince(part.start) / 60)
        guard length > 0, length < PlaceHours.day else { return Town.clock(part.start) }
        return PlaceHours.line([start..<start + length])
    }

    #if DEBUG
    /// `-town-part-day`: today's parts only, so the page shows the list (A): one that ended 2 hours ago, one on
    /// since 10 minutes before launch, one in 20 minutes and two later tonight.
    static func oneDaySamples(_ launch: Date) -> [EventPart] {
        let now = Town.gregorian.dateInterval(of: .minute, for: launch)?.start ?? launch
        let minute: TimeInterval = 60
        let at = { (offset: TimeInterval, length: TimeInterval, title: String) in
            EventPart(title: title, start: now.addingTimeInterval(offset * minute),
                      end: now.addingTimeInterval((offset + length) * minute))
        }
        // Late in the evening the later ones would run past midnight onto a second day: those are left out.
        return [at(-150, 30, "Luminary walk"), at(-10, 40, "Santa arrives"), at(20, 30, "Carolers"),
                at(60, 30, "Letters to Santa"), at(90, 60, "Live music")]
            .filter { Town.day($0.start) == Town.day(now) && Town.day($0.end.addingTimeInterval(-1)) == Town.day(now) }
    }

    /// `-town-part`: an opening that ended 2 hours ago, the artist talk on since 10 minutes before launch, a reception
    /// in 20 minutes, a film tomorrow and the showcase the day after, so the page shows a faded row, "Now",
    /// "In 20 min" and "See all".
    static func samples(_ launch: Date) -> [EventPart] {
        // On the minute, as a host's times are, so the minute's tick reads "In 20 min".
        let now = Town.gregorian.dateInterval(of: .minute, for: launch)?.start ?? launch
        let hour: TimeInterval = 3600
        let at = { (offset: TimeInterval, title: String) in
            EventPart(title: title, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + hour))
        }
        return [at(-3 * hour, "Opening"), at(-600, "Artist talk"), at(1200, "Reception"),
                at(24 * hour, "Film night"), at(48 * hour, "Student Showcase")]
    }
    #endif
}

/// The Schedule section under the Map button: nothing at all while no part is left to show.
struct EventScheduleSection: View {
    let parts: [EventPart]
    /// The words' colour on the page: white, ink on the yellow.
    let ink: Color
    /// The time column's and "See all"'s: the page's tint.
    let tint: Color

    /// The picked day's number on its disc: the page's colour behind the words (BP yellow on the yellow page).
    let picked: Color

    @State private var all = false
    /// The day tapped in the day row; nil until one is, so the row opens on today.
    @State private var day: String?
    /// The number's disc grows with the text size.
    @ScaledMetric(relativeTo: .body) private var disc: CGFloat = EventLook.scheduleDisc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.everyMinute) { context in
            let rows = EventSchedule.rows(parts, at: context.date)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Schedule")
                        .font(.display(EventLook.aboutHeading))
                        .foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, EventLook.scheduleHeadingGap)
                    let days = EventSchedule.days(rows, at: context.date)
                    if let shown = EventSchedule.shown(picked: day, in: days) {
                        dayRow(days, shown: shown)
                        // One day's list over the other while they cross-fade, held to a floor so a day with fewer
                        // parts doesn't pull the page up under the finger (mock B's 128).
                        ZStack(alignment: .topLeading) {
                            dayList(EventSchedule.rows(rows, onDay: shown, at: context.date))
                                .id(shown)
                                .transition(.opacity)
                        }
                        .frame(minHeight: EventLook.scheduleDayFloor, alignment: .top)
                    } else {
                        list(rows)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, EventLook.scheduleTop)
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: day)
    }

    // MARK: The day row (B): Events across several days (BP app event-schedule 02)

    /// Every day from today to the last part's, a week to the screen's width; a longer run scrolls sideways.
    private func dayRow(_ days: [EventSchedule.Day], shown: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(days) { day in
                    Button {
                        // The day already shown changes nothing: no haptic, no fade.
                        guard day.id != shown else { return }
                        withAnimation(reduceMotion ? nil : Motion.select) { self.day = day.id }
                    } label: {
                        dayLabel(day, on: day.id == shown)
                    }
                    .buttonStyle(.press(.squish))
                    .containerRelativeFrame(.horizontal, count: EventLook.scheduleWeek, spacing: 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.spoken)
                    .accessibilityAddTraits(day.id == shown ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(days.count <= EventLook.scheduleWeek)
        .padding(.bottom, EventLook.scheduleDaysGap)
    }

    /// Mock B's day: the weekday's letter over its number on a disc, the picked one's disc filled; today's dot
    /// under it, as Apple's Calendar marks today; a day with nothing planned at 40%.
    private func dayLabel(_ day: EventSchedule.Day, on: Bool) -> some View {
        VStack(spacing: EventLook.scheduleDayGap) {
            Text(day.letter)
                .font(.sansMedium(12))
                .foregroundStyle(tint.opacity(EventLook.scheduleDim))
            Text(day.number)
                .font(on ? .sansSemibold(17) : .sansMedium(17))
                .monospacedDigit()
                .foregroundStyle(on ? picked : ink)
                .frame(width: disc, height: disc)
                .background(Circle().fill(ink).opacity(on ? 1 : 0))
            Circle()
                .fill(Hue.today)
                .frame(width: EventLook.scheduleDot, height: EventLook.scheduleDot)
                .opacity(day.today ? 1 : 0)
        }
        .padding(.vertical, EventLook.scheduleDayGap)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .opacity(day.count == 0 && !on ? EventLook.schedulePast : 1)
    }

    /// The picked day's parts, every one: the name over its hours, "Now" or the countdown at the right.
    @ViewBuilder
    private func dayList(_ rows: [EventSchedule.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("Nothing planned")
                    .font(.sans(15))
                    .foregroundStyle(tint)
                    .frame(minHeight: EventLook.scheduleRow)
            }
            ForEach(rows, id: \.part) { row in
                HStack(spacing: EventLook.scheduleGap) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.part.title)
                            .font(.sansMedium(17))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Text(EventSchedule.span(row.part))
                            .font(.sans(14))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    mark(row)
                }
                .padding(.vertical, EventLook.scheduleDayRowPad)
                .opacity(row.past ? EventLook.schedulePast : 1)
                .animation(reduceMotion ? nil : Motion.smooth, value: row.past)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spoken)
            }
        }
    }

    // MARK: The list (A): one day's parts (happening-now 06)

    @ViewBuilder
    private func list(_ rows: [EventSchedule.Row]) -> some View {
        let visible = EventSchedule.visible(rows)
        ForEach(all ? rows : visible, id: \.part) { row(for: $0) }
        if rows.count > visible.count {
            Button(all ? "Show less" : "See all") {
                withAnimation(reduceMotion ? nil : Motion.smooth) { all.toggle() }
            }
            .font(.sansSemibold(15))
            .foregroundStyle(tint)
            .frame(minHeight: MeetupPillStyle.minTarget)
            .buttonStyle(.press(.squish))
        }
    }

    /// "Now" behind the green dot, or the countdown, for a live part. One `CardTime` from the countdown on, so
    /// "In 1 min" cross-fades to "Now" at the start minute, as on the card.
    @ViewBuilder
    private func mark(_ row: EventSchedule.Row) -> some View {
        if let mark = row.mark {
            let soon: FeedWhenLine? = if case .soon(let line) = mark { line } else { nil }
            CardTime(text: soon?.text ?? "", now: mark == .now, color: soon == nil ? ink : tint)
        }
    }

    private func row(for row: EventSchedule.Row) -> some View {
        HStack(spacing: EventLook.scheduleGap) {
            Text(row.time)
                .font(.sans(15))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: EventLook.scheduleTime, alignment: .leading)
            Text(row.part.title)
                .font(.sans(16))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            mark(row)
        }
        .frame(minHeight: EventLook.scheduleRow)
        .opacity(row.past ? EventLook.schedulePast : 1)
        .animation(reduceMotion ? nil : Motion.smooth, value: row.past)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}
