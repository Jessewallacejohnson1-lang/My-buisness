//
//  FriendsBook.swift
//  Block Party — friend requests and friends (BP app docs/plans/friends, ticket 03): the
//  Friends page's sections, the dot on the friends mark, and where you stand with each
//  person, which one button shows on every row and page.
//
//  The shell holds it, as it holds `RealLifeActions`, so a row and a person's page agree.
//  A tap shows its answer at once with a light tick. The server's reply is the truth: each
//  write answers where the two now stand. A write that fails holds `RealLifeActions.hold`,
//  flips back, and once the flip is done it shakes with the error buzz while a screen with
//  the button is open. The limit and a missing name flip back at once and say why instead.
//

import SwiftUI

@MainActor @Observable
final class FriendsBook {
    enum Action { case add, cancel, confirm, delete }

    /// Why a tap was refused, said in Apple's alert.
    enum Problem: String, Identifiable {
        /// `friend-limit`: the 41st new request in a day.
        case limit = "friend_limit"
        /// `friend-name-needed`: a request needs your name.
        case nameNeeded = "friend_name_needed"
        var id: String { rawValue }
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
    /// One more each time a failed tap on that person flips back while a screen with the
    /// button is open; that screen's button shakes. Never goes down.
    private(set) var failures: [String: Int] = [:]
    /// Where you stand with each person you tapped, over what reads gave, until a read agrees.
    private var chosen: [String: Neighbor.Relation] = [:]
    @ObservationIgnored private var writing: Set<String> = []
    /// Screens with the button open; a failure only buzzes while one is.
    @ObservationIgnored private var open = 0

    private let read: () async throws -> [(kind: String, neighbor: Neighbor)]
    private let readDot: () async throws -> Bool
    private let markSeen: () async throws -> Void
    private let write: (Action, String) async throws -> Neighbor.Relation
    /// No real account: nothing is asked, and taps open Log in.
    let isAnonymous: () -> Bool
    private let hold: Duration
    private let flip: Duration

    init(read: @escaping () async throws -> [(kind: String, neighbor: Neighbor)],
         readDot: @escaping () async throws -> Bool,
         markSeen: @escaping () async throws -> Void,
         write: @escaping (Action, String) async throws -> Neighbor.Relation,
         isAnonymous: @escaping () -> Bool,
         hold: Duration? = nil, flip: Duration? = nil) {
        self.read = read
        self.readDot = readDot
        self.markSeen = markSeen
        self.write = write
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
                      readDot: { try await api().friendsDot() },
                      markSeen: { try await api().markFriendsSeen() },
                      write: { try await api().friendWrite($0, $1) },
                      isAnonymous: { !AuthStore.shared.isSignedIn || AuthStore.shared.isAnonymous })
        case .samples:
            // DEBUG `-friends-fail` makes every tap fail, `-friends-limit` every Add friend hit
            // the daily limit, so the flip back, the shake and the alert can be recorded.
            let args = ProcessInfo.processInfo.arguments
            let fails = args.contains("-friends-fail"), limited = args.contains("-friends-limit")
            self.init(read: { Self.samplePage() }, readDot: { true }, markSeen: {},
                      write: { action, _ in
                          if fails { throw URLError(.notConnectedToInternet) }
                          if limited, action == .add { throw SupabaseError(message: Problem.limit.rawValue, status: 400) }
                          return Self.answer(to: action)
                      },
                      isAnonymous: { false })
        case .offline:
            let offline = URLError(.notConnectedToInternet)
            self.init(read: { throw offline }, readDot: { throw offline }, markSeen: { throw offline },
                      write: { _, _ in throw offline }, isAnonymous: { false })
        }
    }

    // MARK: What screens read

    /// Where you stand with this person: your last tap's answer, or what the read said.
    func relation(_ person: Neighbor) -> Neighbor.Relation {
        chosen[person.id] ?? person.relation
    }

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
    var isEmpty: Bool { page.accepted.isEmpty && requests.isEmpty && friends.isEmpty }

    // MARK: What screens tell it

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
            // A read agrees with every tap that's done; one still being sent stays.
            chosen = chosen.filter { writing.contains($0.key) }
            withAnimation(.easeInOut(duration: RealLifeActions.flip)) { page = next }
            loaded = true
            failed = false
        } catch {
            failed = true
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
    }

    func screenOpened() { open += 1 }
    func screenClosed() { open = max(0, open - 1) }

    /// One tap on Add friend, Cancel, Confirm or Delete. A tap on someone whose last tap is
    /// still being sent does nothing: the button already shows where it's going.
    func act(_ action: Action, _ person: Neighbor) {
        guard !writing.contains(person.id) else { return }
        let before = relation(person)
        let shown: Neighbor.Relation = switch action {
        case .add: .sent
        case .confirm: .friends
        case .cancel, .delete: .stranger
        }
        Haptics.light()
        withAnimation(.easeInOut(duration: RealLifeActions.flip)) { chosen[person.id] = shown }
        writing.insert(person.id)
        Task {
            do {
                let answer = try await write(action, person.id)
                writing.remove(person.id)
                withAnimation(.easeInOut(duration: RealLifeActions.flip)) { chosen[person.id] = answer }
            } catch {
                await turnBack(person.id, to: before, after: action, error: error)
            }
        }
    }

    private func turnBack(_ id: String, to before: Neighbor.Relation, after action: Action, error: Error) async {
        let problem = (error as? SupabaseError).flatMap { Problem(rawValue: $0.message) }
        if problem == nil { try? await Task.sleep(for: hold) }
        writing.remove(id)
        withAnimation(.easeInOut(duration: RealLifeActions.flip)) { chosen[id] = before }
        if let problem {
            self.problem = problem
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
        }
        AccessibilityNotification.Announcement(said).post()
    }

    // MARK: Samples

    /// What the server answers each tap with when it works.
    static func answer(to action: Action) -> Neighbor.Relation {
        switch action {
        case .add: .sent
        case .confirm: .friends
        case .cancel, .delete: .stranger
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
