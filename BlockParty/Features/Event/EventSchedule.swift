//
//  EventSchedule.swift
//  Block Party — a long Event's parts on its page (BP app happening-now 06; Jesse picked mock A, 2026-11-10):
//  "Schedule" under the Map button, Bloomberg's schedule rows, the time in its own column ("Thu 3 PM") and the
//  name beside it. "Now" behind the green dot beside the part on, as the cards say it (`CardTime`); "In 20 min"
//  beside the next one in its last hour (happening-now 01's words). The next 4, "See all" for the rest. Today's
//  ended parts fade, earlier days' drop off. No parts left, no Schedule. The words tick on the minute, in place.
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
        /// Ended today: it stays, faded.
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

    /// The parts as the page lists them at `now`, by start: those still to end, and today's that have ended, faded.
    static func rows(_ parts: [EventPart], at now: Date) -> [Row] {
        let kept = parts
            .filter { $0.end > now || Town.days(from: $0.start, to: now) == 0 }
            .sorted { $0.start < $1.start }
        let next = kept.first { $0.start > now }
        return kept.map { part in
            let mark: Mark? = if part.start <= now, now < part.end { .now }
                else if part == next, let soon = FeedWhenLine.countdown(to: part.start, at: now) { .soon(soon) }
                else { nil }
            return Row(part: part, past: part.end <= now, mark: mark)
        }
    }

    #if DEBUG
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

    @State private var all = false
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
                    ForEach(all ? rows : Array(rows.prefix(EventSchedule.shown)), id: \.part) { row(for: $0) }
                    if rows.count > EventSchedule.shown {
                        Button(all ? "Show less" : "See all") {
                            withAnimation(reduceMotion ? nil : Motion.smooth) { all.toggle() }
                        }
                        .font(.sansSemibold(EventLook.scheduleMore))
                        .foregroundStyle(tint)
                        .frame(minHeight: MeetupPillStyle.minTarget)
                        .buttonStyle(.press(.squish))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, EventLook.scheduleTop)
                .transition(.opacity)
            }
        }
    }

    private func row(for row: EventSchedule.Row) -> some View {
        HStack(spacing: EventLook.scheduleGap) {
            Text(row.time)
                .font(.apple(EventLook.scheduleTimeSize))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: EventLook.scheduleTime, alignment: .leading)
            Text(row.part.title)
                .font(.apple(EventLook.scheduleName))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // One `CardTime` from the countdown on, so "In 1 min" cross-fades to "Now" at the start minute, as on the card.
            if let mark = row.mark {
                let soon: FeedWhenLine? = if case .soon(let line) = mark { line } else { nil }
                CardTime(text: soon?.text ?? "", now: mark == .now, color: soon == nil ? ink : tint)
            }
        }
        .frame(minHeight: EventLook.scheduleRow)
        .opacity(row.past ? EventLook.schedulePast : 1)
        .animation(reduceMotion ? nil : Motion.smooth, value: row.past)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}
