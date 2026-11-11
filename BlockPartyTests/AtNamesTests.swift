//
//  AtNamesTests.swift
//  BlockPartyTests — @ names and # tags in a post's words (BP app docs/plans/town-feed, ticket 60): what the row
//  reads from the `@` to the cursor, who it offers, what a pick writes and sends, which runs of the posted words
//  link where, and the names read from the feed and the bell, a bad one never hiding the post.
//

import XCTest
@testable import BlockParty

@MainActor
final class AtNamesTests: XCTestCase {
    private func typed(_ words: String) -> String? { AtTyping.typed(words, cursor: words.endIndex)?.query }

    func testTheRowReadsFromTheAtToTheCursor() {
        XCTAssertEqual(typed("Pint night with @b"), "b")
        XCTAssertEqual(typed("@"), "", "an @ alone offers everyone")
        XCTAssertEqual(typed("Thanks @bad h"), "bad h", "names have spaces")
        XCTAssertNil(typed("mail me at sam@b"), "an email")
        XCTAssertNil(typed("@ b"), "a space right after the @")
        XCTAssertNil(typed("@sam\nhi"), "a new line")
        XCTAssertNil(typed("@" + String(repeating: "a", count: 31)))
        XCTAssertNil(typed("no at here"))
        let words = "Hi @sa and more"
        let cursor = words.index(words.startIndex, offsetBy: 6)
        let hit = AtTyping.typed(words, cursor: cursor)
        XCTAssertEqual(hit?.query, "sa", "the cursor in the middle")
        XCTAssertEqual(hit.map { String(words[$0.range]) }, "@sa")
    }

    func testFriendsComeFirstThenPlacesByAnyWord() {
        let friends = AtCandidate.friends([neighbor("Sam Rivera"), neighbor("Ben Schmitz"), neighbor("  ")])
        XCTAssertEqual(friends.map(\.name.name), ["Ben Schmitz", "Sam Rivera"], "A to Z, a blank name left out")
        let places = [place("Bad Habit Brewing"), place("Milk & Honey Ciders"), place("Bo Diddley's Deli")]
        func names(_ q: String) -> [String] { AtTyping.matches(q, friends: friends, places: places).map(\.name.name) }
        XCTAssertEqual(names("b"), ["Ben Schmitz", "Bad Habit Brewing", "Bo Diddley's Deli"])
        XCTAssertEqual(names("rivera"), ["Sam Rivera"], "a later word")
        XCTAssertEqual(names("honey"), ["Milk & Honey Ciders"])
        XCTAssertEqual(names("bad h"), ["Bad Habit Brewing"], "the whole name with its space")
        XCTAssertEqual(names("zz"), [])
        XCTAssertEqual(names("").count, 5, "nothing typed: everyone")
    }

    func testOnlyAPlaceWithAPageAndAnIdIsOffered() {
        var park = SearchItem(id: "k:1", kind: .park, name: "Millstream Park")
        park.placeID = "p1"
        var shop = SearchItem(id: "p:2", kind: .business, name: "Bruno Press")
        shop.placeID = "p2"
        let noID = SearchItem(id: "p:3", kind: .restaurant, name: "Krewe")
        XCTAssertEqual(AtCandidate.places([park, shop, noID]).map(\.name), [AtName(kind: .place, id: "p2", name: "Bruno Press")])
    }

    func testAPickWritesTheNameAndPostSendsTheOnesStillThere() {
        var draft = NewPostDraft()
        draft.words = "Pint night with @b"
        let range = AtTyping.typed(draft.words, cursor: draft.words.endIndex)!.range
        let habit = AtName(kind: .place, id: "p1", name: "Bad Habit Brewing")
        let cursor = draft.pick(habit, replacing: range)
        XCTAssertEqual(draft.words, "Pint night with @Bad Habit Brewing ")
        XCTAssertEqual(cursor, draft.words.endIndex)
        let sam = AtName(kind: .user, id: "u1", name: "Sam Rivera")
        draft.words += "and @sa"
        _ = draft.pick(sam, replacing: AtTyping.typed(draft.words, cursor: draft.words.endIndex)!.range)
        _ = draft.pick(sam, replacing: draft.words.endIndex..<draft.words.endIndex)
        XCTAssertEqual(draft.atNames, [habit, sam], "once each, in the order picked")
        XCTAssertEqual(draft.input(id: "x", imageURL: nil, aspect: nil).atNames, [habit, sam])
        draft.words = "Pint night with @Sam Rivera"
        XCTAssertEqual(draft.input(id: "x", imageURL: nil, aspect: nil).atNames, [sam], "Bad Habit was typed away")
    }

    func testThePostedWordsLinkEachNameAndTag() {
        let sam = AtName(kind: .user, id: "u1", name: "Sam")
        let samR = AtName(kind: .user, id: "u2", name: "Sam Rivera")
        let habit = AtName(kind: .place, id: "p1", name: "Bad Habit Brewing")
        let words = "With @Sam Rivera and @Sam at @Bad Habit Brewing! #JoeTownNights #1 a#b @Samantha #über_cool"
        let links = PostWords.links(words, names: [sam, samR, habit])
        XCTAssertEqual(links.map { String(words[$0.range]) },
                       ["@Sam Rivera", "@Sam", "@Bad Habit Brewing", "#JoeTownNights", "#über_cool"])
        XCTAssertEqual(links.map(\.target), [.name(samR), .name(sam), .name(habit), .tag("JoeTownNights"), .tag("über_cool")],
                       "the longer name wins, @Samantha is no one, #1 has no letter, a#b is mid-word")
        XCTAssertEqual(PostWords.links("No names here", names: [sam]), [])
    }

    func testALinkTapOpensWhatItNames() {
        let habit = AtName(kind: .place, id: "3f3c5259-67f9-491e-9af5-5c4b21a80b58", name: "Bad Habit Brewing")
        XCTAssertEqual(PostWords.target(PostWords.url(.name(habit)), names: [habit]), .name(habit))
        XCTAssertEqual(PostWords.target(PostWords.url(.tag("Café_Night")), names: []), .tag("Café_Night"))
        XCTAssertNil(PostWords.target(PostWords.url(.name(habit)), names: []), "a name the post didn't keep")
        XCTAssertNil(PostWords.target(URL(string: "https://example.com")!, names: [habit]))
        let text = PostWords.attributed("Thanks @Bad Habit Brewing", names: [habit])
        XCTAssertEqual(text.runs.compactMap(\.link), [PostWords.url(.name(habit))])
    }

    func testTheFeedSendsTheNamesAndABadOneNeverHidesThePost() throws {
        let json = """
        [{"id":"p1","title":"Thanks @Sam Rivera","created_at":"2026-10-07T15:00:00+00:00","leaves_at":"2099-10-14T15:00:00+00:00",
          "kind":"post","poster":{"id":"u1","name":"Jesse","tagged":[],
          "at_names":[{"kind":"user","id":"u2","name":"Sam Rivera"},{"kind":"group","id":"g","name":"x"},"junk"]}},
         {"id":"p2","title":"Hi","created_at":"2026-10-07T15:00:00+00:00","leaves_at":"2099-10-14T15:00:00+00:00",
          "kind":"post","poster":{"id":"u1","name":"Jesse","at_names":"not a list"}}]
        """
        let posts = try CommunityAPI.townFeedLines(from: Data(json.utf8)).compactMap { line -> TownPost? in
            if case .post(let post) = line { return post }
            return nil
        }
        XCTAssertEqual(posts.map(\.id), ["p1", "p2"])
        XCTAssertEqual(posts[0].atNames, [AtName(kind: .user, id: "u2", name: "Sam Rivera")])
        XCTAssertEqual(posts[1].atNames, [])
    }

    func testTheBellReadsNamedAndTaggedPosts() throws {
        let json = """
        [{"id":"p1","title":"Thanks @Sam Rivera","location":null,"image_url":"https://x/p1.jpg",
          "created_at":"2026-10-07T15:00:00+00:00","leaves_at":"2099-10-14T15:00:00+00:00","heart_count":2,"hearted":false,
          "kind":"post","poster":{"id":"u1","name":"Marlene Ostendorf","tagged":[],
          "at_names":[{"kind":"user","id":"u2","name":"Sam Rivera"}]},"how":"named"},
         {"id":"p2","title":"Sledding","created_at":"2026-10-07T14:00:00+00:00","leaves_at":"2099-10-14T15:00:00+00:00",
          "kind":"post","poster":{"id":"u3","name":"Dale Brunner","tagged":[{"id":"u2","name":"Sam Rivera"}]},"how":"tagged"},
         {"id":"p3","title":"No poster","created_at":"2026-10-07T14:00:00+00:00","leaves_at":"2099-10-14T15:00:00+00:00",
          "kind":"post","poster":null,"how":"named"}]
        """
        let named = try CommunityAPI.namedRows(from: Data(json.utf8))
        XCTAssertEqual(named.map(\.post.id), ["p1", "p2"], "one with no poster is left out")
        XCTAssertEqual(named.map(\.words), ["mentioned you in a post.", "tagged you in a post."])
        XCTAssertEqual(named[0].post.photo?.absoluteString, "https://x/p1.jpg")
    }

    func testANamedPostLightsTheBellUntilItsPageIsOpened() async {
        let keep = UserDefaults(suiteName: "AtNamesTests")!
        keep.removePersistentDomain(forName: "AtNamesTests")
        let post = TownPost(id: "p1", poster: .init(id: "u1", name: "Marlene"), words: "Hi @Sam",
                            posted: Date(), leavesAt: Date().addingTimeInterval(86_400))
        let notices = Notices(read: { [] }, named: { [NamedNotice(post: post, tagged: false)] }, keep: keep)
        await notices.refresh()
        XCTAssertTrue(notices.dot)
        XCTAssertEqual(BellRow.merged(notices.list ?? [], [], named: notices.named).map(\.id), ["named:p1"])
        notices.opened()
        XCTAssertFalse(notices.dot)
        let failing = Notices(read: { throw URLError(.notConnectedToInternet) }, named: { [NamedNotice(post: post, tagged: true)] },
                              keep: keep)
        await failing.refresh()
        XCTAssertTrue(failing.failed, "the changes' read failed with nothing read before")
        XCTAssertEqual(failing.named.count, 1, "the names still came")
    }

    private func neighbor(_ name: String) -> Neighbor {
        Neighbor(userId: "u:\(name)", displayName: name, avatarUrl: nil, since: nil, relation: .friends, mutualFriends: 0)
    }

    private func place(_ name: String) -> AtCandidate {
        var item = SearchItem(id: "p:\(name)", kind: .business, name: name)
        item.placeID = "id:\(name)"
        return AtCandidate.places([item])[0]
    }
}
