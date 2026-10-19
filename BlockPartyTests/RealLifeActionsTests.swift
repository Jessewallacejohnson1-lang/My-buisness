//
//  RealLifeActionsTests.swift
//  BlockPartyTests — the app's one home for Going, Heart and Save (`RealLifeActions`), driven
//  the way the card and the event page drive it, against a stand-in server. The 600 ms hold
//  and 0.18 s flip come in shorter, so these run fast; the order of what happens is
//  the same.
//

import SwiftUI
import XCTest
@testable import BlockParty

@MainActor
final class RealLifeActionsTests: XCTestCase {

    private static let hold: Duration = .milliseconds(150)
    private static let flip: Duration = .milliseconds(90)
    private static let retry: Duration = .milliseconds(20)

    /// Records every write, and says no, gives no answer, or takes its time when told to.
    @MainActor
    private final class Server {
        var writes: [Bool] = []
        var hearts: [Bool] = []
        /// Each save written, as "<event id> <saved>".
        var saves: [String] = []
        /// Each join or leave written, as "<group id> <member>".
        var memberships: [String] = []
        /// The ids that are Events, for the phone's old saves, and how often they were asked.
        var events: Set<String> = []
        var lookups = 0
        /// Answers "no" (a 403), the server refusing the write.
        var failing = false
        /// Never answers, as with no network.
        var offline = false
        var delay: Duration = .zero

        private func answer() throws {
            if offline { throw URLError(.notConnectedToInternet) }
            if failing { throw SupabaseError(message: "no", status: 403) }
        }

        func write(_ eventID: String, _ going: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            writes.append(going)
            try answer()
        }

        func heart(_ eventID: String, _ hearted: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            hearts.append(hearted)
            try answer()
        }

        func save(_ eventID: String, _ saved: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            saves.append("\(eventID) \(saved)")
            try answer()
        }

        func member(_ groupID: String, _ member: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            memberships.append("\(groupID) \(member)")
            try answer()
        }

        /// Answers like `club_events`: only real Event ids, and only UUIDs reach it.
        func knownEvents(_ ids: [String]) async throws -> Set<String> {
            lookups += 1
            XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil }, "a non-UUID would fail the whole read")
            try answer()
            return events.intersection(ids)
        }
    }

    private func actions(_ server: Server, signedIn: Bool = true, keep: UserDefaults? = nil,
                         owner: @escaping () -> String? = { nil }) -> RealLifeActions {
        RealLifeActions(signedIn: signedIn, needsAccount: true, hold: Self.hold, flip: Self.flip,
                        retry: Self.retry, keep: keep, owner: owner,
                        setGoing: server.write, setHeart: server.heart, setSave: server.save,
                        setMember: server.member, knownEvents: server.knownEvents)
    }

    /// A phone of its own for one test, emptied when it ends.
    private func phoneStore() -> UserDefaults {
        let name = "RealLifeActionsTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        addTeardownBlock { store.removePersistentDomain(forName: name) }
        return store
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
        XCTAssertEqual(actions.rsvp(fresher)?.top, "You're going!", "and the card's RSVP area says so")
    }

    /// The RSVP area counts and names friends (town-feed 28), and says "You're going!" the
    /// instant you RSVP, with Invite in the pill (rsvp-and-groups 01).
    func testTheRSVPAreaNamesFriendsThenSaysYoureGoing() async throws {
        let server = Server()
        let actions = actions(server)
        var item = card(going: 3)
        item.friendsGoing = [FeedFriend(name: "Anna", photo: nil)]
        actions.read([item])
        XCTAssertEqual(actions.rsvp(item), RSVPWords(top: "3 going", second: "Anna is going", canLeave: false, pill: .rsvp))
        actions.toggleGoing(item)
        XCTAssertEqual(actions.rsvp(item), RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .invite))
        XCTAssertEqual(actions.going(item).count, 4, "the count includes you")
        XCTAssertEqual(actions.rsvp(item, bar: true), RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: .invite),
                       "the Event page's bar reads the same Going, in fewer words")
        actions.toggleGoing(item)
        XCTAssertEqual(actions.rsvp(item)?.top, "3 going", "Can't go? takes you off in one tap")
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
        XCTAssertNil(actions.rsvp(item), "no account: no RSVP area, as Join never showed without one")

        actions.accountChanged(signedIn: true)
        XCTAssertTrue(actions.canAct, "the quiet account arrives: RSVP comes up")
        XCTAssertEqual(actions.rsvp(item)?.top, "2 going")
        XCTAssertEqual(actions.rsvp(card(going: 0)), RSVPWords(top: nil, second: nil, canLeave: false, pill: .rsvp),
                       "never a count at zero: RSVP alone")
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

    /// Each kind shakes only where its control is: a failed heart on the card; a failed Join
    /// on the Event page and, since RSVP came to the card (rsvp-and-groups 01), on the card.
    func testAHeartAndAJoinShakeOnlyWhereTheirControlIs() async throws {
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
        XCTAssertEqual(actions.failureCount(item.id), 1, "the card's RSVP shakes and buzzes as Join does")
        actions.cardClosed(item.id)

        actions.toggleGoing(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 3)
        XCTAssertEqual(actions.failureCount(item.id), 1, "card and page closed: no shake")
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

    /// A heart that reached the server but lost its answer stays hearted and is sent
    /// again, which is safe; the next read, which has it, agrees.
    func testAHeartThatLostItsAnswerStaysAndIsSentAgain() async throws {
        let server = Server()
        server.offline = true
        let actions = actions(server)
        let item = card(hearts: 3)
        actions.cardOpened(item.id)

        actions.toggleHeart(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 2)
        XCTAssertTrue(actions.heart(item).isHearted, "no answer is no \"no\": it stays")
        XCTAssertEqual(actions.heartFailureCount(item.id), 0)

        server.hearts = []
        server.offline = false
        try await waitWhile(server.hearts != [true])
        XCTAssertEqual(server.hearts, [true], "sent again once back online")
        actions.read([card(hearts: 4, hearted: true)])
        XCTAssertEqual(actions.heart(item), .init(isHearted: true, count: 4))
    }

    // MARK: Offline (town-feed ticket 24)

    /// Offline, a Join stays with no shake; back online it is sent, and a read agrees.
    func testAnOfflineJoinStaysAndIsSentWhenBackOnline() async throws {
        let server = Server()
        server.offline = true
        let actions = actions(server)
        let item = card()
        actions.pageOpened(item.id)

        actions.toggleGoing(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 2)
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 5), "stays Going")
        XCTAssertEqual(actions.failureCount(item.id), 0, "no shake, no buzz")
        XCTAssertFalse(server.writes.isEmpty, "it kept trying")

        server.offline = false
        server.writes = []
        try await waitWhile(server.writes != [true])
        XCTAssertEqual(server.writes, [true], "sent once it could be")
        actions.read([card(going: 5, joined: true)])
        XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 5))
        XCTAssertEqual(actions.failureCount(item.id), 0)
    }

    /// Join then Leave offline: only the last tap goes out once the network is back.
    func testJoinThenLeaveOfflineSendsOnlyTheLeave() async throws {
        let server = Server()
        server.offline = true
        let actions = actions(server)
        let item = card()

        actions.toggleGoing(item)
        try await Task.sleep(for: .milliseconds(10))
        actions.toggleGoing(item)
        XCTAssertFalse(actions.going(item).isGoing)
        try await Task.sleep(for: Self.retry * 3)

        server.writes = []
        server.offline = false
        try await waitWhile(server.writes.isEmpty)
        try await Task.sleep(for: Self.retry * 8)
        XCTAssertEqual(server.writes, [false], "the Leave alone, which also undoes a Join that landed")
        XCTAssertFalse(actions.going(item).isGoing)
    }

    /// A tap that waited offline and then gets the server's "no" flips back quietly: by
    /// then the neighbour may be anywhere, so no shake and no buzz (Jesse, 2026-10-13).
    func testALateNoTurnsBackWithoutAShake() async throws {
        let server = Server()
        server.offline = true
        let actions = actions(server)
        let item = card()
        actions.pageOpened(item.id)

        actions.toggleGoing(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 2)
        XCTAssertTrue(actions.going(item).isGoing)

        server.offline = false
        server.failing = true
        try await waitWhile(actions.going(item).isGoing)
        try await Task.sleep(for: Self.flip * 2)
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 4), "turned back")
        XCTAssertEqual(actions.failureCount(item.id), 0, "no shake for a late no")
    }

    /// The app at launch: the account comes back, then taps are made.
    private func launched(_ server: Server, _ store: UserDefaults, as owner: String) -> RealLifeActions {
        let actions = actions(server, keep: store, owner: { owner })
        actions.accountChanged(signedIn: true)
        return actions
    }

    /// Taps made offline survive a relaunch: the next launch shows them once the account
    /// is back, keeps them through the kept list's older read (which the app hands over
    /// before the account comes back), and sends them.
    func testOfflineTapsSurviveARelaunch() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let item = card(id: Self.event)
        let before = launched(server, store, as: "anna")

        before.toggleGoing(item)
        before.toggleSave(item)
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)  // the app is gone; its writes stop
        try await Task.sleep(for: Self.retry * 8)

        server.offline = false
        server.writes = []
        server.saves = []
        let after = actions(server, keep: store, owner: { "anna" })
        after.read([card(id: Self.event)])  // the kept list comes first, from before the taps
        XCTAssertFalse(after.going(item).isGoing, "nothing until the account is back")
        after.accountChanged(signedIn: true)
        XCTAssertTrue(after.going(item).isGoing, "Going is back after the relaunch")
        XCTAssertTrue(after.saved(item), "and so is the Save")

        after.read([card(id: Self.event)])
        XCTAssertTrue(after.going(item).isGoing, "an older read doesn't undo a waiting tap")
        XCTAssertEqual(Set(after.goingTapped.keys), [Self.event], "You shows it too")
        try await waitWhile(server.writes.isEmpty || server.saves.isEmpty)
        XCTAssertEqual(server.writes, [true])
        XCTAssertEqual(server.saves, ["\(Self.event) true"])

        after.read([card(id: Self.event, going: 5, joined: true)])
        XCTAssertTrue(after.going(item).isGoing)
    }

    /// Another account never gets the last one's waiting taps: they're dropped, not sent.
    func testAnotherAccountsWaitingTapsAreDroppedNotSent() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let item = card(id: Self.event)
        let before = launched(server, store, as: "anna")
        before.toggleGoing(item)
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)
        try await Task.sleep(for: Self.retry * 8)

        server.offline = false
        server.writes = []
        let ben = launched(server, store, as: "ben")
        XCTAssertFalse(ben.going(item).isGoing, "not Ben's tap")
        try await Task.sleep(for: Self.retry * 8)
        XCTAssertEqual(server.writes, [], "never sent under Ben's name")

        let annaAgain = launched(server, store, as: "anna")
        XCTAssertFalse(annaAgain.going(item).isGoing, "dropped for good once another account came")
    }

    /// Daily's sample Suggestions are saved for this run only: never kept for the next.
    func testASampleSaveIsNotKept() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let before = launched(server, store, as: "anna")
        before.toggleSave(card(id: "daily-s1"))
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)

        let after = launched(server, store, as: "anna")
        XCTAssertFalse(after.saved(card(id: "daily-s1")))
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

    /// A failed save turns back like Join, and shakes the bookmark or the page that is open.
    /// The Town card has no bookmark (rsvp-and-groups 01), so it never shakes for one.
    func testAFailedSaveTurnsBackThenCountsOneFailure() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let item = card()
        actions.cardOpened(item.id)
        actions.toggleSave(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 3)
        XCTAssertFalse(actions.saved(item), "turned back")
        XCTAssertEqual(actions.saveFailureCount(item.id), 0, "no bookmark on the Town card: no shake there")
        actions.cardClosed(item.id)
        actions.bookmarkOpened(item.id)

        actions.toggleSave(item)
        try await waitWhile(actions.saved(item))
        XCTAssertFalse(actions.saved(item), "back to unsaved")
        try await waitWhile(actions.saveFailureCount(item.id) == 0)
        XCTAssertEqual(actions.saveFailureCount(item.id), 1, "one turn back, one shake")
        XCTAssertEqual(actions.heartFailureCount(item.id), 0, "the heart never shakes for it")

        actions.bookmarkClosed(item.id)
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

    // MARK: Being in a group (rsvp-and-groups 06)

    private static let groupID = "8d2c4b6a-1e3f-4a5b-9c7d-0e1f2a3b4c5d"

    private func group(members: Int = 4, joined: Bool = false) -> TownGroup {
        var group = TownGroup(id: Self.groupID, name: "Lions Club", memberCount: members)
        group.joined = joined
        return group
    }

    func testJoiningAGroupShowsAtOnceAndCountsYou() async throws {
        let server = Server()
        let actions = actions(server)
        let lions = group()

        actions.toggleMember(lions)
        XCTAssertEqual(actions.member(lions), .init(isMember: true, count: 5), "in at once, counting you")
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.memberships, ["\(Self.groupID) true"])
        XCTAssertEqual(actions.member(lions), .init(isMember: true, count: 5), "a join that lands stays")
        XCTAssertEqual(actions.memberFailureCount(lions.id), 0)
        XCTAssertEqual(server.writes, [], "no Going written")
    }

    /// As a failed RSVP: it holds for the hold, turns back, and shakes the open Group page once
    /// the flip is done.
    func testAFailedJoinOfAGroupHoldsThenTurnsBackThenShakesOnce() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let lions = group()
        actions.pageOpened(lions.id)

        let tapped = ContinuousClock.now
        actions.toggleMember(lions)
        try await waitWhile(actions.member(lions).isMember)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, Self.hold, "turned back before it could be seen")
        XCTAssertEqual(actions.member(lions), .init(isMember: false, count: 4), "back to Join group, count and all")
        try await waitWhile(actions.memberFailureCount(lions.id) == 0)
        XCTAssertEqual(actions.memberFailureCount(lions.id), 1, "one turn back, one shake")
        XCTAssertEqual(actions.failureCount(lions.id), 0, "nothing else shakes")
    }

    func testLeavingAGroupAndTheLastTapWins() async throws {
        let server = Server()
        server.delay = .milliseconds(30)
        let actions = actions(server)
        let lions = group(members: 6, joined: true)

        actions.toggleMember(lions)
        XCTAssertEqual(actions.member(lions), .init(isMember: false, count: 5), "Leave group? takes you out at once")
        try await Task.sleep(for: .milliseconds(5))
        actions.toggleMember(lions)
        XCTAssertEqual(actions.member(lions), .init(isMember: true, count: 6))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(server.memberships, ["\(Self.groupID) false", "\(Self.groupID) true"],
                       "the join lands after the leave, never before")
        XCTAssertTrue(actions.member(lions).isMember)
    }

    /// A groups read sets the base; a join it doesn't agree with yet stays, counted from the read's
    /// number. A Town feed read says nothing of groups.
    func testAGroupsReadReplacesTheBase() async throws {
        let server = Server()
        server.delay = .milliseconds(40)
        let actions = actions(server)
        let pushed = group(members: 4)

        actions.toggleMember(pushed)
        actions.read([group(members: 9)])
        XCTAssertEqual(actions.member(pushed), .init(isMember: true, count: 10),
                       "a read from before the write lands keeps the join, on the read's count")
        try await Task.sleep(for: .milliseconds(100))

        actions.read([card()])
        XCTAssertEqual(actions.member(pushed), .init(isMember: true, count: 10), "a Town read leaves it be")
        actions.read([group(members: 10, joined: true)])
        XCTAssertEqual(actions.member(pushed), .init(isMember: true, count: 10), "the read agrees")
        actions.read([group(members: 3)])
        XCTAssertEqual(actions.member(pushed), .init(isMember: false, count: 3), "once agreed, the next read is the truth")
    }

    /// Join on a Town card (rsvp-and-groups 07) is the Group page's join: one entry, so the two
    /// always agree. The card has no count; the page counts you on its own number.
    func testJoiningFromATownCardIsTheGroupPagesJoin() async throws {
        let server = Server()
        let actions = actions(server)

        XCTAssertFalse(actions.member(groupID: Self.groupID, inGroup: false).isMember)
        actions.toggleMember(groupID: Self.groupID, inGroup: false)
        XCTAssertTrue(actions.member(groupID: Self.groupID, inGroup: false).isMember, "Joined at once")
        XCTAssertEqual(actions.member(group(members: 4)), .init(isMember: true, count: 5), "the Group page agrees")
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.memberships, ["\(Self.groupID) true"])
    }

    /// The feed's word holds until a groups read, which then wins: it knows the count too.
    func testACardTakesTheFeedsWordUntilAGroupsRead() {
        let actions = actions(Server())
        XCTAssertTrue(actions.member(groupID: Self.groupID, inGroup: true).isMember)
        actions.read([group(joined: false)])
        XCTAssertFalse(actions.member(groupID: Self.groupID, inGroup: true).isMember)
    }

    /// A refused join from a card turns back and shakes the card while it's on screen; scrolled
    /// away, it turns back with no shake.
    func testAFailedJoinFromACardShakesOnlyWhileTheCardIsOnScreen() async throws {
        let server = Server()
        server.failing = true
        let actions = actions(server)
        let event = card()
        actions.cardOpened(event.id, group: Self.groupID)

        actions.toggleMember(groupID: Self.groupID, inGroup: false)
        try await waitWhile(actions.member(groupID: Self.groupID, inGroup: false).isMember)
        try await waitWhile(actions.memberFailureCount(Self.groupID) == 0)
        XCTAssertEqual(actions.memberFailureCount(Self.groupID), 1)
        XCTAssertEqual(actions.failureCount(event.id), 0, "the RSVP pill stays still")

        actions.cardClosed(event.id, group: Self.groupID)
        actions.toggleMember(groupID: Self.groupID, inGroup: false)
        try await waitWhile(actions.member(groupID: Self.groupID, inGroup: false).isMember)
        try await Task.sleep(for: Self.flip * 2)
        XCTAssertEqual(actions.memberFailureCount(Self.groupID), 1, "no shake off screen")
    }

    func testNoAccountMeansNoJoin() async throws {
        let server = Server()
        let actions = actions(server, signedIn: false)
        let lions = group()

        actions.toggleMember(lions)
        XCTAssertFalse(actions.member(lions).isMember)
        try await Task.sleep(for: Self.hold)
        XCTAssertEqual(server.memberships, [])
    }

    /// A join made offline is kept on the phone, shown after a relaunch and sent.
    func testAnOfflineJoinSurvivesARelaunch() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let before = launched(server, store, as: "anna")

        before.toggleMember(group())
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)
        try await Task.sleep(for: Self.retry * 8)

        server.offline = false
        server.memberships = []
        let after = launched(server, store, as: "anna")
        XCTAssertTrue(after.member(group()).isMember, "still in after the relaunch")
        try await waitWhile(server.memberships.isEmpty)
        XCTAssertEqual(server.memberships, ["\(Self.groupID) true"])
    }

    /// Polls every 5 ms until `condition` is false, for at most 5 s.
    private func waitWhile(_ condition: @autoclosure () -> Bool) async throws {
        let start = ContinuousClock.now
        while condition(), ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// What the RSVP area says (`RSVPWords`, rsvp-and-groups 01): one rule for the Town card and
/// the Event page, through every Going, count, friends and called-off case.
@MainActor
final class RSVPWordsTests: XCTestCase {
    func testTheWordsAndThePillForEveryCase() {
        let going = RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .invite)
        func notGoing(_ top: String?, _ second: String? = nil) -> RSVPWords {
            RSVPWords(top: top, second: second, canLeave: false, pill: .rsvp)
        }
        let table: [(String, Bool, Int, [String], Bool, RSVPWords)] = [
            ("nobody yet: RSVP alone", false, 0, [], false, notGoing(nil)),
            ("one going", false, 1, [], false, notGoing("1 going")),
            ("many going", false, 41, [], false, notGoing("41 going")),
            ("a friend", false, 41, ["Avery"], false, notGoing("41 going", "Avery is going")),
            ("two friends", false, 41, ["Sam", "Marlene"], false, notGoing("41 going", "Sam and Marlene are going")),
            ("three friends", false, 41, ["Sam", "Marlene", "Dale"], false,
             notGoing("41 going", "Sam and 2 friends are going")),
            ("never fewer than the friends named", false, 0, ["Avery"], false, notGoing("1 going", "Avery is going")),
            ("going", true, 42, [], false, going),
            ("going with friends", true, 42, ["Avery"], false, going),
            ("going, the only one", true, 1, [], false, going),
            ("called off", false, 41, ["Avery"], true, RSVPWords(top: nil, second: nil, canLeave: false, pill: .canceled)),
            ("called off while going: can still leave, the pill says Canceled", true, 42, [], true,
             RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .canceled)),
        ]
        for (name, isGoing, count, friends, cancelled, want) in table {
            XCTAssertEqual(RSVPWords.make(isGoing: isGoing, count: count, friends: friends, cancelled: cancelled),
                           want, name)
        }
    }

    /// The Event page's bar says less (Jesse at rsvp-and-groups 02's Check-in 2): no "Can't go?",
    /// and beside the friends' faces only their names, so they fit by the bigger words.
    func testTheEventPageBarSaysLess() {
        func bar(_ top: String?, _ second: String? = nil, pill: RSVPWords.Pill = .rsvp) -> RSVPWords {
            RSVPWords(top: top, second: second, canLeave: false, pill: pill)
        }
        let table: [(String, Bool, Int, [String], Bool, RSVPWords)] = [
            ("nobody yet: RSVP alone", false, 0, [], false, bar(nil)),
            ("many going", false, 41, [], false, bar("41 going")),
            ("a friend", false, 41, ["Avery"], false, bar("41 going", "Avery")),
            ("two friends", false, 41, ["Sam", "Marlene"], false, bar("41 going", "Sam and Marlene")),
            ("three friends", false, 41, ["Sam", "Marlene", "Dale"], false, bar("41 going", "Sam and 2 friends")),
            ("going: no Can't go?", true, 42, ["Avery"], false, bar("You're going!", pill: .invite)),
            ("called off", false, 41, ["Avery"], true, bar(nil, pill: .canceled)),
            ("called off while going", true, 42, [], true, bar("You're going!", pill: .canceled)),
        ]
        for (name, isGoing, count, friends, cancelled, want) in table {
            XCTAssertEqual(RSVPWords.make(isGoing: isGoing, count: count, friends: friends, cancelled: cancelled, bar: true),
                           want, name)
        }
    }

    /// After a tap on Attend the pill keeps Attend, its calendar checked, until the check's hold
    /// ends, then shows Invite (attend-pill, 2026-10-19). Canceled never turns into Attend.
    func testThePillHoldsAttendWhileTheCheckShows() {
        let going = RSVPWords.make(isGoing: true, count: 42, friends: [], cancelled: false)
        XCTAssertEqual(going.shownPill(checking: true), .rsvp, "the check shows on Attend")
        XCTAssertEqual(going.shownPill(checking: false), .invite, "then Invite")
        let notGoing = RSVPWords.make(isGoing: false, count: 41, friends: [], cancelled: false)
        XCTAssertEqual(notGoing.shownPill(checking: false), .rsvp)
        let calledOff = RSVPWords.make(isGoing: true, count: 42, friends: [], cancelled: true)
        XCTAssertEqual(calledOff.shownPill(checking: true), .canceled)
    }

    /// The pill's colours are tokens, exactly the Figma page's (Meetup's pills, measured at 3x).
    func testThePillIsMeetupsCharcoal() {
        XCTAssertEqual(Hue.pillTop.hexString, "#3A3A3C")
        XCTAssertEqual(Hue.pillDeep.hexString, "#29292B")
        XCTAssertEqual(Hue.pillBottom.hexString, "#353439")
        XCTAssertEqual(Hue.canceled.hexString, Color(uiColor: .systemRed).hexString, "Canceled is Apple's own red")
    }
}
