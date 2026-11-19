//
//  ChatHeartsTests.swift
//  BlockPartyTests — hearts and replies in a chat (BP app messages 03): one emoji each, the same one again takes it
//  back, the pill's order and count, a heart that shows at once and goes back when the server says no, a reply that
//  carries what it answers, and what the quote says. What the server allows is
//  `supabase/tests/chat_hearts.test.mjs`.
//

import XCTest
@testable import BlockParty

@MainActor
final class ChatHeartsTests: XCTestCase {
    private let server = FakeServer()
    private lazy var supabase = Supabase(auth: FakeTokenProvider(userId: "me"), send: server.send)
    private lazy var api = ChatAPI(supabase)

    private func body(of function: String) throws -> [String: Any] {
        let request = try XCTUnwrap(server.requests.last { $0.url!.lastPathComponent == function })
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func thread(with messages: String) async -> ChatThread {
        server.answers["rpc/get_chat_messages"] = .init(body: messages)
        let thread = ChatThread(api: api, me: "me", chat: "c1")
        await thread.read()
        return thread
    }

    private let oneMessage = #"""
        [{"id":"s1","client_id":"M1","sender_id":"SAM","kind":"text","body":"Bingo tonight?","photo_path":null,
          "photo_w":null,"photo_h":null,"card":null,"created_at":"2026-11-03T17:00:00+00:00","sender":null,"host":false,
          "reply":{"gone":false,"sender_id":"ME","kind":"text","name":"Jo Lee","body":"Who's in?"},
          "reactions":[{"user_id":"KIM","emoji":"😂"}]}]
        """#

    func testOneEmojiEachAndTheSameOneAgainTakesItBack() {
        let kim = ChatReaction(userId: "kim", emoji: "😂")
        let hearted = ChatLook.reacted([kim], me: "me", "❤️")
        XCTAssertEqual(hearted, [kim, ChatReaction(userId: "me", emoji: "❤️")])
        XCTAssertEqual(ChatLook.reacted(hearted, me: "me", "👍"), [kim, ChatReaction(userId: "me", emoji: "👍")])
        XCTAssertEqual(ChatLook.reacted(hearted, me: "me", "❤️"), [kim])
        XCTAssertEqual(ChatLook.emoji, ["❤️", "😂", "😮", "😢", "😡", "👍"], "the server takes these six and no others")
    }

    func testThePillShowsTheMostPickedFirstUpToThreeAndHowManyPeople() {
        let r = { (who: String, emoji: String) in ChatReaction(userId: who, emoji: emoji) }
        XCTAssertEqual(ChatLook.pill([r("a", "😂")]).emoji, ["😂"])
        XCTAssertNil(ChatLook.pill([r("a", "😂")]).count, "one person: no number")
        let busy = ChatLook.pill([r("a", "😂"), r("b", "❤️"), r("c", "❤️"), r("d", "😮"), r("e", "👍")])
        XCTAssertEqual(busy.emoji, ["❤️", "😂", "😮"])
        XCTAssertEqual(busy.count, 5)
    }

    func testAMessageReadsWithItsReactionsAndItsQuote() async throws {
        let thread = await thread(with: oneMessage)
        let message = try XCTUnwrap(thread.messages.first)
        XCTAssertEqual(message.reactions, [ChatReaction(userId: "kim", emoji: "😂")])
        XCTAssertEqual(message.reply?.senderId, "me")
        XCTAssertTrue(thread.isMe(message.reply?.senderId))
        XCTAssertEqual(ChatWords.quoted(try XCTUnwrap(message.reply)), "Who's in?")
    }

    func testAHeartShowsAtOnceAndGoesBackWhenTheServerSaysNo() async throws {
        let thread = await thread(with: oneMessage)
        let message = try XCTUnwrap(thread.messages.first)
        await thread.react(message, "❤️")
        XCTAssertEqual(try body(of: "react_chat_message")["p_message"] as? String, "s1")
        XCTAssertEqual(try body(of: "react_chat_message")["p_emoji"] as? String, "❤️")
        XCTAssertEqual(thread.messages[0].reactions.last, ChatReaction(userId: "me", emoji: "❤️"))

        await thread.react(thread.messages[0], "❤️")
        XCTAssertTrue(try body(of: "react_chat_message")["p_emoji"] is NSNull, "the same one again takes it back")
        XCTAssertEqual(thread.messages[0].reactions, [ChatReaction(userId: "kim", emoji: "😂")])

        server.answers["rpc/react_chat_message"] = .init(status: 403, body: #"{"message":"chat_not_accepted"}"#)
        await thread.react(thread.messages[0], "😮")
        XCTAssertEqual(thread.messages[0].reactions, [ChatReaction(userId: "kim", emoji: "😂")], "refused: as it was")
    }

    func testAReplySendsWhatItAnswersAndShowsTheQuoteAtOnce() async throws {
        let thread = await thread(with: oneMessage)
        server.answers["rpc/send_chat_message"] = .init(
            body: #"[{"chat_id":"c1","id":"server-2","created_at":"2026-11-03T18:00:00+00:00"}]"#)
        await thread.send("Me!", replying: thread.messages[0])
        XCTAssertEqual(try body(of: "send_chat_message")["p_reply"] as? String, "s1")
        let reply = try XCTUnwrap(thread.messages.last?.reply)
        XCTAssertEqual(reply.senderId, "sam")
        XCTAssertEqual(ChatWords.quoted(reply), "Bingo tonight?")

        await thread.send("No reply")
        XCTAssertNil(try body(of: "send_chat_message")["p_reply"], "a plain send names nothing, as before")
    }

    func testWhatTheQuoteSays() {
        XCTAssertEqual(ChatWords.replied(mine: true, by: nil, to: "Maya Lund", quotedMine: false, sameSender: false),
                       "You replied to Maya")
        XCTAssertEqual(ChatWords.replied(mine: true, by: nil, to: nil, quotedMine: true, sameSender: true),
                       "You replied to yourself")
        XCTAssertEqual(ChatWords.replied(mine: false, by: "Maya Lund", to: nil, quotedMine: true, sameSender: false),
                       "Maya replied to you")
        XCTAssertEqual(ChatWords.replied(mine: false, by: "Maya Lund", to: "Tom Fry", quotedMine: false, sameSender: false),
                       "Maya replied to Tom")
        XCTAssertEqual(ChatWords.quoted(ChatQuote(gone: true)), "Message unavailable")
        XCTAssertEqual(ChatWords.quoted(ChatQuote(kind: "photo")), "Photo")
        XCTAssertEqual(ChatWords.quoted(ChatQuote(kind: "event", body: "Bingo Night")), "Bingo Night")
    }
}
