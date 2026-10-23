//
//  FriendsBookTests.swift
//  BlockPartyTests — friend requests, friends, Unfriend and Block (`FriendsBook`, BP app
//  docs/plans/friends, tickets 03 and 04), driven the way the Friends page, a person's page and Search drive it, against
//  a stand-in server. The 600 ms hold and 0.18 s flip come in shorter, so these run fast.
//

import XCTest
@testable import BlockParty

@MainActor
final class FriendsBookTests: XCTestCase {

    private static let hold: Duration = .milliseconds(150)
    private static let flip: Duration = .milliseconds(90)

    /// Records every ask, and fails, refuses or takes its time when told to.
    @MainActor
    private final class Server {
        var rows: [(kind: String, neighbor: Neighbor)] = []
        var blocked: [Neighbor] = []
        var dot = false
        var writes: [String] = []
        var reads = 0
        var seen = 0
        var failing: Error?
        var delay: Duration = .zero

        func write(_ action: FriendsBook.Action, _ id: String) async throws -> Neighbor.Relation {
            writes.append("\(action) \(id)")
            if delay > .zero { try? await Task.sleep(for: delay) }
            if let failing { throw failing }
            return FriendsBook.answer(to: action)
        }
    }

    private static func person(_ name: String, _ relation: Neighbor.Relation = .stranger) -> Neighbor {
        Neighbor(userId: name, displayName: name, avatarUrl: nil, since: nil, relation: relation, mutualFriends: 0)
    }

    private func book(_ server: Server, anonymous: Bool = false) -> FriendsBook {
        FriendsBook(read: { server.reads += 1; return server.rows },
                    readBlocked: { server.blocked },
                    readDot: { server.dot },
                    markSeen: { server.seen += 1 },
                    write: { try await server.write($0, $1) },
                    isAnonymous: { anonymous },
                    hold: Self.hold, flip: Self.flip)
    }

    private func wait(_ duration: Duration = .milliseconds(60)) async {
        try? await Task.sleep(for: duration)
    }

    /// Past the hold, the flip and a little more.
    private func waitOutTurnBack() async {
        await wait(Self.hold + Self.flip + .milliseconds(150))
    }

    // MARK: The button

    func testAddShowsRequestSentAtOnceAndKeepsTheServersAnswer() async {
        let server = Server()
        let b = book(server)
        let ana = Self.person("Ana")
        b.act(.add, ana)
        XCTAssertEqual(b.relation(ana), .sent)
        await wait()
        XCTAssertEqual(b.relation(ana), .sent)
        XCTAssertEqual(server.writes, ["add Ana"])
    }

    func testCancelConfirmAndDeleteEachShowTheirAnswer() async {
        let server = Server()
        let b = book(server)
        b.act(.cancel, Self.person("Ana", .sent))
        b.act(.confirm, Self.person("Ben", .received))
        b.act(.delete, Self.person("Cal", .received))
        await wait()
        XCTAssertEqual(b.relation(Self.person("Ana", .sent)), .stranger)
        XCTAssertEqual(b.relation(Self.person("Ben", .received)), .friends)
        XCTAssertEqual(b.relation(Self.person("Cal", .received)), .stranger)
    }

    func testAFailedTapHoldsFlipsBackThenShakesWhileAScreenIsOpen() async {
        let server = Server()
        server.failing = URLError(.notConnectedToInternet)
        let b = book(server)
        b.screenOpened()
        let ana = Self.person("Ana")
        b.act(.add, ana)
        await wait(.milliseconds(60))
        XCTAssertEqual(b.relation(ana), .sent, "holds what was tapped first")
        await waitOutTurnBack()
        XCTAssertEqual(b.relation(ana), .stranger)
        XCTAssertEqual(b.failures["Ana"], 1)
    }

    func testAFailureWithNoScreenOpenFlipsBackWithoutShaking() async {
        let server = Server()
        server.failing = URLError(.notConnectedToInternet)
        let b = book(server)
        let ana = Self.person("Ana")
        b.act(.add, ana)
        await waitOutTurnBack()
        XCTAssertEqual(b.relation(ana), .stranger)
        XCTAssertNil(b.failures["Ana"])
    }

    func testTheDailyLimitFlipsBackAtOnceAndSaysWhy() async {
        let server = Server()
        server.failing = SupabaseError(message: "friend_limit", status: 400)
        let b = book(server)
        b.screenOpened()
        let ana = Self.person("Ana")
        b.act(.add, ana)
        await wait()
        XCTAssertEqual(b.relation(ana), .stranger)
        XCTAssertEqual(b.problem, .limit)
        XCTAssertNil(b.failures["Ana"], "said in words, not shaken")
    }

    func testNoNameFlipsBackAndAsksForOne() async {
        let server = Server()
        server.failing = SupabaseError(message: "friend_name_needed", status: 400)
        let b = book(server)
        b.act(.add, Self.person("Ana"))
        await wait()
        XCTAssertEqual(b.problem, .nameNeeded)
    }

    func testOneTapPerPersonAtATime() async {
        let server = Server()
        server.delay = .milliseconds(200)
        let b = book(server)
        let ana = Self.person("Ana")
        b.act(.add, ana)
        b.act(.cancel, Self.person("Ana", .sent))
        await wait(.milliseconds(300))
        XCTAssertEqual(server.writes, ["add Ana"])
        XCTAssertEqual(b.relation(ana), .sent)
    }

    // MARK: The page

    func testRequestsNewestFirstThenFriendsAToZ() async {
        let server = Server()
        server.rows = [("accepted", Self.person("Marlene", .friends)),
                       ("request", Self.person("Sarah", .received)), ("request", Self.person("Junie", .received)),
                       ("friend", Self.person("Marlene", .friends)), ("friend", Self.person("Dale", .friends))]
        let b = book(server)
        await b.refresh()
        XCTAssertTrue(b.loaded)
        XCTAssertEqual(b.page.accepted.map(\.displayName), ["Marlene"])
        XCTAssertEqual(b.requests.map(\.displayName), ["Sarah", "Junie"])
        XCTAssertEqual(b.friends.map(\.displayName), ["Dale", "Marlene"])
    }

    func testConfirmMovesTheRequestIntoFriendsAToZ() async {
        let server = Server()
        server.rows = [("request", Self.person("Sam", .received)),
                       ("friend", Self.person("Marlene", .friends)), ("friend", Self.person("Tess", .friends))]
        let b = book(server)
        await b.refresh()
        b.act(.confirm, Self.person("Sam", .received))
        XCTAssertEqual(b.requests.map(\.displayName), [])
        XCTAssertEqual(b.friends.map(\.displayName), ["Marlene", "Sam", "Tess"])
    }

    func testAFailedConfirmSlidesTheRowBackIntoRequests() async {
        let server = Server()
        server.rows = [("request", Self.person("Sam", .received))]
        server.failing = URLError(.timedOut)
        let b = book(server)
        await b.refresh()
        b.act(.confirm, Self.person("Sam", .received))
        XCTAssertEqual(b.friends.map(\.displayName), ["Sam"])
        await waitOutTurnBack()
        XCTAssertEqual(b.requests.map(\.displayName), ["Sam"])
        XCTAssertEqual(b.friends.map(\.displayName), [])
    }

    func testDeleteTakesTheRequestAway() async {
        let server = Server()
        server.rows = [("request", Self.person("Sam", .received))]
        let b = book(server)
        await b.refresh()
        b.act(.delete, Self.person("Sam", .received))
        XCTAssertTrue(b.requests.isEmpty)
        XCTAssertTrue(b.isEmpty)
    }

    func testAFailedReadIsNotEmptyItSaysItFailed() async {
        let server = Server()
        let b = FriendsBook(read: { throw URLError(.notConnectedToInternet) }, readDot: { false },
                            markSeen: { server.seen += 1 }, write: { _, _ in .stranger }, isAnonymous: { false })
        await b.refresh()
        XCTAssertFalse(b.loaded, "never 'No friends yet' after a failed read")
        XCTAssertTrue(b.failed)
        await b.seen()
        XCTAssertEqual(server.seen, 0, "nothing drawn, nothing seen")
    }

    func testAReadAgreesWithTapsThatAreDone() async {
        let server = Server()
        let b = book(server)
        b.act(.add, Self.person("Ana"))
        await wait()
        server.rows = [("friend", Self.person("Ana", .friends))]
        await b.refresh()
        XCTAssertEqual(b.relation(Self.person("Ana", .friends)), .friends, "Ana confirmed since")
    }

    /// A request you sent never comes back in the Friends page's read: Request sent stays on
    /// that person's search row and page after a visit to Friends.
    func testATapOnSomeoneTheReadDoesNotReturnStays() async {
        let server = Server()
        server.rows = [("friend", Self.person("Dale", .friends))]
        let b = book(server)
        let ana = Self.person("Ana")
        b.act(.add, ana)
        await wait()
        await b.refresh()
        XCTAssertEqual(b.relation(ana), .sent)
    }

    // MARK: The dot

    func testTheDotClearsOncePageHasBeenSeen() async {
        let server = Server()
        server.dot = true
        let b = book(server)
        await b.refreshDot()
        XCTAssertTrue(b.dot)
        await b.refresh()
        await b.seen()
        XCTAssertFalse(b.dot)
        XCTAssertEqual(server.seen, 1)
    }

    func testAnAnonymousAccountReadsNothingAndHasNoDot() async {
        let server = Server()
        server.dot = true
        let b = book(server, anonymous: true)
        await b.refreshDot()
        await b.refresh()
        XCTAssertFalse(b.dot)
        XCTAssertFalse(b.loaded)
        XCTAssertEqual(server.reads, 0)
    }

    func testAnotherAccountKeepsNothingOfTheLastOne() async {
        let server = Server()
        server.dot = true
        server.rows = [("friend", Self.person("Ana", .friends))]
        let b = book(server)
        await b.refreshDot()
        await b.refresh()
        b.reset()
        XCTAssertFalse(b.dot)
        XCTAssertFalse(b.loaded)
        XCTAssertTrue(b.friends.isEmpty)
    }

    // MARK: Unfriend and Block (ticket 04)

    func testTheSheetOffersUnfriendAndBlockToAFriendAndBlockToAnyoneElse() {
        XCTAssertEqual(FriendsBook.menuChoices(for: .friends), [.unfriend, .block])
        for relation in [Neighbor.Relation.stranger, .sent, .received] {
            XCTAssertEqual(FriendsBook.menuChoices(for: relation), [.block])
        }
    }

    func testUnfriendTakesThemOutOfYourFriendsAndBackToAddFriend() async {
        let server = Server()
        server.rows = [("friend", Self.person("Sam", .friends)), ("friend", Self.person("Tess", .friends))]
        let b = book(server)
        await b.refresh()
        let sam = Self.person("Sam", .friends)
        b.act(.unfriend, sam)
        XCTAssertEqual(b.friends.map(\.displayName), ["Tess"])
        await wait()
        XCTAssertEqual(b.relation(sam), .stranger)
        XCTAssertEqual(server.writes, ["unfriend Sam"])
    }

    func testAFailedUnfriendComesBackAndShakes() async {
        let server = Server()
        server.rows = [("friend", Self.person("Sam", .friends))]
        server.failing = URLError(.notConnectedToInternet)
        let b = book(server)
        await b.refresh()
        b.screenOpened()
        b.act(.unfriend, Self.person("Sam", .friends))
        XCTAssertTrue(b.friends.isEmpty)
        await waitOutTurnBack()
        XCTAssertEqual(b.friends.map(\.displayName), ["Sam"])
        XCTAssertEqual(b.failures["Sam"], 1)
    }

    func testABlockHidesThemEverywhereAtOnce() async {
        let server = Server()
        server.rows = [("accepted", Self.person("Sam", .friends)), ("request", Self.person("Junie", .received)),
                       ("friend", Self.person("Sam", .friends))]
        let b = book(server)
        await b.refresh()
        b.act(.block, Self.person("Sam", .friends))
        b.act(.block, Self.person("Junie", .received))
        XCTAssertTrue(b.accepted.isEmpty)
        XCTAssertTrue(b.requests.isEmpty)
        XCTAssertTrue(b.friends.isEmpty)
        XCTAssertTrue(b.isEmpty)
        let found = NeighborSearch.State.found([Self.person("Sam"), Self.person("Ana")])
        XCTAssertEqual(b.visible(found), .found([Self.person("Ana")]))
        XCTAssertEqual(b.visible(.found([Self.person("Sam")])), NeighborSearch.State.none,
                       "nobody left is nobody found")
    }

    func testABlockStaysAfterTheNextReadOfFriends() async {
        let server = Server()
        server.rows = [("friend", Self.person("Sam", .friends))]
        let b = book(server)
        await b.refresh()
        b.act(.block, Self.person("Sam", .friends))
        await wait()
        server.rows = []
        await b.refresh()
        XCTAssertEqual(b.visible([Self.person("Sam")]), [], "still hidden from an older search result")
    }

    /// The Friends page reads again when a page goes back after a block; a read that left
    /// before the block landed still lists them, and must not bring them back.
    func testAReadThatStillListsSomeoneYouBlockedKeepsThemHidden() async {
        let server = Server()
        server.rows = [("friend", Self.person("Sam", .friends))]
        server.blocked = []
        let b = book(server)
        await b.refresh()
        b.act(.block, Self.person("Sam", .friends))
        await wait()
        await b.refresh()
        await b.refreshBlocked()
        XCTAssertTrue(b.friends.isEmpty)
        XCTAssertEqual(b.visible([Self.person("Sam", .friends)]), [])
    }

    func testABlockWhileAnotherTapIsBeingSentSaysItDidNotGo() async {
        let server = Server()
        server.delay = .milliseconds(200)
        let b = book(server)
        b.act(.add, Self.person("Ana Lee"))
        b.act(.block, Self.person("Ana Lee", .sent))
        XCTAssertEqual(b.problem, .blockFailed("Ana"))
        await wait(.milliseconds(300))
        XCTAssertEqual(server.writes, ["add Ana Lee"])
    }

    func testAFailedBlockBringsThemBackAndSaysSoInWords() async {
        let server = Server()
        server.rows = [("friend", Self.person("Sam Rivera", .friends))]
        server.failing = URLError(.notConnectedToInternet)
        let b = book(server)
        await b.refresh()
        b.screenOpened()
        b.act(.block, Self.person("Sam Rivera", .friends))
        XCTAssertTrue(b.friends.isEmpty)
        await waitOutTurnBack()
        XCTAssertEqual(b.friends.map(\.displayName), ["Sam Rivera"])
        XCTAssertEqual(b.problem, .blockFailed("Sam"))
        XCTAssertEqual(b.problem?.message, "Check your connection and try again.")
        XCTAssertNil(b.failures["Sam Rivera"], "said in words, not shaken")
    }

    func testTheBlockedListUnblocksAtOnce() async {
        let server = Server()
        server.blocked = [Self.person("Hank", .blocked), Self.person("Tess", .blocked)]
        let b = book(server)
        await b.refreshBlocked()
        XCTAssertTrue(b.blockedLoaded)
        XCTAssertEqual(b.blocked.map(\.displayName), ["Hank", "Tess"])
        b.act(.unblock, Self.person("Hank", .blocked))
        XCTAssertEqual(b.blocked.map(\.displayName), ["Tess"])
        await wait()
        XCTAssertEqual(server.writes, ["unblock Hank"])
        XCTAssertEqual(b.relation(Self.person("Hank", .blocked)), .stranger)
    }

    func testAFailedUnblockComesBackAndShakes() async {
        let server = Server()
        server.blocked = [Self.person("Hank", .blocked)]
        server.failing = URLError(.notConnectedToInternet)
        let b = book(server)
        await b.refreshBlocked()
        b.screenOpened()
        b.act(.unblock, Self.person("Hank", .blocked))
        XCTAssertTrue(b.blocked.isEmpty)
        await waitOutTurnBack()
        XCTAssertEqual(b.blocked.map(\.displayName), ["Hank"])
        XCTAssertEqual(b.failures["Hank"], 1)
    }

    func testSomeoneYouJustBlockedIsOnTheBlockedListWhenItReads() async {
        let server = Server()
        let b = book(server)
        let sam = Self.person("Sam", .friends)
        b.act(.block, sam)
        await wait()
        server.blocked = [Self.person("Sam", .blocked)]
        await b.refreshBlocked()
        XCTAssertEqual(b.blocked.map(\.displayName), ["Sam"])
    }

    func testAnEmptyBlockedListIsLoadedAndEmpty() async {
        let b = book(Server())
        await b.refreshBlocked()
        XCTAssertTrue(b.blockedLoaded)
        XCTAssertTrue(b.blocked.isEmpty)
    }

    func testAFailedBlockedReadSaysItFailed() async {
        let b = FriendsBook(read: { [] }, readBlocked: { throw URLError(.notConnectedToInternet) },
                            readDot: { false }, markSeen: {}, write: { _, _ in .stranger }, isAnonymous: { false })
        await b.refreshBlocked()
        XCTAssertFalse(b.blockedLoaded)
        XCTAssertTrue(b.blockedFailed)
    }
}

/// People you may know on Daily (daily-tab 22): the X takes someone off at once and a failed
/// one brings them back; Add friend keeps the card for its Cancel; a friend made elsewhere goes.
@MainActor
final class FriendsBookSuggestionTests: XCTestCase {
    private struct Offline: Error {}

    private static func person(_ name: String, mutual: Int = 0, group: String? = nil) -> Neighbor {
        Neighbor(userId: name, displayName: name, avatarUrl: nil, since: nil, relation: .stranger,
                 mutualFriends: mutual, sharedGroup: group)
    }

    private func book(_ people: [Neighbor], hides: @escaping (String) async throws -> Void = { _ in },
                      write: @escaping (FriendsBook.Action, String) async throws -> Neighbor.Relation = {
                          action, _ in FriendsBook.answer(to: action) },
                      anonymous: Bool = false) -> FriendsBook {
        FriendsBook(read: { [] }, readDot: { false }, markSeen: {}, write: write,
                    readSuggestions: { people }, writeHide: hides,
                    isAnonymous: { anonymous }, hold: .milliseconds(50), flip: .milliseconds(30))
    }

    func testTheReasonLineIsFriendsSharedThenTheGroupThenInstagramsLine() {
        XCTAssertEqual(Self.person("A", mutual: 4).suggestLine, "4 mutual friends")
        XCTAssertEqual(Self.person("A", mutual: 1, group: "Lions Club").suggestLine, "1 mutual friend")
        XCTAssertEqual(Self.person("A", group: "Lions Club").suggestLine, "Both in Lions Club")
        XCTAssertEqual(Self.person("A").suggestLine, "Suggested for you")
    }

    func testTheReadFillsTheRowInTheServersOrder() async {
        let b = book([Self.person("Kim", mutual: 4), Self.person("Hal", mutual: 2)])
        XCTAssertEqual(b.suggested, [])
        await b.refreshSuggestions()
        XCTAssertEqual(b.suggested.map(\.displayName), ["Kim", "Hal"])
    }

    func testAnAnonymousAccountHasNone() async {
        let b = book([Self.person("Kim")], anonymous: true)
        await b.refreshSuggestions()
        XCTAssertEqual(b.suggested, [])
    }

    func testTheXTakesThemOffAtOnceAndTellsTheServer() async {
        var hidden: [String] = []
        let b = book([Self.person("Kim"), Self.person("Hal")], hides: { hidden.append($0) })
        await b.refreshSuggestions()
        b.hide(Self.person("Kim"))
        XCTAssertEqual(b.suggested.map(\.displayName), ["Hal"])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(hidden, ["Kim"])
    }

    func testAnXThatFailsBringsThemBackWhereTheyWere() async {
        let b = book([Self.person("Kim"), Self.person("Hal")], hides: { _ in throw Offline() })
        await b.refreshSuggestions()
        b.hide(Self.person("Kim"))
        XCTAssertEqual(b.suggested.map(\.displayName), ["Hal"])
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(b.suggested.map(\.displayName), ["Kim", "Hal"])
    }

    func testAddFriendKeepsTheCardForItsCancelButAFriendGoes() async {
        let b = book([Self.person("Kim"), Self.person("Hal")])
        await b.refreshSuggestions()
        b.act(.add, Self.person("Kim"))
        b.act(.confirm, Self.person("Hal"))
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(b.suggested.map(\.displayName), ["Kim"])
        XCTAssertEqual(b.relation(b.suggested[0]), .sent)
    }

    /// The server leaves out anyone you asked; coming back to Daily keeps their card and Cancel.
    func testSomeoneYouAskedKeepsTheirCardWhenDailyReadsAgain() async {
        var people = [Self.person("Kim"), Self.person("Hal")]
        let b = FriendsBook(read: { [] }, readDot: { false }, markSeen: {},
                            write: { action, _ in FriendsBook.answer(to: action) },
                            readSuggestions: { people }, isAnonymous: { false },
                            hold: .milliseconds(50), flip: .milliseconds(30))
        await b.refreshSuggestions()
        b.act(.add, Self.person("Kim"))
        try? await Task.sleep(for: .milliseconds(60))
        people = [Self.person("Hal")]
        await b.refreshSuggestions()
        XCTAssertEqual(b.suggested.map(\.displayName), ["Kim", "Hal"])
        XCTAssertEqual(b.relation(b.suggested[0]), .sent)
    }

    func testAnotherAccountKeepsNoneOfThem() async {
        let b = book([Self.person("Kim")])
        await b.refreshSuggestions()
        b.hide(Self.person("Kim"))
        b.reset()
        XCTAssertEqual(b.suggested, [])
    }
}

/// Contacts (friends 06): what leaves the phone, and how the page splits contacts once the server
/// answers. The server's side is `supabase/tests/match_contacts.test.mjs`.
@MainActor
final class ContactsMatchTests: XCTestCase {

    func testOnlyScrambledCodesLeaveThePhoneAndMatchTheServersScrambling() {
        // The server's scrambling: sha256 hex of "ben@example.com", and of "15551230003".
        XCTAssertEqual(ContactCodes.email("  Ben@Example.COM "), "f871a76fb7b15231306b634dd91b385c48e9298974308e28e161d845e3e6f060")
        XCTAssertEqual(ContactCodes.phone("(555) 123-0003"), "8338c01f521a16acddcce9236f9594fb512e2c26dd83751506706cb12d28f16f")
        XCTAssertNil(ContactCodes.email("not an email"))
        XCTAssertEqual(ContactCodes.phone("(555) 123-0003"), ContactCodes.phone("+1 555 123 0003"),
                       "a 10-digit US number takes its 1")
        XCTAssertNil(ContactCodes.phone("911"))
        XCTAssertFalse(ContactCodes.email("ben@example.com")!.contains("ben"))
    }

    func testAtMost2000CodesEmailsFirst() {
        let contacts = (0..<1500).map { PhoneContact(id: "\($0)", name: "P\($0)", phone: "1", thumbnail: nil,
                                                     emailCodes: ["e\($0)"], phoneCodes: ["p\($0)"]) }
        let sent = ContactCodes.payload(contacts)
        XCTAssertEqual(sent.emails.count + sent.phones.count, ContactCodes.cap)
        XCTAssertEqual(sent.emails.first, "e0")
    }

    func testMatchedContactsLeaveInviteAndInviteNeedsAPhone() async {
        let ana = PhoneContact(id: "a", name: "Ana Lee", phone: "555 123 0001", thumbnail: nil, emailCodes: ["ea"])
        let ben = PhoneContact(id: "b", name: "ben ortiz", phone: "555 123 0002", thumbnail: nil, emailCodes: ["eb"],
                               phoneCodes: ["pb"])
        let ben2 = PhoneContact(id: "b2", name: "Ben Ortiz", phone: "(555) 123-0002", thumbnail: nil, phoneCodes: ["pb"])
        let cal = PhoneContact(id: "c", name: "Cal Ruiz", phone: nil, thumbnail: nil, emailCodes: ["ec"])
        var asked: ([String], [String])?
        let model = ContactsMatch(match: { emails, phones in
            asked = (emails, phones)
            return [(code: "ea", neighbor: Neighbor.samples[0])]
        })
        await model.show([cal, ben2, ben, ana])
        XCTAssertEqual(asked?.0, ["ea", "eb", "ec"], "A to Z, case aside")
        guard case .ready(let onApp, let invite) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(onApp, [Neighbor.samples[0]])
        XCTAssertEqual(invite.count, 1, "Ana matched; Cal has no phone; Ben's number saved twice shows once")
    }

    func testTheSixthCheckOfTheDaySaysSoAndOfflineSaysTryAgain() async {
        let limited = ContactsMatch(match: { _, _ in throw SupabaseError(message: "contacts_limit", status: 400) })
        await limited.show([PhoneContact(id: "a", name: "Ana", phone: "1", thumbnail: nil, emailCodes: ["e"])])
        XCTAssertEqual(limited.state, .limit)
        let offline = ContactsMatch(match: { _, _ in throw URLError(.notConnectedToInternet) })
        await offline.show([PhoneContact(id: "a", name: "Ana", phone: "1", thumbnail: nil, emailCodes: ["e"])])
        XCTAssertEqual(offline.state, .failed)
    }

    func testNoCodesAsksNobody() async {
        let model = ContactsMatch(match: { _, _ in XCTFail("asked"); return [] })
        await model.show([PhoneContact(id: "a", name: "Ana", phone: "1", thumbnail: nil)])
        guard case .ready(let onApp, let invite) = model.state else { return XCTFail() }
        XCTAssertTrue(onApp.isEmpty)
        XCTAssertEqual(invite.count, 1)
    }
}
