//
//  YourDayRailDebug.swift
//  Block Party — headless fixtures for the Your Day rail's item-count states.
//
//  There is no scroll or tap automation in this simulator setup, so the only way
//  to see the 0 / 1 / 3 / 7-item states is to launch straight into them. These are
//  clearly-marked fake rows run through the REAL today/merge/sort rules
//  (`YourDayLogic.dayItems`), so a screenshot shows the shipping logic rather than
//  a hand-arranged array.
//
//  DEBUG only — the whole file compiles out of Release.
//

#if DEBUG
import Foundation

@MainActor
enum YourDayRailDebug {
    /// `-yourday-count <n>` — build a rail of exactly n items. 0 is legal and lands
    /// on the empty card.
    static func requestedCount(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Int? {
        guard let flag = arguments.firstIndex(of: "-yourday-count"),
              flag + 1 < arguments.count,
              let count = Int(arguments[flag + 1]),
              count >= 0
        else { return nil }
        return min(count, pool.count)
    }

    static func items(count: Int, now: Date) -> [DayItem] {
        guard count > 0 else { return [] }
        let events = pool.prefix(count).map { $0.event(now: now) }
        return YourDayLogic.dayItems(from: events, now: now)
    }

    /// The one-item state's suggestion. Deliberately NOT drawn from `pool`, so it
    /// cannot collide with a rendered card's id or matched-geometry namespace.
    static func suggestion(now: Date) -> DayItem? {
        let event = UpcomingEvent(
            id: "yourday-debug-suggestion",
            title: "Bonfire down at the mill",
            eventDate: Town.day(now),
            startTime: "8:00 PM",
            location: "Millstream Park",
            goingCount: 3,
            createdAt: "debug",
            rsvpd: false,
            category: .outdoors
        )
        return YourDayLogic.dayItem(for: event, source: .wholeTown, now: now)
    }

    /// The empty card's count. A fixed number is fine HERE because the flag exists
    /// to photograph the state — production passes what it actually knows.
    static let townCount = 4

    // MARK: - The pool

    private struct Fixture {
        let id: String
        let title: String
        let time: String?
        let location: String
        let category: EventCategory
        let rsvpd: Bool
        var isAllDay = false
        /// Minutes before `now`. Forces `isComplete` regardless of what o'clock the
        /// screenshot is taken at — the assumed-two-hour rule alone would make the
        /// completed treatment appear only after mid-morning.
        var endedMinutesAgo: Int?

        func event(now: Date) -> UpcomingEvent {
            UpcomingEvent(
                id: id,
                title: title,
                eventDate: Town.day(now),
                startTime: time,
                location: location,
                goingCount: 0,
                createdAt: "debug",
                rsvpd: rsvpd,
                category: category,
                endAt: endedMinutesAgo.map { now.addingTimeInterval(TimeInterval(-$0 * 60)) },
                isAllDay: isAllDay
            )
        }
    }

    /// Ordered so that each prefix is a believable day: the first card is a real
    /// commitment, the second is the town's, and the categories fan across the
    /// gradient system so a screenshot exercises the colour set rather than one hue.
    private static let pool: [Fixture] = [
        Fixture(
            id: "yourday-debug-market",
            title: "Farmers market",
            time: "8:00 AM",
            location: "Resurrection lot",
            category: .food,
            rsvpd: true,
            endedMinutesAgo: 60
        ),
        Fixture(
            id: "yourday-debug-festival",
            title: "Millstream Arts Festival",
            time: "11 AM",
            location: "Millstream Park",
            category: .musicArts,
            rsvpd: false
        ),
        Fixture(
            id: "yourday-debug-trivia",
            title: "Patio trivia at Local Blend",
            time: "7:00 PM",
            location: "Local Blend",
            category: .games,
            rsvpd: true
        ),
        Fixture(
            id: "yourday-debug-garagesale",
            title: "Town-wide garage sale",
            time: nil,
            location: "All over St. Joe",
            category: .other,
            rsvpd: false,
            isAllDay: true
        ),
        Fixture(
            id: "yourday-debug-cleanup",
            title: "River trail cleanup",
            time: "9:00 AM",
            location: "Wobegon trailhead",
            category: .service,
            rsvpd: false
        ),
        Fixture(
            id: "yourday-debug-soccer",
            title: "Pickup soccer",
            time: "5:30 PM",
            location: "Klinefelter Park",
            category: .sports,
            rsvpd: true
        ),
        Fixture(
            id: "yourday-debug-storyhour",
            title: "Story hour at the library",
            time: "10:30 AM",
            location: "St. Joseph Public Library",
            category: .books,
            rsvpd: false
        ),
    ]
}
#endif
