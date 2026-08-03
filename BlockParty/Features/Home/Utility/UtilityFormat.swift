//
//  UtilityFormat.swift
//  Block Party — small, pure display formatters shared by the Utility Row
//  providers (clock times, weekday names, relative timestamps). `nonisolated`
//  so providers and tests can call them from any context.
//

import Foundation

enum UtilityFormat {
    private nonisolated static func usCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US")
        return c
    }

    /// Minutes-from-midnight → "8 PM" / "10:30 AM".
    nonisolated static func clock(_ minutes: Int) -> String {
        var comps = DateComponents()
        comps.year = 2000; comps.month = 1; comps.day = 1
        comps.hour = minutes / 60; comps.minute = minutes % 60
        guard let date = usCalendar().date(from: comps) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.dateFormat = (minutes % 60 == 0) ? "h a" : "h:mm a"
        return f.string(from: date)
    }

    /// A Date → "3 PM" / "3:30 PM" (for precip "by 3 PM").
    ///
    /// Read and formatted on `Town`'s clock (Central), NOT the device's: the tile
    /// providers compute these instants in town time, so rendering them in the
    /// phone's zone would print an hour the math never chose. The `en_US` locale
    /// pin is separate — it only fixes the US "h:mm a" shape.
    nonisolated static func shortTime(_ date: Date) -> String {
        let m = Town.calendar.component(.minute, from: date)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.timeZone = Town.timeZone
        f.dateFormat = m == 0 ? "h a" : "h:mm a"
        return f.string(from: date)
    }

    /// Apple weekday (1=Sun … 7=Sat) → "Saturday" (or short "Sat").
    nonisolated static func weekdayName(_ weekday: Int, short: Bool = false) -> String {
        let syms = short ? usCalendar().shortWeekdaySymbols : usCalendar().weekdaySymbols
        let idx = (weekday - 1) % 7
        return (idx >= 0 && idx < syms.count) ? syms[idx] : ""
    }

    /// A Date's weekday → "Tuesday" (or short "Tue").
    ///
    /// Resolved on `Town.calendar` (Central), NOT `Calendar.current`: `GarbageSchedule`
    /// already picks the pickup day on the town's clock, so a phone east of Central
    /// would otherwise print a Thursday pickup as "Friday".
    nonisolated static func weekdayName(_ date: Date, short: Bool = false) -> String {
        weekdayName(Town.calendar.component(.weekday, from: date), short: short)
    }

    /// A Date → "Tue, Jul 28".
    ///
    /// Formatted in `Town.timeZone` (Central) for the same reason as `weekdayName`:
    /// the instant being shown is a town date, so a device zone would slide it a day.
    nonisolated static func mediumDate(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.timeZone = Town.timeZone
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    /// A Date → "just now" / "3h ago" / "2d ago" (for the town_status stale note).
    nonisolated static func relative(_ date: Date, now: Date = Date()) -> String {
        let secs = max(0, now.timeIntervalSince(date))
        if secs < 60 { return "just now" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}
