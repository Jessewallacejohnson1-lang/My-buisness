//
//  AppSessionTests.swift
//  BlockPartyTests — an account switch lets go of the last account in every model the shell
//  shares, in the same turn, before anything is read for the next one; then every read goes as
//  the next one (BP app codebase-health 22). Reads go through ticket 16's client to its fake
//  server, so nothing leaves the phone; the shell's real models are handed that client too, and
//  every read of theirs arrives there as the new account.
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
            UserDefaults.standard.removeObject(forKey: name)
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
            searchModel: SearchModel(supabase: Supabase(auth: auth, send: server.send), defaults: phone, actions: actions),
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
            // Never read here (a switch only clears it; the root view reads), but on the session's
            // client like the rest.
            profile: ProfileModel(supabase: Supabase(auth: auth, send: server.send), phone: phone),
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
        XCTAssertNotNil(session.chats.chats, "a's chats")
        session.profile.avatarUrl = "photo-a"   // a's read: the root view's, not the session's

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
        XCTAssertNil(session.chats.chats, "a's chats")
        XCTAssertNil(session.profile.avatarUrl, "a's photo")
        XCTAssertTrue(session.townFeed.unsent.isEmpty, "a's views never go up as b")
        XCTAssertTrue(session.townFeed.hiddenIDs.isEmpty, "a's hidden cards")
        XCTAssertNil(phone.object(forKey: HelloInbox.seenKey), "a's hello look")

        // Then b's reads, every one as b.
        await reads.value
        XCTAssertEqual(Set(functions(from: sent)), ["get_town_feed", "get_my_going", "get_groups",
                                                    "get_event_of_the_day", "get_my_changes", "friends_dot", "get_chats"],
                       "no profile read: the root view's read is the one for each account")
        XCTAssertEqual(Set(server.requests[sent...].map { $0.value(forHTTPHeaderField: "Authorization") }),
                       ["Bearer token-b"])
        XCTAssertFalse(session.actions.going(card).isGoing, "a's Going left with b's feed")
        XCTAssertEqual(session.you.going?.map(\.id), ["going-b"])
        XCTAssertNotNil(session.notices.list)
        XCTAssertTrue(session.friendsBook.dot)
        XCTAssertFalse(session.eventOfTheDay.needsRead(now: Date()))
    }

    /// Your Profile stays between visits to You (`AppSession` keeps it), and another account never
    /// opens on the last one's name, photo, cover, bio or switches (five-tabs 03).
    func testAnotherAccountOpensOnAnEmptyProfile() {
        signIn("a")
        let session = session()
        let profile = session.profile
        profile.displayName = "Account A"
        profile.avatarUrl = "photo-a"
        profile.coverUrl = "cover-a"
        profile.bio = "a's bio"
        profile.sinceLabel = "October 2025"
        profile.plansToFriends = false
        profile.loaded = true

        signIn("b")
        session.accountChanged(from: "a", to: "b", signedIn: true)

        XCTAssertTrue(session.profile === profile, "one Profile for the session, kept between visits")
        XCTAssertEqual(profile.displayName, Interests.displayName(phone) ?? "")
        XCTAssertNil(profile.avatarUrl, "a's photo")
        XCTAssertNil(profile.coverUrl, "a's cover")
        XCTAssertEqual(profile.bio, "", "a's bio")
        XCTAssertNil(profile.sinceLabel)
        XCTAssertNil(profile.plansToFriends, "a's switch waits for b's row")
        XCTAssertFalse(profile.loaded, "b's cover shows only once b's row is read")
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
    func testLoggingInForRealStartsOnlyFriendsAndChatsOver() async throws {
        signIn("a")
        let session = session()
        await session.accountChanged(from: nil, to: "a", signedIn: true).value
        let card = try XCTUnwrap(session.townFeed.cards.first)
        session.actions.toggleSave(card)

        let sent = server.requests.count
        await session.accountChanged(from: "a", to: "a", signedIn: true).value

        XCTAssertTrue(session.actions.saved(card))
        XCTAssertEqual(session.you.going?.map(\.id), ["going-a"])
        XCTAssertEqual(functions(from: sent), ["friends_dot", "get_chats"])
    }

    /// The shell's real models, not stand-ins, handed the session's one client: after a switch
    /// every one's reads arrive at the fake server as the new account, so none goes around the
    /// session to the live network or the last account's token.
    func testEveryModelReadsThroughTheSessionsClient() async {
        signIn("a")
        // A save from before saves moved to the server, so the switch asks which are Events.
        UserDefaults.standard.set([UUID().uuidString], forKey: phoneName)
        let saved = SavedStore(key: phoneName)
        let client = Supabase(auth: auth, send: server.send)
        let session = AppSession(profile: ProfileModel(supabase: client, phone: phone), supabase: client,
                                 phone: phone, saved: saved)
        addTeardownBlock { TownFeedCache.clear() }
        // Search has read its groups, so it reads them again for the next account.
        session.searchModel.show([TownGroup]())

        signIn("b")
        await session.accountChanged(from: "a", to: "b", signedIn: true).value
        // The reads a switch doesn't start: the Saved list, a day in Daily's week, a hide.
        await session.saves.refresh()
        await session.dayPicks.refresh(DailyWeek.days(from: Date())[1])
        // A real Event's id: a sample's sends nothing.
        await session.townFeed.hide(id: UUID().uuidString, host: "Library", mute: false)
        // Your profile's read is the root view's, on the same client.
        await session.profile.read()

        let reached = Set(functions(from: 0))
        let every: Set = ["get_town_feed", "club_events", "get_groups", "get_my_going", "get_my_saves",
                          "get_event_of_the_day", "get_my_changes", "friends_dot", "town_profiles",
                          "set_not_interested"]
        XCTAssertTrue(every.isSubset(of: reached), "never reached the session's client: \(every.subtracting(reached))")
        XCTAssertEqual(Set(server.requests.map { $0.value(forHTTPHeaderField: "Authorization") }), ["Bearer token-b"])
    }

    /// Profile reads through the client it is handed, as the account on it, and its sign-out is
    /// the one it is handed.
    func testProfileGoesThroughTheClientItIsHanded() async {
        signIn("b")
        var signedOut = false
        let model = ProfileModel(supabase: Supabase(auth: auth, send: server.send), signOut: { signedOut = true })
        await model.load()
        await model.signOut()

        XCTAssertEqual(functions(from: 0), ["town_profiles", "get_profile"])
        XCTAssertEqual(Set(server.requests.map { $0.value(forHTTPHeaderField: "Authorization") }), ["Bearer token-b"])
        XCTAssertTrue(signedOut)
    }
}
