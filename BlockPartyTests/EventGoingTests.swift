//
//  EventGoingTests.swift
//  Who's going on an Event page (BP app inside-cards 36): whose faces, what the names say, and when it shows. Who may be
//  named at all is the server's (`supabase/tests/whos_going.test.mjs`).
//

import XCTest
@testable import BlockParty

final class EventGoingTests: XCTestCase {
    private func face(_ name: String, you: Bool = false) -> GoingWords.Face {
        .init(id: name, name: name, photo: nil, you: you)
    }
    private func make(_ count: Int, you: Bool = false, _ names: String...) -> GoingWords? {
        .make(count: count, you: you ? face("You", you: true) : nil, others: names.map { face($0) })
    }

    func testNobodyGoingShowsNothing() {
        XCTAssertNil(make(0))
    }

    func testFourFacesThenTheRest() throws {
        let words = try XCTUnwrap(make(6, "Sam", "Marlene", "Alex", "Ava", "Zoe"))
        XCTAssertEqual(words.faces.map(\.name), ["Sam", "Marlene", "Alex", "Ava"])
        XCTAssertEqual(words.more, 2)
        XCTAssertEqual(words.names, "Sam, Marlene, Alex, Ava, and 2 more")
    }

    func testYouLeadOnceGoing() throws {
        let words = try XCTUnwrap(make(7, you: true, "Sam", "Marlene", "Alex", "Ava"))
        XCTAssertEqual(words.faces.map(\.name), ["You", "Sam", "Marlene", "Alex"])
        XCTAssertEqual(words.names, "You, Sam, Marlene, Alex, and 3 more")
        XCTAssertEqual(make(1, you: true)?.names, "You")
    }

    func testTheWordsByHowMany() {
        XCTAssertEqual(GoingWords.line(["Sam"], more: 0), "Sam")
        XCTAssertEqual(GoingWords.line(["Sam"], more: 4), "Sam and 4 more")
        XCTAssertEqual(GoingWords.line(["Sam", "Ava"], more: 0), "Sam and Ava")
        XCTAssertEqual(GoingWords.line(["Sam", "Ava"], more: 1), "Sam, Ava, and 1 more")
    }

    /// Everyone Going is hidden (under 18, switched off): blank faces, the count, no names.
    func testNobodyToNameDrawsBlankFaces() throws {
        let words = try XCTUnwrap(make(2))
        XCTAssertEqual(words.faces.count, 2)
        XCTAssertEqual(words.more, 0)
        XCTAssertNil(words.names)
        XCTAssertEqual(make(9)?.more, 5)
    }

    /// The count is the feed's and can run behind the read: never fewer than it names.
    func testNeverFewerThanItNames() {
        XCTAssertEqual(make(1, "Sam", "Ava", "Bo")?.total, 3)
        XCTAssertEqual(make(1, "Sam", "Ava", "Bo")?.more, 0)
    }

    func testShowsOnlyForAnEventStillToCome() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func shows(cancelled: Bool = false, final: Bool = false, end: Date?) -> Bool {
            GoingWords.shows(cancelled: cancelled, final: final, end: end, now: now)
        }
        XCTAssertTrue(shows(end: now.addingTimeInterval(60)))
        XCTAssertTrue(shows(end: nil))
        XCTAssertFalse(shows(end: now))
        XCTAssertFalse(shows(cancelled: true, end: nil))
        XCTAssertFalse(shows(final: true, end: nil))
    }
}
