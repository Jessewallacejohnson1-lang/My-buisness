//
//  RealLifeActions.swift
//  Block Party — the app's one home for what a neighbour does with an Event: Going,
//  Heart and Save (BP app docs/plans/real-life-actions).
//
//  The shell holds it, as it holds the Town feed, so a card and its Event page read
//  the same entry and always agree. A Town feed read sets each Event's base state; a
//  tap lays the neighbour's choice over it at once, until a read agrees with it.
//
//  A write the server says no to turns the choice back the way the Event page always
//  has: it holds 600 ms after the tap, flips back, and once the 0.18 s flip is done the
//  screen that asked shakes and buzzes, but only while it is still open: the Event page
//  or the card for Going, the card for Heart, the page or a bookmark for Save. A write
//  that gets no answer (offline, timed out) is no "no": the tap stays and is tried again
//  until it lands, kept on the phone so it survives a relaunch (town-feed ticket 24).
//

import SwiftUI

@MainActor @Observable
final class RealLifeActions {
    struct Going: Equatable {
        var isGoing: Bool
        var count: Int
    }

    struct Heart: Equatable {
        var isHearted: Bool
        var count: Int
    }

    /// A failed Join still shows "Going" this long after the tap before it turns back,
    /// so the turn back reads as the app's answer, not a flicker. Signed out, the write
    /// failed 15 ms after the tap (measured 2026-09-26), about one frame. (guessed)
    static let hold: Duration = .milliseconds(600)

    /// How long Join takes to turn from one face to the other, both ways, in seconds: the
    /// Event page's Join and the card's RSVP pill. A heart turns back as fast.
    static let flip: TimeInterval = 0.18

    /// May act: has an account, or writes go nowhere and need none (`Backend`).
    private(set) var canAct: Bool

    /// What a neighbour does with an Event. Each keeps its own state, writes and shakes.
    private enum Kind: Codable { case going, heart, save }

    private struct Key: Hashable, Codable {
        let kind: Kind
        let id: String
    }

    /// One action on one Event: whether you did it, and how many neighbours did.
    private struct Tally: Equatable {
        var on: Bool
        var count: Int
    }

    /// Each Event as the last Town feed read gave it.
    private var base: [Key: Tally] = [:]
    /// Every Event the neighbour tapped Going or Leave on this session, whole, so the You
    /// page can show a Join made on a card before a read of their Going brings it back
    /// (BP app docs/plans/you-tab). Whether each is still Going is `going(_:)`.
    private(set) var goingTapped: [String: FeedCardItem] = [:]
    /// Every Event saved or unsaved this session, whole, the same way for Profile's Saved
    /// list (you-tab ticket 04). Whether each is still saved is `saved(_:)`.
    private(set) var savedTapped: [String: FeedCardItem] = [:]
    /// The neighbour's own choice, laid over `base` until a read agrees with it.
    private var chosen: [Key: Bool] = [:]
    /// One more each time a failed write turns a choice back by itself while the screen
    /// that asked is open; that screen shakes. Never goes down, so a shake never replays.
    private var failures: [Key: Int] = [:]

    /// The one write running per action and Event. Never cancelled: a write already sent
    /// can't be called back, so the next one waits for it and lands after it.
    @ObservationIgnored private var writers: [Key: Task<Void, Never>] = [:]
    /// Waiting out `hold`, then `flip`, after a failed write.
    @ObservationIgnored private var turnBacks: [Key: Task<Void, Never>] = [:]
    /// Where a failed write goes back to while it waits out `hold`.
    @ObservationIgnored private var failedFrom: [Key: Bool] = [:]
    /// Turned back after a failed write. The write may still have landed with its answer
    /// lost, so the next read is the truth, agreeing or not.
    @ObservationIgnored private var turnedBack: Set<Key> = []
    /// Numbers each tap, so a failure that a newer tap has overtaken is not a turn back.
    @ObservationIgnored private var taps: [Key: Int] = [:]
    @ObservationIgnored private var tappedAt: [Key: ContinuousClock.Instant] = [:]
    /// Which screens that shake are on screen: Event pages for Going and Save, cards for
    /// Going and Heart, bookmarks for Save.
    @ObservationIgnored private var open: [Key: Int] = [:]
    /// The phone's old saves are moving up (`moveUp`): once at a time.
    @ObservationIgnored private var movingUp = false
    /// Numbers each account, so a write the last one sent says nothing about this one.
    @ObservationIgnored private var account = 0
    /// Being sent again after no answer, or brought back at launch. A "no" to one of
    /// these comes long after the tap, so it turns back without the shake and buzz
    /// (Jesse, 2026-10-13); VoiceOver still says it.
    @ObservationIgnored private var late: Set<Key> = []

    /// Taps not yet agreed by a read, kept on the phone for the account that made them,
    /// each with when it was made.
    private struct Waiting: Codable {
        struct Tap: Codable {
            var on: Bool
            var at: Date
        }
        var owner: String
        var taps: [Key: Tap]
    }
    private static let waitingKey = "bp.waitingTaps"
    /// A kept tap older than this is dropped at launch: its Event has most likely gone
    /// from the feed, so no read will ever agree with it.
    private static let keepFor: TimeInterval = 24 * 3600
    /// Whose taps `chosen` holds, set only by `accountChanged`: until then nothing is
    /// kept or wiped, so a launch's first read can't erase taps not yet brought back,
    /// and one account's taps are never filed under the next.
    @ObservationIgnored private var keptFor: String?
    /// When each tap was made, for `keepFor`.
    @ObservationIgnored private var tappedOn: [Key: Date] = [:]

    private let needsAccount: Bool
    private let holdFor: Duration
    private let flipFor: Duration
    /// The first wait before trying a write again after no answer; it doubles to five
    /// times this (2, 4, 8, 10, 10 s in the app, as `RealtimeClient` reconnects).
    private let retryFor: Duration
    /// Where waiting taps are kept: nil keeps none (tests, sample and offline modes).
    private let keep: UserDefaults?
    /// The account a waiting tap belongs to.
    private let owner: () -> String?
    private let setGoing: (_ eventID: String, _ going: Bool) async throws -> Void
    private let setHeart: (_ eventID: String, _ hearted: Bool) async throws -> Void
    private let setSave: (_ eventID: String, _ saved: Bool) async throws -> Void
    /// Which of these ids are Events. The phone's saved list holds Places too.
    private let knownEvents: (_ ids: [String]) async throws -> Set<String>

    /// `hold`, `flip` and `retry` come in here so tests run fast; the app passes the
    /// measured ones.
    init(signedIn: Bool, needsAccount: Bool, hold: Duration, flip: Duration,
         retry: Duration = .seconds(2), keep: UserDefaults? = nil,
         owner: @escaping () -> String? = { nil },
         setGoing: @escaping (_ eventID: String, _ going: Bool) async throws -> Void,
         setHeart: @escaping (_ eventID: String, _ hearted: Bool) async throws -> Void,
         setSave: @escaping (_ eventID: String, _ saved: Bool) async throws -> Void,
         knownEvents: @escaping (_ ids: [String]) async throws -> Set<String>) {
        self.canAct = signedIn || !needsAccount
        self.needsAccount = needsAccount
        self.holdFor = hold
        self.flipFor = flip
        self.retryFor = retry
        self.keep = keep
        self.owner = owner
        self.setGoing = setGoing
        self.setHeart = setHeart
        self.setSave = setSave
        self.knownEvents = knownEvents
    }

    /// Where writes go, chosen once at launch.
    enum Backend: Equatable {
        /// Supabase.
        case live
        /// DEBUG `-town-samples`: every write succeeds and goes nowhere, so a Join on a
        /// sample card never reaches the live database.
        case samples
        /// DEBUG `-town-offline`: every write fails, as with no network.
        case offline
    }

    nonisolated static func backend(for arguments: [String]) -> Backend {
        #if DEBUG
        if arguments.contains("-town-offline") { return .offline }
        if arguments.contains("-town-samples") { return .samples }
        #endif
        return .live
    }

    convenience init() {
        let backend = Self.backend(for: ProcessInfo.processInfo.arguments)
        let setGoing: (String, Bool) async throws -> Void
        let setHeart: (String, Bool) async throws -> Void
        let setSave: (String, Bool) async throws -> Void
        let knownEvents: ([String]) async throws -> Set<String>
        switch backend {
        case .live:
            setGoing = { eventID, going in
                let api = CommunityAPI(auth: AuthStore.shared)
                if going { try await api.rsvpEvent(eventID) } else { try await api.unRsvpEvent(eventID) }
            }
            setHeart = { eventID, hearted in
                let api = SocialAPI(auth: AuthStore.shared)
                if hearted { try await api.likeEvent(eventID) } else { try await api.unlikeEvent(eventID) }
            }
            setSave = { eventID, saved in
                // Daily's sample Suggestions ("daily-s1") are saved on this run only.
                guard UUID(uuidString: eventID) != nil else { return }
                let api = SocialAPI(auth: AuthStore.shared)
                if saved { try await api.saveEvent(eventID) } else { try await api.unsaveEvent(eventID) }
            }
            knownEvents = { try await CommunityAPI(auth: AuthStore.shared).knownEventIDs($0) }
        case .samples:
            // With `-town-refuse` the server says no to every Join, so the hold, the turn
            // back and the shake can be recorded on the card and the page.
            let refuses = ProcessInfo.processInfo.arguments.contains("-town-refuse")
            setGoing = { _, _ in
                if refuses { throw SupabaseError(message: "refused (-town-refuse)", status: 403) }
            }
            setHeart = { _, _ in }
            setSave = { _, _ in }
            knownEvents = { _ in [] }
        case .offline:
            setGoing = { _, _ in throw URLError(.notConnectedToInternet) }
            setHeart = { _, _ in throw URLError(.notConnectedToInternet) }
            setSave = { _, _ in throw URLError(.notConnectedToInternet) }
            knownEvents = { _ in throw URLError(.notConnectedToInternet) }
        }
        // Only the live backend needs an account: sample cards always offered Join, and
        // the Eyes pass must not hang on the live anonymous sign-in, limited per network.
        // Waiting taps are kept only for real ones: never a sample's, and never in a test
        // run, which could otherwise send a tap left on the simulator.
        let keeps = backend == .live && !AuthStore.isTestRun
        self.init(signedIn: AuthStore.shared.isSignedIn, needsAccount: backend == .live,
                  hold: Self.hold, flip: .seconds(Self.flip),
                  keep: keeps ? .standard : nil, owner: { AuthStore.shared.userId },
                  setGoing: setGoing, setHeart: setHeart, setSave: setSave, knownEvents: knownEvents)
    }

    #if DEBUG
    /// For the DEBUG screens that show cards outside the shell (`RootView`).
    static let preview = RealLifeActions(signedIn: true, needsAccount: false, hold: hold,
                                         flip: .seconds(flip), setGoing: { _, _ in },
                                         setHeart: { _, _ in }, setSave: { _, _ in },
                                         knownEvents: { _ in [] })
    #endif

    // MARK: What screens read

    /// The Event's Going: the last read's, with the neighbour's own choice over it. The
    /// count moves with the choice, from whatever the read last said.
    func going(_ item: FeedCardItem) -> Going {
        let tally = tally(.going, item)
        return Going(isGoing: tally.on, count: tally.count)
    }

    /// The Event's Heart, worked out the same way: every neighbour's hearts, and yours.
    func heart(_ item: FeedCardItem) -> Heart {
        let tally = tally(.heart, item)
        return Heart(isHearted: tally.on, count: tally.count)
    }

    /// What the card's RSVP area says (`RSVPWords`): only for someone who may act, as Join
    /// never showed without an account.
    func rsvp(_ item: FeedCardItem) -> RSVPWords? {
        guard canAct else { return nil }
        let going = going(item)
        return .make(isGoing: going.isGoing, count: going.count,
                     friends: item.friendsGoing.map(\.name), cancelled: item.cancelled)
    }

    func failureCount(_ eventID: String) -> Int {
        failures[Key(kind: .going, id: eventID)] ?? 0
    }

    func heartFailureCount(_ eventID: String) -> Int {
        failures[Key(kind: .heart, id: eventID)] ?? 0
    }

    /// Whether the neighbour saved the Event: the last read's, with their own choice over it.
    func saved(_ item: FeedCardItem) -> Bool {
        tally(.save, item).on
    }

    func saveFailureCount(_ eventID: String) -> Int {
        failures[Key(kind: .save, id: eventID)] ?? 0
    }

    // MARK: What screens tell it

    /// Join or leave, shown at once. A tap while a failed write waits to turn back
    /// turns it back now, rather than toggling a state the server never had.
    func toggleGoing(_ item: FeedCardItem) {
        if canAct { goingTapped[item.id] = item }
        toggle(Key(kind: .going, id: item.id), from: going(item).isGoing)
    }

    /// Heart or un-heart, shown at once, turned back the same way as Join.
    func toggleHeart(_ item: FeedCardItem) {
        toggle(Key(kind: .heart, id: item.id), from: heart(item).isHearted)
    }

    /// Save or unsave (the bookmark), shown at once, turned back the same way as Join.
    func toggleSave(_ item: FeedCardItem) {
        if canAct { savedTapped[item.id] = item }
        toggle(Key(kind: .save, id: item.id), from: saved(item))
    }

    /// The photo's double tap: hearts, never un-hearts (taste.md, 2026-09-27). One
    /// during a failed heart's wait keeps it on and writes it again.
    func heartOn(_ item: FeedCardItem) {
        let key = Key(kind: .heart, id: item.id)
        guard canAct else { return }
        if failedFrom[key] == false {
            Haptics.light()
            turnBacks.removeValue(forKey: key)?.cancel()
            failedFrom[key] = nil
            choose(key, true)
        } else if !heart(item).isHearted {
            toggleHeart(item)
        }
    }

    /// A Town feed read: each Event's base state. A choice the read agrees with is done;
    /// one it doesn't stays, since a read can start before the write lands.
    func read(_ cards: [FeedCardItem]) {
        for card in cards {
            base[Key(kind: .going, id: card.id)] = Tally(on: card.isJoined, count: card.goingCount)
            base[Key(kind: .heart, id: card.id)] = Tally(on: card.isLiked, count: card.likeCount)
            base[Key(kind: .save, id: card.id)] = Tally(on: card.isSaved, count: 0)
            // A tap still being sent (one kept from before a relaunch included) shows on
            // You and in Saved too, before the server has it.
            guard canAct else { continue }
            if writers[Key(kind: .going, id: card.id)] != nil { goingTapped[card.id] = card }
            if writers[Key(kind: .save, id: card.id)] != nil { savedTapped[card.id] = card }
        }
        for (key, choice) in chosen where writers[key] == nil && failedFrom[key] == nil {
            if base[key]?.on == choice || turnedBack.contains(key) { chosen[key] = nil }
        }
        turnedBack = []
        save()
    }

    /// An Event's page is on screen. Only then does a failed Join or Save shake and buzz:
    /// the buzz once landed on Town after a pop.
    func pageOpened(_ eventID: String) {
        for kind in [Kind.going, .save] { open[Key(kind: kind, id: eventID), default: 0] += 1 }
    }

    func pageClosed(_ eventID: String) {
        for kind in [Kind.going, .save] { close(Key(kind: kind, id: eventID)) }
    }

    /// An Event's Town card is on screen. Only then does a failed Heart or RSVP shake and
    /// buzz there. It has no bookmark (rsvp-and-groups 01).
    func cardOpened(_ eventID: String) {
        for kind in [Kind.heart, .going] { open[Key(kind: kind, id: eventID), default: 0] += 1 }
    }

    func cardClosed(_ eventID: String) {
        for kind in [Kind.heart, .going] { close(Key(kind: kind, id: eventID)) }
    }

    /// A bookmark off the Event page is on screen (Daily's Suggestions): a failed Save may
    /// shake it.
    func bookmarkOpened(_ eventID: String) {
        open[Key(kind: .save, id: eventID), default: 0] += 1
    }

    func bookmarkClosed(_ eventID: String) {
        close(Key(kind: .save, id: eventID))
    }

    /// Saves this phone kept before saves moved to the server (`SavedStore`): once there
    /// is an account, each Event's is written, shown saved straight away, and dropped
    /// from the phone. Places' stay there for the map. It runs until it has gone through
    /// once with nothing failing (`SavedStore.movedUp`); one that fails stays on the
    /// phone and is tried again next time, so running it again changes nothing that moved.
    func moveUp(_ store: SavedStore) async {
        guard canAct, !movingUp, !store.movedUp else { return }
        movingUp = true
        defer { movingUp = false }
        let account = self.account
        // Map spots ("downtown") and Daily's samples ("daily-s1") aren't Events, and a
        // non-UUID would fail the whole read.
        let ids = store.ids.filter { UUID(uuidString: $0) != nil }
        var events: Set<String> = []
        if !ids.isEmpty {
            guard let known = try? await knownEvents(Array(ids)) else { return }
            events = known
        }
        var failed = false
        for id in events.sorted() {
            do { try await setSave(id, true) } catch { failed = true; continue }
            guard account == self.account else { return }
            let key = Key(kind: .save, id: id)
            // Over a read that came before the write landed, until a read agrees.
            if base[key]?.on != true && writers[key] == nil { chosen[key] = true }
            store.remove(id)
        }
        if !failed { store.movedUp = true }
    }

    /// A new account (or none): the last one's choices are not this one's. Its base
    /// stays until the feed reads again for the new one.
    func accountChanged(signedIn: Bool) {
        canAct = signedIn || !needsAccount
        account &+= 1
        turnBacks.values.forEach { $0.cancel() }
        turnBacks = [:]
        failedFrom = [:]
        turnedBack = []
        chosen = [:]
        late = []
        tappedOn = [:]
        goingTapped = [:]
        savedTapped = [:]
        keptFor = signedIn ? owner() : nil
        restore()
    }

    // MARK: Inside

    private func tally(_ kind: Kind, _ item: FeedCardItem) -> Tally {
        let key = Key(kind: kind, id: item.id)
        let read = base[key] ?? Self.onCard(kind, item)
        guard let choice = chosen[key], choice != read.on else { return read }
        return Tally(on: choice, count: max(0, read.count + (choice ? 1 : -1)))
    }

    /// What the card itself says, before any read.
    private static func onCard(_ kind: Kind, _ item: FeedCardItem) -> Tally {
        switch kind {
        case .going: Tally(on: item.isJoined, count: item.goingCount)
        case .heart: Tally(on: item.isLiked, count: item.likeCount)
        case .save: Tally(on: item.isSaved, count: 0)
        }
    }

    private func toggle(_ key: Key, from isOn: Bool) {
        guard canAct else { return }
        Haptics.light()
        turnBacks.removeValue(forKey: key)?.cancel()
        if let back = failedFrom.removeValue(forKey: key) {
            chosen[key] = back
            return
        }
        choose(key, !isOn)
    }

    private func choose(_ key: Key, _ on: Bool) {
        turnedBack.remove(key)
        late.remove(key)
        chosen[key] = on
        taps[key, default: 0] += 1
        tappedAt[key] = .now
        tappedOn[key] = Date()
        if writers[key] == nil {
            writers[key] = Task { await write(key) }
        }
        save()
    }

    /// Keeps every tap a read hasn't agreed with yet for this account, so a tap made
    /// offline, or sent but not yet read back, still shows after a relaunch and is sent.
    private func save() {
        guard let keep, let keptFor else { return }
        var taps: [Key: Waiting.Tap] = [:]
        // Only real Events: Daily's sample Suggestions ("daily-s1") are this run's only.
        for (key, on) in chosen where !turnedBack.contains(key) && failedFrom[key] == nil
            && UUID(uuidString: key.id) != nil {
            taps[key] = Waiting.Tap(on: on, at: tappedOn[key] ?? Date())
        }
        if taps.isEmpty {
            keep.removeObject(forKey: Self.waitingKey)
        } else if let data = try? JSONEncoder().encode(Waiting(owner: keptFor, taps: taps)) {
            keep.set(data, forKey: Self.waitingKey)
        }
    }

    /// Brings back this account's kept taps and sends them; another account's are
    /// dropped, never sent under someone else's name. No animation: they were already
    /// there before the relaunch.
    private func restore() {
        guard let keep, let keptFor, let data = keep.data(forKey: Self.waitingKey) else { return }
        guard let waiting = try? JSONDecoder().decode(Waiting.self, from: data),
              waiting.owner == keptFor else {
            keep.removeObject(forKey: Self.waitingKey)
            return
        }
        let fresh = waiting.taps.filter { Date().timeIntervalSince($0.value.at) < Self.keepFor }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            for (key, tap) in fresh { chosen[key] = tap.on }
        }
        for (key, tap) in fresh {
            tappedOn[key] = tap.at
            late.insert(key)
            if writers[key] == nil { writers[key] = Task { await write(key) } }
        }
        save()
    }

    private func close(_ key: Key) {
        open[key] = max(0, (open[key] ?? 0) - 1)
    }

    /// Writes the neighbour's latest choice until the server has it, one write at a
    /// time. A failure a newer tap has overtaken just lets the loop write that tap. No
    /// answer at all waits and tries again; only the server's "no" turns back.
    private func write(_ key: Key) async {
        var written: Bool?
        var account = self.account
        var retries = 0
        while let choice = chosen[key] {
            // A new account came mid-write: what the last one's writes did says nothing
            // about this one's, so its choice is written whatever it is.
            if account != self.account {
                account = self.account
                written = nil
            }
            guard choice != written else { break }
            let tap = taps[key]
            do {
                switch key.kind {
                case .going: try await setGoing(key.id, choice)
                case .heart: try await setHeart(key.id, choice)
                case .save: try await setSave(key.id, choice)
                }
                written = choice
                retries = 0
            } catch {
                Log.network("RealLifeActions: \(key.kind) \(choice) for \(key.id) failed: \(error.localizedDescription)")
                // A newer tap, or a new account, overtook this write: no turn back.
                guard tap == taps[key], account == self.account else { continue }
                if error is URLError {
                    // No answer (offline, timed out): the tap stays and is sent again.
                    // A request that did land is safe to send twice: every call is
                    // idempotent. A tap or a new account meanwhile is picked up above.
                    late.insert(key)
                    try? await Task.sleep(for: min(retryFor * (1 << min(retries, 3)), retryFor * 5))
                    retries += 1
                    continue
                }
                writers[key] = nil
                turnBack(key, to: !choice)
                return
            }
        }
        writers[key] = nil
    }

    private func turnBack(_ key: Key, to wasOn: Bool) {
        failedFrom[key] = wasOn
        let tapped = tappedAt[key] ?? .now
        turnBacks[key] = Task { [holdFor, flipFor] in
            try? await Task.sleep(until: tapped + holdFor)
            guard !Task.isCancelled else { return }
            failedFrom[key] = nil
            turnedBack.insert(key)
            // Turns back over `flip`, the time the shake below waits, so it never shakes
            // the two faces mid cross-fade (Jesse, 2026-09-27). A tap before then
            // cancels the shake.
            withAnimation(.easeInOut(duration: Self.flip)) { chosen[key] = wasOn }
            save()
            try? await Task.sleep(for: flipFor)
            guard !Task.isCancelled, (open[key] ?? 0) > 0 else { return }
            if late.remove(key) == nil {
                failures[key, default: 0] += 1
                // Here, not in the view: Reduce Motion drops the shake, never the buzz.
                Haptics.error()
            }
            // The shake and the buzz are silent to VoiceOver; this says it.
            let words = switch key.kind {
            case .going: wasOn ? "Couldn't leave" : "Couldn't join"
            case .heart: wasOn ? "Couldn't unlike" : "Couldn't like"
            case .save: wasOn ? "Couldn't unsave" : "Couldn't save"
            }
            AccessibilityNotification.Announcement(words).post()
        }
    }
}

extension View {
    /// The shake a failed write turns back with (`RealLifeActions`), on the control that
    /// asked: out 6 pt, back past centre, dying away, 0.32 s. It runs each time
    /// `failures` goes up, and `shakes` false stills it, so a tap mid-shake acts at once.
    /// The app had no shake to copy, so every number here is guessed.
    func turnBackShake(failures: Int, shakes: Bool) -> some View {
        keyframeAnimator(initialValue: CGFloat.zero, trigger: failures) { view, x in
            view.offset(x: shakes ? x : 0)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(6, duration: 0.06)
                CubicKeyframe(-5, duration: 0.08)
                CubicKeyframe(3, duration: 0.07)
                CubicKeyframe(-1.5, duration: 0.06)
                CubicKeyframe(0, duration: 0.05)
            }
        }
    }
}
