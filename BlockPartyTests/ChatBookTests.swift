//
//  ChatBookTests.swift
//  BlockPartyTests — chat's model (BP app five-tabs 05): what a list row says, how the server's messages and what's
//  on its way merge, a send and a failed send, the first message to someone, Seen, the answers, the typing dots and
//  the dot, and a Going chat's row, join and updates. What the server allows is `supabase/tests/chat_with_friends.test.mjs` and `going_chat.test.mjs`.
//

import XCTest
@testable import BlockParty

@MainActor
final class ChatBookTests: XCTestCase {
    private let server = FakeServer()
    private lazy var supabase = Supabase(auth: FakeTokenProvider(userId: "me"), send: server.send)
    private lazy var api = ChatAPI(supabase)
    private let now = Date(timeIntervalSince1970: 1_793_750_400)  // 2026-11-03, about noon in the Town

    private func chatJSON(id: String = "c1", kind: String = "direct", name: String? = nil, last: String = "hi",
                          lastKind: String = "text", mine: Bool = false, sender: String = "Sam Rivera",
                          unread: Bool = false, request: Bool = false, waiting: Bool = false) -> String {
        """
        {"chat_id":"\(id)","kind":"\(kind)","name":\(name.map { "\"\($0)\"" } ?? "null"),
         "others":[{"user_id":"sam","display_name":"Sam Rivera","avatar_url":null,"since":null,"relation":"friends",
                    "mutual_friends":0,"friends_since":"2024-03-01T12:00:00+00:00"},
                   {"user_id":"kim","display_name":"Kim Thao","avatar_url":null,"since":null,"relation":"friends",
                    "mutual_friends":0,"friends_since":null}],
         "last_kind":"\(lastKind)","last_body":"\(last)","last_mine":\(mine),"last_sender":"\(sender)",
         "last_at":"2026-11-03T17:00:00+00:00","unread":\(unread),"request":\(request),"waiting":\(waiting)}
        """
    }

    private func chats(_ rows: String...) throws -> [Chat] {
        try Supabase.decode(Data("[\(rows.joined(separator: ","))]".utf8))
    }

    private func message(_ id: String, _ words: String = "hi", from: String = "sam", at seconds: TimeInterval = 0,
                         state: ChatMessage.State = .sent) -> ChatMessage {
        ChatMessage(id: id, serverID: state == .sent ? "s-\(id)" : nil, senderID: from, content: .text(words),
                    at: now.addingTimeInterval(seconds), state: state)
    }

    // MARK: What a row says

    func testARowsTitleAndLine() throws {
        let direct = try chats(chatJSON(last: "See you Saturday!"))[0]
        XCTAssertEqual(direct.title, "Sam Rivera")
        XCTAssertEqual(ChatWords.preview(direct), "See you Saturday!")
        XCTAssertEqual(direct.others[0].friendsSince, "2024-03-01T12:00:00+00:00")

        let named = try chats(chatJSON(kind: "group", name: "Trivia crew", last: "in"))[0]
        XCTAssertEqual(named.title, "Trivia crew")
        XCTAssertEqual(ChatWords.preview(named), "Sam: in", "a group says who")
        let unnamed = try chats(chatJSON(kind: "group"))[0]
        XCTAssertEqual(unnamed.title, "Sam, Kim")

        XCTAssertEqual(ChatWords.preview(try chats(chatJSON(mine: true))[0]), "You: hi")
        XCTAssertEqual(ChatWords.preview(try chats(chatJSON(lastKind: "photo"))[0]), "Sent a photo")
        XCTAssertEqual(ChatWords.preview(try chats(chatJSON(lastKind: "event"))[0]), "Sent an Event")
    }

    func testWhenARowSaysItWas() {
        XCTAssertEqual(ChatWords.ago(now.addingTimeInterval(-20), now: now), "Now")
        XCTAssertEqual(ChatWords.ago(now.addingTimeInterval(-5 * 60), now: now), "5m")
        XCTAssertEqual(ChatWords.ago(now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(ChatWords.ago(now.addingTimeInterval(-24 * 3600), now: now), "Yesterday")
        XCTAssertEqual(ChatWords.ago(now.addingTimeInterval(-3 * 24 * 3600), now: now), Town.format(now.addingTimeInterval(-3 * 24 * 3600), "EEE"))
        XCTAssertEqual(ChatWords.ago(now.addingTimeInterval(-30 * 24 * 3600), now: now), Town.format(now.addingTimeInterval(-30 * 24 * 3600), "MMMd"))
    }

    func testAStampGoesBeforeTheFirstAndAfterAGap() {
        XCTAssertTrue(ChatWords.needsStamp(message("a"), after: nil))
        XCTAssertFalse(ChatWords.needsStamp(message("b", at: 14 * 60), after: message("a")))
        XCTAssertTrue(ChatWords.needsStamp(message("b", at: 15 * 60), after: message("a")))
    }

    // MARK: Going chats

    private let cardJSON = #"{"id":"e1","title":"Holiday Market","event_date":"2026-12-05","going_count":24,"created_at":"2026-11-03T17:00:00+00:00"}"#

    private func goingJSON(id: String = "g1", card: String? = nil, last: String = "Vendors by 8:30", mine: Bool = false,
                           sender: String = "Sam Lee", host: Bool = false, isHost: Bool = false, unread: Bool = false,
                           lights: Bool = false) -> String {
        """
        {"chat_id":"\(id)","kind":"going","name":null,"others":[],"last_kind":"text","last_body":"\(last)","last_mine":\(mine),
         "last_sender":"\(sender)","last_at":"2026-11-03T17:00:00+00:00","unread":\(unread),"request":false,"waiting":false,
         "event":\(card ?? cardJSON),"last_host":\(host),"is_host":\(isHost),"lights":\(lights)}
        """
    }

    func testAGoingChatsRowIsItsEvent() throws {
        let row = try chats(goingJSON(host: true))[0]
        XCTAssertEqual(row.kind, .going)
        XCTAssertEqual(row.title, "Holiday Market")
        XCTAssertEqual(row.card?.id, "e1")
        XCTAssertEqual(ChatWords.preview(row), "Host: Vendors by 8:30")
        XCTAssertEqual(ChatWords.preview(try chats(goingJSON(last: "See you", sender: "Maya Ruiz"))[0]), "Maya: See you")
        XCTAssertEqual(ChatWords.preview(try chats(goingJSON(last: "See you", mine: true, host: true))[0]), "You: See you")
    }

    func testOneOddCardLeavesOutOnlyItsRow() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(goingJSON(id: "odd", card: #"{"nope":1}"#)),\(chatJSON(id: "d"))]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        XCTAssertEqual(book.chats?.count, 2)
        XCTAssertFalse(book.failed)
        XCTAssertEqual(book.messages.map(\.id), ["d"])
    }

    func testOnlyAnUpdateLightsTheDotAndReadingClearsIt() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(goingJSON(unread: true, lights: false))]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        XCTAssertFalse(book.unread, "chatter bolds its row and lights nothing")
        XCTAssertEqual(book.chat(forEvent: "e1")?.id, "g1")

        server.answers["rpc/get_chats"] = .init(body: "[\(goingJSON(unread: true, lights: true))]")
        await book.refresh()
        XCTAssertTrue(book.unread)
        book.markedRead("g1")
        XCTAssertFalse(book.unread)
        XCTAssertEqual(book.chats?.first?.unread, false)
    }

    func testAHostsWordsComeBackAsUpdatesWithWhoWroteThem() throws {
        let rows = try ChatAPI.messages(from: Data(#"""
        [{"id":"s1","client_id":"c1","sender_id":"SAM","kind":"text","body":"Moved inside","photo_path":null,"photo_w":null,"photo_h":null,
          "card":null,"created_at":"2026-11-03T17:00:00+00:00","host":true,
          "sender":{"user_id":"sam","display_name":"Sam Lee","avatar_url":null,"since":null,"relation":"none","mutual_friends":0,"friends_since":null}},
         {"id":"s2","client_id":"c2","sender_id":"ANA","kind":"text","body":"ok","photo_path":null,"photo_w":null,"photo_h":null,
          "card":null,"created_at":"2026-11-03T17:01:00+00:00","host":false,"sender":null}]
        """#.utf8))
        XCTAssertEqual(rows[0].host, true)
        XCTAssertEqual(rows[0].sender?.displayName, "Sam Lee")
        XCTAssertEqual(rows[1].host, false)
        XCTAssertNil(rows[1].sender, "a banned sender goes unnamed")
    }

    func testAGoingChatJoinsBeforeItReadsAndOpensNoTypingChannel() async throws {
        server.answers["rpc/join_going_chat"] = .init(body: #""g9""#)
        server.answers["rpc/get_chat_messages"] = .init(body: "[]")
        let thread = ChatThread(api: api, me: "me", chat: nil, going: "e1")
        XCTAssertTrue(thread.isRoom)
        XCTAssertFalse(thread.loaded, "loading until it's joined, never an empty chat you can't write to")
        await thread.read()
        XCTAssertEqual(thread.chatID, "g9")
        XCTAssertTrue(thread.loaded)
        XCTAssertFalse(thread.gone)
    }

    func testARefusedJoinIsBelievedOnlyAfterTheRetriesAndThePageGoes() async throws {
        server.answers["rpc/join_going_chat"] = .init(status: 403, body: #"{"message":"chat_not_going"}"#)
        let thread = ChatThread(api: api, me: "me", chat: nil, going: "e1")
        thread.joinWaits = [.zero, .zero]
        await thread.read()
        XCTAssertTrue(thread.gone)
        XCTAssertEqual(thread.chatID, nil)
        XCTAssertEqual(server.requests.filter { $0.url?.path.contains("join_going_chat") == true }.count,
                       3)
    }

    func testAHostsSendIsAnUpdateAtOnceAndARefusalSendsThePageAway() async throws {
        server.answers["rpc/send_chat_message"] = .init(status: 403, body: #"{"message":"chat_not_going"}"#)
        let thread = ChatThread(api: api, me: "me", chat: "g1", going: nil, isHost: true)
        await thread.send("Doors at 9")
        XCTAssertEqual(thread.messages.first?.host, true)
        XCTAssertTrue(thread.gone)
        XCTAssertEqual(thread.lastRefusal, "You're not in this chat anymore.")
    }

    // MARK: Group chats

    private func clubJSON(last: String = "Ice isn't safe yet", mine: Bool = false, sender: String = "Ben Ortiz",
                          unread: Bool = false, lights: Bool = false) -> String {
        """
        {"chat_id":"k1","kind":"club","name":"Rod and Gun Club","others":[],"last_kind":"text","last_body":"\(last)",
         "last_mine":\(mine),"last_sender":"\(sender)","last_at":"2026-11-03T17:00:00+00:00","unread":\(unread),
         "request":false,"waiting":false,"event":null,"last_host":false,"is_host":false,"lights":\(lights),"club_id":"g7"}
        """
    }

    func testAGroupChatsRowIsItsGroupAndSaysWhoWrote() throws {
        let row = try chats(clubJSON())[0]
        XCTAssertEqual(row.kind, .club)
        XCTAssertEqual(row.title, "Rod and Gun Club")
        XCTAssertEqual(row.clubId, "g7")
        XCTAssertEqual(ChatWords.preview(row), "Ben: Ice isn't safe yet")
        XCTAssertEqual(ChatWords.preview(try chats(clubJSON(last: "Thanks", mine: true))[0]), "You: Thanks")
    }

    func testAGroupChatIsFoundByItsGroupAndItsWordsLightTheDot() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(clubJSON(unread: true, lights: true))]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        XCTAssertEqual(book.chat(forGroup: "g7")?.id, "k1")
        XCTAssertNil(book.chat(forGroup: "other"))
        XCTAssertTrue(book.unread, "a Group has no host, so every message lights it")
        book.markedRead("k1")
        XCTAssertFalse(book.unread)
    }

    func testAGroupChatJoinsBeforeItReadsAndOpensNoTypingChannel() async throws {
        server.answers["rpc/join_group_chat"] = .init(body: #""k9""#)
        server.answers["rpc/get_chat_messages"] = .init(body: "[]")
        let thread = ChatThread(api: api, me: "me", chat: nil, club: "g7")
        XCTAssertTrue(thread.isRoom)
        XCTAssertFalse(thread.loaded, "\"Say hi\" never flashes over old messages")
        await thread.read()
        XCTAssertEqual(thread.chatID, "k9")
        XCTAssertTrue(thread.loaded)
        XCTAssertFalse(server.requests.contains { $0.url?.path.contains("chat_reads") == true }, "no Seen")
    }

    func testAGroupChatOpenedFromTheListStillJoinsSoItUndoesYourLeave() async throws {
        server.answers["rpc/join_group_chat"] = .init(body: #""k1""#)
        server.answers["rpc/get_chat_messages"] = .init(body: "[]")
        let thread = ChatThread(api: api, me: "me", chat: "k1", club: "g7")
        await thread.read()
        XCTAssertEqual(server.requests.filter { $0.url?.path.contains("join_group_chat") == true }.count, 1)
    }

    func testARefusedGroupChatJoinIsBelievedOnlyAfterTheRetriesAndThePageGoes() async throws {
        server.answers["rpc/join_group_chat"] = .init(status: 403, body: #"{"message":"chat_not_going"}"#)
        let thread = ChatThread(api: api, me: "me", chat: nil, club: "g7")
        thread.joinWaits = [.zero, .zero]
        await thread.read()
        XCTAssertTrue(thread.gone)
        XCTAssertEqual(server.requests.filter { $0.url?.path.contains("join_group_chat") == true }.count,
                       3)
    }

    func testAskingAboutAGroupChatReadsItsOwnFunction() async throws {
        server.answers["rpc/get_group_chat"] = .init(body: #"[{"state":"birthday","is_host":false}]"#)
        let access = try await api.groupAccess("g7")
        XCTAssertEqual(access, ChatAccess(state: .ask, isHost: false))
    }

    func testALimitInAGoingChatSaysSoInMinutes() {
        XCTAssertEqual(ChatWords.refused(SupabaseError(message: "chat_slow_down", status: 403)),
                       "You're sending a lot. Try again in a few minutes.")
    }

    func testABlockFromAPressTakesTheirWordsAtOnce() async throws {
        let thread = ChatThread(api: api, me: "me", chat: "g1")
        server.answers["rpc/send_chat_message"] = .init(status: 500, body: "{}")
        await thread.send("mine")
        thread.dropMessages(from: "ME")
        XCTAssertTrue(thread.messages.isEmpty)
    }

    // MARK: The list

    func testARequestLightsNoDotAndLeavesTheChats() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON(id: "a", unread: true)),\(chatJSON(id: "b", request: true))]")
        let book = ChatBook(supabase: supabase, live: true)
        XCTAssertNil(book.chats, "not read yet: loading, never empty")
        await book.refresh()
        XCTAssertEqual(book.messages.map(\.id), ["a"])
        XCTAssertEqual(book.requests.map(\.id), ["b"])
        XCTAssertTrue(book.unread)
        book.markedRead("a")
        XCTAssertFalse(book.unread, "read on screen: the dot goes at once")

        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON(id: "b", unread: false, request: true))]")
        await book.refresh()
        XCTAssertFalse(book.unread)
    }

    func testAFailedReadKeepsTheListAndSaysSo() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON())]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        server.failure = URLError(.notConnectedToInternet)
        await book.refresh()
        XCTAssertEqual(book.chats?.count, 1)
        XCTAssertTrue(book.failed)
    }

    func testAnotherAccountKeepsNoChat() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON(unread: true))]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        book.sending = FeedCardItem(UpcomingEvent(id: "e", title: "t", eventDate: "2026-11-03", startTime: nil, location: nil,
                                                  goingCount: 0, createdAt: ""))
        book.accountChanged()
        XCTAssertNil(book.chats)
        XCTAssertFalse(book.unread)
        XCTAssertNil(book.sending)
    }

    func testFindsTheChatWithAPerson() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON(id: "g", kind: "group")),\(chatJSON(id: "d"))]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        let sam = try XCTUnwrap(book.chats?.last?.others.first)
        XCTAssertEqual(book.chat(with: sam)?.id, "d", "the direct one, never a group they're in")
    }

    func testSamplesAndOfflineReadNothing() async {
        let book = ChatBook(supabase: supabase, live: false)
        await book.refresh()
        XCTAssertEqual(book.chats, [])
        XCTAssertTrue(server.requests.isEmpty)
    }

    // MARK: Merging

    func testTheServersCopyWinsAndWhatsOnItsWayStays() {
        let sending = message("new", "on its way", from: "me", at: 30, state: .sending)
        let failed = message("bad", "didn't go", from: "me", at: 20, state: .failed)
        let merged = ChatThread.merged([message("a", "old copy"), failed, sending],
                                       [message("a", "server copy", at: 0), message("b", at: 10)])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "bad", "new"])
        XCTAssertEqual(merged[0].content, .text("server copy"))
    }

    func testASentMessageTheServerNoLongerGivesGoes() {
        // Hidden by the admin, or from someone just blocked: inside the page's range and not in it.
        let merged = ChatThread.merged([message("a"), message("hidden", at: 5), message("b", at: 10)],
                                       [message("a"), message("b", at: 10)])
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
    }

    func testAPageJoinsOlderMessagesAndKeepsOneSentWhileItWasOut() {
        let older = ChatThread.merged([message("c", at: 100)], [message("a", at: 0), message("b", at: 10)])
        XCTAssertEqual(older.map(\.id), ["a", "b", "c"])
        let raced = ChatThread.merged([message("a"), message("just-sent", from: "me", at: 60)], [message("a")])
        XCTAssertEqual(raced.map(\.id), ["a", "just-sent"], "sent while the read was out")
    }

    // MARK: Sending

    private func sent(_ chat: String = "c1") -> FakeServer.Answer {
        .init(body: #"[{"chat_id":"\#(chat)","id":"server-1","created_at":"2026-11-03T18:00:00+00:00"}]"#)
    }

    private func args() throws -> [String: Any] {
        let request = try XCTUnwrap(server.requests.last { $0.url!.lastPathComponent == "send_chat_message" })
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testAMessageShowsAtOnceThenItsSent() async throws {
        server.answers["rpc/send_chat_message"] = sent()
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.send("  hello  ")
        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.messages[0].content, .text("hello"))
        XCTAssertEqual(thread.messages[0].state, .sent)
        XCTAssertEqual(thread.messages[0].serverID, "server-1")
        let body = try args()
        XCTAssertEqual(body["p_chat"] as? String, "c1")
        XCTAssertEqual(body["p_body"] as? String, "hello")
        XCTAssertEqual(body["p_client"] as? String, thread.messages[0].id)
        await thread.send("   ")
        XCTAssertEqual(thread.messages.count, 1, "nothing to send")
    }

    func testAFailedSendStaysAndARetryIsTheSameMessage() async throws {
        server.failure = URLError(.notConnectedToInternet)
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.send("hello")
        XCTAssertEqual(thread.messages[0].state, .failed)
        XCTAssertEqual(thread.failures, 1)
        let client = thread.messages[0].id

        server.failure = nil
        server.answers["rpc/send_chat_message"] = sent()
        await thread.retry(thread.messages[0])
        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.messages[0].state, .sent)
        XCTAssertEqual(try args()["p_client"] as? String, client, "a retry can't send it twice")
    }

    func testTheFirstMessageToSomeoneMakesTheChat() async throws {
        server.answers["rpc/send_chat_message"] = sent("new-chat")
        let thread = ChatThread(api: api, me: "me", chat: nil, to: "sam")
        XCTAssertTrue(thread.loaded, "nothing to wait for")
        await thread.send("hi Sam")
        XCTAssertEqual(try args()["p_to"] as? String, "sam")
        XCTAssertEqual(thread.chatID, "new-chat")
        await thread.send("again")
        XCTAssertEqual(try args()["p_chat"] as? String, "new-chat")
    }

    func testARefusalSaysWhy() async {
        server.answers["rpc/send_chat_message"] = .init(status: 400, body: #"{"message":"chat_limit"}"#)
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.send("hi")
        XCTAssertEqual(thread.lastRefusal, "You've sent a lot of new messages today. Try again tomorrow.")
        XCTAssertEqual(thread.messages[0].state, .refused, "no retry: it would only be refused again")
    }

    func testALongMessageIsCutToWhatTheDatabaseTakes() async throws {
        server.answers["rpc/send_chat_message"] = sent()
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.send(String(repeating: "x", count: ChatThread.longest + 5))
        XCTAssertEqual((try args()["p_body"] as? String)?.count, ChatThread.longest)
    }

    func testAcceptShowsAtOnceAndAFailureTakesItBack() async throws {
        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON(id: "r", request: true))]")
        let book = ChatBook(supabase: supabase, live: true)
        await book.refresh()
        let chat = try XCTUnwrap(book.chats?.first)
        server.answers["rpc/accept_chat"] = .init(status: 500, body: "{}")
        do {
            try await book.accept(chat)
            XCTFail("it failed")
        } catch {}
        XCTAssertEqual(book.requests.map(\.id), ["r"], "back in Requests")
        server.answers["rpc/accept_chat"] = .init(body: "null")
        server.answers["rpc/get_chats"] = .init(body: "[\(chatJSON(id: "r"))]")
        try await book.accept(chat)
        XCTAssertEqual(book.messages.map(\.id), ["r"])
    }

    private func eventMessage(cancelled: Bool, day: String = "2030-01-01") -> String {
        """
        [{"id":"1","client_id":"E","sender_id":"sam","kind":"event","body":null,"photo_path":null,"photo_w":null,"photo_h":null,
          "card":{"id":"e","title":"Bingo","event_date":"\(day)","start_time":"7 PM","created_at":"2026-11-01T00:00:00+00:00",
                  "going_count":0,"going":false,"cancelled":\(cancelled),"all_day":false},
          "created_at":"2026-11-03T18:00:00+00:00"}]
        """
    }

    func testAnEventSentToYouCanBeAnsweredUntilItsOff() async throws {
        server.answers["rpc/get_chat_messages"] = .init(body: eventMessage(cancelled: false))
        var thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.read()
        XCTAssertEqual(thread.answerable?.id, "e")

        server.answers["rpc/get_chat_messages"] = .init(body: eventMessage(cancelled: true))
        thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.read()
        XCTAssertNil(thread.answerable, "called off: nothing to say I'm in to")

        server.answers["rpc/get_chat_messages"] = .init(body: eventMessage(cancelled: false, day: "2020-01-01"))
        thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.read()
        XCTAssertNil(thread.answerable, "over")
    }

    func testReadingDecodesEachKindAndMarksRead() async throws {
        server.answers["rpc/get_chat_messages"] = .init(body: """
        [{"id":"3","client_id":"C","sender_id":"SAM","kind":"event","body":null,"photo_path":null,"photo_w":null,"photo_h":null,
          "card":null,"created_at":"2026-11-03T18:00:02+00:00"},
         {"id":"2","client_id":"B","sender_id":"sam","kind":"photo","body":null,"photo_path":"sam/x.jpg","photo_w":800,"photo_h":600,
          "card":null,"created_at":"2026-11-03T18:00:01+00:00"},
         {"id":"1","client_id":"A","sender_id":"me","kind":"text","body":"hi","photo_path":null,"photo_w":null,"photo_h":null,
          "card":null,"created_at":"2026-11-03T18:00:00+00:00"}]
        """)
        server.answers["object/sign/chat-photos"] = .init(body: #"[{"error":null,"path":"sam/x.jpg","signedURL":"/object/sign/chat-photos/sam/x.jpg?token=t"}]"#)
        server.answers["chat_reads"] = .init(body: #"[{"user_id":"SAM","read_at":"2026-11-03T18:00:00+00:00"}]"#)
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.read()
        XCTAssertTrue(thread.loaded)
        XCTAssertEqual(thread.messages.map(\.id), ["a", "b", "c"], "oldest first")
        XCTAssertEqual(thread.messages[0].content, .text("hi"))
        XCTAssertEqual(thread.messages[1].content, .photo(path: "sam/x.jpg", width: 800, height: 600))
        XCTAssertEqual(thread.messages[2].content, .event(nil), "a gone Event says so")
        XCTAssertEqual(thread.messages[2].senderID, "sam", "ids compare in one case")
        XCTAssertEqual(thread.links["sam/x.jpg"]?.absoluteString.hasSuffix("/storage/v1/object/sign/chat-photos/sam/x.jpg?token=t"), true)
        XCTAssertEqual(server.requests.last?.url?.lastPathComponent, "mark_chat_read")
    }

    // MARK: What the screen asks

    private func loaded(_ messages: [ChatMessage], reads: String = "[]") async -> ChatThread {
        let rows = messages.map { m -> String in
            if case .text(let words) = m.content {
                return #"{"id":"\#(m.id)","client_id":"\#(m.id)","sender_id":"\#(m.senderID)","kind":"text","body":"\#(words)","created_at":"\#(DateHelpers.timestampString(m.at))"}"#
            }
            return ""
        }
        server.answers["rpc/get_chat_messages"] = .init(body: "[\(rows.joined(separator: ","))]")
        server.answers["chat_reads"] = .init(body: reads)
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.read()
        return thread
    }

    func testSeenSitsUnderYourLastMessageOnceSomeoneReadsPastIt() async {
        let mine = message("a", from: "me")
        let at = DateHelpers.timestampString(mine.at.addingTimeInterval(5))
        let before = DateHelpers.timestampString(mine.at.addingTimeInterval(-5))
        var thread = await loaded([mine], reads: #"[{"user_id":"sam","read_at":"\#(at)"}]"#)
        XCTAssertTrue(thread.seen)
        thread = await loaded([mine], reads: #"[{"user_id":"sam","read_at":"\#(before)"}]"#)
        XCTAssertFalse(thread.seen, "read, but not this far")
        thread = await loaded([mine], reads: #"[{"user_id":"me","read_at":"\#(at)"}]"#)
        XCTAssertFalse(thread.seen, "your own reading isn't Seen")
        thread = await loaded([mine, message("b", from: "sam", at: 10)], reads: #"[{"user_id":"sam","read_at":"\#(at)"}]"#)
        XCTAssertFalse(thread.seen, "only under your last message when it's the last")
    }

    func testTheDotsComeWithOthersAndGoOnTheirOwn() async throws {
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        thread.heardTyping("me")
        XCTAssertTrue(thread.typing.isEmpty, "never your own")
        thread.heardTyping("sam")
        XCTAssertEqual(thread.typing, ["sam"])
        thread.stopTyping()
        XCTAssertTrue(thread.typing.isEmpty)
    }
}
