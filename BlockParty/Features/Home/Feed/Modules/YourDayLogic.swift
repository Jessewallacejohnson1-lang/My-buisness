//
//  YourDayLogic.swift
//  Block Party — pure ordering and town-time presentation rules for Your Day.
//

import Foundation

nonisolated enum YourDayStripItem: Identifiable {
    case event(UpcomingEvent)
    case findSomething

    var id: String {
        switch self {
        case .event(let event): "event-\(event.id)"
        case .findSomething: "find-something"
        }
    }
}

nonisolated struct YourDaySchedulePresentation: Equatable {
    let dateAndTime: String
    let countdown: String?

    var label: String {
        guard let countdown else { return dateAndTime }
        return "\(dateAndTime) — \(countdown)"
    }
}

nonisolated enum YourDayLogic {
    static let maximumEventCount = 3
    static let countdownWindow: TimeInterval = 48 * 60 * 60

    static func stripItems(from events: [UpcomingEvent]) -> [YourDayStripItem] {
        events.prefix(maximumEventCount).map(YourDayStripItem.event) + [.findSomething]
    }

    static func isWithinCountdown(eventStart: Date, now: Date) -> Bool {
        let remaining = eventStart.timeIntervalSince(now)
        return remaining >= 0 && remaining <= countdownWindow
    }

    static func countdownText(eventStart: Date, now: Date) -> String? {
        guard isWithinCountdown(eventStart: eventStart, now: now) else { return nil }

        let remaining = eventStart.timeIntervalSince(now)
        let minutes = max(1, Int(ceil(remaining / 60)))
        guard minutes >= 60 else {
            return "in \(minutes) \(minutes == 1 ? "min" : "mins")"
        }

        let hours = minutes / 60
        return "in \(hours) \(hours == 1 ? "hr" : "hrs")"
    }

    static func goingLabel(for count: Int) -> String? {
        count > 0 ? "\(count) going" : nil
    }

    /// PRODUCT RULE: nil, never "Location TBD". A blank location is a fact we do
    /// not have, and a card that says nothing about place is honest.
    static func placeText(for event: UpcomingEvent) -> String? {
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty
        else { return nil }
        return location
    }

    static func eventStart(for event: UpcomingEvent) -> Date? {
        guard let minutes = minutes(from: event.startTime),
              let day = eventDay(for: event)
        else { return nil }

        return townInstant(day: day, minutesFromMidnight: minutes)
    }

    /// A wall-clock time-of-day on a given town day → the actual instant.
    ///
    /// `date(bySettingHour:)`, not `date(byAdding: .minute)`: on a DST boundary the
    /// two disagree. Adding 660 absolute minutes to a spring-forward midnight lands
    /// at noon, not the 11 AM the organizer typed. Setting the hour asks the
    /// calendar for that wall-clock time, which is what a poster on a coffee-shop
    /// door means.
    static func townInstant(day: Date, minutesFromMidnight: Int) -> Date? {
        Town.calendar.date(
            bySettingHour: minutesFromMidnight / 60,
            minute: minutesFromMidnight % 60,
            second: 0,
            of: day
        )
    }

    static func scheduleLabel(for event: UpcomingEvent, now: Date) -> String {
        schedulePresentation(for: event, now: now).label
    }

    static func schedulePresentation(
        for event: UpcomingEvent,
        now: Date
    ) -> YourDaySchedulePresentation {
        let dateAndTime = joined(
            day: dayText(for: event, now: now),
            time: startTimeText(for: event)
        ) ?? ""

        guard let start = eventStart(for: event),
              let countdown = countdownText(eventStart: start, now: now)
        else {
            return YourDaySchedulePresentation(dateAndTime: dateAndTime, countdown: nil)
        }

        return YourDaySchedulePresentation(dateAndTime: dateAndTime, countdown: countdown)
    }

    /// Joins whichever schedule parts exist. Nil when neither does — a caller must
    /// render nothing rather than a comma or a "TBD".
    static func joined(day: String?, time: String?) -> String? {
        switch (day, time) {
        case let (day?, time?): "\(day), \(time)"
        case let (day?, nil): day
        case let (nil, time?): time
        case (nil, nil): nil
        }
    }

    /// PRODUCT RULE: nil, never a placeholder. An unparseable date is not a day we
    /// can name, and leaking the raw `2033-05-18` row value would be worse than
    /// saying nothing.
    static func dayText(for event: UpcomingEvent, now: Date) -> String? {
        guard let eventDay = eventDay(for: event) else { return nil }

        let calendar = Town.calendar
        let today = calendar.startOfDay(for: now)
        let difference = calendar.dateComponents(
            [.day],
            from: today,
            to: calendar.startOfDay(for: eventDay)
        ).day

        switch difference {
        case 0:
            if let start = eventStart(for: event), calendar.component(.hour, from: start) >= 17 {
                return "Tonight"
            }
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US")
            formatter.timeZone = Town.timeZone
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: eventDay)
        }
    }

    /// The organizer's own words survive when we cannot parse them ("after dark"),
    /// because that is real data. Only the absence of any time returns nil.
    static func startTimeText(for event: UpcomingEvent) -> String? {
        guard let start = eventStart(for: event) else {
            let raw = event.startTime?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty { return raw }
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: start)
    }

    /// Town midnight on the row's `event_date`. Internal rather than private so the
    /// Your Day item builder shares this one parse — see `YourDayItems.swift`.
    static func eventDay(for event: UpcomingEvent) -> Date? {
        let parts = event.eventDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var components = DateComponents()
        components.calendar = Town.calendar
        components.timeZone = Town.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Town.calendar.date(from: components)
    }

    /// Free-text `club_events.start_time` → minutes from midnight. The live rows
    /// literally read "11 AM", "noon", "7:00 PM", and sometimes prose we cannot
    /// parse at all ("after dark"), which returns nil so the caller can fall back
    /// to the organizer's own words.
    ///
    /// Internal rather than private because the Your Day item builder needs the
    /// same parse — there is exactly ONE free-text time parser in this feature.
    static func minutes(from raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        switch raw.lowercased() {
        case "noon": return 12 * 60
        case "midnight": return 0
        default: break
        }

        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.isLenient = false

        for format in ["h:mm a", "h:mma", "ha", "h a", "HH:mm", "HH:mm:ss"] {
            formatter.dateFormat = format
            guard let date = formatter.date(from: raw) else { continue }
            let components = Town.calendar.dateComponents([.hour, .minute], from: date)
            guard let hour = components.hour, let minute = components.minute else { continue }
            return hour * 60 + minute
        }

        return nil
    }

    #if DEBUG
    /// `-yourday-sample` fixtures. Clearly-marked fake rows covering both lanes and
    /// all three eyebrow shapes, so the rail's states can be screenshotted without
    /// auth or a network.
    ///
    /// Anchored to the town's day rather than offset from `now`, so the sample
    /// cannot drift past midnight and empty itself out when the flag is used late
    /// in the evening.
    @MainActor
    static func debugEvents(now: Date) -> [UpcomingEvent] {
        let today = Town.day(now)
        let startedTwoDaysAgo = Town.day(
            Town.calendar.date(byAdding: .day, value: -2, to: now) ?? now
        )
        let endsTomorrow = Town.calendar.date(byAdding: .day, value: 1, to: now)

        return [
            UpcomingEvent(
                id: "yourday-debug-allday",
                title: "Town-wide garage sale",
                eventDate: today,
                startTime: nil,
                location: "All over St. Joe",
                goingCount: 12,
                createdAt: "debug",
                // Not RSVP'd: this is the whole-town lane, and the rail has to
                // mark it as such rather than let it read as a personal plan.
                rsvpd: false,
                isAllDay: true
            ),
            UpcomingEvent(
                id: "yourday-debug-ongoing",
                title: "Millstream Arts Festival",
                eventDate: startedTwoDaysAgo,
                startTime: "11 AM",
                location: "Millstream Park",
                goingCount: 6,
                createdAt: "debug",
                rsvpd: false,
                endAt: endsTomorrow
            ),
            UpcomingEvent(
                id: "yourday-debug-committed",
                title: "Patio trivia at Local Blend",
                eventDate: today,
                startTime: "7:00 PM",
                location: "Local Blend",
                goingCount: 4,
                createdAt: "debug",
                // The committed lane says yes, so the detail screen's RSVP control
                // tells the truth when the card is opened.
                rsvpd: true
            ),
        ]
    }

    /// The same fixtures, run through the real today/merge/sort rules.
    @MainActor
    static func debugDayItems(now: Date) -> [DayItem] {
        dayItems(from: debugEvents(now: now), now: now)
    }
    #endif
}
