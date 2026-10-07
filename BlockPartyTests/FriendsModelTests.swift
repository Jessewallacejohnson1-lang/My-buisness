//
//  FriendsModelTests.swift
//  BlockPartyTests — the friends inbox's data: row order, the All / Unread filter, typed
//  names, reading a chat, sending, and the time labels.
//

import XCTest
@testable import BlockParty

@MainActor
final class FriendsModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)  // a fixed afternoon

    private func chat(_ name: String, minutesAgo: Double, unread: Bool = false, fromMe: Bool = false) -> FriendChat {
        FriendChat(id: name, name: name, photo: "memorial-park",
                   messages: [FriendMessage(id: name, fromMe: fromMe, text: "hi \(name)", at: now.addingTimeInterval(-minutesAgo * 60))],
                   unread: unread)
    }

    private func model() -> FriendsModel {
        FriendsModel(chats: [chat("Bea Lindgren", minutesAgo: 300),
                             chat("Marlene Ostendorf", minutesAgo: 5, unread: true),
                             chat("Hal Pedersen", minutesAgo: 2000, fromMe: true),
                             chat("Dale Brunner", minutesAgo: 50, unread: true)])
    }

    /// Newest chat first, whatever order they arrive in.
    func testRowsAreNewestFirst() {
        XCTAssertEqual(model().visible.map(\.name), ["Marlene Ostendorf", "Dale Brunner", "Bea Lindgren", "Hal Pedersen"])
    }

    /// Unread keeps only chats with the dot; typing narrows by name, any case.
    func testFilterAndSearch() {
        let m = model()
        m.filter = .unread
        XCTAssertEqual(m.visible.map(\.name), ["Marlene Ostendorf", "Dale Brunner"])
        m.filter = .all
        m.words = "  bea "
        XCTAssertEqual(m.visible.map(\.name), ["Bea Lindgren"])
        m.words = "zzz"
        XCTAssertTrue(m.visible.isEmpty)
    }

    /// Opening a chat takes its dot away, and it drops out of Unread.
    func testOpeningAChatReadsIt() {
        let m = model()
        m.markRead("Marlene Ostendorf")
        XCTAssertEqual(m.chat("Marlene Ostendorf")?.unread, false)
        m.filter = .unread
        XCTAssertEqual(m.visible.map(\.name), ["Dale Brunner"])
    }

    /// A sent message lands last, trimmed, as yours, and moves the chat to the top.
    /// Blank text sends nothing.
    func testSend() {
        let m = model()
        XCTAssertFalse(m.send("   \n ", to: "Hal Pedersen", at: now))
        XCTAssertEqual(m.chat("Hal Pedersen")?.messages.count, 1)
        XCTAssertTrue(m.send("  Thanks again! ", to: "Hal Pedersen", at: now))
        let last = m.chat("Hal Pedersen")?.last
        XCTAssertEqual(last?.text, "Thanks again!")
        XCTAssertEqual(last?.fromMe, true)
        XCTAssertEqual(m.visible.first?.name, "Hal Pedersen")
        XCTAssertEqual(m.chat("Hal Pedersen")?.preview, "You: Thanks again!")
    }

    /// The row's time: the clock today, "Yesterday", the weekday this week, the date after.
    func testTimeLabels() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        XCTAssertEqual(FriendsModel.timeLabel(noon.addingTimeInterval(-3600), now: noon, calendar: cal),
                       noon.addingTimeInterval(-3600).formatted(date: .omitted, time: .shortened))
        let yesterday = cal.date(byAdding: .day, value: -1, to: noon)!
        XCTAssertNotEqual(FriendsModel.timeLabel(yesterday, now: noon, calendar: cal),
                          yesterday.formatted(.dateTime.weekday(.wide)), "yesterday says Yesterday, not its weekday")
        let threeDays = cal.date(byAdding: .day, value: -3, to: noon)!
        XCTAssertEqual(FriendsModel.timeLabel(threeDays, now: noon, calendar: cal), threeDays.formatted(.dateTime.weekday(.wide)))
        let tenDays = cal.date(byAdding: .day, value: -10, to: noon)!
        XCTAssertEqual(FriendsModel.timeLabel(tenDays, now: noon, calendar: cal), tenDays.formatted(.dateTime.month(.defaultDigits).day()))
    }

    /// The samples every DEBUG screenshot shows: eight chats, two unread, each with a message.
    func testSamples() {
        let samples = FriendsModel.samples(now: now)
        XCTAssertEqual(samples.count, 8)
        XCTAssertEqual(samples.filter(\.unread).count, 2)
        XCTAssertTrue(samples.allSatisfy { !$0.messages.isEmpty })
        XCTAssertEqual(Set(samples.map(\.id)).count, samples.count, "ids are unique")
    }
}
