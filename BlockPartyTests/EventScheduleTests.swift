//
//  EventScheduleTests.swift
//  BlockPartyTests — a long Event's Schedule on its page (BP app happening-now 06): which parts show, in what
//  order, which fade, and which carries "Now" or the countdown.
//

import XCTest
@testable import BlockParty

final class EventScheduleTests: XCTestCase {
    /// Nov 2026 in the Town's time.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func part(_ title: String, _ day: Int, _ hour: Int, _ minute: Int = 0, hours: Double = 1,
                      live: Bool = true) -> EventPart {
        let start = at(day, hour, minute)
        return EventPart(title: title, start: start, end: start.addingTimeInterval(hours * 3600), live: live)
    }

    /// Sent in any order, read by start.
    func testPartsReadInTheOrderTheyStart() {
        let parts = [part("Film night", 13, 19), part("Dance lesson", 10, 19), part("Student panel", 11, 19)]
        XCTAssertEqual(EventSchedule.rows(parts, at: at(10, 12)).map(\.part.title),
                       ["Dance lesson", "Student panel", "Film night"])
    }

    /// Today's ended parts stay, faded; earlier days' drop off; one that began yesterday and runs on stays.
    func testTodaysEndedPartsFadeAndEarlierDaysDropOff() {
        let parts = [part("Opening night", 9, 19), part("Overnight vigil", 9, 22, hours: 18),
                     part("Food from home", 10, 12), part("Dance lesson", 10, 19)]
        let rows = EventSchedule.rows(parts, at: at(10, 15))
        XCTAssertEqual(rows.map(\.part.title), ["Overnight vigil", "Food from home", "Dance lesson"])
        XCTAssertEqual(rows.map(\.past), [false, true, false])
    }

    /// Nothing left: no rows, so the page shows no Schedule.
    func testNoPartsLeftIsNoSchedule() {
        XCTAssertTrue(EventSchedule.rows([], at: at(10, 15)).isEmpty)
        XCTAssertTrue(EventSchedule.rows([part("Opening night", 9, 19)], at: at(10, 15)).isEmpty)
    }

    /// The part on carries "Now", from its start to its end.
    func testThePartOnSaysNow() {
        let parts = [part("Food from home", 10, 18, hours: 1.5), part("Film night", 13, 19)]
        XCTAssertNil(EventSchedule.rows(parts, at: at(10, 16, 59)).first?.mark, "61 minutes off, not on")
        XCTAssertEqual(EventSchedule.rows(parts, at: at(10, 18)).first?.mark, .now)
        XCTAssertEqual(EventSchedule.rows(parts, at: at(10, 19, 29)).first?.mark, .now)
        let ended = EventSchedule.rows(parts, at: at(10, 19, 30)).first
        XCTAssertNil(ended?.mark)
        XCTAssertEqual(ended?.past, true)
    }

    /// Only the next part counts down, and only in its last 60 minutes, in 01's words.
    func testTheNextPartCountsDownInItsLastHour() {
        let parts = [part("Food from home", 10, 18, hours: 1.5), part("Dance lesson", 10, 19), part("Panel", 10, 19, 30)]
        let rows = EventSchedule.rows(parts, at: at(10, 18, 40))
        XCTAssertEqual(rows.map(\.mark), [.now, .soon(FeedWhenLine(text: "In 20 min", spoken: "Starts in 20 minutes")), nil])
        XCTAssertNil(EventSchedule.rows(Array(parts.dropFirst()), at: at(10, 17, 59)).compactMap(\.mark).first, "61 minutes off")
        XCTAssertEqual(EventSchedule.rows(parts, at: at(10, 18, 59)).map(\.mark)[1],
                       .soon(FeedWhenLine(text: "In 1 min", spoken: "Starts in 1 minute")))
    }

    /// A part fades when it ended today, wherever it started; one that ended yesterday drops off.
    func testAPartFadesByTheDayItEnded() {
        let parts = [part("Vigil", 9, 22, hours: 3), part("Lantern walk", 9, 20, hours: 2), part("Brunch", 10, 10)]
        let rows = EventSchedule.rows(parts, at: at(10, 15))
        XCTAssertEqual(rows.map(\.part.title), ["Vigil", "Brunch"], "the walk ended yesterday at 10 PM")
        XCTAssertEqual(rows.map(\.past), [true, true])
    }

    /// Only a live part (the server's mark: a real happening under 12 hours) says "Now" or counts down.
    func testOnlyALivePartSaysNowOrCountsDown() {
        let parts = [part("Holiday sale", 10, 14, hours: 2, live: false), part("Open studio", 10, 15, 20, live: false)]
        XCTAssertEqual(EventSchedule.rows(parts, at: at(10, 15)).map(\.mark), [nil, nil])
    }

    /// The first 4 shown: the part on and the next ones; ended parts fill only the places left, the latest ended
    /// first, above them in time order.
    func testTheVisibleFourLeadWithWhatIsOnAndNext() {
        let ended = [part("Breakfast", 10, 8), part("Opening", 10, 9), part("Tour", 10, 11)]
        let ahead = [part("Talk", 10, 14, hours: 2), part("Panel", 10, 16), part("Film", 10, 19), part("Dance", 10, 21),
                     part("Brunch", 11, 10)]
        XCTAssertEqual(EventSchedule.visible(EventSchedule.rows(ended + ahead, at: at(10, 15))).map(\.part.title),
                       ["Talk", "Panel", "Film", "Dance"])
        XCTAssertEqual(EventSchedule.visible(EventSchedule.rows(ended + ahead.prefix(2), at: at(10, 15))).map(\.part.title),
                       ["Opening", "Tour", "Talk", "Panel"])
        XCTAssertEqual(EventSchedule.visible(EventSchedule.rows(ended, at: at(10, 15))).map(\.part.title),
                       ["Breakfast", "Opening", "Tour"])
    }

    /// The time column: the short day and the Town's clock, spoken in full.
    func testTheTimeReadsShortAndSpeaksInFull() {
        let row = EventSchedule.rows([part("Artist talk", 12, 15)], at: at(10, 12))[0]
        XCTAssertEqual(row.time, "Thu 3 PM")
        XCTAssertEqual(row.spoken, "Thursday 3 PM, Artist talk")
        let soon = EventSchedule.rows([part("Artist talk", 10, 15)], at: at(10, 14, 40))[0]
        XCTAssertEqual(soon.spoken, "Tuesday 3 PM, Artist talk, starts in 20 minutes")
        let on = EventSchedule.rows([part("Artist talk", 10, 15)], at: at(10, 15, 10))[0]
        XCTAssertEqual(on.spoken, "Tuesday 3 PM, Artist talk, happening now")
    }

    // MARK: The day row (BP app event-schedule 02)

    /// Parts left on one day give the list; on two or more, the day row.
    func testOneDayIsTheListAndTwoDaysTheDayRow() {
        let evening = [part("Santa arrives", 14, 16, 30), part("Carolers", 14, 17), part("Tree lighting", 14, 19)]
        XCTAssertTrue(EventSchedule.days(EventSchedule.rows(evening, at: at(14, 12)), at: at(14, 12)).isEmpty)
        let week = evening + [part("Brunch", 15, 10)]
        XCTAssertEqual(EventSchedule.days(EventSchedule.rows(week, at: at(14, 12)), at: at(14, 12)).map(\.id),
                       ["2026-11-14", "2026-11-15"])
    }

    /// Every day from today to the last part's, the empty ones in between counted 0; earlier days gone, and a
    /// part that began yesterday and runs on sits under today.
    func testTheRowRunsFromTodayToTheLastDayWithItsGaps() {
        let parts = [part("Opening", 9, 19), part("Vigil", 9, 22, hours: 18), part("Panel", 11, 19), part("Showcase", 14, 19)]
        let now = at(10, 12)
        let days = EventSchedule.days(EventSchedule.rows(parts, at: now), at: now)
        XCTAssertEqual(days.map(\.id), ["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14"])
        XCTAssertEqual(days.map(\.count), [1, 1, 0, 0, 1])
        XCTAssertEqual(days.map(\.today), [true, false, false, false, false])
        XCTAssertEqual(days.map(\.letter), ["T", "W", "T", "F", "S"])
        XCTAssertEqual(days.map(\.number), ["10", "11", "12", "13", "14"])
    }

    /// It opens on today; before the Event, on its first day; a tapped day stays while it's in the row.
    func testItOpensOnTodayElseTheFirstDay() {
        let parts = [part("Dance", 10, 19), part("Panel", 11, 19), part("Showcase", 14, 19)]
        let during = EventSchedule.days(EventSchedule.rows(parts, at: at(11, 9)), at: at(11, 9))
        XCTAssertEqual(EventSchedule.shown(picked: nil, in: during), "2026-11-11")
        XCTAssertEqual(EventSchedule.shown(picked: "2026-11-14", in: during), "2026-11-14")
        let before = EventSchedule.days(EventSchedule.rows(parts, at: at(8, 9)), at: at(8, 9))
        XCTAssertEqual(EventSchedule.shown(picked: nil, in: before), "2026-11-10")
    }

    /// At midnight the day that ended drops off, and a pick of it moves to the new today.
    func testAtMidnightThePickedDayMovesToTheNewToday() {
        let parts = [part("Dance", 10, 19), part("Panel", 11, 19), part("Showcase", 12, 19)]
        let tuesday = at(10, 21)
        XCTAssertEqual(EventSchedule.shown(picked: "2026-11-10",
                                           in: EventSchedule.days(EventSchedule.rows(parts, at: tuesday), at: tuesday)),
                       "2026-11-10")
        let wednesday = at(11, 0, 1)
        let days = EventSchedule.days(EventSchedule.rows(parts, at: wednesday), at: wednesday)
        XCTAssertEqual(days.first?.id, "2026-11-11")
        XCTAssertEqual(EventSchedule.shown(picked: "2026-11-10", in: days), "2026-11-11")
    }

    /// A day's rows: only its own, by start, with today's ended ones faded and "Now" only on a live part on.
    func testADaysRowsFadeAndSayNowAsTheListDoes() {
        let parts = [part("Panel", 11, 19), part("Lunch", 10, 12), part("Talk", 10, 14, hours: 2),
                     part("Sale", 10, 14, hours: 3, live: false)]
        let now = at(10, 15)
        let rows = EventSchedule.rows(EventSchedule.rows(parts, at: now), on: "2026-11-10", at: now)
        XCTAssertEqual(rows.map(\.part.title), ["Lunch", "Talk", "Sale"])
        XCTAssertEqual(rows.map(\.past), [true, false, false])
        XCTAssertEqual(rows.map(\.mark), [nil, .now, nil])
        XCTAssertTrue(EventSchedule.rows(EventSchedule.rows(parts, at: now), on: "2026-11-12", at: now).isEmpty,
                      "a day with none: Nothing planned")
    }

    /// The hours under a part's name, and a day spoken as one button.
    func testTheSpanAndTheSpokenDay() {
        XCTAssertEqual(EventSchedule.span(part("Talk", 12, 15)), "3 – 4 PM")
        XCTAssertEqual(EventSchedule.span(part("Brunch", 12, 11, hours: 2)), "11 AM – 1 PM")
        XCTAssertEqual(EventSchedule.span(part("Carolers", 12, 16, 30, hours: 0.5)), "4:30 – 5 PM")
        let days = EventSchedule.days(EventSchedule.rows([part("A", 14, 19), part("B", 14, 20), part("C", 15, 9)],
                                                         at: at(14, 9)), at: at(14, 9))
        XCTAssertEqual(days.map(\.spoken), ["Saturday, November 14, today, 2 planned", "Sunday, November 15, 1 planned"])
    }
}
