//
//  GarbageSchedule.swift
//  Block Party — pure local date math for the garbage/recycling Utility Row tile.
//  No network. `nonisolated` throughout so it's callable from tests + any context.
//
//  Rules (see UtilityTileProvider spec):
//   • pickup weekday is user-set (Apple weekday numbering, 1=Sun … 7=Sat; default Tue=3),
//   • recycling runs every OTHER week, its phase anchored to a known recycling-week date,
//   • an observed holiday falling on/before the pickup day in that week delays pickup +1 day.
//

import Foundation

enum GarbageSchedule {
    /// Apple weekday numbering: 1=Sun, 2=Mon, 3=Tue … 7=Sat.
    nonisolated static let defaultWeekday = 3   // Tuesday

    /// A date that fell in a RECYCLING week. Recycling-week parity flows from it
    /// (every other week). TODO(jesse): verify against the St. Joseph hauler's
    /// actual calendar — any real recycling-week pickup date works.
    nonisolated static let recyclingAnchor = DateComponents(year: 2026, month: 7, day: 14)  // Tue Jul 14 2026

    /// Observed holidays that delay collection by a day when they fall on/before
    /// the pickup weekday in a given week. TODO(jesse): verify the hauler's list;
    /// floating holidays (Memorial/Labor/Thanksgiving) are per-year — confirm dates.
    nonisolated static let observedHolidays: [MonthDay] = [
        MonthDay(1, 1),     // New Year's Day
        MonthDay(5, 25),    // Memorial Day (last Mon May — 2026; TODO verify per year)
        MonthDay(7, 4),     // Independence Day
        MonthDay(9, 7),     // Labor Day (first Mon Sep — 2026; TODO verify per year)
        MonthDay(11, 26),   // Thanksgiving (4th Thu Nov — 2026; TODO verify per year)
        MonthDay(12, 25),   // Christmas Day
    ]

    struct MonthDay: Equatable, Sendable {
        let month, day: Int
        init(_ month: Int, _ day: Int) { self.month = month; self.day = day }
    }

    struct Pickup: Equatable, Sendable {
        let date: Date
        let isRecyclingWeek: Bool
        let daysFromToday: Int   // 0 = today ("Tonight"), 1 = tomorrow, …
    }

    /// The next pickup at/after `now`, applying the recycling parity + holiday shift.
    nonisolated static func nextPickup(after now: Date = Date(),
                                       pickupWeekday: Int = defaultWeekday,
                                       calendar cal: Calendar = .current) -> Pickup {
        let today = cal.startOfDay(for: now)
        let anchorWeek = weekStart(cal.date(from: recyclingAnchor) ?? today, cal)

        for weekOffset in 0...3 {
            guard let weekBase = cal.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart(today, cal)),
                  let normal = date(forWeekday: pickupWeekday, inWeekStarting: weekBase, cal) else { continue }
            let shifted = holidayDelays(weekStarting: weekBase, pickupWeekday: pickupWeekday, cal)
            let pickup = shifted ? (cal.date(byAdding: .day, value: 1, to: normal) ?? normal) : normal
            guard cal.startOfDay(for: pickup) >= today else { continue }

            let weeks = weeksBetween(anchorWeek, weekBase, cal)
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: pickup)).day ?? 0
            return Pickup(date: pickup, isRecyclingWeek: weeks % 2 == 0, daysFromToday: days)
        }
        return Pickup(date: today, isRecyclingWeek: true, daysFromToday: 0)   // unreachable
    }

    // MARK: - Helpers

    private nonisolated static func weekStart(_ date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    private nonisolated static func date(forWeekday weekday: Int, inWeekStarting weekStart: Date, _ cal: Calendar) -> Date? {
        let startWeekday = cal.component(.weekday, from: weekStart)
        let delta = (weekday - startWeekday + 7) % 7
        return cal.date(byAdding: .day, value: delta, to: weekStart)
    }

    private nonisolated static func weeksBetween(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
        let days = cal.dateComponents([.day], from: a, to: b).day ?? 0
        return Int((Double(days) / 7.0).rounded())
    }

    /// True if an observed holiday in this week falls on a weekday ≤ the pickup day.
    private nonisolated static func holidayDelays(weekStarting weekStart: Date, pickupWeekday: Int, _ cal: Calendar) -> Bool {
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let c = cal.dateComponents([.month, .day, .weekday], from: day)
            guard let m = c.month, let d = c.day, let wd = c.weekday else { continue }
            if wd <= pickupWeekday && observedHolidays.contains(where: { $0.month == m && $0.day == d }) {
                return true
            }
        }
        return false
    }
}
