//
//  RealLifeActions.swift
//  Block Party — the app's one home for what a neighbour does with an Event: Going
//  for now; Save and Heart join it later (BP app docs/plans/real-life-actions).
//
//  The shell holds it, as it holds the Town feed, so a card and its Event page read
//  the same entry and always agree. A Town feed read sets each Event's base state; a
//  tap lays the neighbour's choice over it at once, until a read agrees with it.
//
//  A write that fails turns the choice back the way the Event page always has: it
//  holds "Going" 600 ms after the tap, flips back, and once the 0.18 s flip is done
//  the page shakes and buzzes, but only while that Event's page is still open.
//

import SwiftUI

@MainActor @Observable
final class RealLifeActions {
    struct Going: Equatable {
        var isGoing: Bool
        var count: Int
    }

    /// A failed Join still shows "Going" this long after the tap before it turns back,
    /// so the turn back reads as the app's answer, not a flicker. Signed out, the write
    /// failed 15 ms after the tap (measured 2026-09-26), about one frame. (guessed)
    static let hold: Duration = .milliseconds(600)

    /// How long Join takes to turn from one face to the other, both ways: the card's
    /// join morph (`FeedEventCardJoinButton`), in seconds.
    static let flip: TimeInterval = 0.18

    /// May act: has an account, or writes go nowhere and need none (`Backend`).
    private(set) var canAct: Bool

    /// Each Event as the last Town feed read gave it.
    private var base: [String: Going] = [:]
    /// The neighbour's own Going, laid over `base` until a read agrees with it.
    private var chosen: [String: Bool] = [:]
    /// One more each time a failed write turns an Event back by itself while its page
    /// is open; the page shakes Join on it. Never goes down, so a shake never replays.
    private var failures: [String: Int] = [:]

    /// The one write running per Event. Never cancelled: a write already sent can't be
    /// called back, so the next one waits for it and lands after it.
    @ObservationIgnored private var writers: [String: Task<Void, Never>] = [:]
    /// Waiting out `hold`, then `flip`, after a failed write.
    @ObservationIgnored private var turnBacks: [String: Task<Void, Never>] = [:]
    /// Where a failed write goes back to while it waits out `hold`.
    @ObservationIgnored private var failedFrom: [String: Bool] = [:]
    /// Numbers each tap, so a failure that a newer tap has overtaken is not a turn back.
    @ObservationIgnored private var taps: [String: Int] = [:]
    @ObservationIgnored private var tappedAt: [String: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var openPages: [String: Int] = [:]

    private let needsAccount: Bool
    private let holdFor: Duration
    private let flipFor: Duration
    private let setGoing: (_ eventID: String, _ going: Bool) async throws -> Void

    /// `hold` and `flip` come in here so tests run fast; the app passes the measured ones.
    init(signedIn: Bool, needsAccount: Bool, hold: Duration, flip: Duration,
         setGoing: @escaping (_ eventID: String, _ going: Bool) async throws -> Void) {
        self.canAct = signedIn || !needsAccount
        self.needsAccount = needsAccount
        self.holdFor = hold
        self.flipFor = flip
        self.setGoing = setGoing
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
        switch backend {
        case .live:
            setGoing = { eventID, going in
                let api = CommunityAPI(auth: AuthStore.shared)
                if going { try await api.rsvpEvent(eventID) } else { try await api.unRsvpEvent(eventID) }
            }
        case .samples:
            setGoing = { _, _ in }
        case .offline:
            setGoing = { _, _ in throw URLError(.notConnectedToInternet) }
        }
        // Only the live backend needs an account: sample cards always offered Join, and
        // the Eyes pass must not hang on the live anonymous sign-in, limited per network.
        self.init(signedIn: AuthStore.shared.isSignedIn, needsAccount: backend == .live,
                  hold: Self.hold, flip: .seconds(Self.flip), setGoing: setGoing)
    }

    #if DEBUG
    /// For the DEBUG screens that show cards outside the shell (`RootView`).
    static let preview = RealLifeActions(signedIn: true, needsAccount: false, hold: hold,
                                         flip: .seconds(flip), setGoing: { _, _ in })
    #endif

    // MARK: What screens read

    /// The Event's Going: the last read's, with the neighbour's own choice over it. The
    /// count moves with the choice, from whatever the read last said.
    func going(_ item: FeedCardItem) -> Going {
        let read = base[item.id] ?? Going(isGoing: item.isJoined, count: item.goingCount)
        guard let choice = chosen[item.id], choice != read.isGoing else { return read }
        return Going(isGoing: choice, count: max(0, read.count + (choice ? 1 : -1)))
    }

    /// The card's going line: only for someone who may act, and never at zero, as the
    /// Event page never shows a zero count (taste.md, 2026-10-04: fewer words).
    func goingLine(_ item: FeedCardItem) -> String? {
        canAct ? YourDayLogic.goingLabel(for: going(item).count) : nil
    }

    func failureCount(_ eventID: String) -> Int {
        failures[eventID] ?? 0
    }

    // MARK: What screens tell it

    /// Join or leave, shown at once. A tap while a failed write waits to turn back
    /// turns it back now, rather than toggling a state the server never had.
    func toggleGoing(_ item: FeedCardItem) {
        guard canAct else { return }
        Haptics.light()
        let id = item.id
        turnBacks.removeValue(forKey: id)?.cancel()
        if let back = failedFrom.removeValue(forKey: id) {
            chosen[id] = back
            return
        }
        chosen[id] = !going(item).isGoing
        taps[id, default: 0] += 1
        tappedAt[id] = .now
        if writers[id] == nil {
            writers[id] = Task { await write(id) }
        }
    }

    /// A Town feed read: each Event's base state. A choice the read agrees with is done;
    /// one it doesn't stays, since a read can start before the write lands.
    func read(_ cards: [FeedCardItem]) {
        for card in cards {
            base[card.id] = Going(isGoing: card.isJoined, count: card.goingCount)
        }
        for (id, choice) in chosen where writers[id] == nil && failedFrom[id] == nil {
            if base[id]?.isGoing == choice { chosen[id] = nil }
        }
    }

    /// An Event's page is on screen. Only then does a failed write shake and buzz: the
    /// buzz once landed on Town after a pop.
    func pageOpened(_ eventID: String) {
        openPages[eventID, default: 0] += 1
    }

    func pageClosed(_ eventID: String) {
        openPages[eventID] = max(0, (openPages[eventID] ?? 0) - 1)
    }

    /// A new account (or none): the last one's state is not this one's.
    func accountChanged(signedIn: Bool) {
        canAct = signedIn || !needsAccount
        turnBacks.values.forEach { $0.cancel() }
        turnBacks = [:]
        failedFrom = [:]
        taps = [:]
        chosen = [:]
        base = [:]
    }

    // MARK: Inside

    /// Writes the neighbour's latest choice until the server has it, one write at a
    /// time. A failure a newer tap has overtaken just lets the loop write that tap.
    private func write(_ id: String) async {
        var written: Bool?
        while let choice = chosen[id], choice != written {
            let tap = taps[id]
            do {
                try await setGoing(id, choice)
                written = choice
            } catch {
                Log.network("RealLifeActions: going \(choice) for \(id) failed: \(error.localizedDescription)")
                guard tap == taps[id] else { continue }
                writers[id] = nil
                turnBack(id, to: !choice)
                return
            }
        }
        writers[id] = nil
    }

    private func turnBack(_ id: String, to wasGoing: Bool) {
        failedFrom[id] = wasGoing
        let tapped = tappedAt[id] ?? .now
        turnBacks[id] = Task { [holdFor, flipFor] in
            try? await Task.sleep(until: tapped + holdFor)
            guard !Task.isCancelled else { return }
            failedFrom[id] = nil
            chosen[id] = wasGoing
            // Join first, then the shake: it waits for the face to finish turning, so it
            // never shakes the two labels mid cross-fade (Jesse, 2026-09-27). A tap before
            // then cancels it.
            try? await Task.sleep(for: flipFor)
            guard !Task.isCancelled, (openPages[id] ?? 0) > 0 else { return }
            failures[id, default: 0] += 1
            // Here, not in the view: Reduce Motion drops the shake, never the buzz.
            Haptics.error()
            // The shake and the buzz are silent to VoiceOver; this says it.
            AccessibilityNotification.Announcement(wasGoing ? "Couldn't leave" : "Couldn't join").post()
        }
    }
}
