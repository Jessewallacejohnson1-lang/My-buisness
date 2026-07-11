//
//  CalendarExport.swift
//  Hygge — writes a day's St. Joseph events into the device's Apple Calendar.
//
//  The Calendar tab's one "add to my calendar" action. Uses write-only EventKit
//  access (iOS 17+) — the least-invasive permission: we never read the user's
//  existing events, we only add. Because we can't read, we can't de-dupe; the
//  UI keeps the action terminal after success so a day isn't added twice.
//

import Foundation
import EventKit

enum CalendarExport {
    enum ExportError: LocalizedError {
        case accessDenied
        case noEvents
        case noCalendar
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Calendar access is off. Turn it on in Settings › Hygge."
            case .noEvents:     return "There's nothing on this day to add."
            case .noCalendar:   return "No calendar is available to add to."
            case .saveFailed:   return "Couldn't add these to your calendar."
            }
        }
    }

    /// Add every event for a YYYY-MM-DD into the user's default calendar.
    /// Returns the number of events written. Throws `ExportError` on failure.
    @discardableResult
    static func addDay(date ymd: String, events: [TimelineEvent]) async throws -> Int {
        guard !events.isEmpty else { throw ExportError.noEvents }

        let store = EKEventStore()
        let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        guard granted else { throw ExportError.accessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw ExportError.noCalendar }

        // Atomic: stage every event, commit only if all staged cleanly. Any failure
        // throws before commit, and this local store's uncommitted stages are then
        // discarded — so the user never sees "Added ✓" for a partial write, and a
        // retry can't duplicate the ones that had succeeded (write-only EventKit
        // can't de-dupe, so all-or-nothing is the safe contract).
        for e in events {
            let ek = EKEvent(eventStore: store)
            ek.calendar = calendar
            ek.title = e.title
            if let loc = e.location, !loc.isEmpty { ek.location = loc }
            ek.notes = e.clubName.map { "\($0) · In St. Joseph, MN." } ?? "In St. Joseph, MN."

            let span = timeSpan(ymd: ymd, startTime: e.startTime)
            ek.startDate = span.start
            ek.endDate = span.end
            ek.isAllDay = span.allDay

            do { try store.save(ek, span: .thisEvent, commit: false) }
            catch { throw ExportError.saveFailed }   // one bad event → commit none
        }

        do { try store.commit() } catch { throw ExportError.saveFailed }
        return events.count
    }

    /// Resolve a YYYY-MM-DD + free-text display time ("7 PM", "noon", nil) into a
    /// concrete start/end in the LOCAL timezone. Untimed events become all-day;
    /// timed events get a 2-hour block (matching the app's "live now" window).
    private static func timeSpan(ymd: String, startTime: String?) -> (start: Date, end: Date, allDay: Bool) {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        if parts.count == 3 { comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2] }

        var cal = Calendar.current
        cal.timeZone = .current

        let minutes = DateHelpers.minutesOf(startTime)   // 24*60 ⇒ unparseable / all-day
        if minutes >= 24 * 60 {
            let day = cal.date(from: comps) ?? Date()
            return (day, day, true)
        }

        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let start = cal.date(from: comps) ?? Date()
        return (start, start.addingTimeInterval(2 * 60 * 60), false)
    }
}
