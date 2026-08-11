//
//  HorizonDayTests.swift
//  BlockPartyTests
//
//  Future-dated item exclusion, lane split, whole-day footer counts,
//  overflow, the public-lane cap, tomorrow's stubs in the night window,
//  and overlap-inset layout.
//

import XCTest
@testable import BlockParty

final class HorizonDayTests: XCTestCase {
    private let sunrise = townDate(2026, 8, 11, 6, 13)
    private let sunset = townDate(2026, 8, 11, 21, 2)
    private let width: CGFloat = 400

    private func dayAxis(at now: Date) -> TimeAxis {
        TimeAxis(now: now, sunrise: sunrise, sunset: sunset, width: width)
    }

    private func item(
        _ id: String,
        start: Date,
        end: Date? = nil,
        source: DayItemSource = .committed,
        allDay: Bool = false,
        multiDay: Bool = false
    ) -> DayItem {
        DayItem(
            id: id,
            title: id,
            source: source,
            start: start,
            end: end,
            isAllDay: allDay,
            isMultiDay: multiDay,
            isComplete: false,
            eyebrow: "",
            location: nil,
            goingCount: 0,
            event: UpcomingEvent(
                id: id,
                title: id,
                eventDate: Town.day(start),
                startTime: nil,
                location: nil,
                goingCount: 0,
                createdAt: "fixture"
            )
        )
    }

    // MARK: The future-dated guard

    func testFutureDatedItemIsExcludedEverywhere() {
        // The shipped-bug shape: an Aug 30 RSVP arriving in today's module.
        let now = townDate(2026, 8, 11, 13, 0)
        let future = item("aug30", start: townDate(2026, 8, 30, 18, 0))
        let today = item("today", start: townDate(2026, 8, 11, 15, 0))
        let day = HorizonDay(items: [future, today], axis: dayAxis(at: now), now: now)
        XCTAssertEqual(day.yoursCount, 1)
        XCTAssertEqual(day.yourStubs.map(\.id), ["today"])
        XCTAssertEqual(day.laterCount, 0, "a future date is not 'later today'")
    }

    // MARK: Lanes and counts

    func testLanesSplitBySourceAndCountsCoverTheWholeDay() {
        let now = townDate(2026, 8, 11, 13, 0)
        let items = [
            item("yours-1", start: townDate(2026, 8, 11, 9, 0)),
            item("yours-allday", start: townDate(2026, 8, 11, 0, 0), allDay: true),
            item("yours-late", start: townDate(2026, 8, 11, 21, 30)),  // after sunset
            item("open-1", start: townDate(2026, 8, 11, 15, 0), source: .wholeTown),
            item("open-2", start: townDate(2026, 8, 11, 17, 0), source: .wholeTown),
        ]
        let day = HorizonDay(items: items, axis: dayAxis(at: now), now: now)
        // Footer counts cover midnight to midnight — all-day and post-sunset included.
        XCTAssertEqual(day.yoursCount, 3)
        XCTAssertEqual(day.openCount, 2)
        // Stubs only for timed items inside the window.
        XCTAssertEqual(day.yourStubs.map(\.id), ["yours-1"])
        XCTAssertEqual(day.publicStubs.map(\.id), ["open-1", "open-2"])
        XCTAssertEqual(day.laterCount, 1)
        XCTAssertEqual(day.earlierCount, 0)
    }

    func testAllDayItemsGetNoStubButCount() {
        let now = townDate(2026, 8, 11, 13, 0)
        let day = HorizonDay(
            items: [item("sale", start: townDate(2026, 8, 11, 0, 0), allDay: true)],
            axis: dayAxis(at: now), now: now
        )
        XCTAssertEqual(day.yoursCount, 1)
        XCTAssertTrue(day.yourStubs.isEmpty)
        XCTAssertEqual(day.earlierCount, 0, "an all-day item is not overflow")
    }

    func testEarlierOverflowCountsPreWindowStarts() {
        let now = townDate(2026, 8, 11, 13, 0)
        let day = HorizonDay(
            items: [
                item("early-walk", start: townDate(2026, 8, 11, 5, 45)),  // before 6:13 sunrise
                item("running-festival", start: townDate(2026, 8, 9, 10, 0),
                     end: townDate(2026, 8, 12, 20, 0), multiDay: true),
            ],
            axis: dayAxis(at: now), now: now
        )
        XCTAssertEqual(day.earlierCount, 1, "the running multi-day festival is not 'earlier today'")
        XCTAssertEqual(day.yoursCount, 2)
    }

    // MARK: Public-lane cap

    func testPublicLaneCapsAtFourteenNearestNow() {
        let now = townDate(2026, 8, 11, 13, 0)
        let items = (0..<20).map { i in
            item("open-\(i)", start: townDate(2026, 8, 11, 7, 0).addingTimeInterval(Double(i) * 2400),
                 source: .wholeTown)
        }
        let day = HorizonDay(items: items, axis: dayAxis(at: now), now: now)
        XCTAssertEqual(day.publicStubs.count, 14)
        XCTAssertEqual(day.openCount, 20, "the cap is visual; the count is the day")
        // The kept 14 are the nearest to 13:00 — the extremes fall off.
        XCTAssertFalse(day.publicStubs.contains { $0.id == "open-0" })
        XCTAssertTrue(day.publicStubs.contains { $0.id == "open-9" })
    }

    // MARK: The night window and midnight

    func testTomorrowsSmallHoursRenderAsTomorrowStubsWithoutCounting() {
        let now = townDate(2026, 8, 11, 23, 50)
        let axis = dayAxis(at: now)
        XCTAssertEqual(axis.kind, .night)
        let items = [
            item("tonight", start: townDate(2026, 8, 11, 22, 30)),
            item("tomorrow-1", start: townDate(2026, 8, 12, 0, 30)),
            item("tomorrow-2", start: townDate(2026, 8, 12, 2, 0), source: .wholeTown),
        ]
        let day = HorizonDay(items: items, axis: axis, now: now)
        XCTAssertEqual(day.yourStubs.count, 2)
        XCTAssertEqual(day.publicStubs.count, 1)
        XCTAssertFalse(day.yourStubs.first { $0.id == "tonight" }!.isTomorrow)
        XCTAssertTrue(day.yourStubs.first { $0.id == "tomorrow-1" }!.isTomorrow)
        XCTAssertTrue(day.publicStubs.first { $0.id == "tomorrow-2" }!.isTomorrow)
        // Footer counts stay today-only.
        XCTAssertEqual(day.yoursCount, 1)
        XCTAssertEqual(day.openCount, 0)
    }

    // MARK: Layout

    func testOverlappingStubsStayCountableWithInsetGaps() {
        let now = townDate(2026, 8, 11, 13, 0)
        let axis = dayAxis(at: now)
        let starts = [
            townDate(2026, 8, 11, 14, 0),
            townDate(2026, 8, 11, 14, 10),
            townDate(2026, 8, 11, 14, 20),
        ]
        let stubs = starts.enumerated().map { i, start in
            HorizonStub(id: "s\(i)", start: start, end: nil, isYours: true,
                        category: .outdoors, isTomorrow: false)
        }
        let placed = HorizonDay.layout(stubs, axis: axis, minWidth: 5)
        XCTAssertEqual(placed.count, 3)
        for pair in zip(placed, placed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.x - (pair.0.x + pair.0.width), 1 - 0.001,
                "later stub keeps a 1pt gap from the earlier one"
            )
        }
    }

    func testStubWidthFollowsDuration() {
        let now = townDate(2026, 8, 11, 13, 0)
        let axis = dayAxis(at: now)
        let start = townDate(2026, 8, 11, 14, 0)
        let timed = HorizonStub(id: "timed", start: start, end: start.addingTimeInterval(2 * 3600),
                                isYours: true, category: .outdoors, isTomorrow: false)
        let untimed = HorizonStub(id: "untimed", start: townDate(2026, 8, 11, 18, 0), end: nil,
                                  isYours: true, category: .outdoors, isTomorrow: false)
        let placed = HorizonDay.layout([timed, untimed], axis: axis, minWidth: 5)
        XCTAssertEqual(placed[0].width, 2 * axis.pointsPerHour, accuracy: 0.01)
        XCTAssertEqual(placed[1].width, 5)
    }
}
