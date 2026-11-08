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
        /// Each join or leave written, as "<group id> <member>".
        var memberships: [String] = []
        /// Answers "no" (a 403), the server refusing the write.
        var failing = false
        /// Never answers, as with no network.
        var offline = false
        /// Answers with this status, as Supabase does during a blip (503) or with an expired
        /// token (401).
        var status: Int?
        var delay: Duration = .zero

        private func answer() throws {
            if offline { throw URLError(.notConnectedToInternet) }
            if failing { throw SupabaseError(message: "no", status: 403) }
            if let status { throw SupabaseError(message: "blip", status: status) }
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

        func member(_ groupID: String, _ member: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            memberships.append("\(groupID) \(member)")
            try answer()
        }

        /// Each follow or unfollow written, as "<type> <id> <following>".
        var follows: [String] = []
        /// What `follow_card` answers.
        var card = FollowCard(following: false, followers: 128, friends: [], friendsCount: 0)

        func follow(_ target: FollowTarget, _ following: Bool) async throws {
            if delay > .zero { try? await Task.sleep(for: delay) }
            follows.append("\(target.type.rawValue) \(target.id) \(following)")
            try answer()
        }

        func followCard(_ target: FollowTarget) async throws -> FollowCard {
            try answer()
            return card
        }
    }

    private func actions(_ server: Server, signedIn: Bool = true, anonymous: Bool = false,
                         keep: UserDefaults? = nil, flip: Duration? = nil,
                         owner: @escaping () -> String? = { nil }) -> RealLifeActions {
        RealLifeActions(signedIn: signedIn, needsAccount: true, realAccount: { !anonymous },
                        hold: Self.hold, flip: flip ?? Self.flip,
                        retry: Self.retry, keep: keep, owner: owner,
                        setGoing: server.write, setHeart: server.heart,
                        setMember: server.member, setFollow: server.follow, readFollow: server.followCard)
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
    /// The flip is a second long here: on a loaded Mac the 5 ms poll overslept the 90 ms
    /// one and saw the shake already counted (BP app backlog 03).
    func testAFailedJoinHoldsThenTurnsBackThenCountsOneFailure() async throws {
        let server = Server()
        server.failing = true
        let flip = Duration.seconds(1)
        let actions = actions(server, flip: flip)
        let item = card()
        actions.pageOpened(item.id)

        let tapped = ContinuousClock.now
        actions.toggleGoing(item)
        try await waitWhile(actions.going(item).isGoing)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, Self.hold, "turned back before it could be seen")
        XCTAssertEqual(actions.going(item), .init(isGoing: false, count: 4), "back to Join, count and all")
        XCTAssertEqual(actions.failureCount(item.id), 0, "Join first: no shake while it turns back")

        try await waitWhile(actions.failureCount(item.id) == 0)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, Self.hold + flip, "shook before the flip was done")
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
        try await waitWhile(actions.going(item).isGoing)
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
        XCTAssertEqual(actions.rsvp(item, bar: true, at: .distantPast),
                       RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .invite),
                       "the Event page's bar reads the same Going")
        XCTAssertEqual(actions.rsvp(item, bar: true, at: .distantFuture),
                       RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: .invite),
                       "once it has ended there's nothing left to leave")
        XCTAssertEqual(actions.rsvp(item, town: true), RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: .leave),
                       "and the poster's, with the X that leaves")
        XCTAssertEqual(actions.rsvp(item, card: true), RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: nil),
                       "and the Town card's, with no pill")
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
        XCTAssertNil(actions.rsvp(card(going: 0), card: true), "nobody going: a Town card has no words and no pill")
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

        actions.toggleHeart(item)
        try await Task.sleep(for: (Self.hold + Self.flip) * 3)
        XCTAssertFalse(actions.heart(item).isHearted, "the heart still turns back")
        XCTAssertEqual(actions.heartFailureCount(item.id), 0, "nothing open: no shake, no buzz")

        // The Event page has the heart where the bookmark was (inside-cards 16): it shakes there.
        actions.pageOpened(item.id)
        actions.toggleHeart(item)
        try await waitWhile(actions.heartFailureCount(item.id) == 0)
        XCTAssertEqual(actions.heartFailureCount(item.id), 1, "the Event page's heart shakes and buzzes")
        XCTAssertEqual(actions.failureCount(item.id), 0, "Join never shakes for it")
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
        try await waitWhile(server.hearts.count < 2)
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

    /// A Supabase blip (503) or an expired token (401) is no answer, not a "no": Going stays,
    /// with no shake, and is sent again once the server answers (codebase-health 11).
    func testABlipKeepsGoingAndSendsItAgain() async throws {
        for status in [503, 401] {
            let server = Server()
            server.status = status
            let actions = actions(server)
            let item = card()
            actions.pageOpened(item.id)

            actions.toggleGoing(item)
            try await Task.sleep(for: (Self.hold + Self.flip) * 2)
            XCTAssertEqual(actions.going(item), .init(isGoing: true, count: 5), "\(status): stays Going")
            XCTAssertEqual(actions.failureCount(item.id), 0, "\(status): no shake, no buzz")

            server.status = nil
            server.writes = []
            try await waitWhile(server.writes != [true])
            XCTAssertEqual(server.writes, [true], "\(status): sent once the server answers")
        }
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
        before.toggleHeart(item)
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)  // the app is gone; its writes stop
        try await Task.sleep(for: Self.retry * 8)

        server.offline = false
        server.writes = []
        server.hearts = []
        let after = actions(server, keep: store, owner: { "anna" })
        after.read([card(id: Self.event)])  // the kept list comes first, from before the taps
        XCTAssertFalse(after.going(item).isGoing, "nothing until the account is back")
        after.accountChanged(signedIn: true)
        XCTAssertTrue(after.going(item).isGoing, "Going is back after the relaunch")
        XCTAssertTrue(after.heart(item).isHearted, "and so is the Heart")

        after.read([card(id: Self.event)])
        XCTAssertTrue(after.going(item).isGoing, "an older read doesn't undo a waiting tap")
        XCTAssertEqual(Set(after.goingTapped.keys), [Self.event], "You shows it too")
        XCTAssertEqual(Set(after.likedTapped.keys), [Self.event], "and Liked")
        try await waitWhile(server.writes.isEmpty || server.hearts.isEmpty)
        XCTAssertEqual(server.writes, [true])
        XCTAssertEqual(server.hearts, [true])

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

    /// Daily's sample Suggestions are hearted for this run only: never kept for the next.
    func testASampleHeartIsNotKept() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let before = launched(server, store, as: "anna")
        before.toggleHeart(card(id: "daily-s1"))
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)

        let after = launched(server, store, as: "anna")
        XCTAssertFalse(after.heart(card(id: "daily-s1")).isHearted)
    }

    /// An older build kept a Save tap waiting (inside-cards 16 took Save out): the kept list no longer
    /// reads, so it is dropped once, Going taps with it, and never sent.
    func testAnOlderBuildsWaitingSaveIsDroppedOnce() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let before = launched(server, store, as: "anna")
        before.toggleGoing(card(id: Self.event))
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)
        let kept = try XCTUnwrap(store.data(forKey: "bp.waitingTaps").flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(kept.contains(#""going""#))
        store.set(Data(kept.replacingOccurrences(of: #""going""#, with: #""save""#).utf8), forKey: "bp.waitingTaps")

        server.offline = false
        server.writes = []
        let after = launched(server, store, as: "anna")
        XCTAssertFalse(after.going(card(id: Self.event)).isGoing)
        XCTAssertNil(store.data(forKey: "bp.waitingTaps"), "dropped, so the next launch starts clean")
        try await Task.sleep(for: Self.retry * 8)
        XCTAssertEqual(server.writes + server.hearts, [], "nothing sent")
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

    // MARK: Heart is the save (inside-cards 16)

    private static let event = "6b1f3a2e-0c4d-4f8a-9b21-7e5d3c1a0f44"

    /// A heart lands in You's Liked at once, before the server answers, and stays once it does.
    func testAHeartLandsInLikedAtOnceAndStays() async throws {
        let server = Server()
        server.delay = Self.hold
        let actions = actions(server)
        let item = card()

        actions.toggleHeart(item)
        XCTAssertEqual(Set(actions.likedTapped.keys), ["e1"], "in Liked at once")
        XCTAssertTrue(actions.heart(item).isHearted)
        try await waitWhile(server.hearts.isEmpty)
        try await Task.sleep(for: Self.hold * 2)
        XCTAssertEqual(server.hearts, [true])
        XCTAssertTrue(actions.heart(item).isHearted, "a heart that lands stays")
    }

    /// The photo's double tap is a heart like any other: it lands in Liked too.
    func testADoubleTapLandsInLiked() {
        let actions = actions(Server())
        let item = card()
        actions.heartOn(item)
        XCTAssertEqual(Set(actions.likedTapped.keys), ["e1"])
        XCTAssertTrue(actions.heart(item).isHearted)
    }

    /// Unhearting keeps the Event among this session's taps but no longer hearted, so Liked leaves it
    /// out (`YouCalendar.liked` reads `heart(_:)`).
    func testUnheartingTakesItOutOfLiked() async throws {
        let actions = actions(Server())
        let item = card()
        actions.toggleHeart(item)
        try await Task.sleep(for: Self.hold)
        actions.toggleHeart(item)
        XCTAssertNotNil(actions.likedTapped["e1"])
        XCTAssertFalse(actions.heart(item).isHearted)
    }

    /// A heart kept from before a relaunch and still being sent shows in Liked once the feed reads its
    /// card, as Going does on You.
    func testAHeartStillBeingSentShowsInLikedAfterARelaunch() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let before = launched(server, store, as: "anna")
        before.toggleHeart(card(id: Self.event))
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)

        let after = launched(server, store, as: "anna")
        XCTAssertTrue(after.likedTapped.isEmpty, "nothing read yet")
        after.read([card(id: Self.event)])
        XCTAssertEqual(Set(after.likedTapped.keys), [Self.event], "the read's card, its heart still on its way")
        XCTAssertTrue(after.heart(card(id: Self.event)).isHearted)
        after.accountChanged(signedIn: false)
    }

    /// The card an Event page opens with, from any door (the bell, Going, Liked), carries the heart:
    /// before any Town feed read the page shows it as the card says.
    func testACardFromAnyDoorShowsItsHeart() {
        let actions = actions(Server())
        XCTAssertEqual(actions.heart(card(hearts: 3, hearted: true)), .init(isHearted: true, count: 3))
        XCTAssertEqual(actions.heart(card(id: "e2", hearts: 0)), .init(isHearted: false, count: 0))
    }

    /// No account: nothing lands in Liked.
    func testNoAccountHeartsNothingIntoLiked() async throws {
        let server = Server()
        let actions = actions(server, signedIn: false)
        actions.toggleHeart(card())
        actions.heartOn(card())
        try await Task.sleep(for: Self.hold)
        XCTAssertTrue(actions.likedTapped.isEmpty)
        XCTAssertEqual(server.hearts, [])
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

    /// A Group's chat comes or goes with being in the Group, so Messages and the red dot read again.
    func testAJoinOrLeaveThatLandsTellsTheChatsAndARefusedOneDoesNot() async throws {
        let server = Server()
        let actions = actions(server)
        var told = 0
        actions.memberWritten = { told += 1 }
        actions.toggleMember(group())
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(told, 1)
        server.failing = true
        actions.toggleMember(groupID: "other", inGroup: false)
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(told, 1, "nothing changed, so nothing to read")
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

    // MARK: Following a Place or a person (follows 02)

    private static let krewe = FollowTarget(type: .place, id: "5b0c6f1e-2d3a-4b5c-8d9e-0f1a2b3c4d5e")
    private static let sam = FollowTarget(type: .profile, id: "7e1d2c3b-4a59-4687-9a0b-1c2d3e4f5a6b")

    /// A page opens: its count and friends come in, and Follow says what the read said.
    func testAPageReadsItsCountAndFriends() async throws {
        let server = Server()
        server.card = FollowCard(following: false, followers: 128,
                                 friends: [.init(name: "Sam Rivera", avatarUrl: nil), .init(name: "Ana Lee", avatarUrl: nil)],
                                 friendsCount: 3)
        let actions = actions(server)

        XCTAssertEqual(actions.follow(Self.krewe), .init(isFollowing: false, count: 0), "nothing before the read")
        await actions.refreshFollow(Self.krewe)
        XCTAssertEqual(actions.follow(Self.krewe), .init(isFollowing: false, count: 128))
        XCTAssertEqual(actions.followFriends[Self.krewe]?.friends.map(\.name), ["Sam Rivera", "Ana Lee"])
        XCTAssertEqual(actions.followFriends[Self.krewe]?.count, 3)
    }

    /// One tap: Following at once, counting you, and written once. One more tap undoes it.
    func testFollowShowsAtOnceAndOneTapUndoesIt() async throws {
        let server = Server()
        let actions = actions(server)
        await actions.refreshFollow(Self.krewe)

        actions.toggleFollow(Self.krewe)
        XCTAssertEqual(actions.follow(Self.krewe), .init(isFollowing: true, count: 129), "Following at once, counting you")
        try await Task.sleep(for: Self.hold * 3)
        actions.toggleFollow(Self.krewe)
        XCTAssertEqual(actions.follow(Self.krewe), .init(isFollowing: false, count: 128), "undone with one tap")
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.follows, ["place \(Self.krewe.id) true", "place \(Self.krewe.id) false"])
        XCTAssertEqual(server.memberships, [], "a Place is followed, not joined")
    }

    /// As a failed Join: it holds, turns back, then shakes the button that's on screen once.
    func testAFailedFollowHoldsThenTurnsBackThenShakesOnce() async throws {
        let server = Server()
        let actions = actions(server)
        await actions.refreshFollow(Self.krewe)
        server.failing = true
        actions.followOpened(Self.krewe)

        let tapped = ContinuousClock.now
        actions.toggleFollow(Self.krewe)
        try await waitWhile(actions.follow(Self.krewe).isFollowing)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, Self.hold, "turned back before it could be seen")
        XCTAssertEqual(actions.follow(Self.krewe), .init(isFollowing: false, count: 128), "back to Follow, count and all")
        try await waitWhile(actions.followFailureCount(Self.krewe) == 0)
        XCTAssertEqual(actions.followFailureCount(Self.krewe), 1, "one turn back, one shake")

        actions.followClosed(Self.krewe)
        actions.toggleFollow(Self.krewe)
        try await waitWhile(actions.follow(Self.krewe).isFollowing)
        try await Task.sleep(for: Self.flip * 2)
        XCTAssertEqual(actions.followFailureCount(Self.krewe), 1, "no shake with no button on screen")
    }

    /// Onboarding's Follow 3 picks (onboarding 22): sent only for a signed-up account, written as
    /// follows, and never undoing one, however often they arrive.
    func testOnboardingPicksOnlyEverFollowAndWaitForASignedUpAccount() async throws {
        let server = Server()
        let school = FollowTarget(type: .team, id: "ae12dd85-f0e8-47f2-9f38-426a2560ff72")
        actions(server, anonymous: true).followOn(Self.krewe)
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.follows, [], "an Anonymous account sends nothing")

        let actions = actions(server)
        actions.followOn(Self.krewe)
        actions.followOn(school)
        actions.followOn(Self.krewe)
        XCTAssertTrue(actions.follow(Self.krewe).isFollowing)
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.follows.sorted(), ["place \(Self.krewe.id) true", "team \(school.id) true"])
    }

    /// A Place and a person are kept apart, each written as its own kind.
    func testAPersonsFollowIsTheirsAlone() async throws {
        let server = Server()
        let actions = actions(server)

        actions.toggleFollow(Self.sam)
        XCTAssertTrue(actions.follow(Self.sam).isFollowing)
        XCTAssertFalse(actions.follow(Self.krewe).isFollowing)
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.follows, ["profile \(Self.sam.id) true"])
    }

    /// A school's page says which activities you follow; a star follows one at once, written as an
    /// activity, and one more tap undoes it (school-activities 02).
    func testAnActivityStarReadsFromThePageAndIsWrittenAsAnActivity() async throws {
        let server = Server()
        let actions = actions(server)
        let soccer = FollowTarget(type: .activity, id: "5b1c0d2e-3f40-4a51-8b62-7c83d94ea5f6")
        let band = FollowTarget(type: .activity, id: "6c2d1e3f-4051-4b62-9c73-8d94ea5fb607")
        let page = try JSONDecoder().decode(TeamProfile.self, from: Data("""
            {"id": "t", "name": "Apollo High School", "short": "Apollo", "games": [], "activities": [
              {"id": "\(soccer.id)", "name": "Girls Soccer", "note": "St. Cloud Crush co-op", "kind": "sport",
               "following": false, "next": {"title": "Apollo Girls Soccer vs Tech", "date": "2026-10-27", "time": "5 PM"}},
              {"id": "\(band.id)", "name": "Band", "note": null, "kind": "arts", "following": true, "next": null}]}
            """.utf8))
        actions.read(activities: page.activities)
        XCTAssertFalse(actions.follow(soccer).isFollowing)
        XCTAssertTrue(actions.follow(band).isFollowing, "the page's own word, before any tap")

        actions.toggleFollow(soccer)
        XCTAssertTrue(actions.follow(soccer).isFollowing, "starred at once")
        try await Task.sleep(for: Self.hold * 3)
        actions.toggleFollow(soccer)
        XCTAssertFalse(actions.follow(soccer).isFollowing, "one more tap undoes it")
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.follows, ["activity \(soccer.id) true", "activity \(soccer.id) false"])
    }

    /// Following needs a real account: with the quiet Anonymous one, or none, it isn't there.
    func testOnlyARealAccountFollowsOrJoins() {
        XCTAssertFalse(actions(Server(), anonymous: true).hasAccount, "Anonymous isn't one")
        XCTAssertFalse(actions(Server(), signedIn: false).hasAccount, "no account at all")
        XCTAssertTrue(actions(Server()).hasAccount)
        let samples = RealLifeActions(signedIn: false, needsAccount: false, realAccount: { false }, hold: Self.hold,
                                      flip: Self.flip, setGoing: { _, _ in }, setHeart: { _, _ in })
        XCTAssertTrue(samples.hasAccount, "sample writes go nowhere and need none")
    }

    /// With no real account, Follow and Join do nothing and show nothing; a Group you're in can
    /// still be left.
    func testNoRealAccountFollowAndJoinDoNothing() async throws {
        let server = Server()
        let actions = actions(server, anonymous: true)
        let place = FollowTarget(type: .place, id: "p1")
        actions.toggleFollow(place)
        XCTAssertFalse(actions.follow(place).isFollowing)
        actions.toggleMember(groupID: Self.groupID, inGroup: false)
        XCTAssertFalse(actions.member(groupID: Self.groupID, inGroup: false).isMember)
        try await Task.sleep(for: Self.hold * 3)
        XCTAssertEqual(server.follows, [])
        XCTAssertEqual(server.memberships, [])

        actions.toggleMember(groupID: Self.groupID, inGroup: true)
        XCTAssertFalse(actions.member(groupID: Self.groupID, inGroup: true).isMember, "leaving still works")
    }

    /// The Following list: everything on it is followed. A tap there unfollows at once, and the
    /// next read of the list is the truth.
    func testTheFollowingListReadsAsFollowed() async throws {
        let server = Server()
        let actions = actions(server)

        actions.read(following: [Self.krewe, Self.sam])
        XCTAssertTrue(actions.follow(Self.krewe).isFollowing)
        XCTAssertTrue(actions.follow(Self.sam).isFollowing)
        actions.toggleFollow(Self.sam)
        XCTAssertFalse(actions.follow(Self.sam).isFollowing, "Follow again at once, still on the list")
        try await Task.sleep(for: Self.hold * 3)
        actions.read(following: [Self.krewe])
        XCTAssertFalse(actions.follow(Self.sam).isFollowing)
        XCTAssertEqual(server.follows, ["profile \(Self.sam.id) false"])
    }

    /// A follow made offline is kept on the phone, shown after a relaunch and sent.
    func testAnOfflineFollowSurvivesARelaunch() async throws {
        let server = Server()
        server.offline = true
        let store = phoneStore()
        let before = launched(server, store, as: "anna")

        before.toggleFollow(Self.krewe)
        try await Task.sleep(for: Self.retry * 2)
        before.accountChanged(signedIn: false)
        try await Task.sleep(for: Self.retry * 8)

        server.offline = false
        server.follows = []
        let after = launched(server, store, as: "anna")
        XCTAssertTrue(after.follow(Self.krewe).isFollowing, "still Following after the relaunch")
        try await waitWhile(server.follows.isEmpty)
        XCTAssertEqual(server.follows, ["place \(Self.krewe.id) true"])
    }

    func testFollowWords() {
        XCTAssertNil(FollowWords.count(0), "never a zero")
        XCTAssertEqual(FollowWords.count(1), "1 follower")
        XCTAssertEqual(FollowWords.count(128), "128 followers")
        XCTAssertEqual(FollowWords.count(2_200), "2,200 followers")
        XCTAssertNil(FollowWords.followedBy([], count: 0))
        XCTAssertEqual(FollowWords.followedBy(["Sam Rivera"], count: 1), "Followed by Sam")
        XCTAssertEqual(FollowWords.followedBy(["Sam Rivera", "Ana Lee"], count: 2), "Followed by Sam and Ana")
        XCTAssertEqual(FollowWords.followedBy(["Sam Rivera", "Ana Lee", "Dee Moss"], count: 3),
                       "Followed by Sam and 2 others")
        XCTAssertEqual(FollowWords.followedBy(["Sam Rivera", "Ana Lee", "Dee Moss"], count: 7),
                       "Followed by Sam and 6 others")
    }
}

extension XCTestCase {
    /// Polls every 5 ms until `condition` is false, for at most 5 s: a test waits on the state it
    /// checks, never a fixed time that GitHub's slower runner can outlast.
    @MainActor
    func waitWhile(_ condition: @autoclosure @escaping () -> Bool) async throws {
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

    /// Once a game's final is in (game-card 02): who went, in the past, and no pill, so Attend is
    /// gone, for someone who went too; nobody, no words.
    func testAGameThatIsOverSaysWhoWentAndOffersNothingToTap() {
        func over(_ isGoing: Bool, _ count: Int, _ friends: [String], bar: Bool = false) -> RSVPWords {
            RSVPWords.make(isGoing: isGoing, count: count, friends: friends, cancelled: false, bar: bar, over: true)
        }
        XCTAssertEqual(over(false, 212, []), RSVPWords(top: "212 went", second: nil, canLeave: false, pill: nil))
        XCTAssertEqual(over(true, 212, []), RSVPWords(top: "212 went", second: nil, canLeave: false, pill: nil),
                       "you went too: no You're going! and no Can't go?")
        XCTAssertEqual(over(false, 40, ["Sam", "Marlene"]).second, "Sam and Marlene went")
        XCTAssertEqual(over(false, 40, ["Avery"], bar: true).second, "Avery", "the bar: the names alone")
        XCTAssertEqual(over(false, 0, []), RSVPWords(top: nil, second: nil, canLeave: false, pill: nil))
    }

    /// The Event page's bar says less (Jesse at rsvp-and-groups 02's Check-in 2): beside the friends'
    /// faces only their names, so they fit by the bigger words. Its "Can't go?" is where you leave an
    /// Event (Jesse at event-card 07's Check-in 1).
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
            ("going: Can't go? leaves", true, 42, ["Avery"], false,
             RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .invite)),
            ("called off", false, 41, ["Avery"], true, bar(nil, pill: .canceled)),
            ("called off while going: can still leave", true, 42, [], true,
             RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .canceled)),
        ]
        for (name, isGoing, count, friends, cancelled, want) in table {
            XCTAssertEqual(RSVPWords.make(isGoing: isGoing, count: count, friends: friends, cancelled: cancelled, bar: true),
                           want, name)
        }
    }

    /// A Town card has no Attend and no X, Going or not (Jesse, event-card 07): just who's going, with the
    /// friends' names left off. Canceled stays. Nobody going: no words, so `rsvp` gives the card nothing to draw.
    func testATownCardHasNoAttendAndNoX() {
        func card(_ isGoing: Bool, count: Int = 42, cancelled: Bool = false, over: Bool = false) -> RSVPWords {
            RSVPWords.make(isGoing: isGoing, count: count, friends: count > 0 ? ["Avery"] : [], cancelled: cancelled,
                           card: true, over: over)
        }
        XCTAssertEqual(card(false), RSVPWords(top: "42 going", second: nil, canLeave: false, pill: nil))
        XCTAssertEqual(card(true), RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: nil))
        XCTAssertTrue(card(true).goingLine, "You're going! still cross-fades in over the count")
        XCTAssertEqual(card(false, count: 0), RSVPWords(top: nil, second: nil, canLeave: false, pill: nil))
        XCTAssertEqual(card(false, cancelled: true), RSVPWords(top: nil, second: nil, canLeave: false, pill: .canceled))
        XCTAssertEqual(card(true, cancelled: true),
                       RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .canceled))
        XCTAssertEqual(card(false, count: 212, over: true), RSVPWords(top: "212 went", second: nil, canLeave: false, pill: nil))
    }

    /// On the poster, Going turns the pill into the round X that leaves, with no "Can't go?" (attend-x,
    /// 2026-10-21); the check shows on Attend first, as before Invite. Called off, the pill stays
    /// Canceled and "Can't go?" still leaves. Not going, the count without the friends' names.
    func testOnTownThePillTurnsIntoTheXThatLeaves() {
        func town(_ isGoing: Bool, cancelled: Bool = false) -> RSVPWords {
            RSVPWords.make(isGoing: isGoing, count: 42, friends: ["Avery"], cancelled: cancelled, town: true)
        }
        XCTAssertEqual(town(true), RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: .leave))
        XCTAssertTrue(town(true).goingLine, "You're going! cross-fades in over the count")
        XCTAssertEqual(town(true).shownPill(checking: true), .rsvp, "the check shows on Attend")
        XCTAssertEqual(town(true).shownPill(checking: false), .leave, "then the X")
        XCTAssertEqual(town(false), RSVPWords(top: "42 going", second: nil, canLeave: false, pill: .rsvp),
                       "the count alone: no friends' names on Town (event-card 06)")
        XCTAssertFalse(town(false).goingLine)
        XCTAssertEqual(town(true, cancelled: true),
                       RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true, pill: .canceled))
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
