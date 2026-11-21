//
//  CommentsTests.swift
//  BlockPartyTests — comments on a post (BP app backlog 38): what the sheet reads, what a sent comment does with each
//  answer of the check, the pill agreeing with the sheet, who a reply's @ offers first, the count the feed carries
//  and the bell's grouped rows.
//

import XCTest
@testable import BlockParty

@MainActor
final class CommentsTests: XCTestCase {
    private let posted = "2026-11-21T15:00:00+00:00"

    private func post(comments: Int = 0) -> TownPost {
        TownPost(id: "p1", poster: .init(id: "marlene", name: "Marlene Ostendorf"), words: "Sledding after school?",
                 posted: Date(), leavesAt: Date().addingTimeInterval(86_400), comments: comments)
    }

    private func api(_ server: FakeServer) -> CommunityAPI {
        CommunityAPI(auth: FakeTokenProvider(userId: "me"), send: server.send)
    }

    private func methods(_ server: FakeServer, _ path: String) -> [String] {
        server.requests.filter { $0.url!.path.hasSuffix(path) }.compactMap(\.httpMethod)
    }

    func testTheSheetReadsEachCommentWithItsWriter() throws {
        let json = """
        [{"id":"c1","body":"Count me in @Dale Brunner","created_at":"\(posted)","mine":false,"can_delete":true,
          "author":{"id":"ana","name":"Ana Nguyen","photo":"https://x/ana.jpg"},
          "at_names":[{"kind":"user","id":"dale","name":"Dale Brunner"},"junk"]},
         {"id":"c2","body":"No writer","created_at":"\(posted)","author":null},
         {"id":"c3","body":"Mine","created_at":"\(posted)","mine":true,"can_delete":true,
          "author":{"id":"me","name":"Jesse"},"at_names":null}]
        """
        let comments = try CommunityAPI.commentRows(from: Data(json.utf8))
        XCTAssertEqual(comments.map(\.id), ["c1", "c3"], "one with no writer (blocked or gone) is left out")
        XCTAssertEqual(comments[0].author.name, "Ana Nguyen")
        XCTAssertEqual(comments[0].authorPhoto?.absoluteString, "https://x/ana.jpg")
        XCTAssertEqual(comments[0].atNames, [AtName(kind: .user, id: "dale", name: "Dale Brunner")])
        XCTAssertTrue(comments[0].canDelete, "on your post")
        XCTAssertFalse(comments[0].mine)
        XCTAssertTrue(comments[1].mine)
        XCTAssertFalse(comments.contains(where: \.posting))
    }

    func testASentCommentGoesUpPendingAndTheCheckSaysYes() async throws {
        let server = FakeServer()
        
        server.answers["moderate-post"] = .init(body: #"{"ok":true,"reason":""}"#)
        let dale = AtName(kind: .user, id: "dale", name: "Dale Brunner")
        let check = await api(server).sendComment(id: "c9", post: "p1", body: "Hi @Dale Brunner", atNames: [dale])
        XCTAssertEqual(check, .shown)
        let insert = try XCTUnwrap(server.requests.first { $0.url!.path.hasSuffix("event_comments") && $0.httpMethod == "POST" })
        let row = try XCTUnwrap(insert.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(row["id"] as? String, "c9")
        XCTAssertEqual(row["event_id"] as? String, "p1")
        XCTAssertEqual(row["user_id"] as? String, "me")
        XCTAssertEqual(row["body"] as? String, "Hi @Dale Brunner")
        XCTAssertNil(row["status"], "the database makes it pending; the app can't say otherwise")
        XCTAssertEqual((row["at_names"] as? [[String: String]])?.first?["id"], "dale")
        let check2 = server.requests.last { $0.url!.path.hasSuffix("moderate-post") }
        XCTAssertEqual(check2.flatMap { $0.httpBody }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] },
                       ["comment": "c9"])
        XCTAssertFalse(methods(server, "event_comments").contains("DELETE"))
    }

    func testATurnedDownCommentSaysWhy() async {
        let server = FakeServer()
        server.answers["moderate-post"] = .init(body: #"{"ok":false,"reason":"Please keep it kind."}"#)
        let check = await api(server).sendComment(id: "c9", post: "p1", body: "idiot", atNames: [])
        XCTAssertEqual(check, .declined("Please keep it kind."))
        XCTAssertFalse(methods(server, "event_comments").contains("DELETE"), "it stays turned down, counted in the day's 50")
        XCTAssertEqual(CommunityAPI.declineWords("  "), "This comment can't be posted as it is.")
    }

    func testTheDaysFiftyUsedTakesItBackDown() async {
        let server = FakeServer()
        server.answers["moderate-post"] = .init(status: 429, body: #"{"ok":false,"reason":"Not checked."}"#)
        let check = await api(server).sendComment(id: "c9", post: "p1", body: "Hi", atNames: [])
        XCTAssertEqual(check, .busy)
        XCTAssertEqual(methods(server, "event_comments"), ["POST", "DELETE"])
    }

    func testNoAnswerReadsTheCommentOnceBeforeTakingItBack() async {
        let server = FakeServer()
        server.answers["moderate-post"] = .init(status: 502, body: #"{"ok":false}"#)
        server.answers["event_comments"] = .init(body: #"[{"status":"shown"}]"#)
        let yes = await api(server).sendComment(id: "c9", post: "p1", body: "Hi", atNames: [])
        XCTAssertEqual(yes, .shown, "the lost answer was a yes")
        XCTAssertEqual(methods(server, "event_comments"), ["POST", "GET"])

        let still = FakeServer()
        still.answers["moderate-post"] = .init(status: 502, body: #"{"ok":false}"#)
        still.answers["event_comments"] = .init(body: #"[{"status":"pending"}]"#)
        let none = await api(still).sendComment(id: "c9", post: "p1", body: "Hi", atNames: [])
        XCTAssertEqual(none, .noAnswer)
        XCTAssertEqual(methods(still, "event_comments"), ["POST", "GET", "DELETE"], "taken back, so a resend can't post it twice")
    }

    func testAFailedInsertTakesBackWhateverWentUp() async {
        let server = FakeServer()
        server.answers["event_comments"] = .init(status: 500, body: "{}")
        let check = await api(server).sendComment(id: "c9", post: "p1", body: "Hi", atNames: [])
        XCTAssertEqual(check, .noAnswer)
        XCTAssertEqual(methods(server, "event_comments"), ["POST", "DELETE"])
        XCTAssertTrue(methods(server, "moderate-post").isEmpty)
    }

    func testThePillFollowsTheSheet() async {
        let server = FakeServer()
        server.answers["rpc/get_post_comments"] = .init(body: """
        [{"id":"c1","body":"Yes!","created_at":"\(posted)","author":{"id":"ana","name":"Ana Nguyen"},"can_delete":false}]
        """)
        server.answers["moderate-post"] = .init(body: #"{"ok":true}"#)
        let thread = CommentThread(post: post(comments: 4), api: api(server))
        XCTAssertEqual(thread.count, 4, "the feed's count until the sheet reads")
        await thread.load()
        XCTAssertEqual(thread.count, 1, "then the list, so pill and sheet agree")
        let me = TownPost.Person(id: "me", name: "Jesse")
        let refused = await thread.send("Count me in", names: [], me: me, photo: nil)
        XCTAssertNil(refused)
        XCTAssertEqual(thread.count, 2)
        XCTAssertEqual(thread.comments.last?.body, "Count me in")
        XCTAssertEqual(thread.comments.last?.posting, false)
        let deleted = await thread.delete(thread.comments[1])
        XCTAssertTrue(deleted)
        XCTAssertEqual(thread.count, 1)
    }

    func testATurnedDownCommentLeavesTheListAndTheCount() async {
        let server = FakeServer()
        server.answers["moderate-post"] = .init(body: #"{"ok":false,"reason":"Please keep it kind."}"#)
        let thread = CommentThread(post: post(), api: api(server))
        await thread.load()
        let refused = await thread.send("idiot", names: [], me: .init(id: "me", name: "Jesse"), photo: nil)
        XCTAssertEqual(refused, CommentRefusal(words: "Please keep it kind.", red: true))
        XCTAssertTrue(thread.comments.isEmpty)
        XCTAssertEqual(thread.count, 0)
    }

    func testAFailedDeleteComesBack() async {
        let server = FakeServer()
        server.answers["rpc/get_post_comments"] = .init(body: """
        [{"id":"c1","body":"Yes!","created_at":"\(posted)","author":{"id":"me","name":"Jesse"},"mine":true,"can_delete":true}]
        """)
        let thread = CommentThread(post: post(), api: api(server))
        await thread.load()
        server.failure = URLError(.notConnectedToInternet)
        let deleted = await thread.delete(thread.comments[0])
        XCTAssertFalse(deleted)
        XCTAssertEqual(thread.comments.map(\.id), ["c1"])
    }

    func testAReplyOffersTheThreadFirstNeverYou() async {
        let server = FakeServer()
        server.answers["rpc/get_post_comments"] = .init(body: """
        [{"id":"c1","body":"a","created_at":"\(posted)","author":{"id":"ana","name":"Ana Nguyen"}},
         {"id":"c2","body":"b","created_at":"\(posted)","author":{"id":"me","name":"Jesse"}},
         {"id":"c3","body":"c","created_at":"\(posted)","author":{"id":"dale","name":"Dale Brunner"}},
         {"id":"c4","body":"d","created_at":"\(posted)","author":{"id":"ana","name":"Ana Nguyen"}}]
        """)
        let thread = CommentThread(post: post(), api: api(server))
        await thread.load()
        XCTAssertEqual(thread.people(me: "me").map(\.name.name), ["Ana Nguyen", "Dale Brunner", "Marlene Ostendorf"])
        XCTAssertEqual(CommentCopy.placeholder(poster: "Marlene Ostendorf"), "Add a comment for Marlene…")
        XCTAssertEqual(CommentCopy.placeholder(poster: nil), "Add a comment…")
    }

    func testTheFeedCarriesEachPostsCount() throws {
        let json = """
        [{"id":"p1","title":"Sledding?","created_at":"\(posted)","leaves_at":"2099-10-14T15:00:00+00:00",
          "kind":"post","poster":{"id":"u1","name":"Marlene","tagged":[],"comments":3}},
         {"id":"p2","title":"Hi","created_at":"\(posted)","leaves_at":"2099-10-14T15:00:00+00:00",
          "kind":"post","poster":{"id":"u1","name":"Marlene"}}]
        """
        let posts = try CommunityAPI.townFeedLines(from: Data(json.utf8)).compactMap { line -> TownPost? in
            if case .post(let post) = line { return post }
            return nil
        }
        XCTAssertEqual(posts.map(\.comments), [3, 0])
    }

    func testTheBellGroupsCommentsAndReplies() throws {
        let json = """
        [{"id":"p1","title":"Sledding?","created_at":"\(posted)","leaves_at":"2099-10-14T15:00:00+00:00","kind":"post",
          "poster":{"id":"me","name":"Jesse"},"how":"commented","who":{"id":"dale","name":"Dale Brunner","photo":null},
          "others":2,"at":"2026-11-21T16:00:00+00:00"},
         {"id":"p2","title":"Pint night","created_at":"\(posted)","leaves_at":"2099-10-14T15:00:00+00:00","kind":"post",
          "poster":{"id":"sam","name":"Sam Rivera"},"how":"replied","who":{"id":"ana","name":"Ana Nguyen"},
          "others":0,"at":"2026-11-21T15:30:00+00:00"},
         {"id":"p3","title":"x","created_at":"\(posted)","leaves_at":"2099-10-14T15:00:00+00:00","kind":"post",
          "poster":{"id":"sam","name":"Sam Rivera"},"how":"commented","who":null,"others":0,"at":"2026-11-21T15:30:00+00:00"}]
        """
        let rows = try CommunityAPI.commentNoticeRows(from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.post.id), ["p1", "p2"], "one with no writer is left out")
        XCTAssertEqual(rows.map(\.name), ["Dale Brunner", "Ana Nguyen"])
        XCTAssertEqual(rows.map(\.othersLabel), ["2 others", nil])
        XCTAssertEqual(rows.map(\.words), ["commented on your post.", "replied to you."])
        XCTAssertTrue(rows.allSatisfy(\.opensComments))
        XCTAssertEqual(NamedNotice(post: rows[0].post, how: .commented, others: 1).othersLabel, "1 other")

        var newer = rows[0]
        newer.at = rows[0].when.addingTimeInterval(60)
        XCTAssertNotEqual(newer.id, rows[0].id, "a new comment lights the dot again")
        XCTAssertEqual(BellRow.merged([], [], named: rows).first?.id, rows[0].id, "newest first, by the comment's time")
    }
}
