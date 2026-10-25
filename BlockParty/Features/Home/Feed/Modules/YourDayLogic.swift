//
//  YourDayLogic.swift
//  Block Party — town-time rules left over from Your Day.
//
//  The Your Day rail and its day sheet were deleted (rail 2026-09-17, sheet 2026-10-25;
//  docs/archive/GUTTING-LEDGER.md). What stays is what live code reads: the free-text
//  time parser, the town-day parse and the assumed event length, plus the realtime
//  relevance filter, kept as the shape to copy when a second realtime subscriber comes
//  back (docs/rules/architecture.md).
//

import Foundation

nonisolated enum YourDayLogic {
    /// How long an event runs when the row does not say. Matches the window
    /// `DateHelpers.isLiveNow` uses to keep a map pin pulsing.
    static var assumedEventDuration: TimeInterval { 2 * 60 * 60 }

    /// Town midnight on a `yyyy-MM-dd` date column.
    static func townDay(_ date: String) -> Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var components = DateComponents()
        components.calendar = Town.calendar
        components.timeZone = Town.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Town.calendar.date(from: components)
    }

    /// Free-text `club_events.start_time` → minutes from midnight. The live rows
    /// literally read "11 AM", "noon", "7:00 PM", and sometimes prose we cannot
    /// parse at all ("after dark"), which returns nil so the caller can fall back
    /// to the organizer's own words.
    static func minutes(from raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        switch raw.lowercased() {
        case "noon": return 12 * 60
        case "midnight": return 0
        default: break
        }

        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.isLenient = false

        for format in ["h:mm a", "h:mma", "ha", "h a", "HH:mm", "HH:mm:ss"] {
            formatter.dateFormat = format
            guard let date = formatter.date(from: raw) else { continue }
            let components = Town.calendar.dateComponents([.hour, .minute], from: date)
            guard let hour = components.hour, let minute = components.minute else { continue }
            return hour * 60 + minute
        }

        return nil
    }

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
