//
//  DayCompletionStore.swift
//  Block Party — who says an item is done, and where that answer is kept.
//
//  THE SEAM IS THE POINT. "Done means done tomorrow too" is the wanted behaviour,
//  and it is NOT implemented here, on purpose:
//
//    * there is no completion table — `club_events` has no per-user done column
//      and `event_rsvps` means "I am going", which is a different claim;
//    * schema migrations are gated, so inventing one is not this change's call.
//
//  So completion is modelled behind a protocol with an in-memory implementation.
//  A tick survives scrolling, closing the sheet, and re-opening it; it does not
//  survive relaunch, and nothing here writes to Supabase. When the column lands,
//  the whole change is a second conformance plus swapping `.shared` for it — no
//  view moves.
//
//  `DayItem.isComplete` is the OTHER answer: derived from the clock (see
//  `YourDayLogic.completionInstant`). A user tick overrides it in both
//  directions, which is why the store holds `Bool?` overrides rather than a set
//  of done ids — "I un-ticked the thing the clock thinks is over" has to be
//  representable.
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

/// The shipping implementation until a completion column exists.
@MainActor
final class DayCompletionStore: DayCompletionStoring {
    /// One store per app session, so a tick survives closing and re-opening the
    /// sheet. Injected everywhere rather than reached for, so a test or a preview
    /// can hand over its own.
    static let shared = DayCompletionStore()

    @Published private var overrides: [String: Bool] = [:]

    init(overrides: [String: Bool] = [:]) {
        self.overrides = overrides
    }

    func override(for id: String) -> Bool? { overrides[id] }

    /// Immutable update — a fresh dictionary, never a mutation of the old one.
    func setComplete(_ isComplete: Bool, for id: String) {
        overrides = overrides.merging([id: isComplete]) { _, new in new }
    }

    #if DEBUG
    /// Seed a preview's ticks without pretending they came from a backend.
    static func seeded(complete ids: [String]) -> DayCompletionStore {
        DayCompletionStore(
            overrides: Dictionary(uniqueKeysWithValues: ids.map { ($0, true) })
        )
    }
    #endif
}
