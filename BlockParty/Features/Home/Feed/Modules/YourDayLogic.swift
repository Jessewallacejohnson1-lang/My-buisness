//
//  YourDayLogic.swift
//  Block Party — town-time rules left over from Your Day.
//
//  The Your Day rail and its day sheet were deleted (rail 2026-09-17, sheet 2026-10-25;
//  docs/archive/GUTTING-LEDGER.md). What stays is the realtime relevance filter, kept as
//  the shape to copy when a second realtime subscriber comes back
//  (docs/rules/architecture.md). Its time rules moved to `EventWhen` (codebase-health 10).
//

import Foundation

nonisolated enum YourDayLogic {
    // MARK: - Realtime relevance

    /// Should a `club_events` change re-sync the rail? Mirrors `MapModel.handle`'s
    /// test, widened from `event_date == today` to the same
    /// `[today − lookback, today]` town-time window (`CommunityAPI.dayLookbackDays`) —
    /// a multi-day row dated days ago can still overlap today.
    ///
    /// Status is deliberately NOT checked: the UPDATE that approves a pending
    /// event must count, and an irrelevant insert only costs one idempotent
    /// (debounced) refetch. A DELETE's `old_record` carries only the primary key,
    /// so deletes match by shown id.
    static func changeIsRelevant(
        _ change: RealtimeClient.Change,
        shownIDs: Set<String>,
        now: Date
    ) -> Bool {
        let today = Town.day(now)
        let earliest = Town.day(
            Town.calendar.date(byAdding: .day, value: -CommunityAPI.dayLookbackDays, to: now) ?? now
        )
        // "YYYY-MM-DD" compares correctly as a string.
        func inWindow(_ row: RealtimeClient.Change.Row?) -> Bool {
            guard let row else { return false }
            if let kind = row.kind, kind != "event" { return false }
            guard let date = row.eventDate else { return false }
            return date >= earliest && date <= today
        }
        func shown(_ id: String?) -> Bool {
            id.map(shownIDs.contains) ?? false
        }
        switch change.kind {
        case .insert: return inWindow(change.new)
        case .update: return inWindow(change.new) || shown(change.new?.id ?? change.old?.id)
        case .delete: return shown(change.old?.id)
        }
    }
}
