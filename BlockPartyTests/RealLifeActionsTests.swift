//
//  RealLifeActionsTests.swift
//  BlockPartyTests — the app's one home for Going (`RealLifeActions`), driven the way
//  the card and the event page drive it, against a stand-in server. The 600 ms hold
//  and 0.18 s flip come in shorter, so these run fast; the order of what happens is
//  the same.
//

import XCTest
@testable import BlockParty

@MainActor
final class RealLifeActionsTests: XCTestCase {

    private static let hold: Duration = .milliseconds(150)
    private static let flip: Duration = .milliseconds(90)

    /// Records every write, and fails or takes its time when told to.
    @MainActor
    private final class Server {
        var writes: [Bool] = []
        var failing = false
        var delay: Duration = .zero

        func write(_ eventID: String, _ going: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            writes.append(going)
            if failing { throw URLError(.notConnectedToInternet) }
        }
    }

    private func actions(_ server: Server, signedIn: Bool = true) -> RealLifeActions {
        RealLifeActions(signedIn: signedIn, needsAccount: true, hold: Self.hold, flip: Self.flip,
                        setGoing: server.write)
    }

    private func card(going: Int = 4, joined: Bool = false) -> FeedCardItem {
        FeedCardItem(UpcomingEvent(id: "e1", title: "Trivia night", eventDate: "2026-10-12",
                                   startTime: "7 PM", location: nil, goingCount: going,
                                   createdAt: "2026-10-06T16:08:20+00:00", rsvpd: joined))
    }

    func testAJoinShowsAtOnceAndStays() async throws {
        let server = Server()
        let actions = actions(server)
        let item = card()

        actions.toggleGoing(item)
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 5), "Going at once, counting you")

        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.writes, [true])
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 5), "a Join that lands stays")
        XCTAssertEqual(actions.failureCount(item.id), 0)
    }

    /// A failed Join holds "Going" for the hold, turns back, and counts one failure only
    /// once the flip is done, so the page never shakes the two faces mid cross-fade.
    func testAFailedJoinHoldsThenTurnsBackThenCountsOneFailure() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.pageOpened(item.id)

        let tapped = ContinuousClock.now
        actions.toggleGoing(item)
        try await waitWhile(actions.going(item).isGoing)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, Self.hold, "turned back before it could be seen")
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 4), "back to Join, count and all")
        XCTAssertEqual(actions.failureCount(item.id), 0, "Join first: no shake while it turns back")

        let flipped = ContinuousClock.now
        try await waitWhile(actions.failureCount(item.id) == 0)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - flipped, Self.flip - .milliseconds(5))
        XCTAssertEqual(actions.failureCount(item.id), 1, "one turn back, one shake")
    }

    /// A tap while a failed write waits to turn back goes straight back to Join, writes
    /// nothing, and is no failure: the neighbour asked for the state they get. A tap
    /// after the turn back but before its shake cancels that shake.
    func testATapDuringTheWaitTurnsBackAtOnce() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.pageOpened(item.id)

        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(server.writes, [true], "the write has failed; the face still holds")
        actions.toggleGoing(item)
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 4), "Join at once")
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertFalse(actions.going(item).isGoing, "and nothing flips it back to Going")
        XCTAssertEqual(server.writes, [true], "the server never changed, so nothing to undo")
        XCTAssertEqual(actions.failureCount(item.id), 0)

        actions.toggleGoing(item)
        try await waitWhile(actions.going(item).isGoing)
        actions.toggleGoing(item)
        XCTAssertTrue(actions.going(item).isGoing, "a tap before the shake shows Going at once")
        try await waitWhile(actions.going(item).isGoing)
        try await waitWhile(actions.failureCount(item.id) == 0)
        XCTAssertEqual(actions.failureCount(item.id), 1, "only the Join that ran its course shakes")
    }

    /// Join then Leave before the first write answers: the writes go one after the other,
    /// never cancelled, so the last tap is what the server ends with.
    func testTheLastTapWins() async throws {
        let server = Server()
        server.delay = .milliseconds(30)
        let actions = actions(server)
        let item = card()

        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(5))
        actions.toggleGoing(item)
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 4))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(server.writes, [true, false], "Leave lands after Join, never before")
        XCTAssertFalse(actions.going(item).isGoing)

        // Three quick taps while the first write is out: the last choice is the same as
        // the one being written, so nothing more is sent.
        server.writes = []
        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(5))
        actions.toggleGoing(item)
        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(server.writes, [true])
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 5))
    }

    /// Popped before a failed Join turns back: it still turns back, so the card behind
    /// shows the truth, but nothing shakes or buzzes on the screen underneath.
    func testAClosedPageCountsNoShake() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.pageOpened(item.id)

        actions.toggleGoing(item)
        actions.pageClosed(item.id)
        try await Task.sleep(for: (Self.hold + Self.flip) * 3)
        XCTAssertFalse(actions.going(item).isGoing, "the card goes back to the truth")
        XCTAssertEqual(actions.failureCount(item.id), 0, "no shake, and so no buzz, once the page has gone")
    }

    /// The card holds the item from the latest read; the page holds the one it was
    /// pushed with. They show the same Going.
    func testTheCardAndThePageReadTheSameState() async throws {
        let server = Server()
        let actions = actions(server)
        let pushed = card(going: 4)
        let fresher = card(going: 6)
        actions.read([fresher])
        XCTAssertEqual(actions.going(pushed), actions.going(fresher), "the page sees the newer read")

        actions.toggleGoing(pushed)
        XCTAssertEqual(actions.going(fresher), .init(isGoing: true, count: 7), "a Join on the page shows on the card")
        XCTAssertEqual(actions.goingLine(fresher), "7 going")
    }

    /// A read sets each Event's base. A choice the read agrees with is done; one it
    /// doesn't agree with yet stays, counted from the read's number.
    func testAFeedReadReplacesTheBase() async throws {
        let server = Server()
        server.delay = .milliseconds(40)
        let actions = actions(server)
        let item = card(going: 4)

        actions.toggleGoing(item)
        actions.read([card(going: 9)])
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 10),
                       "a read from before the write lands keeps the Join, on the read's count")
        try await Task.sleep(for: .milliseconds(100))

        actions.read([card(going: 10, joined: true)])
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 10), "the read agrees")
        actions.read([card(going: 3, joined: false)])
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 3),
                       "once confirmed, the next read is the truth")
    }

    func testNoAccountMeansNoAction() async throws {
        let server = Server()
        let actions = actions(server, signedIn: false)
        let item = card(going: 2)

        actions.toggleGoing(item)
        XCTAssertFalse(actions.going(item).isGoing)
        try await Task.sleep(for: Self.hold)
        XCTAssertEqual(server.writes, [])
        XCTAssertNil(actions.goingLine(item), "no account: no going line")

        actions.accountChanged(signedIn: true)
        XCTAssertTrue(actions.canAct, "the quiet account arrives: Join comes up")
        XCTAssertEqual(actions.goingLine(item), "2 going")
        XCTAssertNil(actions.goingLine(card(going: 0)), "never at zero")
    }

    /// The account changes while a write is out (the quiet account replacing a cleared
    /// one): that write's failure turns nothing back for the new account, and the new
    /// account's own tap is written, even when it matches what the old write sent.
    func testANewAccountIgnoresTheLastOnesWrite() async throws {
        let server = Server()
        server.delay = .milliseconds(40)
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.pageOpened(item.id)

        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(5))
        actions.accountChanged(signedIn: true)
        XCTAssertFalse(actions.going(item).isGoing, "the last account's choice is gone")
        try await Task.sleep(for: (Self.hold + Self.flip) * 2)
        XCTAssertFalse(actions.going(item).isGoing)
        XCTAssertEqual(actions.failureCount(item.id), 0, "no shake for the last account's write")

        server.failing = false
        server.writes = []
        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(5))
        actions.accountChanged(signedIn: true)
        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(server.writes, [true, true], "the new account's Join is sent, not assumed")
        XCTAssertTrue(actions.going(item).isGoing)
    }

    /// Sample mode's writes go nowhere, so a Join on a sample card never reaches the
    /// live database; offline's always fail. Release builds always write for real.
    func testSampleModeNeverWritesLive() {
        XCTAssertEqual(RealLifeActions.backend(for: ["-open-tab", "town", "-town-samples"]), .samples)
        XCTAssertEqual(RealLifeActions.backend(for: ["-town-offline"]), .offline)
        XCTAssertEqual(RealLifeActions.backend(for: []), .live)
    }

    /// Polls every 5 ms until `condition` is false, for at most 5 s.
    private func waitWhile(_ condition: @autoclosure () -> Bool) async throws {
        let start = ContinuousClock.now
        while condition(), ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
