//
//  DayCompletionStore.swift
//  Block Party — who says an item is done, and where that answer is kept.
//
//  IT IS KEPT IN SUPABASE. `public.event_completions (user_id, event_id,
//  completed_at)` now exists, so the seam this file was built around is filled:
//  the store still answers the same one question to the same two views, and behind
//  it a tick is a row, an untick is a DELETE, and both survive a relaunch.
//
//  THREE ANSWERS, IN PRECEDENCE ORDER, and the whole file is about keeping them
//  straight:
//    1. what this neighbour just tapped   (`overrides`, optimistic, this session)
//    2. what the server says              (seeded into `overrides` by `refresh`)
//    3. what the clock guesses            (`DayItem.isComplete`)
//  A stored completion therefore WINS over the time-based guess — that is the
//  reconcile the rebuild asked for — while an in-flight tap wins over both, so the
//  UI answers the finger before the network answers us.
//
//  THE ONE THING PRESENCE-ONLY STORAGE CANNOT HOLD. "I un-ticked the thing the
//  clock thinks is over" is representable in memory (`overrides[id] == false`) and
//  is NOT representable in the table, because unticking deletes the row and there
//  is no false to store. So a deliberate untick of a clock-complete item survives
//  the session and not a relaunch, where the clock's guess resumes. Storing a
//  tombstone would need a nullable boolean column and a second migration; the
//  behaviour is documented rather than faked.
//
//  OPTIMISTIC WITH ROLLBACK, the same shape as `BriefingModel.vote` / `setRsvp`:
//  flip locally so the box answers the tap, write, and put the previous value back
//  if the write fails — the sheet must never show a tick that did not land.
//

import Combine
import Foundation

@MainActor
protocol DayCompletionStoring: AnyObject, ObservableObject {
    /// The neighbour's own answer, or nil when they have not said.
    func override(for id: String) -> Bool?
    func setComplete(_ isComplete: Bool, for id: String)
}

extension DayCompletionStoring {
    /// What the row should render: the neighbour's answer if they gave one,
    /// otherwise the clock's.
    func isComplete(_ item: DayItem) -> Bool {
        override(for: item.id) ?? item.isComplete
    }
}

@MainActor
final class DayCompletionStore: DayCompletionStoring {
    /// One store per app session, so a tick survives closing and re-opening the
    /// sheet — and, now, closing and re-opening the app. Injected everywhere rather
    /// than reached for, so a test or a preview can hand over its own.
    static let shared = DayCompletionStore(api: sessionAPI)

    /// The API the shared store writes through, or nil when the app is running on
    /// FIXTURE data. A screenshot flag stages events whose ids belong to no
    /// `club_events` row, and a tick under one of those flags has no business
    /// reaching the live table — `-seed-places` is the only debug flag in this app
    /// allowed to be a backend write, and it says so.
    private static var sessionAPI: (any EventCompletionStoring)? {
        #if DEBUG
        let fixtureFlags = [
            "-yourday-sample", "-yourday-loading", "-yourday-error", "-yourday-empty",
            "-yourday-count", "-day-sheet-preview", "-day-sheet-demo",
        ]
        let args = ProcessInfo.processInfo.arguments
        if fixtureFlags.contains(where: args.contains) { return nil }
        #endif
        return EventCompletionsAPI(auth: AuthStore.shared)
    }

    /// Nil in previews, tests and the DEBUG fixtures: with no API the store is
    /// exactly the in-memory one it used to be, which is what keeps a screenshot
    /// flag from writing to the live database.
    private let api: (any EventCompletionStoring)?

    @Published private var overrides: [String: Bool] = [:]

    init(overrides: [String: Bool] = [:], api: (any EventCompletionStoring)? = nil) {
        self.overrides = overrides
        self.api = api
    }

    func override(for id: String) -> Bool? { overrides[id] }

    // MARK: - Reading

    /// Pull this neighbour's stored completions for the rail that is about to be
    /// drawn. Best-effort: a failed read leaves whatever is already known, because
    /// a day with no tick marks is a better wrong answer than an empty rail.
    ///
    /// LOCAL WINS ON MERGE. A refresh can land after a tap (the rail reloads while
    /// a write is in flight), and the server's older truth must not overwrite what
    /// the neighbour just did.
    func refresh(for ids: [String]) async {
        guard let api, !ids.isEmpty else { return }

        do {
            let done = try await api.completedEventIDs(among: ids)
            let stored = Dictionary(uniqueKeysWithValues: done.map { ($0, true) })
            overrides = stored.merging(overrides) { _, local in local }
        } catch {
            Log.network("day completions read failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Writing

    /// Flip now, write next, put it back if the write fails.
    ///
    /// The flip is SYNCHRONOUS on purpose: the caller wraps this in
    /// `withAnimation(DayScheduleMotion.check)`, and a state change made one hop
    /// later would land outside that transaction and the box would snap instead of
    /// springing.
    ///
    /// Immutable update — a fresh dictionary, never a mutation of the old one.
    func setComplete(_ isComplete: Bool, for id: String) {
        let previous = overrides[id]
        overrides = overrides.merging([id: isComplete]) { _, new in new }

        guard api != nil else { return }
        Task { [weak self] in
            await self?.writeThrough(isComplete, for: id, revertingTo: previous)
        }
    }

    /// The network half of `setComplete`, split off so a test can await one round
    /// trip instead of racing an unstructured task.
    func writeThrough(_ isComplete: Bool, for id: String, revertingTo previous: Bool?) async {
        guard let api else { return }
        do {
            if isComplete {
                try await api.complete(id)
            } else {
                try await api.uncomplete(id)
            }
        } catch {
            Log.network("day completion write failed: \(error.localizedDescription)")
            restore(previous, for: id)
            Haptics.error()
        }
    }

    /// Undo one optimistic flip, from whatever the state is NOW — restoring a whole
    /// snapshot would revert any other row that was ticked during the await.
    private func restore(_ previous: Bool?, for id: String) {
        var next = overrides
        next[id] = previous
        overrides = next
    }

    #if DEBUG
    /// Seed a preview's ticks without pretending they came from a backend. No API,
    /// so nothing here can write to the live table.
    static func seeded(complete ids: [String]) -> DayCompletionStore {
        DayCompletionStore(
            overrides: Dictionary(uniqueKeysWithValues: ids.map { ($0, true) })
        )
    }
    #endif
}
