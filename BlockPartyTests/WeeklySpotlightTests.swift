//
//  WeeklySpotlightTests.swift
//  BlockPartyTests
//

import XCTest
@testable import BlockParty

final class WeeklySpotlightTests: XCTestCase {
    func testWeekIdentifierStaysStableFromMondayThroughSunday() {
        XCTAssertEqual(SpotlightWeek.identifier(for: "2026-08-03"), "2026-W32")
        XCTAssertEqual(SpotlightWeek.identifier(for: "2026-08-09"), "2026-W32")
    }

    func testWeekIdentifierChangesAtMondayBoundary() {
        XCTAssertEqual(SpotlightWeek.identifier(for: "2026-08-09"), "2026-W32")
        XCTAssertEqual(SpotlightWeek.identifier(for: "2026-08-10"), "2026-W33")
    }

    func testArchiveKeepsPastWeekAfterASecondWeekIsAssigned() {
        var archive = SpotlightArchive()
        archive.assign(spotlightID: "sacred-heart", for: "2026-08-03")
        archive.assign(spotlightID: "saint-johns", for: "2026-08-10")

        XCTAssertEqual(archive.spotlightID(for: "2026-08-03"), "sacred-heart")
        XCTAssertEqual(archive.spotlightID(for: "2026-08-10"), "saint-johns")
    }

    func testArchiveKeepsFirstAssignmentForEveryDayInAWeek() {
        var archive = SpotlightArchive()
        archive.assign(spotlightID: "wobegon", for: "2026-08-03")
        archive.assign(spotlightID: "downtown", for: "2026-08-09")

        XCTAssertEqual(archive.spotlightID(for: "2026-08-09"), "wobegon")
    }

    func testSignOffUsesTheTownWeekday() {
        XCTAssertEqual(
            SignOffCopy.line(for: "2026-08-05"),
            "That's St. Joe for Wednesday. See you tomorrow."
        )
    }

    func testMapLinkIsAbsentWithoutAPlaceID() {
        XCTAssertNil(
            SpotlightMapLink.url(
                placeID: nil,
                title: "Sacred Heart Chapel"
            )
        )
    }
}
