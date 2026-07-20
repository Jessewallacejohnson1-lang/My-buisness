#if DEBUG
import Foundation

enum CommunityFeedBucketerSelfCheck {
    nonisolated static func run() {
        let today = "2026-07-19"
        let now = ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z")!
        let events = [
            event("same-day", date: "2026-07-19", time: "9am", createdAt: "2026-07-19T11:00:00Z"),
            event("tomorrow-late", date: "2026-07-20", time: "8pm", createdAt: "2026-07-19T11:00:00Z"),
            event("tomorrow-early", date: "2026-07-20", time: "8am", createdAt: "2026-07-19T11:00:00Z"),
            event("day-seven", date: "2026-07-26", time: "noon", createdAt: "2026-07-19T11:00:00Z"),
            event("fresh-newest", date: "2026-08-02", time: "5pm", createdAt: "2026-07-19T11:00:00Z"),
            event("fresh-date-late", date: "2026-07-30", time: "8pm", createdAt: "2026-07-18T12:00:00Z"),
            event("fresh-date-early", date: "2026-07-29", time: "7am", createdAt: "2026-07-18T12:00:00Z"),
            event("fresh-time-late", date: "2026-07-31", time: "8pm", createdAt: "2026-07-18T12:00:00Z"),
            event("fresh-time-early", date: "2026-07-31", time: "7am", createdAt: "2026-07-18T12:00:00Z"),
            event("fresh-tie-a", date: "2026-08-01", time: "6pm", createdAt: "2026-07-18T12:00:00Z"),
            event("fresh-tie-b", date: "2026-08-01", time: "6pm", createdAt: "2026-07-18T12:00:00Z"),
            event("fresh-exactly-seven-days", date: "2026-08-03", time: "noon", createdAt: "2026-07-12T12:00:00Z"),
            event("stale-day-eight", date: "2026-07-27", time: "8am", createdAt: "2026-07-12T11:59:59Z"),
            event("later-day-eight", date: "2026-07-27", time: "9am", createdAt: "2026-07-12T11:59:59Z"),
            event("later-tie-a", date: "2026-07-28", time: "6pm", createdAt: "2026-07-12T11:59:59Z"),
            event("later-tie-b", date: "2026-07-28", time: "6pm", createdAt: "2026-07-12T11:59:59Z"),
            event("invalid-date", date: "not-a-date", time: "10am", createdAt: "2026-07-19T11:00:00Z")
        ]

        let sections = CommunityFeedBucketer.sections(for: events, today: today, now: now)

        assert(sections.map(\.bucket) == [.thisWeek, .fresh, .later])
        assert(sections[0].events.map(\.id) == ["tomorrow-early", "tomorrow-late", "day-seven"])
        assert(sections[1].events.map(\.id) == [
            "fresh-newest",
            "fresh-date-early",
            "fresh-date-late",
            "fresh-time-early",
            "fresh-time-late",
            "fresh-tie-a",
            "fresh-tie-b",
            "fresh-exactly-seven-days"
        ])
        assert(sections[2].events.map(\.id) == ["stale-day-eight", "later-day-eight", "later-tie-a", "later-tie-b"])
    }

    private nonisolated static func event(
        _ id: String,
        date: String,
        time: String?,
        createdAt: String
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: id,
            eventDate: date,
            startTime: time,
            location: nil,
            goingCount: 0,
            createdAt: createdAt
        )
    }
}
#endif
