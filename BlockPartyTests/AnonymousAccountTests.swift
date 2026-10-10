//
//  AnonymousAccountTests.swift
//  The quiet anonymous account every install gets (BP app docs/plans/real-life-actions,
//  ticket 01): a session GoTrue marks anonymous reads as one, a session stored before
//  then reads as real, and a card shows no going line at zero.
//

import XCTest
@testable import BlockParty

@MainActor
final class AnonymousAccountTests: XCTestCase {

    private func session(user: String) throws -> Session {
        let json = """
        {"access_token":"a","refresh_token":"r","expires_at":2000000000,"token_type":"bearer",
         "user":\(user)}
        """
        return try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    /// GoTrue's answer to an anonymous sign-up, trimmed to what the app reads.
    func testAnAnonymousSignUpReadsAsAnonymous() throws {
        let s = try session(user: #"{"id":"u1","email":"","is_anonymous":true,"role":"authenticated"}"#)
        XCTAssertEqual(s.user.isAnonymous, true)
    }

    /// Sessions in the Keychain from before anonymous accounts carry no flag: real.
    func testASessionStoredBeforeAnonymousAccountsReadsAsReal() throws {
        let s = try session(user: #"{"id":"u1","email":"sam@example.com"}"#)
        XCTAssertNil(s.user.isAnonymous)
        // And it round-trips through the Keychain's encoding unchanged.
        let again = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(again, s)
    }

    /// A card shows who's going only where RSVPs can be read, and never at zero, as
    /// the event page never shows a zero count.
    func testACardShowsNoGoingLineAtZero() {
        func card(going: Int, canJoin: Bool) -> FeedCardItem {
            var item = FeedCardItem(UpcomingEvent(id: "e", title: "Trivia", eventDate: "2026-10-12",
                                                  startTime: "7 PM", location: nil, goingCount: going,
                                                  createdAt: "2026-10-06T16:08:20+00:00"))
            item.canJoin = canJoin
            return item
        }
        XCTAssertFalse(card(going: 0, canJoin: true).showsGoingLine)
        XCTAssertTrue(card(going: 2, canJoin: true).showsGoingLine)
        XCTAssertFalse(card(going: 2, canJoin: false).showsGoingLine)
    }
}
