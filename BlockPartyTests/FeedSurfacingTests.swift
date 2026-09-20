//
//  FeedSurfacingTests.swift
//  BlockPartyTests — the Town feed's surfacing window.
//
//  Town is one-time news, not a standing calendar. A posting gets its debut day
//  and the week running up to the event; a recurring series gets the debut only.
//  These are pure date rules, so they are tested against fixed "today" strings
//  rather than the clock.
//

import XCTest
@testable import BlockParty

final class FeedSurfacingTests: XCTestCase {

    // MARK: A one-time posting — debut, then quiet, then the week of

    func testPostingIsVisibleOnTheDayItWasPosted() {
        let announced = deduped([
            posting("fair", title: "Street Fair", eventDate: "2026-11-14", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(announced, today: "2026-09-19"), ["fair"])
    }

    func testPostingGoesQuietBetweenItsDebutAndTheWeekOfTheEvent() {
        let announced = deduped([
            posting("fair", title: "Street Fair", eventDate: "2026-11-14", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(announced, today: "2026-09-20"), [])
        XCTAssertEqual(visibleIDs(announced, today: "2026-10-15"), [])
        // Eight days out is still quiet — the window opens at seven.
        XCTAssertEqual(visibleIDs(announced, today: "2026-11-06"), [])
    }

    func testPostingReturnsForTheWeekOfTheEventThroughTheEventDay() {
        let announced = deduped([
            posting("fair", title: "Street Fair", eventDate: "2026-11-14", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(announced, today: "2026-11-07"), ["fair"])   // seven days out
        XCTAssertEqual(visibleIDs(announced, today: "2026-11-13"), ["fair"])   // day before
        XCTAssertEqual(visibleIDs(announced, today: "2026-11-14"), ["fair"])   // day of
    }

    func testPostingDisappearsAfterTheEvent() {
        let announced = deduped([
            posting("fair", title: "Street Fair", eventDate: "2026-11-14", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(announced, today: "2026-11-15"), [])
    }

    func testEventPostedInsideItsOwnWeekStaysVisibleThrough() {
        let announced = deduped([
            posting("potluck", title: "Potluck", eventDate: "2026-09-22", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(announced, today: "2026-09-19"), ["potluck"])
        XCTAssertEqual(visibleIDs(announced, today: "2026-09-21"), ["potluck"])
        XCTAssertEqual(visibleIDs(announced, today: "2026-09-22"), ["potluck"])
    }

    // MARK: A recurring series — news once, never a repeat

    func testRecurringSeriesShowsOnceOnItsDebutDay() {
        let yoga = deduped([
            posting("yoga-1", title: "Yoga Club", eventDate: "2026-09-26", postedOn: "2026-09-19"),
            posting("yoga-2", title: "Yoga Club", eventDate: "2026-10-03", postedOn: "2026-09-19"),
            posting("yoga-3", title: "Yoga Club", eventDate: "2026-10-10", postedOn: "2026-09-19")
        ])

        // One card, not three, and it is labelled as the series.
        XCTAssertEqual(visibleIDs(yoga, today: "2026-09-19"), ["yoga-1"])
        XCTAssertEqual(yoga.first?.recurrence, "WEEKLY · SAT")
    }

    func testRecurringSeriesNeverReturnsForTheWeekOfAnOccurrence() {
        let yoga = deduped([
            posting("yoga-1", title: "Yoga Club", eventDate: "2026-09-26", postedOn: "2026-09-19"),
            posting("yoga-2", title: "Yoga Club", eventDate: "2026-10-03", postedOn: "2026-09-19"),
            posting("yoga-3", title: "Yoga Club", eventDate: "2026-10-10", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(yoga, today: "2026-09-22"), [])   // the week of yoga-1
        XCTAssertEqual(visibleIDs(yoga, today: "2026-09-26"), [])   // the day of yoga-1
    }

    /// The dedupe keeps the NEAREST upcoming occurrence, whose row may have been
    /// written long after the series began. Debut has to be the series' first
    /// posting or every newly-added Saturday re-announces the same club.
    func testRecurringDebutIsTheEarliestPostingInTheSeries() {
        let yoga = deduped([
            posting("yoga-old", title: "Yoga Club", eventDate: "2026-09-26", postedOn: "2026-06-01"),
            posting("yoga-mid", title: "Yoga Club", eventDate: "2026-10-03", postedOn: "2026-09-19"),
            posting("yoga-new", title: "Yoga Club", eventDate: "2026-10-10", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(yoga, today: "2026-06-01"), ["yoga-old"])
        // The day a later Saturday was added is NOT a second debut.
        XCTAssertEqual(visibleIDs(yoga, today: "2026-09-19"), [])
    }

    // MARK: Postings with no event date

    func testUndatedPostingShowsOnItsDebutDayOnly() {
        let note = deduped([
            posting("note", title: "Road Closed on Minnesota St", eventDate: nil, postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(note, today: "2026-09-19"), ["note"])
        XCTAssertEqual(visibleIDs(note, today: "2026-09-20"), [])
    }

    // MARK: Same-titled one-offs are not a series

    func testIrregularlySpacedSameTitledPostingsKeepTheirOwnWindows() {
        // No consistent cadence → dedupe leaves them as separate postings, so each
        // one earns its own debut and its own week-of.
        let socials = deduped([
            posting("social-1", title: "Town Social", eventDate: "2026-09-23", postedOn: "2026-09-19"),
            posting("social-2", title: "Town Social", eventDate: "2026-09-28", postedOn: "2026-09-19")
        ])

        XCTAssertEqual(visibleIDs(socials, today: "2026-09-19"), ["social-1", "social-2"])
        XCTAssertEqual(visibleIDs(socials, today: "2026-09-22"), ["social-1", "social-2"])
        // social-1 has passed; social-2 is still inside its week.
        XCTAssertEqual(visibleIDs(socials, today: "2026-09-24"), ["social-2"])
    }

    // MARK: Helpers

    private func deduped(_ postings: [FeedPosting]) -> [FeedRecurringPosting] {
        dedupeRecurring(postings, today: "2026-09-19")
    }

    private func visibleIDs(
        _ items: [FeedRecurringPosting],
        today: String
    ) -> [String] {
        townSurfacing(items, today: today).map(\.posting.id)
    }

    /// Local noon on a YYYY-MM-DD day — midday so no timezone shift can roll the
    /// date over into a neighbouring day.
    private func noon(_ ymd: String) -> Date {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    private func posting(
        _ id: String,
        title: String,
        eventDate: String?,
        postedOn: String
    ) -> FeedPosting {
        FeedPosting(
            id: id,
            title: title,
            eventDate: eventDate,
            startTime: nil,
            location: nil,
            imageUrl: nil,
            createdAt: noon(postedOn),
            posterName: "Neighbor",
            posterAvatar: nil,
            posterTarget: FollowTarget(type: .profile, id: "poster"),
            followerCount: 0,
            likeCount: 0,
            commentCount: 0,
            goingCount: 0,
            liked: false,
            following: false,
            rsvpd: false
        )
    }
}
