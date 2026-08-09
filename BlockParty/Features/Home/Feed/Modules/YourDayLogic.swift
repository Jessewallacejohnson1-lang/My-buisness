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

    static func eventStart(for event: UpcomingEvent) -> Date? {
        guard let minutes = minutes(from: event.startTime),
              let day = eventDay(for: event)
        else { return nil }

        return Town.calendar.date(byAdding: .minute, value: minutes, to: day)
    }

    static func scheduleLabel(for event: UpcomingEvent, now: Date) -> String {
        schedulePresentation(for: event, now: now).label
    }

    static func schedulePresentation(
        for event: UpcomingEvent,
        now: Date
    ) -> YourDaySchedulePresentation {
        let dateAndTime = "\(dayLabel(for: event, now: now)), \(timeLabel(for: event))"

        guard let start = eventStart(for: event),
              let countdown = countdownText(eventStart: start, now: now)
        else {
            return YourDaySchedulePresentation(dateAndTime: dateAndTime, countdown: nil)
        }

        return YourDaySchedulePresentation(dateAndTime: dateAndTime, countdown: countdown)
    }

    static func dayLabel(for event: UpcomingEvent, now: Date) -> String {
        guard let eventDay = eventDay(for: event) else { return event.eventDate }

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

    static func timeLabel(for event: UpcomingEvent) -> String {
        guard let start = eventStart(for: event) else {
            let raw = event.startTime?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty { return raw }
            return "Time TBD"
        }

        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: start)
    }

    private static func eventDay(for event: UpcomingEvent) -> Date? {
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

    private static func minutes(from raw: String?) -> Int? {
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
    @MainActor
    static func debugEvents(now: Date) -> [UpcomingEvent] {
        let starts = [
            now.addingTimeInterval(4 * 60 * 60),
            now.addingTimeInterval(30 * 60 * 60),
            now.addingTimeInterval(4 * 24 * 60 * 60),
        ]
        let titles = [
            "Patio trivia at Local Blend",
            "Millstream morning walk",
            "Community supper downtown",
        ]
        let locations = ["Local Blend", "Millstream Park", "Church of Saint Joseph"]
        let goingCounts = [0, 6, 12]

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Town.calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = Town.timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Town.calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = Town.timeZone
        timeFormatter.dateFormat = "h:mm a"

        return starts.indices.map { index in
            UpcomingEvent(
                id: "yourday-debug-\(index)",
                title: titles[index],
                eventDate: dateFormatter.string(from: starts[index]),
                startTime: timeFormatter.string(from: starts[index]),
                location: locations[index],
                goingCount: goingCounts[index],
                createdAt: "debug"
            )
        }
    }
    #endif
}
