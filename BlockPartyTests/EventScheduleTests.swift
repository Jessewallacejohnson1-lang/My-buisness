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
}
