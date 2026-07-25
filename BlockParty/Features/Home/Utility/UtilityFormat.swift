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
    nonisolated static func shortTime(_ date: Date) -> String {
        let m = Calendar.current.component(.minute, from: date)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
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
    nonisolated static func weekdayName(_ date: Date, short: Bool = false) -> String {
        weekdayName(Calendar.current.component(.weekday, from: date), short: short)
    }

    /// A Date → "Tue, Jul 28".
    nonisolated static func mediumDate(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
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
