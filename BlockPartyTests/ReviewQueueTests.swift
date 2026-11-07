//
//  ReviewQueueTests.swift
//  The admin Review queue: each item's words and why it waits (BP app launch-ready 07), how its reads
//  decode, and its decline reasons (ADR-021).
//

import XCTest
@testable import BlockParty

final class ReviewQueueTests: XCTestCase {

    func testWhenIsTheDayTheTimeThenWhere() {
        XCTAssertEqual(ReviewRow.when(eventDate: "2026-11-09", startTime: "5:30 PM", allDay: false,
                                      location: "Episcopal House of Prayer"),
                       "Mon, Nov 9 · 5:30 PM · Episcopal House of Prayer")
        XCTAssertEqual(ReviewRow.when(eventDate: "2026-11-09", startTime: nil, allDay: true, location: "610 County Rd 2"),
                       "Mon, Nov 9 · All day · 610 County Rd 2")
        // An everyday post has no day: only where, when it says.
        XCTAssertEqual(ReviewRow.when(eventDate: nil, startTime: nil, allDay: false, location: "Klinefelter Park"),
                       "Klinefelter Park")
        XCTAssertEqual(ReviewRow.when(eventDate: nil, startTime: nil, allDay: false, location: ""), "")
    }

    /// The instant check stamps `checked_at` when it was asked; a found Event's top line already says why.
    func testHeldTagSaysWhyItWaits() {
        XCTAssertEqual(ReviewRow.heldTag(found: false, checkedAt: "2026-11-07T19:00:00+00:00"), "Held: the check didn't answer")
        XCTAssertEqual(ReviewRow.heldTag(found: false, checkedAt: nil), "Held: not checked")
        XCTAssertNil(ReviewRow.heldTag(found: true, checkedAt: nil))
    }

    func testReportTagSaysWhenAndWhy() {
        XCTAssertEqual(ReviewRow.reportTag(reasons: ["wrong_info"], reports: 1, firstAt: "2026-10-26T14:00:00+00:00"),
                       "Reported Oct 26: Wrong info")
        // Late evening in town is still that day, though it is the next in UTC.
        XCTAssertEqual(ReviewRow.reportTag(reasons: ["wrong_info"], reports: 1, firstAt: "2026-10-27T03:30:00+00:00"),
                       "Reported Oct 26: Wrong info")
        XCTAssertEqual(ReviewRow.reportTag(reasons: ["scam", "wrong_info"], reports: 3, firstAt: "2026-10-26T14:00:00+00:00"),
                       "3 reports: Scam, fraud or spam, Wrong info")
        XCTAssertEqual(ReviewRow.reportTag(reasons: ["wrong_info"], reports: 1, firstAt: nil), "Reported: Wrong info")
    }

    func testAgeIsHowLongAgoOrWhenFound() {
        let now = DateHelpers.timestamp("2026-11-07T21:00:00+00:00")!
        XCTAssertEqual(ReviewRow.age(createdAt: "2026-11-07T19:00:00+00:00", found: false, now: now), "2h")
        XCTAssertEqual(ReviewRow.age(createdAt: "2026-11-07T13:00:00+00:00", found: true, now: now), "found today")
        XCTAssertEqual(ReviewRow.age(createdAt: "2026-10-19T17:00:00+00:00", found: true, now: now), "found Oct 19")
        XCTAssertNil(ReviewRow.age(createdAt: nil, found: true, now: now))
    }

    /// `list_held` as the server sends it: an Event opens its page, an everyday post (no date) still comes
    /// through with its words and poster, and a deleted poster is no poster.
    @MainActor func testHeldItemsDecodeEvenWithoutADate() throws {
        let json = """
        [{"id": "e1", "kind": "event", "checked_at": "2026-11-07T19:00:00+00:00",
          "card": {"id": "e1", "title": "Bingo night", "event_date": "2026-11-10", "start_time": "6:30 PM",
                   "location": "Sal's", "description": "Bring a friend", "going_count": 0,
                   "created_at": "2026-11-07T19:00:00+00:00", "image_url": null, "source_name": null},
          "poster": {"id": "u1", "name": "Maya", "photo": null, "tagged": []}},
         {"id": "p1", "kind": "post", "checked_at": null,
          "card": {"id": "p1", "title": "Lost cat", "event_date": null, "going_count": 0,
                   "created_at": "2026-11-07T17:00:00+00:00",
                   "image_url": "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/u1/a.jpg"},
          "poster": null}]
        """
        let rows = try Supabase.decode(Data(json.utf8), as: [PendingPost].self)
        XCTAssertEqual(rows.map(\.id), ["e1", "p1"])
        XCTAssertEqual(rows[0].card.event?.title, "Bingo night")
        XCTAssertEqual(rows[0].card.description, "Bring a friend")
        XCTAssertEqual(rows[0].poster?.name, "Maya")
        XCTAssertNotNil(rows[0].checkedAt)
        XCTAssertEqual(rows[1].kind, .post)
        XCTAssertNil(rows[1].card.event, "a post has no day, so no Event page")
        XCTAssertEqual(rows[1].card.picture?.lastPathComponent, "a.jpg")
        XCTAssertNil(rows[1].poster)
    }

    func testAReportedEventDecodesItsCardAndPoster() throws {
        let json = """
        [{"event_id": "e1", "title": "Craft fair", "event_date": "2026-11-09", "reasons": ["wrong_info"], "reports": 1,
          "first_at": "2026-10-26T14:00:00+00:00",
          "card": {"id": "e1", "title": "Craft fair", "event_date": "2026-11-09", "going_count": 4,
                   "created_at": "2026-10-19T17:00:00+00:00", "description": "Local makers",
                   "source_name": "CSB SJU Campus Events"},
          "poster": null}]
        """
        let report = try XCTUnwrap(Supabase.decode(Data(json.utf8), as: [ReportedEvent].self).first)
        XCTAssertEqual(report.tag, "Reported Oct 26: Wrong info")
        XCTAssertEqual(report.card?.description, "Local makers")
        XCTAssertEqual(report.card?.found, true)
        XCTAssertEqual(report.card?.event?.goingCount, 4)
    }

    /// The database's check constraint accepts exactly these values.
    func testDeclineReasonsMatchTheDatabase() {
        XCTAssertEqual(DeclineReason.allCases.map(\.rawValue),
                       ["not_event", "wrong_when", "wrong_place", "wrong_title", "other"])
    }
}
