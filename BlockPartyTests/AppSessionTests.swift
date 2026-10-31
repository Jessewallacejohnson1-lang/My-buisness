//
//  AppSessionTests.swift
//  BlockPartyTests — an account switch lets go of the last account in every model the shell
//  shares, in the same turn, before anything is read for the next one; then every read goes as
//  the next one (BP app codebase-health 22). Reads go through ticket 16's client to its fake
//  server, so nothing leaves the phone.
//

import XCTest
@testable import BlockParty

@MainActor
final class AppSessionTests: XCTestCase {
    private lazy var auth = FakeTokenProvider(userId: "a")
    private lazy var server = FakeServer()
    /// A phone of its own for each test, emptied when it ends.
    private lazy var phoneName: String = {
        let name = "AppSessionTests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: name + ".movedUp")
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return name
    }()
    private lazy var phone = UserDefaults(suiteName: phoneName)!

    /// One read through the app's one client, answering the account it went as.
    private func read(_ function: String) async throws -> String {
        let who = auth.userId ?? ""
        try await Supabase(auth: auth, send: server.send).rpc(function)
        return who
    }

    private func event(_ id: String, going: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: id, title: "Trivia night", eventDate: "2026-10-12", startTime: "7 PM", location: nil,
                      goingCount: going ? 1 : 0, createdAt: "2026-10-06T16:08:20+00:00", rsvpd: going)
    }

    /// The shell's models, each reading for whoever is signed in: account a is Going to e1, b isn't.
    private func session() -> AppSession {
        let actions = RealLifeActions(signedIn: true, needsAccount: true, hold: .zero, flip: .zero,
                                      setGoing: { _, _ in }, setHeart: { _, _ in }, setSave: { _, _ in },
                                      knownEvents: { _ in [] })
        return AppSession(
            actions: actions,
            townFeed: TownFeed(read: {
                let who = try await self.read("get_town_feed")
                return [TownFeedEntry(card: FeedCardItem(self.event("e1", going: who == "a")), leavesAt: .distantFuture)]
            }, actions: actions),
            searchModel: SearchModel(defaults: phone, actions: actions),
            friendsBook: FriendsBook(read: { [] }, readDot: { _ = try await self.read("friends_dot"); return true },
                                     markSeen: {}, write: { _, _ in .stranger }, isAnonymous: { false }),
            you: YouModel(read: { _, _ in
                let who = try await self.read("get_my_going")
                return [self.event("going-\(who)")]
            }, groups: { _ = try await self.read("get_groups"); return [] }),
            saves: YouModel(read: { _, _ in
                let who = try await self.read("get_my_saves")
                return [self.event("saved-\(who)")]
            }),
            eventOfTheDay: EventOfTheDay(read: { _ = try await self.read("get_event_of_the_day"); return [] }),
            dayPicks: DailyDayPicks(read: { _ in _ = try await self.read("get_event_of_the_day"); return [] }),
            notices: Notices(read: { _ = try await self.read("get_my_changes"); return [] }, keep: phone),
            hello: HelloInbox(keep: phone), saved: SavedStore(key: phoneName),
            supabase: Supabase(auth: auth, send: server.send))
    }

    private func signIn(_ id: String) {
        auth.userId = id
        auth.token = "token-\(id)"
    }

    private func functions(from index: Int) -> [String] {
        server.requests[index...].map { $0.url!.lastPathComponent }
    }

    func testAnotherAccountKeepsNothingOfTheLastOne() async throws {
        signIn("a")
        let session = session()
        await session.accountChanged(from: nil, to: "a", signedIn: true).value
        // Account a's day: Going to e1, a Save tapped, a card hidden, a view waiting to go up,
        // the You tab, the Saved list, the bell, the friends dot and the hello pill's look.
        await session.saves.refresh()
        let card = try XCTUnwrap(session.townFeed.cards.first)
        XCTAssertTrue(session.actions.going(card).isGoing)
        session.actions.toggleSave(card)
        XCTAssertTrue(session.actions.saved(card))
        await session.townFeed.hide(id: "e2", host: "Library", mute: false)
        session.townFeed.opened(card.id)
        phone.set(["e1"], forKey: HelloInbox.seenKey)
        XCTAssertEqual(session.you.going?.map(\.id), ["going-a"])
        XCTAssertEqual(session.saves.going?.map(\.id), ["saved-a"])
        XCTAssertNotNil(session.you.groups)
        XCTAssertNotNil(session.notices.list)
        XCTAssertTrue(session.friendsBook.dot)
        XCTAssertFalse(session.eventOfTheDay.needsRead(now: Date()))

        signIn("b")
        let sent = server.requests.count
        let reads = session.accountChanged(from: "a", to: "b", signedIn: true)

        // In the same turn, before anything is read for b, every model has let a go.
        XCTAssertEqual(server.requests.count, sent, "nothing is read for b before every model lets a go")
        XCTAssertFalse(session.actions.saved(card), "a's Save")
        XCTAssertNil(session.you.going, "a's You tab")
        XCTAssertNil(session.you.groups, "a's groups")
        XCTAssertNil(session.saves.going, "a's Saved list")
        XCTAssertTrue(session.eventOfTheDay.needsRead(now: Date()), "a's Event of the day reads again")
        XCTAssertNil(session.notices.list, "a's bell")
        XCTAssertFalse(session.friendsBook.dot, "a's friends dot")
        XCTAssertTrue(session.townFeed.unsent.isEmpty, "a's views never go up as b")
        XCTAssertTrue(session.townFeed.hiddenIDs.isEmpty, "a's hidden cards")
        XCTAssertNil(phone.object(forKey: HelloInbox.seenKey), "a's hello look")

        // Then b's reads, every one as b.
        await reads.value
        XCTAssertEqual(Set(functions(from: sent)), ["get_town_feed", "get_my_going", "get_groups",
                                                    "get_event_of_the_day", "get_my_changes", "friends_dot"])
        XCTAssertEqual(Set(server.requests[sent...].map { $0.value(forHTTPHeaderField: "Authorization") }),
                       ["Bearer token-b"])
        XCTAssertFalse(session.actions.going(card).isGoing, "a's Going left with b's feed")
        XCTAssertEqual(session.you.going?.map(\.id), ["going-b"])
        XCTAssertNotNil(session.notices.list)
        XCTAssertTrue(session.friendsBook.dot)
        XCTAssertFalse(session.eventOfTheDay.needsRead(now: Date()))
    }

    /// The first quiet account arriving after the first read is not another account: the views
    /// made before it go up under it.
    func testTheFirstAccountKeepsWhatCameBeforeIt() async {
        auth.userId = nil
        let session = session()
        session.townFeed.opened("e1")
        phone.set(["e1"], forKey: HelloInbox.seenKey)

        signIn("a")
        await session.accountChanged(from: nil, to: "a", signedIn: true).value

        XCTAssertEqual(session.townFeed.unsent.map(\.itemID), ["e1"])
        XCTAssertNotNil(phone.object(forKey: HelloInbox.seenKey))
        XCTAssertEqual(session.you.going?.map(\.id), ["going-a"])
    }

    /// The same account logging in for real keeps its taps and lists; only friends start over.
    func testLoggingInForRealStartsOnlyFriendsOver() async throws {
        signIn("a")
        let session = session()
        await session.accountChanged(from: nil, to: "a", signedIn: true).value
        let card = try XCTUnwrap(session.townFeed.cards.first)
        session.actions.toggleSave(card)

        let sent = server.requests.count
        await session.accountChanged(from: "a", to: "a", signedIn: true).value

        XCTAssertTrue(session.actions.saved(card))
        XCTAssertEqual(session.you.going?.map(\.id), ["going-a"])
        XCTAssertEqual(functions(from: sent), ["friends_dot"])
    }
}
