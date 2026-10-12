//
//  RealLifeActionsTests.swift
//  BlockPartyTests — the app's one home for Going, Heart and Save (`RealLifeActions`), driven
//  the way the card and the event page drive it, against a stand-in server. The 600 ms hold
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
        var hearts: [Bool] = []
        /// Each save written, as "<event id> <saved>".
        var saves: [String] = []
        /// The ids that are Events, for the phone's old saves, and how often they were asked.
        var events: Set<String> = []
        var lookups = 0
        var failing = false
        var delay: Duration = .zero

        func write(_ eventID: String, _ going: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            writes.append(going)
            if failing { throw URLError(.notConnectedToInternet) }
        }

        func heart(_ eventID: String, _ hearted: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            hearts.append(hearted)
            if failing { throw URLError(.notConnectedToInternet) }
        }

        func save(_ eventID: String, _ saved: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            saves.append("\(eventID) \(saved)")
            if failing { throw URLError(.notConnectedToInternet) }
        }

        /// Answers like `club_events`: only real Event ids, and only UUIDs reach it.
        func knownEvents(_ ids: [String]) async throws -> Set<String> {
            lookups += 1
            XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil }, "a non-UUID would fail the whole read")
            if failing { throw URLError(.notConnectedToInternet) }
            return events.intersection(ids)
        }
    }

    private func actions(_ server: Server, signedIn: Bool = true) -> RealLifeActions {
        RealLifeActions(signedIn: signedIn, needsAccount: true, hold: Self.hold, flip: Self.flip,
                        setGoing: server.write, setHeart: server.heart, setSave: server.save,
                        knownEvents: server.knownEvents)
    }

    private func card(id: String = "e1", going: Int = 4, joined: Bool = false,
                      hearts: Int = 3, hearted: Bool = false) -> FeedCardItem {
        var card = FeedCardItem(UpcomingEvent(id: id, title: "Trivia night", eventDate: "2026-10-12",
                                              startTime: "7 PM", location: nil, goingCount: going,
                                              createdAt: "2026-10-06T16:08:20+00:00", rsvpd: joined))
        card.likeCount = hearts
        card.isLiked = hearted
        return card
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

    // MARK: Heart

    func testAHeartShowsAtOnceAndStays() async throws {
        let server = Server()
        let actions = actions(server)
        let item = card()

        actions.toggleHeart(item)
        XCTAssertEqual(actions.heart(item), .init(isHearted: true, count: 4), "hearted at once, counting you")
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 4), "Going is untouched")

        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.hearts, [true])
        XCTAssertEqual(server.writes, [], "no Going write")
        XCTAssertEqual(actions.heart(item), .init(isHearted: true, count: 4), "a heart that lands stays")

        actions.toggleHeart(item)
        try await Task.sleep(for: Self.hold)
        XCTAssertEqual(server.hearts, [true, false], "un-hearting is written too")
        XCTAssertEqual(actions.heart(item), .init(isHearted: false, count: 3))
    }

    /// A failed heart holds, turns back, then shakes its card once, as a failed Join
    /// does on its page.
    func testAFailedHeartHoldsThenTurnsBackThenCountsOneFailure() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.cardOpened(item.id)

        let tapped = ContinuousClock.now
        actions.toggleHeart(item)
        try await waitWhile(actions.heart(item).isHearted)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, Self.hold, "turned back before it could be seen")
        XCTAssertEqual(actions.heart(item), .init(isHearted: false, count: 3))
        XCTAssertEqual(actions.heartFailureCount(item.id), 0, "no shake while it turns back")

        try await waitWhile(actions.heartFailureCount(item.id) == 0)
        XCTAssertEqual(actions.heartFailureCount(item.id), 1, "one turn back, one shake")
        XCTAssertEqual(actions.failureCount(item.id), 0, "Join doesn't shake for a heart")
    }

    /// Each kind shakes only on its own screen: a failed heart on the card, a failed Join
    /// on the Event page. Neither shakes the other's screen, or a closed one.
    func testAHeartAndAJoinShakeOnlyTheirOwnScreen() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()

        actions.pageOpened(item.id)
        actions.toggleHeart(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 3)
        XCTAssertFalse(actions.heart(item).isHearted, "the heart still turns back")
        XCTAssertEqual(actions.heartFailureCount(item.id), 0, "card closed: no shake, no buzz")
        actions.pageClosed(item.id)

        actions.cardOpened(item.id)
        actions.toggleGoing(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 3)
        XCTAssertFalse(actions.going(item).isGoing)
        XCTAssertEqual(actions.failureCount(item.id), 0, "page closed: no Join shake on the card")
    }

    /// The photo's double tap hearts and never un-hearts.
    func testADoubleTapOnlyHearts() async throws {
        let server = Server()
        let actions = actions(server)
        let item = card()

        actions.heartOn(item)
        actions.heartOn(item)
        XCTAssertTrue(actions.heart(item).isHearted)
        try await Task.sleep(for: Self.hold)
        XCTAssertEqual(server.hearts, [true], "the second double tap writes nothing")
        XCTAssertEqual(actions.heart(item).count, 4)
    }

    /// A double tap while a failed heart waits to turn back keeps it on and writes it
    /// again, rather than turning it off (taste.md: a double tap still likes).
    func testADoubleTapDuringAFailedHeartsWaitKeepsItOn() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.cardOpened(item.id)

        actions.heartOn(item)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(server.hearts, [true], "the write has failed; the heart still holds")
        server.failing = false
        actions.heartOn(item)
        XCTAssertTrue(actions.heart(item).isHearted)
        try await Task.sleep(for: (Self.hold + Self.flip) * 2)
        XCTAssertEqual(server.hearts, [true, true], "written again")
        XCTAssertEqual(actions.heart(item), .init(isHearted: true, count: 4), "and it stays")
        XCTAssertEqual(actions.heartFailureCount(item.id), 0)
    }

    /// Heart, un-heart, heart before the first write answers: one write at a time, never
    /// cancelled, and the server ends with the last tap.
    func testTheLastHeartTapWins() async throws {
        let server = Server()
        server.delay = .milliseconds(30)
        let actions = actions(server)
        let item = card()

        actions.toggleHeart(item)
        try await Task.sleep(for: .milliseconds(5))
        actions.toggleHeart(item)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(server.hearts, [true, false])
        XCTAssertEqual(actions.heart(item), .init(isHearted: false, count: 3))
    }

    /// A heart that reached the server but lost its answer turns back; the next read,
    /// which has it, is the truth, and nothing stays wrong until a relaunch.
    func testAReadCorrectsAHeartThatLandedButLostItsAnswer() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card(hearts: 3)

        actions.toggleHeart(item)
        try await waitWhile(actions.heart(item).isHearted)
        XCTAssertEqual(server.hearts, [true], "the server took it; only the answer was lost")
        actions.read([card(hearts: 4, hearted: true)])
        XCTAssertEqual(actions.heart(item), .init(isHearted: true, count: 4))
    }

    /// A read sets each Event's heart base: everyone's count and your own heart.
    func testAFeedReadSetsTheHeartBase() {
        let actions = actions(Server())
        let pushed = card(hearts: 3)
        actions.read([card(hearts: 7, hearted: true)])
        XCTAssertEqual(actions.heart(pushed), .init(isHearted: true, count: 7))
        actions.read([card(hearts: 2, hearted: false)])
        XCTAssertEqual(actions.heart(pushed), .init(isHearted: false, count: 2))
    }

    /// No account: the card hides the heart, and the module refuses it anyway.
    func testNoAccountMeansNoHeart() async throws {
        let server = Server()
        let actions = actions(server, signedIn: false)
        let item = card()

        actions.toggleHeart(item)
        actions.heartOn(item)
        try await Task.sleep(for: Self.hold)
        XCTAssertFalse(actions.heart(item).isHearted)
        XCTAssertEqual(server.hearts, [])
    }

    // MARK: Save

    func testASaveShowsAtOnceAndStays() async throws {
        let server = Server()
        let actions = actions(server)
        let item = card()

        actions.toggleSave(item)
        XCTAssertTrue(actions.saved(item), "saved at once")
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.saves, ["e1 true"])
        XCTAssertTrue(actions.saved(item), "a save that lands stays")
        XCTAssertEqual(actions.saveFailureCount(item.id), 0)
    }

    /// A failed save turns back like Join, and shakes the card or the page that is open.
    func testAFailedSaveTurnsBackThenCountsOneFailure() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.cardOpened(item.id)

        actions.toggleSave(item)
        try await waitWhile(actions.saved(item))
        XCTAssertFalse(actions.saved(item), "back to unsaved")
        try await waitWhile(actions.saveFailureCount(item.id) == 0)
        XCTAssertEqual(actions.saveFailureCount(item.id), 1, "one turn back, one shake")
        XCTAssertEqual(actions.heartFailureCount(item.id), 0, "the heart never shakes for it")

        actions.cardClosed(item.id)
        actions.pageOpened(item.id)
        actions.toggleSave(item)
        try await waitWhile(actions.saveFailureCount(item.id) == 1)
        XCTAssertEqual(actions.saveFailureCount(item.id), 2, "the Event page shakes for it too")
        XCTAssertEqual(actions.failureCount(item.id), 0, "Join never shakes for it")
    }

    /// The feed's read says what you saved; the card, the page and Daily read one entry.
    func testAFeedReadSetsSavedForEveryScreen() {
        let actions = actions(Server())
        let pushed = card()
        var read = card()
        read.isSaved = true
        actions.read([read])
        XCTAssertTrue(actions.saved(pushed), "a page pushed with an older item agrees with the read")
        read.isSaved = false
        actions.read([read])
        XCTAssertFalse(actions.saved(pushed))
    }

    func testNoAccountMeansNoSave() async throws {
        let server = Server()
        let actions = actions(server, signedIn: false)
        let item = card()

        actions.toggleSave(item)
        try await Task.sleep(for: Self.hold)
        XCTAssertFalse(actions.saved(item))
        XCTAssertEqual(server.saves, [])
    }

    // MARK: The phone's old saves move up once

    private static let event = "6b1f3a2e-0c4d-4f8a-9b21-7e5d3c1a0f44"
    private static let place = "3c9e7d14-5b62-4a08-9f37-2d8c6e1b5a90"

    /// A saved list of its own, so no test touches the phone's real one.
    private func phone(_ ids: [String]) -> SavedStore {
        let key = "RealLifeActionsTests.\(UUID().uuidString)"
        UserDefaults.standard.set(ids, forKey: key)
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key + ".movedUp")
        }
        return SavedStore(key: key)
    }

    func testOldPhoneSavesMoveUpOnceAndPlacesStay() async throws {
        let server = Server()
        server.events = [Self.event]
        let actions = actions(server)
        let store = phone([Self.event, Self.place, "downtown", "daily-s1"])

        await actions.moveUp(store)
        XCTAssertEqual(server.saves, ["\(Self.event) true"])
        XCTAssertEqual(store.ids, [Self.place, "downtown", "daily-s1"], "the map's Places stay on the phone")
        XCTAssertTrue(actions.saved(card(id: Self.event)), "saved before any read says so")
        XCTAssertTrue(SavedStore(key: store.key).ids == store.ids, "kept across launches")

        server.events = []
        await actions.moveUp(store)
        XCTAssertEqual(server.saves, ["\(Self.event) true"], "running it again writes nothing")
        XCTAssertTrue(store.movedUp)
        XCTAssertEqual(server.lookups, 1, "done once: the map's Places never send another read")
    }

    /// A read that started before the move-up landed doesn't blank the bookmark.
    func testAnOlderReadKeepsAMovedSaveShowing() async throws {
        let server = Server()
        server.events = [Self.event]
        let actions = actions(server)
        actions.read([card(id: Self.event)])

        await actions.moveUp(phone([Self.event]))
        XCTAssertTrue(actions.saved(card(id: Self.event)))
        var agreed = card(id: Self.event)
        agreed.isSaved = true
        actions.read([agreed])
        XCTAssertTrue(actions.saved(card(id: Self.event)))
    }

    func testAFailedMoveUpKeepsTheSaveOnThePhone() async throws {
        let server = Server()
        server.events = [Self.event]
        server.failing = true
        let actions = actions(server)
        let store = phone([Self.event])

        await actions.moveUp(store)
        XCTAssertEqual(store.ids, [Self.event], "tried again next time")
        XCTAssertFalse(actions.saved(card(id: Self.event)))
        XCTAssertFalse(store.movedUp)
    }

    func testNoAccountMovesNothing() async throws {
        let server = Server()
        server.events = [Self.event]
        let store = phone([Self.event])

        await actions(server, signedIn: false).moveUp(store)
        XCTAssertEqual(server.saves, [])
        XCTAssertEqual(store.ids, [Self.event])
    }

    /// Polls every 5 ms until `condition` is false, for at most 5 s.
    private func waitWhile(_ condition: @autoclosure () -> Bool) async throws {
        let start = ContinuousClock.now
        while condition(), ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
