//
//  ChatBook.swift
//  Block Party — chat's state (BP app five-tabs 05). `ChatBook`, the shell's, holds your chats, the unread
//  dot and the live updates; `ChatThread` holds one open chat: its messages, what's on its way, who has
//  read how far and who's typing. Any change the socket hears reads again, and what comes back is merged by
//  the phone's id for each message, so nothing unsent is lost and no bubble jumps.
//

import SwiftUI

@MainActor @Observable
final class ChatBook {
    /// Your chats, newest first; nil until the first read.
    private(set) var chats: [Chat]?
    /// The last read failed.
    private(set) var failed = false
    /// The Event page's "Send in a chat": its picker is up (`ChatPicker`).
    var sending: FeedCardItem?

    let api: ChatAPI
    private let live: Bool
    /// Whether it opens a socket: the app's does, a test's never.
    private let sockets: Bool
    @ObservationIgnored private var socket: RealtimeClient?
    /// Pushes on the shell's stack, from a sheet that's closing or a page outside it; the shell sets it.
    @ObservationIgnored var push: ((ChatRoute) -> Void)?
    /// The chat on screen, which hears what the socket hears.
    @ObservationIgnored weak var open: ChatThread?
    @ObservationIgnored private var latestRead = 0
    /// The read that's waiting for what the socket heard to settle.
    @ObservationIgnored private var hearing: Task<Void, Never>?

    /// A burst the socket hears becomes one read, this long after its first.
    static let hearingSettles: Duration = .milliseconds(500)

    init(supabase: Supabase, live: Bool = LaunchFlags.backend == .live, sockets: Bool = false) {
        api = ChatAPI(supabase)
        self.live = live
        self.sockets = sockets
        if !live { chats = [] }
    }

    /// The chats themselves, less your Requests.
    var messages: [Chat] { (chats ?? []).filter { !$0.request && ($0.kind != .going || $0.card != nil) } }
    var requests: [Chat] { (chats ?? []).filter(\.request) }
    /// A request lights no dot: nobody earns one by writing to a stranger.
    var unread: Bool { messages.contains { $0.lights ?? $0.unread } }

    /// The chat with one person, if there's one yet.
    func chat(with person: Neighbor) -> Chat? {
        chats?.first { $0.kind == .direct && $0.others.first?.id == person.id }
    }

    /// An Event's Going chat, once it's on your list.
    func chat(forEvent id: String) -> Chat? {
        chats?.first { $0.kind == .going && $0.card?.id == id }
    }

    /// A Group's chat, once it's on your list.
    func chat(forGroup id: String) -> Chat? {
        chats?.first { $0.kind == .club && $0.clubId == id }
    }

    func refresh() async {
        guard live, db.auth.userId != nil else { return }
        latestRead &+= 1
        let thisRead = latestRead
        do {
            let new = try await api.chats()
            guard thisRead == latestRead else { return }
            withAnimation(Motion.smooth) { chats = new }
            failed = false
        } catch {
            guard !Task.isCancelled, thisRead == latestRead else { return }
            Log.network("ChatBook: \(error)")
            failed = true
        }
    }

    private var db: Supabase { api.db }

    /// Live while the app's open, for a real account: a closed app learns nothing until it opens.
    func start() {
        guard live, sockets, db.auth.isSignedIn, !db.auth.isAnonymous else { return }
        if socket == nil {
            let auth = db.auth
            let socket = RealtimeClient(name: "chat", tables: ["chat_messages", "chat_reads"],
                                        tokenProvider: { try? await auth.validAccessToken() })
            socket.onChange = { [weak self] _ in self?.heard() }
            // Subscribed again after a drop: read what was missed.
            socket.onStatus = { [weak self] status in if status == .subscribed { self?.heard() } }
            self.socket = socket
        }
        socket?.start()
    }

    func stop() { socket?.stop() }

    private func heard() {
        guard hearing == nil else { return }
        hearing = Task { [weak self] in
            try? await Task.sleep(for: Self.hearingSettles)
            self?.hearing = nil
            await self?.refresh()
            await self?.open?.read()
        }
    }

    /// Another account: nothing of the last one's stays.
    func accountChanged() {
        stop()
        socket = nil
        hearing?.cancel()
        hearing = nil
        latestRead &+= 1
        chats = live ? nil : []
        failed = false
        sending = nil
    }

    /// Read on screen, so its dot goes at once.
    func markedRead(_ id: String) {
        guard let i = chats?.firstIndex(where: { $0.id == id }), chats?[i].unread == true || chats?[i].lights == true else { return }
        chats?[i].unread = false
        chats?[i].lights = false
    }

    /// Accepted, deleted or left: the list says so at once, and the read behind it agrees. An Accept that
    /// fails puts the request back.
    func accept(_ chat: Chat) async throws {
        let i = chats?.firstIndex { $0.id == chat.id }
        if let i { withAnimation(Motion.smooth) { chats?[i].request = false } }
        do {
            try await api.accept(chat.id)
        } catch {
            if let now = chats?.firstIndex(where: { $0.id == chat.id }) {
                withAnimation(Motion.smooth) { chats?[now].request = true }
            }
            throw error
        }
        await refresh()
    }

    func decline(_ chat: Chat) async throws {
        try await api.decline(chat.id)
        withAnimation(Motion.smooth) { chats?.removeAll { $0.id == chat.id } }
    }

    func leave(_ chat: String) async throws {
        try await api.leave(chat)
        withAnimation(Motion.smooth) { chats?.removeAll { $0.id == chat } }
    }
}

/// One chat on screen.
@MainActor @Observable
final class ChatThread {
    /// Oldest first.
    private(set) var messages: [ChatMessage] = []
    /// A read has come back; until then the chat shows its loading bubbles.
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var hasOlder = false
    /// One more each time a send fails, for its bubble's shake.
    private(set) var failures = 0
    /// What the server refused the last send for, in words, when there are any.
    private(set) var lastRefusal: String?
    /// How far each other person has read.
    private(set) var reads: [String: Date] = [:]
    /// Who's typing now, by id.
    private(set) var typing: Set<String> = []
    /// Links to the chat's photos, by path, for as long as the page is up.
    private(set) var links: [String: URL] = [:]
    /// A photo on its way, as picked, by the message's id.
    private(set) var picked: [String: UIImage] = [:]
    /// The chat, once it exists: nil for a first message to someone, or a Going or Group chat not joined yet.
    private(set) var chatID: String?
    /// Out of a Going or Group chat: left on another phone, or its Event or Group closed. The page goes.
    private(set) var gone = false

    private let api: ChatAPI
    private let book: ChatBook?
    private let actions: RealLifeActions?
    private let person: String?
    private let me: String
    /// A Going chat's Event (five-tabs 06): its chat is joined, never started.
    private let goingEvent: String?
    /// A Group chat's Group (five-tabs 07): joined the same way.
    let club: String?
    /// You're the host: whatever you write is an update.
    let isHost: Bool
    @ObservationIgnored private var joined = false
    @ObservationIgnored private var channel: RealtimeClient?
    @ObservationIgnored private var lastTyping = Date.distantPast
    @ObservationIgnored private var typingEnds: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var latestRead = 0

    static let page = 40
    static let longest = 2000
    /// A "typing" goes out at most this often, and shows this long after the last one heard.
    static let typingEvery: TimeInterval = 2
    static let typingShows: Duration = .seconds(4)
    /// The row comes with Attend's or Join's tap, so its write may still be on its way: a no is only believed after these.
    static let joinRetries: [Duration] = [.milliseconds(700), .milliseconds(1400), .milliseconds(2800), .seconds(5)]
    /// Those waits, short in a test.
    @ObservationIgnored var joinWaits = ChatThread.joinRetries

    init(api: ChatAPI, me: String, chat: String?, to person: String? = nil, book: ChatBook? = nil,
         actions: RealLifeActions? = nil, going: String? = nil, club: String? = nil, isHost: Bool = false) {
        self.api = api
        self.me = me.lowercased()
        chatID = chat
        self.person = person
        self.book = book
        self.actions = actions
        goingEvent = going
        self.club = club
        self.isHost = isHost
        // A first message to someone has nothing to wait for.
        loaded = chat == nil && going == nil && club == nil
    }

    // MARK: Reading

    /// A room of people who didn't pick each other, a Going or a Group chat: joined before it reads, with no Seen,
    /// no typing dots and no photos.
    var isRoom: Bool { goingEvent != nil || club != nil }

    func read() async {
        if isRoom, !joined {
            do {
                let id = try await join()
                chatID = id
                joined = true
                // A Leave just undone: the list hears now, so its row and the page's aren't a step behind.
                if book?.chats?.contains(where: { $0.id == id }) == false { Task { await book?.refresh() } }
            } catch {
                guard !Task.isCancelled else { return }
                Log.network("ChatThread join: \(error)")
                gone = (error as? SupabaseError)?.message == "chat_not_going"
                failed = true
                return
            }
        }
        guard let chatID else { return }
        latestRead &+= 1
        let thisRead = latestRead
        do {
            async let newest = api.messages(chatID, limit: Self.page)
            // A room writes no reads: nobody is shown as having read it.
            async let read = isRoom ? [:] : api.reads(chatID)
            let (rows, seen) = try await (newest, read)
            guard thisRead == latestRead else { return }
            actions?.read(rows.compactMap(\.card))
            hasOlder = loaded ? hasOlder : rows.count == Self.page
            let before = messages.count
            withAnimation(before == 0 ? nil : Motion.smooth) { messages = Self.merged(messages, rows) }
            reads = seen.filter { $0.key != me }
            loaded = true
            failed = false
            // Others' messages landing while the app is open: VoiceOver says so.
            if before > 0, messages.count > before, let last = messages.last, last.senderID != me {
                AccessibilityNotification.Announcement("New message").post()
            }
            await sign()
            await markRead()
        } catch {
            guard !Task.isCancelled, thisRead == latestRead else { return }
            Log.network("ChatThread: \(error)")
            failed = true
        }
    }

    private func join() async throws -> String {
        for wait in joinWaits {
            do {
                return try await joinOnce()
            } catch let error as SupabaseError where error.message == "chat_not_going" {
                try await Task.sleep(for: wait)
            }
        }
        return try await joinOnce()
    }

    private func joinOnce() async throws -> String {
        if let club { return try await api.joinGroup(club) }
        return try await api.joinGoing(goingEvent ?? "")
    }

    func readOlder() async {
        guard let chatID, hasOlder, let oldest = messages.first(where: { $0.state == .sent }) else { return }
        guard let rows = try? await api.messages(chatID, before: oldest.at, limit: Self.page) else { return }
        actions?.read(rows.compactMap(\.card))
        hasOlder = rows.count == Self.page
        messages = Self.merged(messages, rows)
        await sign()
    }

    /// What's on screen and what the server sent, oldest first: the server's copy of each message wins,
    /// anything on its way or failed stays until it has one, and a page's messages join what's already
    /// here. A sent message the server no longer gives inside the page's range (hidden, or from someone
    /// just blocked) goes; one newer than the page was sent while the read was out, so it stays.
    static func merged(_ local: [ChatMessage], _ rows: [ChatMessage]) -> [ChatMessage] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let from = rows.map(\.at).min() ?? .distantFuture, to = rows.map(\.at).max() ?? .distantPast
        var kept = local.filter { message in
            guard byID[message.id] == nil else { return false }
            return message.state != .sent || message.at < from || message.at > to
        }
        kept.append(contentsOf: rows)
        return kept.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    private func sign() async {
        let missing = messages.compactMap { message -> String? in
            guard case .photo(let path?, _, _) = message.content, links[path] == nil else { return nil }
            return path
        }
        guard !missing.isEmpty, let new = try? await api.signedLinks(missing) else { return }
        links.merge(new) { _, fresh in fresh }
    }

    private func markRead() async {
        guard let chatID else { return }
        book?.markedRead(chatID)
        try? await api.markRead(chatID)
    }

    // MARK: Sending

    func send(_ words: String) async {
        // The database's own limit, kept here so a long message isn't refused whole.
        let words = String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ChatThread.longest))
        guard !words.isEmpty else { return }
        lastRefusal = nil
        // A host's update shows their face at once, from their last one when there is one.
        await deliver(ChatMessage(id: UUID().uuidString.lowercased(), senderID: me, content: .text(words), at: .now,
                                  state: .sending, sender: isHost ? messages.last { $0.senderID == me }?.sender : nil,
                                  host: isHost))
    }

    func send(card: FeedCardItem) async {
        await deliver(ChatMessage(id: UUID().uuidString.lowercased(), senderID: me, content: .event(card), at: .now,
                                  state: .sending))
    }

    /// A photo as picked: it shows at once, goes up, then sends.
    func send(photo: UIImage) async {
        let id = UUID().uuidString.lowercased()
        picked[id] = photo
        let pixels = CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
        await deliver(ChatMessage(id: id, senderID: me,
                                  content: .photo(path: nil, width: max(Int(pixels.width), 1), height: max(Int(pixels.height), 1)),
                                  at: .now, state: .sending))
    }

    func retry(_ message: ChatMessage) async {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].state = .sending
        await deliver(messages[i], placed: true)
    }

    private func deliver(_ message: ChatMessage, placed: Bool = false) async {
        if !placed {
            withAnimation(Motion.snappy) { messages.append(message) }
            Haptics.light()
        }
        do {
            let draft = try await draft(for: message)
            let sent = try await api.send(chat: chatID, to: chatID == nil ? person : nil, client: message.id, draft)
            let first = chatID == nil
            chatID = sent.chatId
            if let i = messages.firstIndex(where: { $0.id == message.id }) {
                messages[i].state = .sent
                messages[i].serverID = sent.id
                messages[i].at = DateHelpers.timestamp(sent.createdAt) ?? messages[i].at
            }
            if first { startTyping() }
            await book?.refresh()
            await sign()
            // Waiting for the first read: this chat's own socket-less start. A host's first update reads who they are.
            if first || (message.host && message.sender == nil) { await read() }
        } catch {
            Log.network("ChatThread send: \(error)")
            lastRefusal = ChatWords.refused(error)
            gone = (error as? SupabaseError)?.message == "chat_not_going"
            let refused = lastRefusal != nil
            if let i = messages.firstIndex(where: { $0.id == message.id }) {
                messages[i].state = refused ? .refused : .failed
            }
            failures += 1
            Haptics.error()
            // Refused: where the chat stands has changed, and its foot should say so.
            if refused { await book?.refresh() }
        }
    }

    private func draft(for message: ChatMessage) async throws -> ChatDraft {
        switch message.content {
        case .text(let words): return .text(words)
        case .event(let card):
            guard let card else { throw SupabaseError(message: "That Event is gone.", status: nil) }
            return .event(card.id)
        case .photo(let path, let width, let height):
            if let path { return .photo(path: path, width: width, height: height) }
            guard let jpeg = picked[message.id]?.jpegData(compressionQuality: ChatMetric.photoQuality) else {
                throw SupabaseError(message: "That photo can't be sent.", status: nil)
            }
            let uploaded = try await api.uploadPhoto(jpeg, id: message.id)
            if let i = messages.firstIndex(where: { $0.id == message.id }) {
                messages[i].content = .photo(path: uploaded, width: width, height: height)
            }
            return .photo(path: uploaded, width: width, height: height)
        }
    }

    // MARK: Typing

    /// The chat's private channel, while it's on screen.
    func startTyping() {
        // Not in a room: a typing signal would show who is reading quietly.
        guard channel == nil, !isRoom, let chatID else { return }
        let auth = api.db.auth
        let channel = RealtimeClient(privateChannel: "chat:\(chatID)",
                                     tokenProvider: { try? await auth.validAccessToken() })
        channel.onBroadcast = { [weak self] event, payload in
            guard event == "typing", let who = payload["who"] as? String else { return }
            self?.heardTyping(who.lowercased())
        }
        self.channel = channel
        channel.start()
    }

    func stopTyping() {
        channel?.stop()
        channel = nil
        for end in typingEnds.values { end.cancel() }
        typingEnds = [:]
        typing = []
    }

    /// You're typing: others hear it at most every `typingEvery` seconds. No words go with it.
    func typed(at now: Date = .now) {
        guard now.timeIntervalSince(lastTyping) >= Self.typingEvery else { return }
        lastTyping = now
        channel?.broadcast("typing", ["who": me])
    }

    func heardTyping(_ who: String) {
        guard who != me else { return }
        withAnimation(Motion.smooth) { _ = typing.insert(who) }
        typingEnds[who]?.cancel()
        typingEnds[who] = Task { [weak self] in
            try? await Task.sleep(for: Self.typingShows)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.smooth) { _ = self?.typing.remove(who) }
        }
    }

    // MARK: What the screen asks

    /// "Seen" sits under your last message once someone else has read past it.
    var seen: Bool {
        guard let last = messages.last(where: { $0.senderID == me && $0.state == .sent }),
              messages.last?.id == last.id else { return false }
        return reads.values.contains { $0 >= last.at }
    }

    /// The Event a reply can answer: the last message, from someone else (the mock's I'm in, Maybe, Can't).
    var answerable: FeedCardItem? {
        guard let last = messages.last, last.senderID != me, case .event(let card?) = last.content,
              !card.cancelled, (card.when?.end ?? .distantFuture) > .now else { return nil }
        return card
    }

    func isMine(_ message: ChatMessage) -> Bool { message.senderID == me }

    /// Blocked from a press: their words go at once, and the next read agrees.
    func dropMessages(from person: String) {
        let person = person.lowercased()
        withAnimation(Motion.smooth) { messages.removeAll { $0.senderID == person } }
    }

    /// Any other person's last message: what a report from the ••• names.
    var lastFromOthers: ChatMessage? { messages.last { $0.senderID != me && $0.serverID != nil } }
}

extension ChatMessage {
    var card: FeedCardItem? {
        if case .event(let card) = content { card } else { nil }
    }
}

/// Chat's words, in one place (BP app five-tabs 05). Working words.
enum ChatWords {
    /// A row's line in Messages: what it says, who said it in a group, "You:" for yours.
    static func preview(_ chat: Chat) -> String {
        let said: String = switch chat.lastKind {
        case "photo": "Sent a photo"
        case "event": "Sent an Event"
        default: chat.lastBody ?? ""
        }
        if chat.lastMine { return "You: \(said)" }
        if chat.lastHost == true { return "Host: \(said)" }
        if chat.kind != .direct, let name = chat.lastSender?.split(separator: " ").first { return "\(name): \(said)" }
        return said
    }

    /// When, short, as Instagram's rows say it: 5m, 3h, Yesterday, Mon, Oct 3.
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let days = Town.days(from: date, to: now)
        if days == 0 { return "\(Int(seconds / 3600))h" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return Town.format(date, "EEE") }
        return Town.format(date, "MMMd")
    }

    /// A chat's stamp between messages: today's time, or the day and time.
    static func stamp(_ date: Date, now: Date = .now) -> String {
        let days = Town.days(from: date, to: now)
        if days == 0 { return Town.clock(date) }
        if days == 1 { return "Yesterday \(Town.clock(date))" }
        if days < 7 { return "\(Town.format(date, "EEE")) \(Town.clock(date))" }
        return "\(Town.format(date, "MMMd")) \(Town.clock(date))"
    }

    /// A stamp goes before a message 15 minutes or more after the last, and before the first.
    static func needsStamp(_ message: ChatMessage, after last: ChatMessage?) -> Bool {
        guard let last else { return true }
        return message.at.timeIntervalSince(last.at) >= 15 * 60
    }

    /// What the server's refusals mean to whoever tapped.
    static func refused(_ error: Error) -> String? {
        guard let message = (error as? SupabaseError)?.message else { return nil }
        switch message {
        case "chat_limit": return "You've sent a lot of new messages today. Try again tomorrow."
        case "chat_not_available", "chat_not_member": return "This person can't get messages right now."
        case "chat_waiting": return "You can write more once they accept."
        case "chat_text_only": return "You can send photos and Events once they accept."
        case "chat_event_gone": return "That Event is no longer available."
        case "chat_not_going": return "You're not in this chat anymore."
        case "chat_slow_down": return "You're sending a lot. Try again in a few minutes."
        default: return nil
        }
    }
}
