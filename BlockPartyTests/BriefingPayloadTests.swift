//
//  BriefingPayloadTests.swift
//  Block Party — the briefing contract, pinned.
//
//  These decode the real fixture files rather than inline literals, so the Swift
//  types and `fixtures/briefing_*.json` cannot drift apart silently. If the
//  contract changes, this fails first.
//

import XCTest
@testable import BlockParty

final class BriefingPayloadTests: XCTestCase {

    // fixtures/ sits at the repo root, next to BlockPartyTests/.
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // BlockPartyTests/
        .deletingLastPathComponent()      // repo root
        .appendingPathComponent("fixtures")

    private func load(_ name: String) throws -> BriefingPayload {
        let url = Self.fixturesDir.appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try SupabaseCoding.decoder.decode(BriefingPayload.self, from: data)
    }

    private static let allFixtures = [
        "briefing_sample", "briefing_one_event", "briefing_zero_events",
        "briefing_voted", "briefing_none", "briefing_degraded",
    ]

    // MARK: - Every fixture decodes

    func testAllFixturesDecode() throws {
        for name in Self.allFixtures {
            XCTAssertNoThrow(try load(name), "fixture \(name) failed to decode")
        }
    }

    func testCaughtUpIsNeverNilInAnyFixture() throws {
        for name in Self.allFixtures {
            let p = try load(name)
            XCTAssertFalse(p.caughtUp.label.isEmpty, "\(name) has empty caught-up label")
        }
    }

    // MARK: - Contract invariants

    func testVoteCountsAreIndexAlignedAndSumToTotal() throws {
        for name in Self.allFixtures {
            guard let touch = try load(name).touch else { continue }
            XCTAssertEqual(touch.voteCounts.count, touch.choices.count,
                           "\(name): vote_counts is not index-aligned with options")
            XCTAssertEqual(touch.voteCounts.reduce(0, +), touch.totalVotes,
                           "\(name): vote_counts does not sum to total_votes")
        }
    }

    func testFeaturedRanksAreContiguousFromOne() throws {
        for name in Self.allFixtures {
            let ranks = try load(name).featured.map(\.rank)
            XCTAssertEqual(ranks, Array(1...max(ranks.count, 1)).prefix(ranks.count).map { $0 },
                           "\(name): featured ranks are not 1...n")
        }
    }

    /// The fallback carries the Happening Soon slot exactly when there are no
    /// events AND a briefing was actually published. On a `none` day there is no
    /// row, so there is no fallback copy either.
    func testFallbackPresenceMatchesEmptyFeatured() throws {
        for name in Self.allFixtures {
            let p = try load(name)
            let expected = p.featured.isEmpty && p.status == .published
            XCTAssertEqual(p.featuredFallback != nil, expected,
                           "\(name): featured_fallback presence is wrong")
        }
    }

    // MARK: - Specific states

    func testSampleHasThreeEventsAndAnUnvotedPoll() throws {
        let p = try load("briefing_sample")
        XCTAssertEqual(p.status, .published)
        XCTAssertEqual(p.featured.count, 3)
        XCTAssertEqual(p.featured.first?.title, "Music in Millstream Park")
        XCTAssertEqual(p.touch?.kind, .poll)
        XCTAssertFalse(p.touch?.hasVoted ?? true)
        XCTAssertNotNil(p.spotlight)
        XCTAssertNotNil(p.weather)
    }

    func testOneEventFixtureDrivesTheHeroVariant() throws {
        let p = try load("briefing_one_event")
        XCTAssertEqual(p.featured.count, 1)
        XCTAssertNil(p.featuredFallback)
    }

    func testZeroEventsFallsBackToEvergreen() throws {
        let p = try load("briefing_zero_events")
        XCTAssertTrue(p.featured.isEmpty)
        XCTAssertEqual(p.featuredFallback?.kind, "evergreen")
        XCTAssertFalse(p.featuredFallback?.body.isEmpty ?? true)
    }

    func testVotedFixtureReportsTheUsersChoice() throws {
        let touch = try XCTUnwrap(try load("briefing_voted").touch)
        XCTAssertTrue(touch.hasVoted)
        XCTAssertEqual(touch.myVote, 0)
    }

    func testNoneStateHasEveryModuleNil() throws {
        let p = try load("briefing_none")
        XCTAssertEqual(p.status, .none)
        XCTAssertTrue(p.isUnavailable)
        XCTAssertNil(p.almanac)
        XCTAssertNil(p.weather)
        XCTAssertNil(p.touch)
        XCTAssertNil(p.spotlight)
        XCTAssertNil(p.featuredFallback)
        XCTAssertTrue(p.featured.isEmpty)
    }

    func testDegradedStateStillRendersACaughtUpFooter() throws {
        let p = try load("briefing_degraded")
        XCTAssertEqual(p.status, .published)
        XCTAssertNil(p.almanac)
        XCTAssertNotNil(p.featuredFallback)
        XCTAssertFalse(p.caughtUp.label.isEmpty)
    }

    // MARK: - Behaviour

    func testShareIsZeroOnAnUnvotedPollRatherThanDividingByZero() throws {
        let json = #"""
        {"id":"x","kind":"poll","prompt":"p","options":["a","b"],"body":null,
         "vote_counts":[0,0],"total_votes":0,"my_vote":null}
        """#
        let touch = try SupabaseCoding.decoder.decode(BriefingTouch.self, from: Data(json.utf8))
        XCTAssertEqual(touch.share(at: 0), 0)
        XCTAssertEqual(touch.share(at: 5), 0, "out-of-range index must not trap")
        XCTAssertEqual(touch.count(at: 5), 0)
    }

    func testAlmanacFallsBackToTheTownLineWhenPersonalIsMissing() throws {
        let json = #"""
        {"line":null,"format":null,"source":"town","town_line":"Town copy."}
        """#
        let a = try SupabaseCoding.decoder.decode(BriefingAlmanac.self, from: Data(json.utf8))
        XCTAssertEqual(a.displayLine, "Town copy.")
        XCTAssertFalse(a.isPersonal)
    }

    /// Postgres emits microsecond precision (6 fractional digits). The shared
    /// decoder's fractional formatter has to accept that, not just milliseconds.
    func testDecodesPostgresMicrosecondTimestamps() throws {
        let json = #"""
        {"next_briefing_at":"2026-08-05T22:52:40.201967+00:00","label":"New briefing at 6 AM"}
        """#
        XCTAssertNoThrow(
            try SupabaseCoding.decoder.decode(BriefingCaughtUp.self, from: Data(json.utf8)),
            "PostgREST microsecond timestamps must decode"
        )
    }

    func testUnknownStatusDecodesToNoneRatherThanThrowing() throws {
        XCTAssertEqual(
            try SupabaseCoding.decoder.decode(BriefingStatus.self, from: Data(#""archived""#.utf8)),
            .none
        )
    }
}
