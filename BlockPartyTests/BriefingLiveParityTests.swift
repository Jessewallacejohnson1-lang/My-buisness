//
//  BriefingLiveParityTests.swift
//  Block Party — the fixture and the live RPC must agree.
//
//  The fixtures are hand-written; the RPC is not. This pins a payload captured
//  VERBATIM from production (`select get_today_briefing('2026-08-05',
//  'America/Chicago')` against lxdgwhvqjqmqliobwjpi) so a server-side change that
//  drifts from the contract fails here rather than as a blank Today tab.
//
//  Note what real Postgres output carries that the fixtures do not: key order is
//  arbitrary, `weather` is null, `almanac.line` is null with source "town", and
//  `published_at` has SIX fractional digits.
//

import XCTest
@testable import BlockParty

final class BriefingLiveParityTests: XCTestCase {

    /// Captured from production, unedited.
    private static let livePayload = #"""
    {"tz": "America/Chicago", "touch": {"id": "c33d8db0-bdae-4e0b-80ca-86a74c4846c6", "body": null, "kind": "poll", "prompt": "How do you take your sweet corn?", "my_vote": null, "options": ["Butter and salt, done", "Butter, salt, pepper", "Straight off the cob, dry", "Cut off, in a bowl"], "total_votes": 0, "vote_counts": [0, 0, 0, 0]}, "status": "published", "almanac": {"line": null, "format": null, "source": "town", "town_line": "Early August, and the evenings pull back a little earlier each night."}, "weather": null, "featured": [{"id": "46fa2aea-181e-404a-b1ce-a8b0b0ec3b80", "rank": 1, "liked": false, "rsvpd": false, "saved": false, "title": "St. Joseph Farmers Market", "category": "other", "location": "Lake Wobegon Trailhead, County Rd 2, St. Joseph", "club_name": null, "image_url": null, "event_date": "2026-08-07", "like_count": 0, "start_time": "3 PM", "going_count": 0, "comment_count": 0, "going_avatars": []}], "caught_up": {"label": "New briefing at 6 AM", "next_briefing_at": "2026-08-06T11:00:00+00:00"}, "spotlight": {"id": "8aba6e16-84c7-49d1-9b65-161425860254", "slug": "downtown", "blurb": "A few walkable blocks of Minnesota Street: locally-owned coffee, a deli, a brewery taproom, and storefronts where the person behind the counter tends to know your order.", "title": "Downtown", "place_id": null, "image_url": null}, "published_at": "2026-08-05T22:25:29.979108+00:00", "briefing_date": "2026-08-05", "featured_fallback": null}
    """#

    private func decodeLive() throws -> BriefingPayload {
        try SupabaseCoding.decoder.decode(BriefingPayload.self, from: Data(Self.livePayload.utf8))
    }

    func testTheLiveRPCPayloadDecodes() throws {
        XCTAssertNoThrow(try decodeLive())
    }

    /// Postgres emits microseconds. This is the exact string production returned.
    func testMicrosecondPublishedAtDecodes() throws {
        XCTAssertNotNil(try decodeLive().publishedAt)
    }

    func testEveryModuleMapsToTheRightSwiftShape() throws {
        let p = try decodeLive()
        XCTAssertEqual(p.status, .published)
        XCTAssertEqual(p.briefingDate, "2026-08-05")
        XCTAssertEqual(p.tz, "America/Chicago")

        // Weather genuinely absent — the routine composed this day without a
        // snapshot, and the briefing still has to render.
        XCTAssertNil(p.weather)

        // No personal almanac row for the caller, so the town line carries it.
        let almanac = try XCTUnwrap(p.almanac)
        XCTAssertNil(almanac.line)
        XCTAssertFalse(almanac.isPersonal)
        XCTAssertEqual(almanac.displayLine, almanac.townLine)

        XCTAssertEqual(p.featured.count, 1)
        let event = try XCTUnwrap(p.featured.first)
        XCTAssertEqual(event.rank, 1)
        XCTAssertEqual(event.title, "St. Joseph Farmers Market")
        XCTAssertEqual(event.startTime, "3 PM", "start_time is free text, not a Date")
        XCTAssertEqual(event.eventDate, "2026-08-07")
        XCTAssertTrue(event.goingAvatars.isEmpty)
        XCTAssertNil(event.imageURL)

        let touch = try XCTUnwrap(p.touch)
        XCTAssertEqual(touch.kind, .poll)
        XCTAssertEqual(touch.choices.count, 4)
        XCTAssertEqual(touch.voteCounts, [0, 0, 0, 0])
        XCTAssertFalse(touch.hasVoted)

        XCTAssertEqual(p.spotlight?.slug, "downtown")
        XCTAssertEqual(p.caughtUp.label, "New briefing at 6 AM")
    }

    /// The invariants the RPC guarantees, checked against real output rather than
    /// against a fixture I wrote to satisfy them.
    func testLivePayloadHoldsTheContractInvariants() throws {
        let p = try decodeLive()
        XCTAssertEqual(p.featured.map(\.rank), Array(1...p.featured.count))
        let touch = try XCTUnwrap(p.touch)
        XCTAssertEqual(touch.voteCounts.count, touch.choices.count)
        XCTAssertEqual(touch.voteCounts.reduce(0, +), touch.totalVotes)
        XCTAssertEqual(p.featuredFallback != nil,
                       p.featured.isEmpty && p.status == .published)
    }

    /// A one-event day renders the hero, not the carousel — and with only a couple
    /// of upcoming events in production, this is the normal case, not an edge one.
    func testTheLiveDayIsAHeroDay() throws {
        XCTAssertEqual(try decodeLive().featured.count, 1)
    }

    // MARK: - Offline

    /// The morning bad-wifi case: whatever the RPC returned is written to disk
    /// verbatim and must decode back to an identical payload with no network.
    @MainActor
    func testCachedBytesReplayToAnIdenticalPayloadOffline() throws {
        let raw = Data(Self.livePayload.utf8)
        BriefingCache.clear()
        XCTAssertNil(BriefingCache.load(), "cache should start empty")

        BriefingCache.save(raw)
        let restored = try XCTUnwrap(BriefingCache.load(), "a saved briefing must reload")
        XCTAssertEqual(restored, try decodeLive(),
                       "the offline copy must equal what the server sent")

        BriefingCache.clear()
        XCTAssertNil(BriefingCache.load())
    }

    /// A contract change ships a new shape. A stale cache must miss quietly, never
    /// crash the tab.
    @MainActor
    func testAnUndecodableCacheMissesRatherThanThrowing() {
        BriefingCache.save(Data(#"{"nonsense": true}"#.utf8))
        XCTAssertNil(BriefingCache.load())
        BriefingCache.clear()
    }
}
