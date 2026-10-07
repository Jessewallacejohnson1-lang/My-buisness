//
//  FriendsModel.swift
//  Block Party — the friends inbox and its chats: what the Town bar's friends mark opens.
//
//  Jesse's pick (2026-10-06, Figma "Block Party · Friends"): the inbox is option B, a
//  WhatsApp-style list with option A's black unread dot, and a chat is option C, Instagram's
//  one-chat layout with black bubbles for you. References: BP app/references/friends-inbox/.
//
//  There are no real messages yet. Sign-in is off, nobody can follow a person, and other
//  people's names and photos aren't readable, so the chats are DEBUG samples, the same call
//  Search's People row and the Daily Spotlight make. A release build has no chats, and the
//  friends mark keeps opening the reserved screen. Real messaging's plan:
//  BP app/references/friends-inbox/plan-draft.md.
//

import Foundation
import Observation

/// One message in a chat.
struct FriendMessage: Identifiable, Hashable {
    let id: String
    let fromMe: Bool
    let text: String
    let at: Date
}

/// A one-to-one chat with a neighbour. The newest message is last.
struct FriendChat: Identifiable, Hashable {
    let id: String
    let name: String
    /// A bundled town photo standing in for a face (`Resources/Images/<photo>.jpg`).
    let photo: String
    var messages: [FriendMessage]
    var unread: Bool

    var last: FriendMessage? { messages.last }

    /// The inbox row's second line: the last message, "You: " in front when it was yours.
    var preview: String {
        guard let last else { return "" }
        return last.fromMe ? "You: \(last.text)" : last.text
    }
}

/// The inbox's two filters. Clubs joins when group chats exist.
enum FriendsFilter: String, CaseIterable, Hashable {
    case all, unread

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        }
    }
}

/// What the shell's stack pushes: the inbox, or one chat by id.
enum FriendsRoute: Hashable {
    case inbox
    case chat(String)
}

@MainActor @Observable
final class FriendsModel {
    var chats: [FriendChat]
    var filter: FriendsFilter = .all
    var words = ""

    /// Nil takes the samples, resolved here rather than in a default argument
    /// (docs/rules/swift-traps.md, MainActor defaults).
    init(chats: [FriendChat]? = nil) {
        self.chats = chats ?? Self.samples()
    }

    /// The inbox's rows: newest chat first, narrowed by the filter and the typed name.
    var visible: [FriendChat] {
        let query = words.trimmingCharacters(in: .whitespaces)
        return chats
            .filter { filter == .all || $0.unread }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { ($0.last?.at ?? .distantPast) > ($1.last?.at ?? .distantPast) }
    }

    func chat(_ id: String) -> FriendChat? { chats.first { $0.id == id } }

    /// Opening a chat reads it: the dot goes.
    func markRead(_ id: String) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[i].unread = false
    }

    /// Adds your message to the end of the chat. Blank text sends nothing.
    /// ponytail: samples only, nothing leaves the phone; the real send is `send_message`
    /// in plan-draft.md once sign-in and follows exist.
    @discardableResult
    func send(_ text: String, to id: String, at now: Date = .now) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let i = chats.firstIndex(where: { $0.id == id }) else { return false }
        chats[i].messages.append(FriendMessage(id: UUID().uuidString, fromMe: true, text: body, at: now))
        return true
    }

    // MARK: Time labels

    /// The inbox row's time, as the iOS lists Jesse picked write it: the time today,
    /// "Yesterday", the weekday within the last week, then the date.
    nonisolated static func timeLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return relativeDay(date)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }

    /// The stamp over a chat's first message: "Today 9:12 AM", "Yesterday 3:39 PM", or the
    /// date and time further back.
    nonisolated static func stamp(_ date: Date) -> String {
        "\(relativeDay(date)) \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "Today" or "Yesterday" in the phone's language, the date further back.
    nonisolated private static func relativeDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }
}

// MARK: - Samples

extension FriendsModel {
    #if DEBUG
    /// INVENTED: the Figma mockup's chats, until real messages exist. The people are
    /// Search's sample neighbours; their faces are town photos.
    static func samples(now: Date = .now) -> [FriendChat] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func chat(_ name: String, _ photo: String, unread: Bool = false, _ lines: [(Bool, String, Double)]) -> FriendChat {
            FriendChat(id: name, name: name, photo: photo,
                       messages: lines.enumerated().map { i, line in
                           FriendMessage(id: "\(name)-\(i)", fromMe: line.0, text: line.1, at: ago(line.2))
                       },
                       unread: unread)
        }
        let day = 24.0 * 60
        return [
            chat("Marlene Ostendorf", "memorial-park", unread: true, [
                (false, "Hi neighbor!", 29),
                (false, "Saw you at the market! Did they have the apple cider?", 28),
                (true, "They did! Got two jugs", 20),
                (true, "Want one for the block party?", 19),
                (false, "Yes please 🙌", 5),
            ]),
            chat("Dale Brunner", "wobegon-trail", unread: true, [
                (true, "Trail ride Thursday?", 2 * 60),
                (false, "Thursday works", 50),
            ]),
            chat("Bea Lindgren", "farmers-market", [(false, "Sent a photo", 3 * 60)]),
            chat("Hal Pedersen", "rivers-bend-park", [
                (false, "Ladder's by the garage", day + 60),
                (true, "Thanks for the ladder", day),
            ]),
            chat("Junie Okonkwo", "millstream-arts-festival", [(false, "See you Saturday", 3 * day)]),
            chat("Kesia Vue", "sju-arboretum-trail", [(false, "Liked a message", 4 * day)]),
            chat("Sam Rivera", "centennial-park", [(true, "On my way", 9 * day)]),
            chat("Marcus Whitefeather", "klinefelter-park-trail", [(false, "Is the trail open?", 11 * day)]),
        ]
    }
    #else
    static func samples(now: Date = .now) -> [FriendChat] { [] }
    #endif
}
