import Foundation

enum CommunityFeedBucket: String, CaseIterable, Identifiable {
    case thisWeek
    case fresh
    case later

    var id: Self { self }

    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .fresh: "Fresh from around town"
        case .later: "Coming up later"
        }
    }
}

struct CommunityFeedSection: Identifiable {
    let bucket: CommunityFeedBucket
    let events: [UpcomingEvent]

    var id: CommunityFeedBucket { bucket }
}

enum CommunityFeedBucketer {
    nonisolated static func sections(
        for events: [UpcomingEvent],
        today: String = defaultToday(),
        now: Date = Date()
    ) -> [CommunityFeedSection] {
        guard let todayDate = localDate(from: today) else { return [] }

        let classified = events.enumerated().compactMap { index, event -> ClassifiedEvent? in
            guard let eventDate = localDate(from: event.eventDate) else { return nil }
            let dayOffset = localCalendar.dateComponents(
                [.day],
                from: localCalendar.startOfDay(for: todayDate),
                to: localCalendar.startOfDay(for: eventDate)
            ).day ?? 0
            guard dayOffset > 0 else { return nil }

            let createdAt = iso8601Date(from: event.createdAt)
            let bucket: CommunityFeedBucket
            switch dayOffset {
            case 1...7:
                bucket = .thisWeek
            case 8... where isFresh(createdAt, now: now):
                bucket = .fresh
            default:
                bucket = .later
            }

            return ClassifiedEvent(
                event: event,
                date: eventDate,
                minutes: minutesOf(event.startTime),
                createdAt: createdAt,
                index: index,
                bucket: bucket
            )
        }

        return CommunityFeedBucket.allCases.compactMap { bucket in
            let bucketEvents = classified.filter { $0.bucket == bucket }
            guard !bucketEvents.isEmpty else { return nil }
            return CommunityFeedSection(
                bucket: bucket,
                events: sorted(bucketEvents, for: bucket).map(\.event)
            )
        }
    }

    private struct ClassifiedEvent {
        let event: UpcomingEvent
        let date: Date
        let minutes: Int
        let createdAt: Date?
        let index: Int
        let bucket: CommunityFeedBucket
    }

    private nonisolated static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Matches DateHelpers.localDate() while keeping this pure helper nonisolated.
    private nonisolated static func defaultToday() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private nonisolated static func localDate(from value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = localCalendar.date(from: components) else { return nil }

        let normalized = localCalendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year, normalized.month == month, normalized.day == day else { return nil }
        return date
    }

    private nonisolated static func iso8601Date(from value: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    /// Mirrors DateHelpers.minutesOf(_:) for nonisolated sorting.
    private nonisolated static func minutesOf(_ value: String?) -> Int {
        guard let raw = value?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty
        else { return 24 * 60 }
        if raw.contains("noon") { return 12 * 60 }
        if raw.contains("midnight") { return 0 }
        guard let matchRange = raw.range(
            of: #"(\d{1,2})(?::(\d{2}))?\s*(a|p)"#,
            options: .regularExpression
        ) else { return 24 * 60 }

        let match = String(raw[matchRange])
        let digits = match.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var hour = digits.first else { return 24 * 60 }
        let minute = digits.count > 1 ? digits[1] : 0
        if match.contains("p"), hour < 12 { hour += 12 }
        if match.contains("p") == false, hour == 12 { hour = 0 }
        return hour * 60 + minute
    }

    private nonisolated static func isFresh(_ createdAt: Date?, now: Date) -> Bool {
        guard let createdAt else { return false }
        return now.timeIntervalSince(createdAt) <= 7 * 24 * 60 * 60
    }

    private nonisolated static func sorted(
        _ events: [ClassifiedEvent],
        for bucket: CommunityFeedBucket
    ) -> [ClassifiedEvent] {
        events.sorted { lhs, rhs in
            if bucket == .fresh, lhs.createdAt != rhs.createdAt {
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.minutes != rhs.minutes { return lhs.minutes < rhs.minutes }
            return lhs.index < rhs.index
        }
    }
}
