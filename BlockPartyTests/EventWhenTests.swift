//
//  EventWhenTests.swift
//  BlockPartyTests — the one rule for when an event happens (codebase-health 10): every
//  way organizers write a time, read the same on a Central and a Pacific phone, and
//  "on now" at its edges.
//

import XCTest
@testable import BlockParty

final class EventWhenTests: XCTestCase {

    private let day = "2026-10-21"
    private func at(_ hour: Int, _ minute: Int = 0, plusDays: Int = 0) -> Date {
        Town.midnight(day)!.addingTimeInterval(TimeInterval(plusDays * 86400 + hour * 3600 + minute * 60))
    }

    /// Raw text → minutes after midnight (nil: untimed, the organizer's words show).
    private let table: [(String?, Int?)] = [
        ("7 PM", 19 * 60), ("7pm", 19 * 60), ("7:00 PM", 19 * 60), ("7:00 p.m.", 19 * 60),
        ("6:30 PM", 18 * 60 + 30), ("10 AM", 10 * 60), ("7 a.m.", 7 * 60), ("8:15 pm", 20 * 60 + 15),
        ("12 PM", 12 * 60), ("12pm", 12 * 60), ("12 AM", 0), ("12am", 0),
        ("7pm-9pm", 19 * 60), ("7 PM - midnight", 19 * 60), ("Doors 6:30 PM", 18 * 60 + 30),
        ("19:00", 19 * 60), ("19:00:00", 19 * 60), ("18:30", 18 * 60 + 30), ("07:30", 7 * 60 + 30),
        ("00:00", 0),
        ("noon", 12 * 60), ("Noon", 12 * 60), ("12 noon", 12 * 60),
        ("midnight", 0), ("Midnight", 0),
        ("7:00", nil), ("7 at dusk", nil), ("after dark", nil), ("TBA", nil), ("All day", nil),
        ("25:00", nil), ("13 PM", nil), ("", nil), ("  ", nil), (nil, nil),
    ]

    func testEveryWayATimeIsWrittenReadsTheSameOnAnyPhone() {
        for zone in ["America/Chicago", "America/Los_Angeles", "Asia/Tokyo"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            for (raw, minutes) in table {
                XCTAssertEqual(EventWhen.minutes(raw), minutes, "\(raw ?? "nil") on a \(zone) phone")
                let when = EventWhen(date: day, time: raw, endAt: nil)
                XCTAssertEqual(when?.timed, minutes != nil, "\(raw ?? "nil")")
                XCTAssertEqual(when?.start, minutes.map { at($0 / 60, $0 % 60) } ?? at(0), "\(raw ?? "nil") on \(zone)")
            }
        }
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = TimeZone.current
    }

    func testOnNowRunsFromItsStartToItsEnd() {
        let concert = EventWhen(date: day, time: "7 PM", endAt: nil)!
        XCTAssertFalse(concert.isOn(at(18, 59)))
        XCTAssertTrue(concert.isOn(at(19)))
        XCTAssertTrue(concert.isOn(at(20, 59)))
        XCTAssertFalse(concert.isOn(at(21)), "two hours with no end_at")

        let pilates = EventWhen(date: day, time: "10 AM", endAt: at(11))!
        XCTAssertTrue(pilates.isOn(at(10, 59)))
        XCTAssertFalse(pilates.isOn(at(11)), "its own end_at wins")

        let game = EventWhen(date: day, time: "7 PM", endAt: nil, game: true)!
        XCTAssertTrue(game.isOn(at(21, 59)), "a game runs three hours")
        XCTAssertFalse(game.isOn(at(22)))
    }

    func testUntimedIsOnOnlyWhenItRunsOverDays() {
        XCTAssertFalse(EventWhen(date: day, time: nil, endAt: nil)!.isOn(at(12)))
        XCTAssertFalse(EventWhen(date: day, time: "9 AM", endAt: nil, allDay: true)!.isOn(at(12)),
                       "all day wins over a time")
        XCTAssertFalse(EventWhen(date: day, time: nil, endAt: at(0, plusDays: 1), allDay: true)!.isOn(at(12)))
        let sale = EventWhen(date: day, time: nil, endAt: at(0, plusDays: 6), allDay: true)!
        XCTAssertTrue(sale.isOn(at(12, plusDays: 3)))
        XCTAssertFalse(sale.isOn(at(0, plusDays: 6)))
    }

    func testDayWords() {
        let now = at(10)
        XCTAssertEqual(EventWhen(date: day, time: "11 AM", endAt: nil)?.dayWord(now), "Today")
        XCTAssertEqual(EventWhen(date: day, time: "5 PM", endAt: nil)?.dayWord(now), "Tonight")
        XCTAssertEqual(EventWhen(date: day, time: nil, endAt: nil)?.dayWord(now), "Today")
        XCTAssertEqual(EventWhen(date: "2026-10-22", time: "9 PM", endAt: nil)?.dayWord(now), "Tomorrow")
        XCTAssertEqual(EventWhen(date: "2026-10-22", time: "9 PM", endAt: nil)?.dayWord(at(23, 59)), "Tomorrow")
        XCTAssertNil(EventWhen(date: "2026-10-23", time: "9 AM", endAt: nil)?.dayWord(now))
        XCTAssertNil(EventWhen(date: "Oct 21", time: "9 AM", endAt: nil))
    }
}
