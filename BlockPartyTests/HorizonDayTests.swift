//
//  HorizonDayTests.swift
//  BlockPartyTests
//
//  Future-dated item exclusion, lane split, whole-day footer counts, the
//  public-lane cap, and overlap-inset layout — on the whole-day tape,
//  where every timed item is a stub at its true strip position (the
//  overflow markers retired with the fixed window).
//

import XCTest
@testable import BlockParty

final class HorizonDayTests: XCTestCase {
    private let width: CGFloat = 400

    private func dayAxis(at now: Date) -> TimeAxis {
        TimeAxis(now: now, width: width)
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
        let day = HorizonDay(items: [future, today], now: now)
        XCTAssertEqual(day.yoursCount, 1)
        XCTAssertEqual(day.yourStubs.map(\.id), ["today"])
    }

    // MARK: Lanes and counts

    func testLanesSplitBySourceAndCountsCoverTheWholeDay() {
        let now = townDate(2026, 8, 11, 13, 0)
        let items = [
            item("yours-1", start: townDate(2026, 8, 11, 9, 0)),
            item("yours-allday", start: townDate(2026, 8, 11, 0, 0), allDay: true),
            item("yours-late", start: townDate(2026, 8, 11, 22, 30)),
            item("open-1", start: townDate(2026, 8, 11, 15, 0), source: .wholeTown),
            item("open-2", start: townDate(2026, 8, 11, 17, 0), source: .wholeTown),
        ]
        let day = HorizonDay(items: items, now: now)
        // Footer counts cover midnight to midnight — all-day included.
        XCTAssertEqual(day.yoursCount, 3)
        XCTAssertEqual(day.openCount, 2)
        // The tape covers the whole day: 10:30 PM is an ordinary stub now,
        // reached by scrubbing. Only the all-day item stays count-only.
        XCTAssertEqual(day.yourStubs.map(\.id), ["yours-1", "yours-late"])
        XCTAssertEqual(day.publicStubs.map(\.id), ["open-1", "open-2"])
    }

    func testAllDayItemsGetNoStubButCount() {
        let now = townDate(2026, 8, 11, 13, 0)
        let day = HorizonDay(
            items: [item("sale", start: townDate(2026, 8, 11, 0, 0), allDay: true)],
            now: now
        )
        XCTAssertEqual(day.yoursCount, 1)
        XCTAssertTrue(day.yourStubs.isEmpty)
    }

    func testEarlyMorningItemsAreStubsAndRunningMultiDayIsCountOnly() {
        let now = townDate(2026, 8, 11, 13, 0)
        let day = HorizonDay(
            items: [
                item("early-walk", start: townDate(2026, 8, 11, 5, 45)),
                item("running-festival", start: townDate(2026, 8, 9, 10, 0),
                     end: townDate(2026, 8, 12, 20, 0), multiDay: true),
            ],
            now: now
        )
        // 5:45 AM sits on the tape like any other time; the running
        // multi-day festival counts but never marks the strip.
        XCTAssertEqual(day.yourStubs.map(\.id), ["early-walk"])
        XCTAssertEqual(day.yoursCount, 2)
    }

    // MARK: Public-lane cap

    func testPublicLaneCapsAtFourteenNearestNow() {
        let now = townDate(2026, 8, 11, 13, 0)
        let items = (0..<20).map { i in
            item("open-\(i)", start: townDate(2026, 8, 11, 7, 0).addingTimeInterval(Double(i) * 2400),
                 source: .wholeTown)
        }
        let day = HorizonDay(items: items, now: now)
        XCTAssertEqual(day.publicStubs.count, 14)
        XCTAssertEqual(day.openCount, 20, "the cap is visual; the count is the day")
        // The kept 14 are the nearest to 13:00 — the extremes fall off.
        XCTAssertFalse(day.publicStubs.contains { $0.id == "open-0" })
        XCTAssertTrue(day.publicStubs.contains { $0.id == "open-9" })
    }

    // MARK: Late night — today's events stay on the tape, tomorrow stays out

    func testLateNightItemsStayOnTheTapeAndTomorrowStaysExcluded() {
        let now = townDate(2026, 8, 11, 23, 50)
        let day = HorizonDay(
            items: [
                item("tonight", start: townDate(2026, 8, 11, 22, 30)),
                item("tomorrow-1", start: townDate(2026, 8, 12, 0, 30)),
                item("tomorrow-2", start: townDate(2026, 8, 12, 2, 0), source: .wholeTown),
            ],
            now: now
        )
        // 10:30 PM tonight is a stub at its true strip position — the tape
        // has no edge to fall off.
        XCTAssertEqual(day.yourStubs.map(\.id), ["tonight"])
        XCTAssertEqual(day.yoursCount, 1)
        // Tomorrow's small hours are not today's news anywhere.
        XCTAssertTrue(day.publicStubs.isEmpty)
        XCTAssertEqual(day.openCount, 0)
    }

    // MARK: Layout

    func testOverlappingStubsStayCountableWithInsetGaps() {
        let now = townDate(2026, 8, 11, 13, 0)
        let axis = dayAxis(at: now)
        // Five minutes is ~2.8 pt at the tape's ~33 pt/hour — inside the
        // 5 pt min width, so these genuinely overlap and take the inset.
        let starts = [
            townDate(2026, 8, 11, 14, 0),
            townDate(2026, 8, 11, 14, 5),
            townDate(2026, 8, 11, 14, 10),
        ]
        let stubs = starts.enumerated().map { i, start in
            HorizonStub(id: "s\(i)", start: start, end: nil, isYours: true,
                        category: .outdoors)
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

    func testStubsSitAtTrueStripPositions() {
        let now = townDate(2026, 8, 11, 13, 0)
        let axis = dayAxis(at: now)
        let early = HorizonStub(
            id: "seven-sharp", start: townDate(2026, 8, 11, 7, 0), end: nil,
            isYours: true, category: .outdoors)
        let late = HorizonStub(
            id: "ten-sharp", start: townDate(2026, 8, 11, 22, 0), end: nil,
            isYours: true, category: .outdoors)
        let placed = HorizonDay.layout([early, late], axis: axis, minWidth: 5)
        // On a sliding tape a stub's position IS its time — no edge
        // clamping (the old bookend rule retired with the fixed window).
        XCTAssertEqual(placed[0].x, 7 * axis.pointsPerHour, accuracy: 0.01)
        XCTAssertEqual(placed[1].x, 22 * axis.pointsPerHour, accuracy: 0.01)
    }

    // MARK: Past dimming — a stated end wins, else the assumed two hours

    func testIsPastUsesStatedEndOrTheAssumedTwoHours() {
        let now = townDate(2026, 8, 11, 13, 0)
        func stub(_ id: String, start: Date, end: Date? = nil) -> HorizonStub {
            HorizonStub(id: id, start: start, end: end, isYours: true, category: .outdoors)
        }

        // No end: past exactly two hours after start, not a minute sooner.
        XCTAssertTrue(HorizonDay.isPast(
            stub("over", start: townDate(2026, 8, 11, 10, 0)), now: now))
        XCTAssertFalse(HorizonDay.isPast(
            stub("running", start: townDate(2026, 8, 11, 11, 0)), now: now))
        XCTAssertFalse(HorizonDay.isPast(
            stub("ahead", start: townDate(2026, 8, 11, 15, 0)), now: now))

        // A stated end overrides the assumption in both directions.
        XCTAssertTrue(HorizonDay.isPast(
            stub("short", start: townDate(2026, 8, 11, 12, 30),
                 end: townDate(2026, 8, 11, 12, 50)), now: now))
        XCTAssertFalse(HorizonDay.isPast(
            stub("long", start: townDate(2026, 8, 11, 8, 0),
                 end: townDate(2026, 8, 11, 18, 0)), now: now))
    }

    // MARK: The scrub's event line + on-an-event bubble

    func testScrubLineNamesTheHoursEventNearestFirst() {
        let now = townDate(2026, 8, 11, 13, 0)
        let day = HorizonDay(
            items: [
                item("early", start: townDate(2026, 8, 11, 15, 0)),
                item("late", start: townDate(2026, 8, 11, 15, 40), source: .wholeTown),
                item("evening", start: townDate(2026, 8, 11, 19, 0)),
            ],
            now: now
        )
        // Dense hour: nearest to the scrub position wins.
        XCTAssertEqual(
            day.scrubLine(at: townDate(2026, 8, 11, 15, 10)),
            .event(day.markedItems[0]))
        XCTAssertEqual(
            day.scrubLine(at: townDate(2026, 8, 11, 15, 35)),
            .event(day.markedItems[1]))
        // A gap hour between events reads quiet.
        XCTAssertEqual(day.scrubLine(at: townDate(2026, 8, 11, 17, 30)), .quietHour)
        // Landing exactly on a start is "at".
        XCTAssertEqual(
            day.scrubLine(at: townDate(2026, 8, 11, 19, 0)),
            .event(day.markedItems[2]))
        // Past the last event, the day is done.
        XCTAssertEqual(day.scrubLine(at: townDate(2026, 8, 11, 21, 30)), .dayDone)
        // Before the first, quiet — not done.
        XCTAssertEqual(day.scrubLine(at: townDate(2026, 8, 11, 8, 0)), .quietHour)
    }

    func testScrubLineStaysRestingOnADayWithNothingTimed() {
        let now = townDate(2026, 8, 11, 13, 0)
        XCTAssertEqual(
            HorizonDay(items: [], now: now).scrubLine(at: now), .resting)
        // All-day items count but never mark the strip — still resting.
        let allDay = HorizonDay(
            items: [item("sale", start: townDate(2026, 8, 11, 0, 0), allDay: true)],
            now: now)
        XCTAssertEqual(allDay.scrubLine(at: now), .resting)
    }

    func testScrubLineBehavesAtMidnightAdjacentTimes() {
        let now = townDate(2026, 8, 11, 23, 50)
        let day = HorizonDay(
            items: [item("tonight", start: townDate(2026, 8, 11, 23, 30))],
            now: now
        )
        // Inside the 11 PM hour the event is named…
        XCTAssertEqual(
            day.scrubLine(at: townDate(2026, 8, 11, 23, 45)),
            .event(day.markedItems[0]))
        // …the 10 PM hour before it is quiet, not done…
        XCTAssertEqual(day.scrubLine(at: townDate(2026, 8, 11, 22, 59)), .quietHour)
        // …and one minute before next midnight it is past the last start
        // but still in the event's hour, so it stays named.
        XCTAssertEqual(
            day.scrubLine(at: townDate(2026, 8, 11, 23, 59)),
            .event(day.markedItems[0]))
    }

    func testOnEventItemUsesTheMagnetsEightMinuteWindow() {
        let now = townDate(2026, 8, 11, 13, 0)
        let day = HorizonDay(
            items: [
                item("target", start: townDate(2026, 8, 11, 15, 0)),
                item("neighbor", start: townDate(2026, 8, 11, 15, 12)),
            ],
            now: now
        )
        // Exactly 8 minutes out is ON (the magnet's own inclusive window).
        XCTAssertEqual(
            day.onEventItem(at: townDate(2026, 8, 11, 14, 52))?.id, "target")
        // Nine minutes out is not.
        XCTAssertNil(day.onEventItem(at: townDate(2026, 8, 11, 14, 51)))
        // Dense: the nearest of two wins.
        XCTAssertEqual(
            day.onEventItem(at: townDate(2026, 8, 11, 15, 7))?.id, "neighbor")
        // Empty day: never on anything.
        XCTAssertNil(HorizonDay(items: [], now: now).onEventItem(at: now))
    }

    func testMarkedItemsMatchTheDrawnStubsThroughThePublicCap() {
        let now = townDate(2026, 8, 11, 13, 0)
        let items = (0..<20).map { i in
            item("open-\(i)", start: townDate(2026, 8, 11, 7, 0).addingTimeInterval(Double(i) * 2400),
                 source: .wholeTown)
        }
        let day = HorizonDay(items: items, now: now)
        // The magnet/line/bubble set is exactly the drawn set: a capped-out
        // stub can't be "on" anything it doesn't show.
        XCTAssertEqual(
            Set(day.markedItems.map(\.id)),
            Set(day.publicStubs.map(\.id)).union(day.yourStubs.map(\.id)))
        XCTAssertEqual(day.markedItems.count, 14)
        // And it stays start-sorted for the line's past-last rule.
        XCTAssertEqual(
            day.markedItems.map(\.start),
            day.markedItems.map(\.start).sorted())
    }

    // MARK: Fixture titles — gate recordings leave the review loop

    func testFixtureTitlesReadAsRealStJoeEvents() {
        // A literal "o11" on camera reads as a bug (Phase 2 gate
        // carry-forward): every §7 fixture item must carry a humanized
        // title, never its id, and the DayItem and its embedded event
        // must agree — the bubble reads one, the day sheet the other.
        let day = Town.calendar.startOfDay(for: townDate(2026, 8, 11, 13, 0))
        for state in HorizonDayState.allCases {
            for item in HorizonMock.items(for: state, day: day) {
                XCTAssertNotEqual(item.title, item.id, "\(state) leaks an id as a title")
                XCTAssertGreaterThan(item.title.count, 3, "\(state): '\(item.title)'")
                XCTAssertEqual(item.title, item.event.title)
            }
        }
    }

    func testStubWidthFollowsDuration() {
        let now = townDate(2026, 8, 11, 13, 0)
        let axis = dayAxis(at: now)
        let start = townDate(2026, 8, 11, 14, 0)
        let timed = HorizonStub(id: "timed", start: start, end: start.addingTimeInterval(2 * 3600),
                                isYours: true, category: .outdoors)
        let untimed = HorizonStub(id: "untimed", start: townDate(2026, 8, 11, 18, 0), end: nil,
                                  isYours: true, category: .outdoors)
        let placed = HorizonDay.layout([timed, untimed], axis: axis, minWidth: 5)
        XCTAssertEqual(placed[0].width, 2 * axis.pointsPerHour, accuracy: 0.01)
        XCTAssertEqual(placed[1].width, 5)
    }
}
