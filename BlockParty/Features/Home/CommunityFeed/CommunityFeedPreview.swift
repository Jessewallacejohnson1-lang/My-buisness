//
//  CommunityFeedPreview.swift
//  Block Party — deterministic DEBUG-only data for the community-feed simulator preview.
//

#if DEBUG
import Foundation

enum CommunityFeedPreview {
    /// Included only so the simulator capture can verify the existing Today RSVP
    /// row and its renamed heading; it is never part of a release build.
    static let today = [
        TimelineEvent(
            id: "today-coffee",
            title: "Coffee with new neighbors",
            startTime: "4:00 PM",
            location: "Block Party Cafe",
            goingCount: 6,
            rsvpd: false,
            clubName: "Welcome circle",
            fromJoinedClub: false
        )
    ]

    static let events: [UpcomingEvent] = {
        let calendar = Calendar.current
        let now = Date()

        return [
            event("week-market", "Farmers market morning", daysFromToday: 1, time: "9:00 AM", location: "Downtown plaza", going: 18, createdAt: now),
            event("week-walk", "Riverside walking club", daysFromToday: 3, time: "6:00 PM", location: "Riverwalk trailhead", going: 9, createdAt: now),
            event("week-potluck", "Neighborhood potluck", daysFromToday: 6, time: "5:30 PM", location: "Civic center lawn", going: 24, createdAt: now),
            event("fresh-film", "Backyard film night", daysFromToday: 10, time: "8:15 PM", location: "Maple Street", going: 12, createdAt: now.addingTimeInterval(-60 * 60)),
            event("later-cleanup", "Creek cleanup crew", daysFromToday: 14, time: "10:00 AM", location: "Eastside creek", going: 7, createdAt: now.addingTimeInterval(-9 * 24 * 60 * 60)),
            event("later-book-club", "Sunday book club", daysFromToday: 20, time: "3:00 PM", location: "Library reading room", going: 11, createdAt: now.addingTimeInterval(-12 * 24 * 60 * 60))
        ]
        .map { event in
            var event = event
            event.eventDate = dateString(for: calendar.date(byAdding: .day, value: event.dayOffset, to: now)!)
            return event.upcomingEvent
        }
    }()

    private static func event(
        _ id: String,
        _ title: String,
        daysFromToday: Int,
        time: String,
        location: String,
        going: Int,
        createdAt: Date
    ) -> FixtureEvent {
        FixtureEvent(
            id: id,
            title: title,
            dayOffset: daysFromToday,
            startTime: time,
            location: location,
            goingCount: going,
            createdAt: iso8601String(for: createdAt)
        )
    }

    private static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func iso8601String(for date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private struct FixtureEvent {
        let id: String
        let title: String
        let dayOffset: Int
        let startTime: String
        let location: String
        let goingCount: Int
        let createdAt: String
        var eventDate = ""

        var upcomingEvent: UpcomingEvent {
            UpcomingEvent(
                id: id,
                title: title,
                eventDate: eventDate,
                startTime: startTime,
                location: location,
                goingCount: goingCount,
                createdAt: createdAt,
                imageUrl: nil,
                rsvpd: false,
                clubName: nil
            )
        }
    }
}
#endif
