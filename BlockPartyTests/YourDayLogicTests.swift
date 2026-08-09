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
