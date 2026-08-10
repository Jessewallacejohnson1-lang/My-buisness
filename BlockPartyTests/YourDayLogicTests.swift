//
//  YourDayLogicTests.swift
//  Block PartyTests — pure presentation rules for the personal Today module.
//

import Foundation
import XCTest
@testable import BlockParty

final class YourDayLogicTests: XCTestCase {
    func testCountdownWindowIncludesExactlyFortyEightHours() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(
            YourDayLogic.isWithinCountdown(
                eventStart: now.addingTimeInterval(48 * 60 * 60),
                now: now
            )
        )
        XCTAssertFalse(
            YourDayLogic.isWithinCountdown(
                eventStart: now.addingTimeInterval(48 * 60 * 60 + 1),
                now: now
            )
        )
        XCTAssertFalse(
            YourDayLogic.isWithinCountdown(
                eventStart: now.addingTimeInterval(-1),
                now: now
            )
        )
    }

    func testCountdownFormattingUsesConciseLiveUnits() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            YourDayLogic.countdownText(
                eventStart: now.addingTimeInterval(4 * 60 * 60),
                now: now
            ),
            "in 4 hrs"
        )
        XCTAssertEqual(
            YourDayLogic.countdownText(
                eventStart: now.addingTimeInterval(60 * 60),
                now: now
            ),
            "in 1 hr"
        )
        XCTAssertEqual(
            YourDayLogic.countdownText(
                eventStart: now.addingTimeInterval(35 * 60),
                now: now
            ),
            "in 35 mins"
        )
        XCTAssertNil(
            YourDayLogic.countdownText(
                eventStart: now.addingTimeInterval(49 * 60 * 60),
                now: now
            )
        )
    }

    func testSchedulePresentationKeepsInAcrossHourAndMinuteCountdowns() throws {
        let now = try townDate(year: 2033, month: 5, day: 18, hour: 15)
        let justBeforeStart = try townDate(
            year: 2033,
            month: 5,
            day: 18,
            hour: 15,
            minute: 0,
            second: 30
        )

        let cases: [(event: UpcomingEvent, now: Date, dateAndTime: String, countdown: String, label: String)] = [
            (
                sampleEvent(id: "tonight", date: "2033-05-18", time: "7:00 PM"),
                now,
                "Tonight, 7:00 PM",
                "in 4 hrs",
                "Tonight, 7:00 PM — in 4 hrs"
            ),
            (
                sampleEvent(id: "tomorrow", date: "2033-05-19", time: "9:00 PM"),
                now,
                "Tomorrow, 9:00 PM",
                "in 30 hrs",
                "Tomorrow, 9:00 PM — in 30 hrs"
            ),
            (
                sampleEvent(id: "minutes", date: "2033-05-18", time: "3:35 PM"),
                now,
                "Today, 3:35 PM",
                "in 35 mins",
                "Today, 3:35 PM — in 35 mins"
            ),
            (
                sampleEvent(id: "starting", date: "2033-05-18", time: "3:01 PM"),
                justBeforeStart,
                "Today, 3:01 PM",
                "in 1 min",
                "Today, 3:01 PM — in 1 min"
            ),
        ]

        for item in cases {
            let presentation = YourDayLogic.schedulePresentation(
                for: item.event,
                now: item.now
            )

            XCTAssertEqual(presentation.dateAndTime, item.dateAndTime)
            XCTAssertEqual(presentation.countdown, item.countdown)
            XCTAssertEqual(presentation.label, item.label)
            XCTAssertEqual(
                YourDayLogic.scheduleLabel(for: item.event, now: item.now),
                item.label
            )
        }
    }

    func testFindSomethingItemIsAlwaysLastAfterAtMostThreeEvents() {
        let events = (1...5).map { sampleEvent(id: "event-\($0)") }

        for count in 0...events.count {
            let items = YourDayLogic.stripItems(from: Array(events.prefix(count)))

            if case .findSomething? = items.last {
                // Expected: discovery is the terminal tile for every event count.
            } else {
                XCTFail("Find something must always be last")
            }
            XCTAssertEqual(items.count, min(count, 3) + 1)
        }

        let visibleEventIDs: [String] = YourDayLogic.stripItems(from: events).compactMap { item in
            guard case .event(let event) = item else { return nil }
            return event.id
        }
        XCTAssertEqual(visibleEventIDs, ["event-1", "event-2", "event-3"])
    }

    func testZeroGoingCountProducesNoRenderedLabel() {
        XCTAssertNil(YourDayLogic.goingLabel(for: 0))
        XCTAssertNil(YourDayLogic.goingLabel(for: -1))
        XCTAssertEqual(YourDayLogic.goingLabel(for: 1), "1 going")
        XCTAssertEqual(YourDayLogic.goingLabel(for: 8), "8 going")
    }

    // MARK: - Your Day: today only, town time
    //
    // Every case below is driven by an injected `FixedDateProvider`. Nothing here
    // may touch the wall clock: "did the 2pm event end yet" is only a question a
    // test can ask if the test gets to say what time it is.

    /// The shipped bug: the rail showed a festival dated Aug 30 while the device
    /// read Aug 10, because the query asked for `event_date >= today`.
    func testDayItemsExcludeEveryDayButToday() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let candidates = [
            townEvent(id: "future-festival", date: "2026-08-30", time: "11 AM"),
            townEvent(id: "tomorrow", date: "2026-08-11", time: "9:00 AM"),
            townEvent(id: "yesterday", date: "2026-08-09", time: "9:00 AM"),
            townEvent(id: "last-month", date: "2026-07-10", time: "9:00 AM"),
        ]

        XCTAssertEqual(YourDayLogic.dayItems(from: candidates, now: clock.now), [])
    }

    func testEmptyCandidateListProducesAnEmptyDay() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        XCTAssertEqual(YourDayLogic.dayItems(from: [], now: clock.now), [])
        XCTAssertEqual(
            YourDayLogic.dayItems(committed: [], wholeTown: [], now: clock.now),
            []
        )
    }

    func testSingleItemDayCarriesItsLaneAndStartTime() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [townEvent(id: "supper", date: "2026-08-10", time: "6:30 PM", rsvpd: true)],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item.id, "supper")
        XCTAssertEqual(item.source, .committed)
        XCTAssertEqual(item.eyebrow, "6:30 PM")
        XCTAssertFalse(item.isAllDay)
        XCTAssertFalse(item.isMultiDay)
        XCTAssertFalse(item.isComplete)
    }

    func testThreeItemDayOrdersByStartAscending() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 6))

        let items = YourDayLogic.dayItems(
            from: [
                townEvent(id: "evening", date: "2026-08-10", time: "7:00 PM"),
                townEvent(id: "morning", date: "2026-08-10", time: "8:00 AM"),
                townEvent(id: "midday", date: "2026-08-10", time: "noon"),
            ],
            now: clock.now
        )

        XCTAssertEqual(items.map(\.id), ["morning", "midday", "evening"])
        XCTAssertEqual(items.map(\.eyebrow), ["8:00 AM", "12:00 PM", "7:00 PM"])
    }

    func testSevenItemDayKeepsEveryItemInStartOrder() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 5))
        let times = ["7:00 AM", "8:30 AM", "10:00 AM", "noon", "2:15 PM", "5:45 PM", "9:00 PM"]

        // Shuffled deterministically by reversing: order must come from the rule,
        // not from the order the rows happened to arrive in.
        let candidates = times.enumerated().reversed().map { index, time in
            townEvent(id: "slot-\(index)", date: "2026-08-10", time: time)
        }

        let items = YourDayLogic.dayItems(from: candidates, now: clock.now)

        XCTAssertEqual(items.count, 7)
        XCTAssertEqual(items.map(\.id), (0..<7).map { "slot-\($0)" })
        XCTAssertEqual(items.map(\.start), items.map(\.start).sorted())
    }

    func testAllDayItemSortsFirstAndShowsNoStartTime() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [
                townEvent(id: "early-bird", date: "2026-08-10", time: "6:00 AM"),
                townEvent(id: "garage-sale", date: "2026-08-10", time: nil, isAllDay: true),
            ],
            now: clock.now
        )

        XCTAssertEqual(items.map(\.id), ["garage-sale", "early-bird"])

        let allDay = try XCTUnwrap(items.first)
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertEqual(allDay.eyebrow, "Today · all day")
        XCTAssertFalse(allDay.eyebrow.contains(":"), "An all-day item must show no clock time")
        // Still running: an all-day item is done only when its day is.
        XCTAssertFalse(allDay.isComplete)
    }

    func testMultiDayItemSpanningTodayReadsOngoing() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let endsTomorrow = try townDate(year: 2026, month: 8, day: 11, hour: 18)

        let items = YourDayLogic.dayItems(
            from: [
                townEvent(
                    id: "millstream",
                    date: "2026-08-08",
                    time: "11 AM",
                    endAt: endsTomorrow
                )
            ],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(item.isMultiDay)
        XCTAssertEqual(item.eyebrow, "Today · ongoing")
        XCTAssertFalse(item.isComplete)
    }

    func testMultiDayItemThatFinishedBeforeTodayIsExcluded() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let endedYesterday = try townDate(year: 2026, month: 8, day: 9, hour: 20)

        let items = YourDayLogic.dayItems(
            from: [
                townEvent(id: "over", date: "2026-08-07", time: "11 AM", endAt: endedYesterday)
            ],
            now: clock.now
        )

        XCTAssertEqual(items, [])
    }

    func testItemThatEndedTwoHoursAgoIsComplete() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 14))
        let statedEnd = try townDate(year: 2026, month: 8, day: 10, hour: 12)

        // No end_at: the assumed two-hour duration (the same window that keeps a
        // map pin pulsing) has elapsed since the 10 AM start.
        let assumed = YourDayLogic.dayItems(
            from: [townEvent(id: "assumed", date: "2026-08-10", time: "10:00 AM")],
            now: clock.now
        )
        XCTAssertTrue(try XCTUnwrap(assumed.first).isComplete)

        // With a stated end_at, the row's own word wins.
        let stated = YourDayLogic.dayItems(
            from: [
                townEvent(id: "stated", date: "2026-08-10", time: "8:00 AM", endAt: statedEnd)
            ],
            now: clock.now
        )
        XCTAssertTrue(try XCTUnwrap(stated.first).isComplete)

        // A stated end still ahead of us is not complete, even though the assumed
        // two hours would already have run out.
        let longRun = try townDate(year: 2026, month: 8, day: 10, hour: 17)
        let running = YourDayLogic.dayItems(
            from: [
                townEvent(id: "running", date: "2026-08-10", time: "8:00 AM", endAt: longRun)
            ],
            now: clock.now
        )
        XCTAssertFalse(try XCTUnwrap(running.first).isComplete)
    }

    func testItemStartingInTenMinutesIsNotComplete() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [townEvent(id: "soon", date: "2026-08-10", time: "9:10 AM", rsvpd: true)],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertFalse(item.isComplete)
        XCTAssertEqual(item.start.timeIntervalSince(clock.now), 10 * 60)
        XCTAssertEqual(item.eyebrow, "9:10 AM")
    }

    func testItemAtElevenFiftyNinePmIsStillToday() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [
                townEvent(id: "last-minute", date: "2026-08-10", time: "11:59 PM"),
                // Midnight belongs to tomorrow — the interval is half-open.
                townEvent(id: "midnight-tomorrow", date: "2026-08-11", time: "12:00 AM"),
            ],
            now: clock.now
        )

        XCTAssertEqual(items.map(\.id), ["last-minute"])
        XCTAssertEqual(try XCTUnwrap(items.first).eyebrow, "11:59 PM")
    }

    func testUnparseableStartTimeKeepsTheOrganizersWordsAndSortsLast() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [
                townEvent(id: "prose", date: "2026-08-10", time: "after dark"),
                townEvent(id: "timed", date: "2026-08-10", time: "8:00 PM"),
            ],
            now: clock.now
        )

        XCTAssertEqual(items.map(\.id), ["timed", "prose"])
        XCTAssertEqual(items.last?.eyebrow, "after dark")
    }

    /// America/Chicago springs forward on 2026-03-08 (a 23-hour day) and falls
    /// back on 2026-11-01 (25 hours). Both must still be exactly one town day, and
    /// an 11 AM event must still read 11 AM.
    func testDaylightSavingBoundaryDaysStayOneTownDay() throws {
        let springForward = FixedDateProvider(
            try townDate(year: 2026, month: 3, day: 8, hour: 9)
        )
        let fallBack = FixedDateProvider(
            try townDate(year: 2026, month: 11, day: 1, hour: 9)
        )

        let spring = YourDayLogic.todayInterval(now: springForward.now)
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 60 * 60)

        let fall = YourDayLogic.todayInterval(now: fallBack.now)
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 25 * 60 * 60)

        // The wall-clock time the organizer typed survives the transition: adding
        // 660 absolute minutes to a spring-forward midnight would land at noon.
        let items = YourDayLogic.dayItems(
            from: [
                townEvent(id: "brunch", date: "2026-03-08", time: "11 AM"),
                townEvent(id: "closing", date: "2026-03-08", time: "11:59 PM"),
            ],
            now: springForward.now
        )

        XCTAssertEqual(items.map(\.id), ["brunch", "closing"])
        XCTAssertEqual(items.map(\.eyebrow), ["11:00 AM", "11:59 PM"])
        XCTAssertEqual(
            Town.calendar.component(.hour, from: try XCTUnwrap(items.first).start),
            11
        )
    }

    func testMergeKeepsBothLanesAndMarksWhichIsWhich() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 7))

        let items = YourDayLogic.dayItems(
            committed: [townEvent(id: "my-trivia", date: "2026-08-10", time: "7:00 PM", rsvpd: true)],
            wholeTown: [townEvent(id: "town-supper", date: "2026-08-10", time: "5:00 PM")],
            now: clock.now
        )

        XCTAssertEqual(items.map(\.id), ["town-supper", "my-trivia"])
        XCTAssertEqual(items.map(\.source), [.wholeTown, .committed])
    }

    func testRsvpToATownWideEventAppearsOnceAsCommitted() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 7))
        let shared = townEvent(id: "block-party", date: "2026-08-10", time: "4:00 PM", rsvpd: true)

        let merged = YourDayLogic.dayItems(
            committed: [shared],
            wholeTown: [
                shared,
                townEvent(id: "other", date: "2026-08-10", time: "6:00 PM"),
            ],
            now: clock.now
        )

        XCTAssertEqual(merged.map(\.id), ["block-party", "other"])
        XCTAssertEqual(merged.map(\.source), [.committed, .wholeTown])
        XCTAssertEqual(merged.filter { $0.id == "block-party" }.count, 1)

        // The same truth via the single-list entry point, which splits the lanes
        // off the viewer's own RSVP state.
        let split = YourDayLogic.dayItems(
            from: [shared, townEvent(id: "other", date: "2026-08-10", time: "6:00 PM")],
            now: clock.now
        )
        XCTAssertEqual(split.map(\.id), ["block-party", "other"])
        XCTAssertEqual(split.map(\.source), [.committed, .wholeTown])
    }

    func testMissingEndTimeDegradesToTheStartInstant() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [townEvent(id: "no-end", date: "2026-08-10", time: "11 AM")],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertNil(item.end, "A missing end_at must never be filled in with a guess")
        XCTAssertFalse(item.isMultiDay)
    }

    func testFixedClockDoesNotMoveBetweenReads() throws {
        let instant = try townDate(year: 2026, month: 8, day: 10, hour: 9)
        let clock = FixedDateProvider(instant)

        XCTAssertEqual(clock.now, instant)
        XCTAssertEqual(clock.now, clock.now)
    }

    // MARK: - Fixtures

    private func townEvent(
        id: String,
        date: String,
        time: String?,
        rsvpd: Bool = false,
        isAllDay: Bool = false,
        endAt: Date? = nil,
        goingCount: Int = 0
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: "Event \(id)",
            eventDate: date,
            startTime: time,
            location: "Downtown",
            goingCount: goingCount,
            createdAt: "2026-08-01T12:00:00Z",
            rsvpd: rsvpd,
            endAt: endAt,
            isAllDay: isAllDay
        )
    }

    private func sampleEvent(
        id: String,
        date: String = "2033-05-18",
        time: String = "7:00 PM"
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: "Neighborhood walk",
            eventDate: date,
            startTime: time,
            location: "Downtown",
            goingCount: 0,
            createdAt: "2033-05-01T12:00:00Z"
        )
    }

    private func townDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = Town.calendar
        components.timeZone = Town.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return try XCTUnwrap(Town.calendar.date(from: components))
    }
}
