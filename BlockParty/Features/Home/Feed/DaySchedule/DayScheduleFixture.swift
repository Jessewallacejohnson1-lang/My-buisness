//
//  DayScheduleFixture.swift
//  Block Party — a canned Monday, for verifying the day sheet headlessly.
//
//  There is no gesture automation in this simulator setup and the sim is signed
//  out, so a screen only reachable by tapping a rail card is otherwise
//  unverifiable. `-day-sheet-preview` mounts the real sheet from these fixtures
//  with no auth and no network, exactly as `-briefing-preview` does for Today.
//
//  THE FIXTURES MIRROR THE SCHEMA AS IT ACTUALLY IS: every row has `endAt == nil`
//  and no coordinates, because `club_events.end_at` does not exist yet and events
//  carry no location geometry. So the screenshots show the REAL stat-column
//  suppression — `ENDS IN`, `DURATION` and `DISTANCE` never appear, and a row
//  nobody has joined shows no stat row at all. Padding the fixture with an
//  invented `end_at` would make the screenshots a picture of a different app.
//

#if DEBUG
import Foundation

nonisolated struct DayScheduleFixture {
    let items: [DayItem]
    let anchor: DayScheduleAnchor
    let dates: any DateProviding

    /// 2026-08-10, 09:23 in town time — a Monday morning with the day underway, so
    /// the now line renders and past, present and future rows are all on screen.
    static var fixedNow: Date {
        var components = DateComponents()
        components.calendar = Town.calendar
        components.timeZone = Town.timeZone
        components.year = 2026
        components.month = 8
        components.day = 10
        components.hour = 9
        components.minute = 23
        return Town.calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// `-day-sheet-state upcoming|inprogress|completed|empty|cta`. Defaults to the
    /// whole day with nothing pre-selected.
    ///
    /// `cta` is the rail's ADD TILE opening the day — it rests on the bottom of the
    /// timeline with the "Add to today" button under it, rather than on a row.
    static func fromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments)
        -> DayScheduleFixture {
        let now = fixedNow
        let dates = FixedDateProvider(now)
        let day = items(now: now)

        guard let flag = arguments.firstIndex(of: "-day-sheet-state"),
              flag + 1 < arguments.count
        else {
            return DayScheduleFixture(items: day, anchor: .top, dates: dates)
        }

        switch arguments[flag + 1] {
        case "upcoming":
            return DayScheduleFixture(items: day, anchor: .item("fixture-trivia"), dates: dates)
        case "inprogress":
            return DayScheduleFixture(items: day, anchor: .item("fixture-story"), dates: dates)
        case "completed":
            return DayScheduleFixture(items: day, anchor: .item("fixture-walk"), dates: dates)
        case "cta":
            return DayScheduleFixture(items: day, anchor: .callToAction, dates: dates)
        case "empty":
            return DayScheduleFixture(items: [], anchor: .top, dates: dates)
        default:
            return DayScheduleFixture(items: day, anchor: .top, dates: dates)
        }
    }

    /// Built through the real `YourDayLogic.dayItems`, so the fixture exercises the
    /// shipped ordering, overlap and completion rules rather than a hand-made array
    /// that could disagree with them.
    static func items(now: Date) -> [DayItem] {
        YourDayLogic.dayItems(from: events(now: now), now: now)
    }

    private static func events(now: Date) -> [UpcomingEvent] {
        let today = day(now)
        return [
            event(
                id: "fixture-sale",
                title: "Sidewalk sale on College Avenue",
                date: today,
                time: nil,
                location: "College Avenue",
                going: 9,
                category: .other,
                isAllDay: true
            ),
            event(
                id: "fixture-walk",
                title: "Millstream morning walk",
                date: today,
                time: "7:00 AM",
                location: "Millstream Park",
                going: 6,
                category: .outdoors
            ),
            event(
                id: "fixture-market",
                title: "Farmers market setup",
                date: today,
                time: "8:30 AM",
                location: "College Avenue",
                going: 0,
                category: .food
            ),
            event(
                id: "fixture-story",
                title: "Toddler story time",
                date: today,
                time: "9:00 AM",
                location: "St. Joseph Public Library",
                going: 4,
                category: .families
            ),
            event(
                id: "fixture-supper",
                title: "Community supper",
                date: today,
                time: "5:30 PM",
                location: "Church of Saint Joseph",
                going: 0,
                category: .service
            ),
            event(
                id: "fixture-trivia",
                title: "Patio trivia at Local Blend",
                date: today,
                time: "6:30 PM",
                location: "Local Blend",
                going: 12,
                category: .games
            ),
        ]
    }

    private static func event(
        id: String,
        title: String,
        date: String,
        time: String?,
        location: String,
        going: Int,
        category: EventCategory,
        isAllDay: Bool = false
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: title,
            eventDate: date,
            startTime: time,
            location: location,
            goingCount: going,
            createdAt: "fixture",
            rsvpd: true,
            category: category,
            // Deliberately nil. See the file header.
            endAt: nil,
            isAllDay: isAllDay
        )
    }

    private static func day(_ date: Date) -> String { Town.day(date) }
}
#endif
