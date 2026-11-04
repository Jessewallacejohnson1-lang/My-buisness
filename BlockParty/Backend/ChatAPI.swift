//
//  ChatAPI.swift
//  Block Party — chat's reads and writes (BP app five-tabs 05): the database's `get_chats`,
//  `get_chat_messages` and `send_chat_message` and friends, and photos in the private `chat-photos`
//  bucket, read through links signed for the people who can see them.
//

import Foundation

/// One line of Messages: a chat with a friend, a group of friends, or everyone Going to an Event.
struct Chat: Identifiable, Hashable, Decodable {
    enum Kind: String, Decodable { case direct, group, going }

    let chatId: String
    let kind: Kind
    /// A group's name, when it was given one.
    let name: String?
    /// Everyone else in it, less anyone blocked or gone.
    let others: [Neighbor]
    var lastKind: String?
    var lastBody: String?
    var lastMine: Bool
    var lastSender: String?
    var lastAt: String
    var unread: Bool
    /// Waiting in your Requests.
    var request: Bool
    /// Yours is waiting in theirs: one message until they accept. It reads the same whether they've seen
    /// it, deleted it or it was kept from them.
    var waiting: Bool
    /// A Going chat's Event (five-tabs 06), the same card as everywhere.
    var event: ChatEvent?
    /// Its last word is the host's: the row says "Host:".
    var lastHost: Bool?
    /// You're its host: whatever you write is an update.
    var isHost: Bool?
    /// What may light the red dot: in a Going chat only an update, so a busy Event doesn't light the tab all day.
    var lights: Bool?

    var id: String { chatId }
    var card: FeedCardItem? { event?.card }

    /// Its Event's title, else its name, else who's in it: a friend's whole name, a group's first names.
    var title: String {
        if let card { return card.title }
        if let name { return name }
        if kind == .direct, let other = others.first { return other.displayName }
        return others.map(\.firstName).joined(separator: ", ")
    }

    var lastDate: Date { DateHelpers.timestamp(lastAt) ?? .distantPast }
}

/// A Going chat's Event. A card that won't decode leaves that row with no Event, never fails all of Messages.
struct ChatEvent: Hashable, Decodable {
    let card: FeedCardItem?

    init(from decoder: Decoder) { card = (try? UpcomingEvent(from: decoder)).map { FeedCardItem($0) } }
}

/// What the Event page's Going chat row asks. Whether you're Going is the app's own to know, so this read can't
/// race Attend's write. `ask`: no birthday yet, so the row asks once. `hidden`: the row stays away.
nonisolated struct GoingChatAccess: Equatable, Decodable {
    enum State: String, Decodable {
        case open, hidden = "none", ask = "birthday"
    }

    let state: State
    let isHost: Bool
}

/// One message in a chat, sent or on its way.
struct ChatMessage: Identifiable, Hashable {
    enum Content: Hashable {
        case text(String)
        case photo(path: String?, width: Int, height: Int)
        /// nil: the Event is gone, or kept to adults from someone under 18.
        case event(FeedCardItem?)
    }

    /// `refused`: the server said no for a reason a retry can't change, so it offers none.
    enum State: Hashable { case sent, sending, failed, refused }

    /// The phone's id for it, the same before and after the server has it, so its bubble never jumps.
    let id: String
    /// The server's id, once it has it: what a report names.
    var serverID: String? = nil
    let senderID: String
    var content: Content
    var at: Date
    var state = State.sent
    /// Who wrote it, in a Going chat, where no list of people names them.
    var sender: Neighbor? = nil
    /// The host's: an update, drawn as a card.
    var host = false
}

/// What a message sends.
enum ChatDraft {
    case text(String)
    case photo(path: String, width: Int, height: Int)
    case event(String)
}

/// What a sent message came back as.
nonisolated struct ChatSent: Decodable {
    let chatId: String
    let id: String
    let createdAt: String
}

/// A reported message as the admin's review queue shows it.
nonisolated struct ReportedMessage: Identifiable, Equatable, Decodable {
    let id: String
    let senderName: String?
    let kind: String
    let body: String?
    let photoPath: String?
    let eventTitle: String?
    let reason: String
}

struct ChatAPI {
    let db: Supabase

    init(_ db: Supabase) { self.db = db }

    func chats() async throws -> [Chat] {
        try Supabase.decode(await db.rpc("get_chats"))
    }

    /// Newest first, as the server sends them; each Event's card is the same card as everywhere.
    func messages(_ chat: String, before: Date? = nil, limit: Int = 40) async throws -> [ChatMessage] {
        var args: [String: Any] = ["p_chat": chat, "p_limit": limit]
        if let before { args["p_before"] = DateHelpers.timestampString(before) }
        return try Self.messages(from: await db.rpc("get_chat_messages", args))
    }

    static func messages(from data: Data) throws -> [ChatMessage] {
        struct Row: Decodable {
            let id: String
            let clientId: String
            let senderId: String
            let kind: String
            let body: String?
            let photoPath: String?
            let photoW: Int?
            let photoH: Int?
            let card: UpcomingEvent.Lenient?
            let createdAt: String
            let sender: Neighbor?
            let host: Bool?
        }
        return try Supabase.decode(data, as: [Row].self).compactMap { row in
            guard let at = DateHelpers.timestamp(row.createdAt) else { return nil }
            let content: ChatMessage.Content
            switch row.kind {
            case "text": content = .text(row.body ?? "")
            case "photo": content = .photo(path: row.photoPath, width: row.photoW ?? 1, height: row.photoH ?? 1)
            case "event": content = .event(row.card?.value.map { FeedCardItem($0) })
            default: return nil
            }
            return ChatMessage(id: row.clientId.lowercased(), serverID: row.id, senderID: row.senderId.lowercased(),
                               content: content, at: at, sender: row.sender, host: row.host ?? false)
        }
    }

    /// How far each person in the chat has read, by their id: what "Seen" reads.
    func reads(_ chat: String) async throws -> [String: Date] {
        struct Row: Decodable {
            let userId: String
            let readAt: String
        }
        let rows: [Row] = try Supabase.decode(await db.rest("chat_reads", [("select", "user_id,read_at"),
                                                                           ("chat_id", "eq.\(chat)")]))
        return Dictionary(rows.compactMap { row in DateHelpers.timestamp(row.readAt).map { (row.userId.lowercased(), $0) } },
                          uniquingKeysWith: max)
    }

    /// Sends into a chat, or to one person with none yet, which makes it. A retry with the same `client`
    /// is the same message.
    func send(chat: String?, to person: String?, client: String, _ draft: ChatDraft) async throws -> ChatSent {
        var args: [String: Any] = ["p_chat": chat ?? NSNull(), "p_to": person ?? NSNull(), "p_client": client]
        switch draft {
        case .text(let words): args["p_body"] = words
        case .photo(let path, let width, let height):
            args["p_photo"] = path
            args["p_w"] = width
            args["p_h"] = height
        case .event(let id): args["p_event"] = id
        }
        let rows: [ChatSent] = try Supabase.decode(await db.rpc("send_chat_message", args))
        guard let sent = rows.first else { throw SupabaseError(message: "The message didn't send.", status: nil) }
        return sent
    }

    /// A group of your friends, its id; it reaches them with its first message.
    func startGroup(_ members: [String], name: String?) async throws -> String {
        try Supabase.decode(await db.rpc("start_group_chat", ["p_members": members, "p_name": name ?? NSNull()]))
    }

    func goingAccess(_ event: String) async throws -> GoingChatAccess {
        let rows: [GoingChatAccess] = try Supabase.decode(await db.rpc("get_going_chat", ["p_event": event]))
        return rows.first ?? GoingChatAccess(state: .hidden, isHost: false)
    }

    /// An Event's Going chat, opened: made with its first person in, and your Leave undone.
    func joinGoing(_ event: String) async throws -> String {
        try Supabase.decode(await db.rpc("join_going_chat", ["p_event": event]))
    }

    func markRead(_ chat: String) async throws { try await db.rpc("mark_chat_read", ["p_chat": chat]) }
    func accept(_ chat: String) async throws { try await db.rpc("accept_chat", ["p_chat": chat]) }
    func decline(_ chat: String) async throws { try await db.rpc("decline_chat", ["p_chat": chat]) }
    func leave(_ chat: String) async throws { try await db.rpc("leave_chat", ["p_chat": chat]) }

    func report(message: String, reason: ReportReason) async throws {
        try await db.rpc("report_chat_message", ["p_message": message, "p_reason": reason.rawValue])
    }

    // MARK: Photos

    /// A photo in your own folder of the private bucket, where a message can name it; a retry told it's
    /// already there has what it came for.
    func uploadPhoto(_ jpeg: Data, id: String) async throws -> String {
        let path = "\(try db.userID.lowercased())/\(id).jpg"
        do {
            _ = try await db.upload(bucket: "chat-photos", path: path, jpeg, type: "image/jpeg")
        } catch let error as SupabaseError where error.alreadyThere {}
        return path
    }

    /// Links to read those photos for an hour, so a Block or a Hide reaches them soon; a path you can't
    /// see has none.
    func signedLinks(_ paths: [String]) async throws -> [String: URL] {
        try await db.signedLinks(bucket: "chat-photos", paths: paths, expires: 3600)
    }

    // MARK: The admin's review queue

    func reportedMessages() async throws -> [ReportedMessage] {
        try Supabase.decode(await db.rpc("get_chat_reports"))
    }

    func resolve(report: String, hide: Bool) async throws {
        try await db.rpc("resolve_chat_report", ["p_report": report, "p_hide": hide])
    }
}
