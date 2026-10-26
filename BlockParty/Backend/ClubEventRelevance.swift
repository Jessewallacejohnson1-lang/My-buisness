//
//  ClubEventRelevance.swift
//  Block Party — does a realtime `club_events` change matter to what a screen shows? The one
//  rule every subscriber reads (the map today; codebase-health 13 in the BP app folder).
//

import Foundation

nonisolated enum ClubEventRelevance {
    /// True when the change touches an event dated in `days` ("YYYY-MM-DD", Town days) or one
    /// the screen shows (`shownIDs`), so it should read again.
    ///
    /// Status is deliberately NOT checked: the UPDATE that approves a pending event must count,
    /// and an irrelevant insert only costs one idempotent (debounced) refetch. A DELETE's
    /// `old_record` carries only the primary key, so deletes match by shown id. Only events,
    /// never trails.
    static func matters(_ change: RealtimeClient.Change, shownIDs: Set<String>,
                        days: ClosedRange<String>) -> Bool {
        // "YYYY-MM-DD" compares correctly as a string.
        func inDays(_ row: RealtimeClient.Change.Row?) -> Bool {
            guard let row else { return false }
            if let kind = row.kind, kind != "event" { return false }
            guard let date = row.eventDate else { return false }
            return days.contains(date)
        }
        func shown(_ id: String?) -> Bool {
            id.map(shownIDs.contains) ?? false
        }
        switch change.kind {
        case .insert: return inDays(change.new)
        case .update: return inDays(change.new) || shown(change.new?.id ?? change.old?.id)
        case .delete: return shown(change.old?.id)
        }
    }
}
