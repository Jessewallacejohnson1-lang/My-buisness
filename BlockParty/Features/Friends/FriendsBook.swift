//
//  FriendsBook.swift
//  Block Party — friend requests and friends (BP app docs/plans/friends, tickets 03 and 04):
//  the Friends page's sections, the dot on the friends mark, where you stand with each
//  person, which one button shows on every row and page, the friend sheet (Unfriend, Block)
//  and Profile's Blocked list. Someone you block drops out of every list at once.
//
//  The shell holds it, as it holds `RealLifeActions`, so a row and a person's page agree.
//  A tap shows its answer at once with a light tick. The server's reply is the truth: each
//  write answers where the two now stand. A write that fails holds `RealLifeActions.hold`,
//  flips back, and once the flip is done it shakes with the error buzz while a screen with
//  the button is open. The limit and a missing name flip back at once and say why instead,
//  and so does a failed Block, after the hold: nobody should think they're safe when they
//  aren't.
//

import SwiftUI

@MainActor @Observable
final class FriendsBook {
    enum Action { case add, cancel, confirm, delete, unfriend, block, unblock }

    /// Why a tap was refused, said in Apple's alert.
    enum Problem: Identifiable, Equatable {
        /// `friend-limit`: the 41st new request in a day.
        case limit
        /// `friend-name-needed`: a request needs your name.
        case nameNeeded
        /// A Block that didn't go through (offline): their first name.
        case blockFailed(String)

        /// The server's refusals, by the message it raises.
        init?(server message: String) {
            switch message {
            case "friend_limit": self = .limit
            case "friend_name_needed": self = .nameNeeded
            default: return nil
            }
        }

        var id: String { title }

        var title: String {
            switch self {
            case .limit: "You've sent a lot of requests today. Try again tomorrow."
            case .nameNeeded: "Add your name so neighbors know who's asking."
            case .blockFailed(let name): "Couldn't block \(name)"
            }
        }

        var message: String? {
            if case .blockFailed = self { "Check your connection and try again." } else { nil }
        }
    }

    /// The Friends page as the last read gave it.
    struct Page: Equatable {
        var accepted: [Neighbor] = []
        var requests: [Neighbor] = []
        var friends: [Neighbor] = []
    }

    private(set) var page = Page()
    /// A read has come back. Until then the page shows its loading rows, never "No friends yet".
    private(set) var loaded = false
    /// The last read failed.
    private(set) var failed = false
    /// A request newer than your last visit to Friends.
    private(set) var dot = false
    /// Said in an alert, then cleared by it.
    var problem: Problem?
    /// The person whose friend sheet is up (ticket 04).
    var menu: Neighbor?
    /// The friend sheet is on screen, closing included: a page waits for it to go before it
    /// goes back after a block, so the two never slide at once.
    var menuOnScreen = false
    /// Profile's Blocked list as the last read gave it.
    private(set) var blockedRead: [Neighbor] = []
    private(set) var blockedLoaded = false
    private(set) var blockedFailed = false
    /// One more each time a failed tap on that person flips back while a screen with the
    /// button is open; that screen's button shakes. Never goes down.
    private(set) var failures: [String: Int] = [:]
    /// People you may know as the last read gave them (daily-tab 22).
    private(set) var suggestionsRead: [Neighbor] = []
    /// Hidden with the X since that read, so they go at once.
    private var hidden: Set<String> = []
    /// Where you stand with each person you tapped, over what reads gave, until a read agrees.
    private var chosen: [String: Neighbor.Relation] = [:]
    @ObservationIgnored private var writing: Set<String> = []
    /// Screens with the button open; a failure only buzzes while one is.
    @ObservationIgnored private var open = 0

    private let read: () async throws -> [(kind: String, neighbor: Neighbor)]
    private let readBlocked: () async throws -> [Neighbor]
    private let readDot: () async throws -> Bool
    private let markSeen: () async throws -> Void
    private let write: (Action, String) async throws -> Neighbor.Relation
    private let readSuggestions: () async throws -> [Neighbor]
    private let writeHide: (String) async throws -> Void
    /// No real account: nothing is asked, and taps open Log in.
    let isAnonymous: () -> Bool
    private let hold: Duration
    private let flip: Duration

    init(read: @escaping () async throws -> [(kind: String, neighbor: Neighbor)],
         readBlocked: @escaping () async throws -> [Neighbor] = { [] },
         readDot: @escaping () async throws -> Bool,
         markSeen: @escaping () async throws -> Void,
         write: @escaping (Action, String) async throws -> Neighbor.Relation,
         readSuggestions: @escaping () async throws -> [Neighbor] = { [] },
         writeHide: @escaping (String) async throws -> Void = { _ in },
         isAnonymous: @escaping () -> Bool,
         hold: Duration? = nil, flip: Duration? = nil) {
        self.read = read
        self.readBlocked = readBlocked
        self.readDot = readDot
        self.markSeen = markSeen
        self.write = write
        self.readSuggestions = readSuggestions
        self.writeHide = writeHide
        self.isAnonymous = isAnonymous
        // Join's hold and flip unless a test passes shorter ones.
        self.hold = hold ?? RealLifeActions.hold
        self.flip = flip ?? .seconds(RealLifeActions.flip)
    }

    /// Supabase; under DEBUG `-town-samples` the sample neighbours, every tap succeeding and
    /// going nowhere, and under `-town-offline` every read and tap failing
    /// (`RealLifeActions.backend`).
    convenience init() {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live:
            let api = { CommunityAPI(auth: AuthStore.shared) }
            self.init(read: { try await api().getFriends() },
                      readBlocked: { try await api().getBlocked() },
                      readDot: { try await api().friendsDot() },
                      markSeen: { try await api().markFriendsSeen() },
                      write: { try await api().friendWrite($0, $1) },
                      readSuggestions: { try await api().peopleYouMayKnow() },
                      writeHide: { try await api().hideSuggestion($0) },
                      isAnonymous: { !AuthStore.shared.isSignedIn || AuthStore.shared.isAnonymous })
        case .samples:
            // DEBUG `-friends-fail` makes every tap fail, `-friends-limit` every Add friend hit
            // the daily limit, so the flip back, the shake and the alert can be recorded.
            let args = ProcessInfo.processInfo.arguments
            let fails = args.contains("-friends-fail"), limited = args.contains("-friends-limit")
            self.init(read: { Self.samplePage() },
                      readBlocked: { Neighbor.samples.filter { $0.relation == .blocked } },
                      readDot: { true }, markSeen: {},
                      write: { action, _ in
                          if fails { throw URLError(.notConnectedToInternet) }
                          if limited, action == .add { throw SupabaseError(message: "friend_limit", status: 400) }
                          return Self.answer(to: action)
                      },
                      readSuggestions: { Neighbor.sampleSuggestions },
                      writeHide: { _ in if fails { throw URLError(.notConnectedToInternet) } },
                      isAnonymous: { false })
        case .offline:
            let offline = URLError(.notConnectedToInternet)
            self.init(read: { throw offline }, readBlocked: { throw offline },
                      readDot: { throw offline }, markSeen: { throw offline },
                      write: { _, _ in throw offline }, readSuggestions: { throw offline },
                      writeHide: { _ in throw offline }, isAnonymous: { false })
        }
    }

    // MARK: What screens read

    /// Where you stand with this person: your last tap's answer, or what the read said.
    func relation(_ person: Neighbor) -> Neighbor.Relation {
        chosen[person.id] ?? person.relation
    }

    /// Everyone here but the people you blocked: for search results.
    func visible(_ people: [Neighbor]) -> [Neighbor] {
        people.filter { relation($0) != .blocked }
    }

    /// A search's answer less the people you blocked: nobody left is nobody found.
    func visible(_ state: NeighborSearch.State) -> NeighborSearch.State {
        guard case .found(let people) = state else { return state }
        let left = visible(people)
        return left.isEmpty ? .none : .found(left)
    }

    /// "Sam accepted your friend request.", unless you've since blocked Sam.
    var accepted: [Neighbor] { visible(page.accepted) }

    /// Requests still waiting on you, newest first.
    var requests: [Neighbor] {
        page.requests.filter { relation($0) == .received }
    }

    /// Your friends A to Z, a request you just confirmed among them.
    var friends: [Neighbor] {
        (page.friends + page.requests)
            .filter { relation($0) == .friends }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Nothing to show: no accepted line, no request, no friend.
    var isEmpty: Bool { accepted.isEmpty && requests.isEmpty && friends.isEmpty }

    /// People you may know: less anyone you hid, and anyone who became more than a stranger
    /// since the read, but a request you just sent stays, so its Cancel is right there.
    var suggested: [Neighbor] {
        suggestionsRead.filter { !hidden.contains($0.id) && [.stranger, .sent].contains(relation($0)) }
    }

    /// Profile's Blocked list: the people you blocked, less any you just unblocked.
    var blocked: [Neighbor] {
        blockedRead.filter { relation($0) == .blocked }
    }

    /// The friend sheet's rows: Unfriend and Block for a friend, Block for anyone else.
    static func menuChoices(for relation: Neighbor.Relation) -> [Action] {
        relation == .friends ? [.unfriend, .block] : [.block]
    }

    // MARK: What screens tell it

    /// Daily opened (or came back): read People you may know again. A failed read keeps the
    /// last one; an Anonymous account has none.
    func refreshSuggestions() async {
        guard !isAnonymous() else { suggestionsRead = []; return }
        guard let people = try? await readSuggestions() else { return }
        // The read is the truth for whom it returned; a tap still being sent keeps its answer.
        let read = Set(people.map(\.id))
        chosen = chosen.filter { !read.contains($0.key) || writing.contains($0.key) || $0.value == .blocked }
        withAnimation(.easeInOut(duration: RealLifeActions.flip)) { suggestionsRead = people }
    }

    /// The X: they go at once, with a light tick, and never come back. A hide that fails brings
    /// them back where they were with the error buzz, while a screen with the card is open.
    func hide(_ person: Neighbor) {
        Haptics.light()
        withAnimation(Motion.smooth) { _ = hidden.insert(person.id) }
        Task {
            do {
                try await writeHide(person.id)
            } catch {
                try? await Task.sleep(for: hold)
                withAnimation(Motion.smooth) { _ = hidden.remove(person.id) }
                guard open > 0 else { return }
                Haptics.error()
                // `friend-fail-vo`'s kind of line.
                AccessibilityNotification.Announcement("Couldn't remove \(person.firstName)").post()
            }
        }
    }

    /// The Friends page opened (or came back): read it again.
    func refresh() async {
        guard !isAnonymous() else { reset(); return }
        do {
            let rows = try await read()
            var next = Page()
            for row in rows {
                switch row.kind {
                case "accepted": next.accepted.append(row.neighbor)
                case "request": next.requests.append(row.neighbor)
                default: next.friends.append(row.neighbor)
                }
            }
            // The read is the truth for everyone it returned whose tap is done. Taps on people
            // it doesn't return (a request you sent, someone you only found) stay, and so does a
            // block: a read that left before it landed must not bring them back.
            let read = Set(rows.map(\.neighbor.id))
            chosen = chosen.filter { !read.contains($0.key) || writing.contains($0.key) || $0.value == .blocked }
            withAnimation(.easeInOut(duration: RealLifeActions.flip)) { page = next }
            loaded = true
            failed = false
        } catch {
            failed = true
        }
    }

    /// Profile's Blocked list opened (or came back): read it again.
    func refreshBlocked() async {
        guard !isAnonymous() else { return }
        do {
            let people = try await readBlocked()
            let read = Set(people.map(\.id))
            chosen = chosen.filter { !read.contains($0.key) || writing.contains($0.key) || $0.value == .blocked }
            withAnimation(.easeInOut(duration: RealLifeActions.flip)) { blockedRead = people }
            blockedLoaded = true
            blockedFailed = false
        } catch {
            blockedFailed = true
        }
    }

    /// The page has drawn what it read: the dot clears here and on the server, and the
    /// accepted lines count as seen (they go on the next read).
    func seen() async {
        guard loaded, !failed, !isAnonymous() else { return }
        dot = false
        try? await markSeen()
    }

    /// The dot, read on launch, on coming back to the app and on each visit to Town.
    func refreshDot() async {
        guard !isAnonymous() else { dot = false; return }
        if let fresh = try? await readDot() { withAnimation(.snappy) { dot = fresh } }
    }

    /// Another account: nothing of the last one stays.
    func reset() {
        page = Page()
        chosen = [:]
        loaded = false
        failed = false
        dot = false
        menu = nil
        blockedRead = []
        blockedLoaded = false
        blockedFailed = false
        suggestionsRead = []
        hidden = []
    }

    func screenOpened() { open += 1 }
    func screenClosed() { open = max(0, open - 1) }

    /// One tap on Add friend, Cancel, Confirm or Delete, or a confirmed Unfriend, Block or
    /// Unblock. A tap on someone whose last tap is still being sent does nothing: the button
    /// already shows where it's going.
    func act(_ action: Action, _ person: Neighbor) {
        guard !writing.contains(person.id) else {
            // A Block never goes quietly unsent.
            if action == .block { Haptics.error(); problem = .blockFailed(person.firstName) }
            return
        }
        let before = relation(person)
        let shown = Self.answer(to: action)
        Haptics.light()
        withAnimation(.easeInOut(duration: RealLifeActions.flip)) { chosen[person.id] = shown }
        writing.insert(person.id)
        Task {
            do {
                let answer = try await write(action, person.id)
                writing.remove(person.id)
                withAnimation(.easeInOut(duration: RealLifeActions.flip)) { chosen[person.id] = answer }
            } catch {
                await turnBack(person, to: before, after: action, error: error)
            }
        }
    }

    private func turnBack(_ person: Neighbor, to before: Neighbor.Relation, after action: Action, error: Error) async {
        let id = person.id
        let refused = (error as? SupabaseError).flatMap { Problem(server: $0.message) }
        if refused == nil { try? await Task.sleep(for: hold) }
        writing.remove(id)
        withAnimation(.easeInOut(duration: RealLifeActions.flip)) { chosen[id] = before }
        if let refused {
            problem = refused
            return
        }
        if action == .block {
            Haptics.error()
            problem = .blockFailed(person.firstName)
            return
        }
        try? await Task.sleep(for: flip)
        guard open > 0 else { return }
        failures[id, default: 0] += 1
        Haptics.error()
        // `friend-fail-vo`
        let said = switch action {
        case .add: "Couldn't send request"
        case .cancel: "Couldn't cancel request"
        case .confirm: "Couldn't confirm"
        case .delete: "Couldn't delete request"
        case .unfriend: "Couldn't unfriend"
        case .block: "Couldn't block"
        case .unblock: "Couldn't unblock"
        }
        AccessibilityNotification.Announcement(said).post()
    }

    // MARK: Samples

    /// What the server answers each tap with when it works.
    static func answer(to action: Action) -> Neighbor.Relation {
        switch action {
        case .add: .sent
        case .confirm: .friends
        case .block: .blocked
        case .cancel, .delete, .unfriend, .unblock: .stranger
        }
    }

    /// `-town-samples`: the sample neighbours as the Friends page reads them.
    static func samplePage() -> [(kind: String, neighbor: Neighbor)] {
        let byName = Dictionary(uniqueKeysWithValues: Neighbor.samples.map { ($0.displayName, $0) })
        let accepted = ["Marlene Ostendorf"].compactMap { byName[$0] }.map { (kind: "accepted", neighbor: $0) }
        let requests = ["Sarah Lindgren", "Junie Okonkwo"].compactMap { byName[$0] }.map { (kind: "request", neighbor: $0) }
        let friends = Neighbor.samples.filter { $0.relation == .friends }
            .sorted { $0.displayName < $1.displayName }.map { (kind: "friend", neighbor: $0) }
        return accepted + requests + friends
    }
}
