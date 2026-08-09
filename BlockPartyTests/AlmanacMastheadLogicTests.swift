//
//  AlmanacMastheadLogicTests.swift
//  BlockPartyTests — deterministic fallback suggestions and the optional civic line.
//

import XCTest
@testable import BlockParty

final class AlmanacMastheadLogicTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private let localSubjects = [
        AlmanacSuggestionGenerator.Subject(id: "park-millstream", name: "Millstream Park", kind: .park),
        AlmanacSuggestionGenerator.Subject(id: "trail-wobegon", name: "Wobegon Trail", kind: .trail),
        AlmanacSuggestionGenerator.Subject(id: "place-downtown", name: "Downtown", kind: .landmark),
    ]

    func testSuggestionIsStableForTheSameTownDayAndUser() {
        let inputs = AlmanacSuggestionGenerator.Inputs(
            townDate: "2026-08-05",
            userKey: "user-42",
            rsvps: [],
            subjects: localSubjects
        )

        XCTAssertEqual(
            AlmanacSuggestionGenerator.suggestion(for: inputs),
            AlmanacSuggestionGenerator.suggestion(for: inputs)
        )
    }

    func testSuggestionChangesOnTheNextTownDay() throws {
        let first = try XCTUnwrap(AlmanacSuggestionGenerator.suggestion(for: .init(
            townDate: "2026-08-05",
            userKey: "user-42",
            rsvps: [],
            subjects: localSubjects
        )))
        let next = try XCTUnwrap(AlmanacSuggestionGenerator.suggestion(for: .init(
            townDate: "2026-08-06",
            userKey: "user-42",
            rsvps: [],
            subjects: localSubjects
        )))

        XCTAssertNotEqual(first, next)
    }

    func testUpcomingRSVPBeatsAGenericLocalSubject() throws {
        let line = try XCTUnwrap(AlmanacSuggestionGenerator.suggestion(for: .init(
            townDate: "2026-08-05",
            userKey: "user-42",
            rsvps: [
                .init(
                    id: "event-market",
                    title: "Farmers Market",
                    eventDate: "2026-08-07",
                    startTime: "3pm",
                    location: "Resurrection Lutheran"
                ),
            ],
            subjects: localSubjects
        )))

        XCTAssertTrue(line.contains("Farmers Market"))
        XCTAssertTrue(line.contains("Resurrection Lutheran"))
        XCTAssertFalse(localSubjects.contains { line.contains($0.name) })
    }

    func testNoRSVPUsesAnInjectedLocalSubject() throws {
        let line = try XCTUnwrap(AlmanacSuggestionGenerator.suggestion(for: .init(
            townDate: "2026-08-05",
            userKey: "user-42",
            rsvps: [],
            subjects: [
                .init(id: "park-millstream", name: "Millstream Park", kind: .park),
            ]
        )))

        XCTAssertTrue(line.contains("Millstream Park"))
        XCTAssertFalse(line.contains("Wobegon"))
    }

    func testRecyclingLineAppearsWithinTwoDaysOfPickup() {
        let line = AlmanacCivicLine.text(
            on: date(2026, 1, 13),
            pickupWeekday: 5,
            schoolClosing: nil,
            calendar: calendar()
        )

        XCTAssertEqual(line, "Recycling week — bins out Wednesday night")
    }

    func testCivicLineIsAbsentOutsideThePickupWindow() {
        let line = AlmanacCivicLine.text(
            on: date(2026, 1, 16),
            pickupWeekday: 5,
            schoolClosing: nil,
            calendar: calendar()
        )

        XCTAssertNil(line)
    }

    func testSchoolClosingUsesTheReservedCivicSlot() {
        let line = AlmanacCivicLine.text(
            on: date(2026, 1, 16),
            pickupWeekday: 5,
            schoolClosing: "  St. Cloud Area Schools are closed today  ",
            calendar: calendar()
        )

        XCTAssertEqual(line, "St. Cloud Area Schools are closed today")
    }
}
