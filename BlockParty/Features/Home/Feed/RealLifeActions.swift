//
//  RealLifeActions.swift
//  Block Party — the app's one home for what a neighbour does with an Event: Going and
//  Heart for now; Save joins them later (BP app docs/plans/real-life-actions).
//
//  The shell holds it, as it holds the Town feed, so a card and its Event page read
//  the same entry and always agree. A Town feed read sets each Event's base state; a
//  tap lays the neighbour's choice over it at once, until a read agrees with it.
//
//  A write that fails turns the choice back the way the Event page always has: it
//  holds 600 ms after the tap, flips back, and once the 0.18 s flip is done the screen
//  that asked shakes and buzzes, but only while it is still open: the Event page for
//  Going, the card for Heart.
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

    /// How long Join takes to turn from one face to the other, both ways: the card's
    /// join morph (`FeedEventCardJoinButton`), in seconds. A heart turns back as fast.
    static let flip: TimeInterval = 0.18

    /// May act: has an account, or writes go nowhere and need none (`Backend`).
    private(set) var canAct: Bool

    /// What a neighbour does with an Event. Each keeps its own state, writes and shakes.
    private enum Kind { case going, heart }

    private struct Key: Hashable {
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
    /// Numbers each tap, so a failure that a newer tap has overtaken is not a turn back.
    @ObservationIgnored private var taps: [Key: Int] = [:]
    @ObservationIgnored private var tappedAt: [Key: ContinuousClock.Instant] = [:]
    /// Which screens that shake are on screen: Event pages for Going, cards for Heart.
    @ObservationIgnored private var open: [Key: Int] = [:]
    /// Numbers each account, so a write the last one sent says nothing about this one.
    @ObservationIgnored private var account = 0

    private let needsAccount: Bool
    private let holdFor: Duration
    private let flipFor: Duration
    private let setGoing: (_ eventID: String, _ going: Bool) async throws -> Void
    private let setHeart: (_ eventID: String, _ hearted: Bool) async throws -> Void

    /// `hold` and `flip` come in here so tests run fast; the app passes the measured ones.
    init(signedIn: Bool, needsAccount: Bool, hold: Duration, flip: Duration,
         setGoing: @escaping (_ eventID: String, _ going: Bool) async throws -> Void,
         setHeart: @escaping (_ eventID: String, _ hearted: Bool) async throws -> Void) {
        self.canAct = signedIn || !needsAccount
        self.needsAccount = needsAccount
        self.holdFor = hold
        self.flipFor = flip
        self.setGoing = setGoing
        self.setHeart = setHeart
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
        case .samples:
            setGoing = { _, _ in }
            setHeart = { _, _ in }
        case .offline:
            setGoing = { _, _ in throw URLError(.notConnectedToInternet) }
            setHeart = { _, _ in throw URLError(.notConnectedToInternet) }
        }
        // Only the live backend needs an account: sample cards always offered Join, and
        // the Eyes pass must not hang on the live anonymous sign-in, limited per network.
        self.init(signedIn: AuthStore.shared.isSignedIn, needsAccount: backend == .live,
                  hold: Self.hold, flip: .seconds(Self.flip), setGoing: setGoing, setHeart: setHeart)
    }

    #if DEBUG
    /// For the DEBUG screens that show cards outside the shell (`RootView`).
    static let preview = RealLifeActions(signedIn: true, needsAccount: false, hold: hold,
                                         flip: .seconds(flip), setGoing: { _, _ in },
                                         setHeart: { _, _ in })
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

    /// The card's going line: only for someone who may act, and never at zero, as the
    /// Event page never shows a zero count (taste.md, 2026-10-04: fewer words).
    func goingLine(_ item: FeedCardItem) -> String? {
        canAct ? YourDayLogic.goingLabel(for: going(item).count) : nil
    }

    func failureCount(_ eventID: String) -> Int {
        failures[Key(kind: .going, id: eventID)] ?? 0
    }

    func heartFailureCount(_ eventID: String) -> Int {
        failures[Key(kind: .heart, id: eventID)] ?? 0
    }

    // MARK: What screens tell it

    /// Join or leave, shown at once. A tap while a failed write waits to turn back
    /// turns it back now, rather than toggling a state the server never had.
    func toggleGoing(_ item: FeedCardItem) {
        toggle(Key(kind: .going, id: item.id), from: going(item).isGoing)
    }

    /// Heart or un-heart, shown at once, turned back the same way as Join.
    func toggleHeart(_ item: FeedCardItem) {
        toggle(Key(kind: .heart, id: item.id), from: heart(item).isHearted)
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
        }
        for (key, choice) in chosen where writers[key] == nil && failedFrom[key] == nil {
            if base[key]?.on == choice { chosen[key] = nil }
        }
    }

    /// An Event's page is on screen. Only then does a failed Join shake and buzz: the
    /// buzz once landed on Town after a pop.
    func pageOpened(_ eventID: String) {
        open[Key(kind: .going, id: eventID), default: 0] += 1
    }

    func pageClosed(_ eventID: String) {
        close(Key(kind: .going, id: eventID))
    }

    /// An Event's card is on screen. Only then does a failed Heart shake and buzz.
    func cardOpened(_ eventID: String) {
        open[Key(kind: .heart, id: eventID), default: 0] += 1
    }

    func cardClosed(_ eventID: String) {
        close(Key(kind: .heart, id: eventID))
    }

    /// A new account (or none): the last one's choices are not this one's. Its base
    /// stays until the feed reads again for the new one.
    func accountChanged(signedIn: Bool) {
        canAct = signedIn || !needsAccount
        account &+= 1
        turnBacks.values.forEach { $0.cancel() }
        turnBacks = [:]
        failedFrom = [:]
        chosen = [:]
    }

    // MARK: Inside

    private func tally(_ kind: Kind, _ item: FeedCardItem) -> Tally {
        let key = Key(kind: kind, id: item.id)
        let read = base[key] ?? (kind == .going ? Tally(on: item.isJoined, count: item.goingCount)
                                                : Tally(on: item.isLiked, count: item.likeCount))
        guard let choice = chosen[key], choice != read.on else { return read }
        return Tally(on: choice, count: max(0, read.count + (choice ? 1 : -1)))
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
        chosen[key] = on
        taps[key, default: 0] += 1
        tappedAt[key] = .now
        if writers[key] == nil {
            writers[key] = Task { await write(key) }
        }
    }

    private func close(_ key: Key) {
        open[key] = max(0, (open[key] ?? 0) - 1)
    }

    /// Writes the neighbour's latest choice until the server has it, one write at a
    /// time. A failure a newer tap has overtaken just lets the loop write that tap.
    private func write(_ key: Key) async {
        var written: Bool?
        var account = self.account
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
                }
                written = choice
            } catch {
                Log.network("RealLifeActions: \(key.kind) \(choice) for \(key.id) failed: \(error.localizedDescription)")
                // A newer tap, or a new account, overtook this write: no turn back.
                guard tap == taps[key], account == self.account else { continue }
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
            // Turns back over `flip`, the time the shake below waits, so it never shakes
            // the two faces mid cross-fade (Jesse, 2026-09-27). A tap before then
            // cancels the shake.
            withAnimation(.easeInOut(duration: Self.flip)) { chosen[key] = wasOn }
            try? await Task.sleep(for: flipFor)
            guard !Task.isCancelled, (open[key] ?? 0) > 0 else { return }
            failures[key, default: 0] += 1
            // Here, not in the view: Reduce Motion drops the shake, never the buzz.
            Haptics.error()
            // The shake and the buzz are silent to VoiceOver; this says it.
            let words = switch key.kind {
            case .going: wasOn ? "Couldn't leave" : "Couldn't join"
            case .heart: wasOn ? "Couldn't unlike" : "Couldn't like"
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
