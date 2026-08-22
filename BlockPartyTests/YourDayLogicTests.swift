//
//  YourDayLogicTests.swift
//  Block PartyTests — pure presentation rules for the personal Today module.
//

import Foundation
import SwiftUI
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

    // MARK: - Realtime relevance

    /// A fixed May instant, safely away from any DST boundary, so ±day math
    /// lands on the expected town dates.
    private static let realtimeNow = Date(timeIntervalSince1970: 2_000_000_000)

    @MainActor
    private func change(
        _ kind: RealtimeClient.Change.Kind,
        new: RealtimeClient.Change.Row? = nil,
        old: RealtimeClient.Change.Row? = nil
    ) -> RealtimeClient.Change {
        RealtimeClient.Change(kind: kind, new: new, old: old)
    }

    @MainActor
    private func row(
        id: String = "e1", date: String?, kind: String? = "event"
    ) -> RealtimeClient.Change.Row {
        RealtimeClient.Change.Row(
            id: id, eventDate: date, startTime: nil, status: "approved",
            kind: kind, title: nil, location: nil
        )
    }

    @MainActor
    func testInsertRelevanceMatchesTheCandidateWindow() {
        let now = Self.realtimeNow
        let today = Town.day(now)
        let withinLookback = Town.day(now.addingTimeInterval(-3 * 86_400))
        let tomorrow = Town.day(now.addingTimeInterval(86_400))
        let beyondLookback = Town.day(
            now.addingTimeInterval(-Double(CommunityAPI.dayLookbackDays + 1) * 86_400)
        )

        func relevant(_ c: RealtimeClient.Change) -> Bool {
            YourDayLogic.changeIsRelevant(c, shownIDs: [], now: now)
        }

        XCTAssertTrue(relevant(change(.insert, new: row(date: today))))
        // A multi-day row dated within the lookback can still overlap today.
        XCTAssertTrue(relevant(change(.insert, new: row(date: withinLookback))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: tomorrow))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: beyondLookback))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: today, kind: "trail"))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: nil))))
    }

    @MainActor
    func testUpdateIsRelevantWhenItTouchesTheWindowOrAShownItem() {
        let now = Self.realtimeNow
        let tomorrow = Town.day(now.addingTimeInterval(86_400))

        // An edit that moves a shown event OFF today must still re-sync,
        // matched by id — the new row itself no longer touches the window.
        XCTAssertTrue(YourDayLogic.changeIsRelevant(
            change(.update, new: row(id: "shown", date: tomorrow)),
            shownIDs: ["shown"], now: now
        ))
        XCTAssertFalse(YourDayLogic.changeIsRelevant(
            change(.update, new: row(id: "other", date: tomorrow)),
            shownIDs: ["shown"], now: now
        ))
        // The approval UPDATE of a pending event counts — status is not checked.
        XCTAssertTrue(YourDayLogic.changeIsRelevant(
            change(.update, new: row(id: "new", date: Town.day(now))),
            shownIDs: [], now: now
        ))
    }

    @MainActor
    func testDeleteMatchesByShownIdOnly() {
        let now = Self.realtimeNow
        // A DELETE's old_record carries only the primary key.
        XCTAssertTrue(YourDayLogic.changeIsRelevant(
            change(.delete, old: row(id: "shown", date: nil, kind: nil)),
            shownIDs: ["shown"], now: now
        ))
        XCTAssertFalse(YourDayLogic.changeIsRelevant(
            change(.delete, old: row(id: "gone-long-ago", date: nil, kind: nil)),
            shownIDs: ["shown"], now: now
        ))
        XCTAssertFalse(YourDayLogic.changeIsRelevant(
            change(.delete),
            shownIDs: ["shown"], now: now
        ))
    }
}

/// The Your Day RAIL's pure layer — copy, spoken text, the category colour map and
/// the two numbers the 116pt ceiling depends on.
///
/// Deliberately appended to this already-registered file rather than added as a new
/// one: the test target uses an EXPLICIT source list, so a new file is invisible to
/// `xcodebuild test` until `project.pbxproj` is edited — and `project.pbxproj` is the
/// likeliest file in the repo to collide with a parallel agent's work.
final class YourDayRailSpecTests: XCTestCase {

    // MARK: - The count in the section header

    func testCountLabelIsOmittedEntirelyAtZero() {
        XCTAssertNil(YourDayRailCopy.countLabel(0))
    }

    func testCountLabelIsSingularForOneAndPluralAbove() {
        XCTAssertEqual(YourDayRailCopy.countLabel(1), "1 thing")
        XCTAssertEqual(YourDayRailCopy.countLabel(3), "3 things")
        XCTAssertEqual(YourDayRailCopy.countLabel(7), "7 things")
    }

    // MARK: - The empty card never invents a number

    func testEmptyMetaDropsTheNumberWhenTheCountIsUnknown() {
        XCTAssertEqual(
            YourDayRailCopy.emptyMeta(townCount: nil),
            "See what’s happening in St. Joe →"
        )
    }

    func testEmptyMetaDropsTheNumberRatherThanSayingZero() {
        XCTAssertEqual(
            YourDayRailCopy.emptyMeta(townCount: 0),
            "See what’s happening in St. Joe →"
        )
    }

    func testEmptyMetaCountsRealThings() {
        XCTAssertEqual(
            YourDayRailCopy.emptyMeta(townCount: 1),
            "1 thing happening in St. Joe →"
        )
        XCTAssertEqual(
            YourDayRailCopy.emptyMeta(townCount: 4),
            "4 things happening in St. Joe →"
        )
    }

    // MARK: - One card, one accessibility element

    func testCommittedCardReadsWhenTitleCategoryPlaceAndCompletion() {
        let item = makeItem(
            eyebrow: "11 AM",
            title: "Farmers market",
            category: .food,
            location: "Resurrection lot",
            source: .committed,
            isComplete: false
        )

        XCTAssertEqual(
            YourDayRailAccessibility.label(for: item),
            "11 AM, Farmers market, Food & drink, Resurrection lot, not completed"
        )
    }

    func testWholeTownCardSaysSoOutLoud() {
        let item = makeItem(source: .wholeTown)

        XCTAssertTrue(
            YourDayRailAccessibility.label(for: item).contains("on the town calendar"),
            "A town-calendar item must not be spoken as a personal plan."
        )
    }

    func testCommittedCardDoesNotClaimTheTownCalendar() {
        let item = makeItem(source: .committed)

        XCTAssertFalse(
            YourDayRailAccessibility.label(for: item).contains("on the town calendar")
        )
    }

    func testCompletedCardSaysCompleted() {
        let item = makeItem(isComplete: true)

        XCTAssertTrue(YourDayRailAccessibility.label(for: item).hasSuffix(", completed"))
    }

    func testBlankLocationIsSkippedRatherThanSpokenAsAnEmptyGap() {
        let blank = makeItem(location: "   ")
        let missing = makeItem(location: nil)

        for label in [
            YourDayRailAccessibility.label(for: blank),
            YourDayRailAccessibility.label(for: missing),
        ] {
            XCTAssertFalse(label.contains(", ,"))
            XCTAssertEqual(label, "11 AM, Farmers market, Food & drink, not completed")
        }
    }

    func testRailAnnouncesItsCount() {
        XCTAssertEqual(YourDayRailAccessibility.railLabel(count: 3), "Your day, 3 things")
        XCTAssertEqual(YourDayRailAccessibility.railLabel(count: 1), "Your day, 1 thing")
        XCTAssertEqual(
            YourDayRailAccessibility.railLabel(count: 0),
            "Your day, nothing planned"
        )
    }

    // MARK: - Dynamic Type may not grow the card

    func testTitleGivesUpItsSecondLineBeforeTheCardGivesUpItsCeiling() {
        XCTAssertEqual(YourDayRailMetrics.titleLineLimit(for: .large), 2)
        XCTAssertEqual(YourDayRailMetrics.titleLineLimit(for: .xLarge), 2)
        XCTAssertEqual(YourDayRailMetrics.titleLineLimit(for: .xxLarge), 1)
        XCTAssertEqual(YourDayRailMetrics.titleLineLimit(for: .accessibility5), 1)
    }

    func testTheCardCeilingIsTheOneTheRebuildPromised() {
        // 208 -> 116. If this number moves, the phase's whole point moved with it.
        XCTAssertEqual(YourDayRailMetrics.cardHeight, 116)
        XCTAssertEqual(YourDayRailMetrics.cardWidth, 236)
        XCTAssertEqual(YourDayRailMetrics.addTileWidth, 100)
    }

    // MARK: - Category colour is a system, not a per-view choice

    func testEveryCategoryResolvesToAGradientAndUncategorisedReadsAsATownEvent() {
        // Today EVERY live row is `.other`, so this mapping is what the app
        // actually looks like until categories are backfilled.
        XCTAssertEqual(CategoryGradient.of(.other), .eventsFestivals)
        XCTAssertEqual(CategoryGradient.of(.outdoors), .outdoorsTrails)
        XCTAssertEqual(CategoryGradient.of(.sports), .outdoorsTrails)
        XCTAssertEqual(CategoryGradient.of(.musicArts), .eventsFestivals)
        XCTAssertEqual(CategoryGradient.of(.food), .foodDrink)
        XCTAssertEqual(CategoryGradient.of(.families), .clubsGroups)
        XCTAssertEqual(CategoryGradient.of(.books), .clubsGroups)
        XCTAssertEqual(CategoryGradient.of(.games), .clubsGroups)
        XCTAssertEqual(CategoryGradient.of(.faith), .civicTown)
        XCTAssertEqual(CategoryGradient.of(.service), .civicTown)
    }

    func testTheSameCategoryAlwaysResolvesToTheSameTwoStops() {
        for category in EventCategory.allCases {
            XCTAssertEqual(
                CategoryGradient.of(category),
                CategoryGradient.of(category),
                "Category colour must be stable — it is a system, not decoration."
            )
        }
    }

    // MARK: - Helper

    private func makeItem(
        eyebrow: String = "11 AM",
        title: String = "Farmers market",
        category: EventCategory = .food,
        location: String? = nil,
        source: DayItemSource = .committed,
        isComplete: Bool = false
    ) -> DayItem {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        return DayItem(
            id: "test-\(title)-\(source.rawValue)",
            title: title,
            source: source,
            start: start,
            end: nil,
            isAllDay: false,
            isMultiDay: false,
            isComplete: isComplete,
            eyebrow: eyebrow,
            location: location,
            goingCount: 0,
            event: UpcomingEvent(
                id: "test-event",
                title: title,
                eventDate: "2033-05-18",
                startTime: "11 AM",
                location: location,
                goingCount: 0,
                createdAt: "test",
                category: category
            )
        )
    }
}

// MARK: - Horizon card copy: plain words, Apple hierarchy
//
// Appended to this registered file for the same pbxproj reason as
// YourDayRailSpecTests above.

final class HorizonCopyTests: XCTestCase {
    func testPrimaryLineCountsPlansInPlainWords() {
        XCTAssertEqual(HorizonCopy.primaryLine(yours: 5, open: 11), "5 plans today")
        XCTAssertEqual(HorizonCopy.primaryLine(yours: 1, open: 0), "1 plan today")
    }

    func testZeroYoursWithOpenReadsNothingPlannedYet() {
        XCTAssertEqual(HorizonCopy.primaryLine(yours: 0, open: 11), "Nothing planned yet")
    }

    func testBothZeroKeepsTheNothingPostedLineAlone() {
        XCTAssertEqual(
            HorizonCopy.primaryLine(yours: 0, open: 0), "Nothing posted for today yet.")
        XCTAssertNil(HorizonCopy.secondaryLine(open: 0))
    }

    func testSecondaryLineCountsTheTownAndVanishesAtZero() {
        XCTAssertEqual(HorizonCopy.secondaryLine(open: 11), "11 more around town")
        XCTAssertEqual(HorizonCopy.secondaryLine(open: 1), "1 more around town")
        XCTAssertNil(HorizonCopy.secondaryLine(open: 0))
    }

    func testCardAccessibilityLabelMirrorsTheVisibleWording() {
        // No "Your day" prefix: the section header is its own VoiceOver
        // element and already says it — the prefix made the swipe order
        // read "Your day → Your day, 5 plans…" (review finding).
        XCTAssertEqual(
            HorizonCopy.cardAccessibilityLabel(yours: 5, open: 11),
            "5 plans today, 11 more around town."
        )
        XCTAssertEqual(
            HorizonCopy.cardAccessibilityLabel(yours: 0, open: 0),
            "Nothing posted for today yet."
        )
        XCTAssertFalse(
            HorizonCopy.cardAccessibilityLabel(yours: 3, open: 2)
                .contains(YourDayRailCopy.header),
            "the header speaks its own name; the card must not repeat it"
        )
    }

    func testSeeAllLinkNamesTheCountAndVanishesAtZero() {
        XCTAssertEqual(HorizonCopy.seeAllLink(16), "See all 16 ›")
        XCTAssertEqual(HorizonCopy.seeAllLink(1), "See all 1 ›")
        XCTAssertNil(HorizonCopy.seeAllLink(0), "no postings, nothing to link")
        XCTAssertEqual(
            HorizonCopy.seeAllLinkAccessibilityLabel(16),
            "See all 16 of today's postings"
        )
    }

    func testScrubAccessibilityValueSpeaksTimeThenNearestEvent() {
        XCTAssertEqual(
            HorizonCopy.scrubAccessibilityValue(
                time: "2:30 PM", nearestTitle: "Farmers market", nearestTime: "3 PM"),
            "2:30 PM. Nearest: Farmers market at 3 PM")
        // An empty day speaks the time alone.
        XCTAssertEqual(
            HorizonCopy.scrubAccessibilityValue(
                time: "2:30 PM", nearestTitle: nil, nearestTime: nil),
            "2:30 PM")
    }

    func testScrubbingHintReplacesTheDoorThatWentQuiet() {
        // Mid-session the card's tap deliberately does nothing, so the
        // resting hint's promise ("Opens your day schedule") must not
        // stand while scrubbing — the live hint teaches the steps and
        // the escape way out instead.
        XCTAssertNotEqual(
            HorizonCopy.scrubbingAccessibilityHint, HorizonCopy.cardAccessibilityHint)
        XCTAssertTrue(HorizonCopy.scrubbingAccessibilityHint.contains("two fingers"))
        XCTAssertFalse(HorizonCopy.scrubbingAccessibilityHint.contains("!"))
    }

    func testVoiceHasNoExclamationMarksAnywhere() {
        for text in [
            HorizonCopy.primaryLine(yours: 5, open: 11),
            HorizonCopy.primaryLine(yours: 0, open: 11),
            HorizonCopy.primaryLine(yours: 0, open: 0),
            HorizonCopy.secondaryLine(open: 11) ?? "",
            HorizonCopy.cardAccessibilityLabel(yours: 3, open: 2),
        ] {
            XCTAssertFalse(text.contains("!"))
            XCTAssertFalse(text.lowercased().contains("hygge"))
        }
    }
}

// MARK: - end_at and all_day, now that the columns exist
//
// The migration landed; the BACKFILL did not. So the two halves below matter
// equally: with the fields, the eyebrow and the duration columns light up; without
// them — which is every live row today — nothing appears that was not there before.

final class YourDayEndAtTests: XCTestCase {

    /// The shipping case. No `end_at`, so the eyebrow is a bare start time and
    /// nothing invents a length from the two-hour completion assumption.
    func testWithoutAStatedEndTheEyebrowIsJustTheStartTime() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))

        let items = YourDayLogic.dayItems(
            from: [event(id: "market", date: "2026-08-10", time: "11 AM")],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.eyebrow, "11:00 AM")
        XCTAssertNil(item.end)
        XCTAssertFalse(item.eyebrow.contains("·"))
        XCTAssertFalse(item.eyebrow.contains("hr"))
    }

    func testAStatedEndPutsTheDurationInTheEyebrow() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let end = try townDate(year: 2026, month: 8, day: 10, hour: 13)

        let items = YourDayLogic.dayItems(
            from: [event(id: "market", date: "2026-08-10", time: "11 AM", endAt: end)],
            now: clock.now
        )

        XCTAssertEqual(try XCTUnwrap(items.first).eyebrow, "11:00 AM · 2 hr")
    }

    /// The two structural eyebrows say what they are, not how long they run — an
    /// all-day item's "length" is the day, and a festival's is not today's news.
    func testTheStructuralEyebrowsNeverGrowADuration() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let endsTonight = try townDate(year: 2026, month: 8, day: 10, hour: 22)
        let endsTomorrow = try townDate(year: 2026, month: 8, day: 11, hour: 18)

        let allDay = YourDayLogic.dayItems(
            from: [
                event(
                    id: "garage-sale", date: "2026-08-10", time: nil,
                    isAllDay: true, endAt: endsTonight
                )
            ],
            now: clock.now
        )
        XCTAssertEqual(try XCTUnwrap(allDay.first).eyebrow, "Today · all day")

        let ongoing = YourDayLogic.dayItems(
            from: [
                event(id: "millstream", date: "2026-08-08", time: "11 AM", endAt: endsTomorrow)
            ],
            now: clock.now
        )
        XCTAssertEqual(try XCTUnwrap(ongoing.first).eyebrow, "Today · ongoing")
    }

    /// all_day still sorts first and still shows no clock time, with an end stated.
    func testAnAllDayItemWithAStatedEndStillSortsFirstAndShowsNoStartTime() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let end = try townDate(year: 2026, month: 8, day: 10, hour: 20)

        let items = YourDayLogic.dayItems(
            from: [
                event(id: "early-bird", date: "2026-08-10", time: "6:00 AM"),
                event(
                    id: "garage-sale", date: "2026-08-10", time: nil,
                    isAllDay: true, endAt: end
                ),
            ],
            now: clock.now
        )

        XCTAssertEqual(items.map(\.id), ["garage-sale", "early-bird"])
        XCTAssertFalse(try XCTUnwrap(items.first).eyebrow.contains(":"))
    }

    /// The way a person says a length of time. `10.6 hr` shipped to the day sheet's
    /// DURATION column and nobody says "ten point six hours".
    func testDurationTextReadsAsHoursAndMinutesNotADecimal() throws {
        let start = try townDate(year: 2026, month: 8, day: 10, hour: 9)

        func text(minutes: Double) -> String? {
            YourDayLogic.durationText(start: start, end: start.addingTimeInterval(minutes * 60))
        }

        // Sub-hour: minutes alone, no leading "0 hr".
        XCTAssertEqual(text(minutes: 45), "45 min")
        XCTAssertEqual(text(minutes: 1), "1 min")

        // Exact hours: no trailing "0 min".
        XCTAssertEqual(text(minutes: 60), "1 hr")
        XCTAssertEqual(text(minutes: 120), "2 hr")

        // Hours with minutes — both clauses, including the case that started this.
        XCTAssertEqual(text(minutes: 65), "1 hr 5 min")
        XCTAssertEqual(text(minutes: 90), "1 hr 30 min")
        XCTAssertEqual(text(minutes: 636), "10 hr 36 min", "The 10.6 hr that shipped")
    }

    /// Rounding happens ONCE, to the nearest minute, before anything is worded — so
    /// a hair under an hour reads `1 hr`, never `0 hr 60 min`.
    func testDurationTextRoundsToTheNearestMinuteBeforeWordingIt() throws {
        let start = try townDate(year: 2026, month: 8, day: 10, hour: 9)

        XCTAssertEqual(
            YourDayLogic.durationText(start: start, end: start.addingTimeInterval(59 * 60 + 40)),
            "1 hr"
        )
        XCTAssertEqual(
            YourDayLogic.durationText(start: start, end: start.addingTimeInterval(59 * 60 + 20)),
            "59 min"
        )
        XCTAssertEqual(
            YourDayLogic.durationText(start: start, end: start.addingTimeInterval(119 * 60 + 40)),
            "2 hr"
        )
    }

    /// The suppression path, which is still the COMMON path: every live
    /// `club_events` row leaves `end_at` NULL. No end is no duration, ever — never
    /// the assumed two hours, never a zero, never a negative.
    func testDurationTextRefusesNonsenseAndStaysSilentWithoutAnEnd() throws {
        let start = try townDate(year: 2026, month: 8, day: 10, hour: 9)

        XCTAssertNil(
            YourDayLogic.durationText(start: start, end: nil),
            "No end_at is no duration — never the assumed two hours"
        )
        XCTAssertNil(
            YourDayLogic.durationText(start: start, end: start),
            "A zero-length event is bad data, not a 0 min label"
        )
        XCTAssertNil(
            YourDayLogic.durationText(start: start, end: start.addingTimeInterval(-3600))
        )
        XCTAssertNil(
            YourDayLogic.durationText(start: start, end: start.addingTimeInterval(20)),
            "Twenty seconds rounds to zero minutes, which is not a duration"
        )
    }

    /// A NULL `end_at` must leave the eyebrow and the DURATION column exactly as
    /// they were before the column existed: a bare clock time, and no stat.
    func testANullEndAtStillProducesNoDurationClauseAnywhere() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let items = YourDayLogic.dayItems(
            from: [event(id: "no-end", date: "2026-08-10", time: "11:00 AM")],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.eyebrow, "11:00 AM")
        XCTAssertNil(DayScheduleLogic.duration(item))
        XCTAssertEqual(
            DayScheduleLogic.stats(for: item, state: .completed, now: clock.now).map(\.label),
            ["WENT"],
            "No end, no DURATION column — and no dash where it would have been"
        )
    }

    /// The eyebrow and the stat column are one function, so a long event says the
    /// same words in both places.
    func testTheEyebrowCarriesTheSameHoursAndMinutesAsTheDurationColumn() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 9))
        let end = try townDate(year: 2026, month: 8, day: 10, hour: 21, minute: 36)

        let items = YourDayLogic.dayItems(
            from: [event(id: "long-day", date: "2026-08-10", time: "11:00 AM", endAt: end)],
            now: clock.now
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.eyebrow, "11:00 AM · 10 hr 36 min")
        XCTAssertEqual(DayScheduleLogic.duration(item), "10 hr 36 min")
        // The gutter still finds the meridiem: it splits on the FIRST " · ", so the
        // duration clause's own spaces never get read as an AM/PM.
        XCTAssertEqual(DayScheduleLogic.gutterTime(for: item)?.value, "11:00")
        XCTAssertEqual(DayScheduleLogic.gutterTime(for: item)?.meridiem, "AM")
    }

    /// The rule the rebuild asked for, restated at the boundary: a stated end wins
    /// over the assumed two hours in BOTH directions.
    func testAStatedEndOverridesTheAssumedTwoHoursInBothDirections() throws {
        let clock = FixedDateProvider(try townDate(year: 2026, month: 8, day: 10, hour: 14))
        let earlier = try townDate(year: 2026, month: 8, day: 10, hour: 13)
        let later = try townDate(year: 2026, month: 8, day: 10, hour: 18)

        // Assumed 2h from 1 PM would still be running at 2 PM; the stated 1 PM end
        // says it is over.
        let short = YourDayLogic.dayItems(
            from: [event(id: "short", date: "2026-08-10", time: "12:30 PM", endAt: earlier)],
            now: clock.now
        )
        XCTAssertTrue(try XCTUnwrap(short.first).isComplete)

        // Assumed 2h from 8 AM would be long over; the stated 6 PM end says not yet.
        let long = YourDayLogic.dayItems(
            from: [event(id: "long", date: "2026-08-10", time: "8:00 AM", endAt: later)],
            now: clock.now
        )
        XCTAssertFalse(try XCTUnwrap(long.first).isComplete)
    }

    // MARK: - Fixtures

    private func event(
        id: String,
        date: String,
        time: String?,
        isAllDay: Bool = false,
        endAt: Date? = nil
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: "Event \(id)",
            eventDate: date,
            startTime: time,
            location: "Downtown",
            goingCount: 0,
            createdAt: "2026-08-01T12:00:00Z",
            endAt: endAt,
            isAllDay: isAllDay
        )
    }

    private func townDate(
        year: Int, month: Int, day: Int, hour: Int, minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = Town.calendar
        components.timeZone = Town.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(Town.calendar.date(from: components))
    }
}

// MARK: - Completion: who wins, and what happens when the write does not land

/// A stand-in for `event_completions`, including one that refuses every write —
/// the only way to assert the rollback, which is the half of "optimistic" that is
/// easy to ship broken.
@MainActor
private final class FakeCompletions: EventCompletionStoring {
    var stored: Set<String>
    var failsWrites = false
    private(set) var inserted: [String] = []
    private(set) var deleted: [String] = []

    init(stored: Set<String> = []) { self.stored = stored }

    struct Refused: Error {}

    func completedEventIDs(among ids: [String]) async throws -> Set<String> {
        if failsWrites { throw Refused() }
        return stored.intersection(ids)
    }

    func complete(_ eventId: String) async throws {
        if failsWrites { throw Refused() }
        inserted.append(eventId)
        stored.insert(eventId)
    }

    func uncomplete(_ eventId: String) async throws {
        if failsWrites { throw Refused() }
        deleted.append(eventId)
        stored.remove(eventId)
    }
}

@MainActor
final class DayCompletionStoreTests: XCTestCase {

    /// The reconcile. `DayItem.isComplete` is only what the clock guesses; a stored
    /// completion is what the neighbour actually said.
    func testAStoredCompletionBeatsTheClocksGuess() async {
        let api = FakeCompletions(stored: ["morning-walk"])
        let store = DayCompletionStore(api: api)
        let notYetOver = item(id: "morning-walk", clockSaysComplete: false)

        XCTAssertFalse(store.isComplete(notYetOver), "Nothing read yet")

        await store.refresh(for: ["morning-walk"])

        XCTAssertTrue(store.isComplete(notYetOver))
    }

    /// And the clock still answers for a row nobody has ticked.
    func testAnUntickedRowFallsBackToTheClock() async {
        let store = DayCompletionStore(api: FakeCompletions())
        await store.refresh(for: ["over", "ahead"])

        XCTAssertTrue(store.isComplete(item(id: "over", clockSaysComplete: true)))
        XCTAssertFalse(store.isComplete(item(id: "ahead", clockSaysComplete: false)))
    }

    /// "I un-ticked the thing the clock thinks is over" has to be representable, or
    /// the box springs back the instant it is cleared.
    func testUntickingSomethingTheClockCallsDoneSticksForTheSession() {
        let store = DayCompletionStore(api: FakeCompletions())
        let over = item(id: "over", clockSaysComplete: true)

        store.setComplete(false, for: over.id)

        XCTAssertFalse(store.isComplete(over))
    }

    /// A refresh landing after a tap must not overwrite the tap.
    func testALateRefreshDoesNotUndoWhatTheNeighbourJustDid() async {
        let api = FakeCompletions(stored: ["supper"])
        let store = DayCompletionStore(api: api)
        let supper = item(id: "supper", clockSaysComplete: false)

        store.setComplete(false, for: supper.id)
        await store.refresh(for: ["supper"])

        XCTAssertFalse(
            store.isComplete(supper),
            "The server's older truth must lose to the finger"
        )
    }

    func testTickingIsAnInsertAndUntickingIsADelete() async {
        let api = FakeCompletions()
        let store = DayCompletionStore(api: api)

        await store.writeThrough(true, for: "trivia", revertingTo: nil)
        await store.writeThrough(false, for: "trivia", revertingTo: true)

        XCTAssertEqual(api.inserted, ["trivia"])
        XCTAssertEqual(api.deleted, ["trivia"])
        XCTAssertTrue(api.stored.isEmpty, "Presence-only: unticking removes the row")
    }

    /// The flip is synchronous so it lands inside the caller's `withAnimation`.
    func testTheBoxAnswersTheTapBeforeTheNetworkDoes() {
        let store = DayCompletionStore(api: FakeCompletions())
        let trivia = item(id: "trivia", clockSaysComplete: false)

        store.setComplete(true, for: trivia.id)

        XCTAssertTrue(store.isComplete(trivia))
    }

    func testAFailedWriteRollsTheTickBack() async {
        let api = FakeCompletions()
        api.failsWrites = true
        let store = DayCompletionStore(api: api)
        let trivia = item(id: "trivia", clockSaysComplete: false)

        let previous = store.override(for: trivia.id)
        store.setComplete(true, for: trivia.id)
        XCTAssertTrue(store.isComplete(trivia), "Optimistic")

        await store.writeThrough(true, for: trivia.id, revertingTo: previous)

        XCTAssertFalse(store.isComplete(trivia), "The sheet must not show a tick that did not land")
        XCTAssertNil(store.override(for: trivia.id), "Rolled back to 'not said', not to false")
    }

    func testAFailedUntickRollsForwardToDoneAgain() async {
        let api = FakeCompletions(stored: ["walk"])
        let store = DayCompletionStore(api: api)
        let walk = item(id: "walk", clockSaysComplete: false)
        await store.refresh(for: ["walk"])

        let previous = store.override(for: walk.id)
        store.setComplete(false, for: walk.id)
        api.failsWrites = true
        await store.writeThrough(false, for: walk.id, revertingTo: previous)

        XCTAssertTrue(store.isComplete(walk))
    }

    /// No API — a preview, a gallery, a screenshot flag — writes nothing and reads
    /// nothing, and still behaves exactly as the in-memory store always did.
    func testWithoutAnApiTheStoreIsPurelyLocal() async {
        let store = DayCompletionStore()
        let trivia = item(id: "trivia", clockSaysComplete: false)

        await store.refresh(for: ["trivia"])
        XCTAssertFalse(store.isComplete(trivia))

        store.setComplete(true, for: trivia.id)
        XCTAssertTrue(store.isComplete(trivia))
    }

    // MARK: - Surviving a relaunch
    //
    // A relaunch is, from this store's point of view, exactly one thing: a BRAND
    // NEW store with an empty dictionary. Nothing is written to disk on purpose —
    // the row in `event_completions` is the persistence, and a local mirror would
    // be a second source of truth to go stale. So "does a tick survive a restart"
    // decomposes into two decidable questions, both asked below.

    /// One: a fresh store remembers NOTHING by itself. If this ever starts passing
    /// for the wrong reason — a cache, a UserDefaults mirror — the test below stops
    /// proving anything.
    func testAFreshStoreHasNoMemoryOfTheLastOne() {
        let api = FakeCompletions()
        let first = DayCompletionStore(api: api)
        let trivia = item(id: "trivia", clockSaysComplete: false)

        first.setComplete(true, for: trivia.id)
        XCTAssertTrue(first.isComplete(trivia))

        let afterRelaunch = DayCompletionStore(api: api)
        XCTAssertFalse(
            afterRelaunch.isComplete(trivia),
            "Anything a new store already knows did not come from the server"
        )
    }

    /// Two: and the read on the way in puts it back. Together these are the
    /// restart: tick, throw the store away, build a new one, read, still ticked.
    func testATickComesBackFromTheServerOnTheNextLaunch() async {
        let api = FakeCompletions()
        let trivia = item(id: "trivia", clockSaysComplete: false)

        let beforeQuit = DayCompletionStore(api: api)
        beforeQuit.setComplete(true, for: trivia.id)
        await beforeQuit.writeThrough(true, for: trivia.id, revertingTo: nil)
        XCTAssertEqual(api.stored, ["trivia"], "The tick reached the table")

        let afterRelaunch = DayCompletionStore(api: api)
        await afterRelaunch.refresh(for: [trivia.id])

        XCTAssertTrue(afterRelaunch.isComplete(trivia))
    }

    /// And an untick does not come back, because the row is gone.
    func testAnUntickAlsoSurvivesWhenTheClockAgrees() async {
        let api = FakeCompletions(stored: ["walk"])
        let walk = item(id: "walk", clockSaysComplete: false)

        let beforeQuit = DayCompletionStore(api: api)
        await beforeQuit.refresh(for: [walk.id])
        beforeQuit.setComplete(false, for: walk.id)
        await beforeQuit.writeThrough(false, for: walk.id, revertingTo: true)

        let afterRelaunch = DayCompletionStore(api: api)
        await afterRelaunch.refresh(for: [walk.id])

        XCTAssertFalse(afterRelaunch.isComplete(walk))
    }

    /// THE DOCUMENTED LIMIT, pinned so nobody "fixes" it by accident. Presence-only
    /// storage cannot hold "I un-ticked the thing the clock calls done": the untick
    /// deletes a row that was never there, and after a relaunch the clock's guess
    /// resumes. A tombstone would need a second migration.
    func testUntickingAClockCompleteItemDoesNotSurviveARelaunch() async {
        let api = FakeCompletions()
        let over = item(id: "over", clockSaysComplete: true)

        let beforeQuit = DayCompletionStore(api: api)
        beforeQuit.setComplete(false, for: over.id)
        await beforeQuit.writeThrough(false, for: over.id, revertingTo: nil)
        XCTAssertFalse(beforeQuit.isComplete(over))

        let afterRelaunch = DayCompletionStore(api: api)
        await afterRelaunch.refresh(for: [over.id])

        XCTAssertTrue(
            afterRelaunch.isComplete(over),
            "Known limitation — if this ever fails, the table gained a tombstone"
        )
    }

    // MARK: - Fixture

    private func item(id: String, clockSaysComplete: Bool) -> DayItem {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        return DayItem(
            id: id,
            title: "Thing \(id)",
            source: .committed,
            start: start,
            end: nil,
            isAllDay: false,
            isMultiDay: false,
            isComplete: clockSaysComplete,
            eyebrow: "11 AM",
            location: nil,
            goingCount: 0,
            event: UpcomingEvent(
                id: id,
                title: "Thing \(id)",
                eventDate: "2033-05-18",
                startTime: "11 AM",
                location: nil,
                goingCount: 0,
                createdAt: "test"
            )
        )
    }
}
