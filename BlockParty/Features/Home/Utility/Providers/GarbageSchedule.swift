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

    /// FIXED-date observed holidays. The floating ones (Memorial / Labor /
    /// Thanksgiving) are computed per-year by rule in `floatingHolidays`, so the
    /// shift stays correct every year. TODO(jesse): verify the hauler's actual list.
    nonisolated static let observedHolidays: [MonthDay] = [
        MonthDay(1, 1),     // New Year's Day
        MonthDay(7, 4),     // Independence Day
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

    /// True if an observed holiday in this collection week falls ON OR BEFORE the
    /// pickup day — compared by POSITION in the week (offset from weekStart), so it
    /// is correct for any calendar's `firstWeekday`, not only Sunday-first.
    private nonisolated static func holidayDelays(weekStarting weekStart: Date, pickupWeekday: Int, _ cal: Calendar) -> Bool {
        let startWeekday = cal.component(.weekday, from: weekStart)
        let pickupOffset = (pickupWeekday - startWeekday + 7) % 7
        for offset in 0...pickupOffset {
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            if isHoliday(day, cal) { return true }
        }
        return false
    }

    private nonisolated static func isHoliday(_ day: Date, _ cal: Calendar) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: day)
        guard let y = c.year, let m = c.month, let d = c.day else { return false }
        if observedHolidays.contains(where: { $0.month == m && $0.day == d }) { return true }
        return floatingHolidays(year: y, cal).contains { cal.isDate($0, inSameDayAs: day) }
    }

    /// US floating federal holidays that shift collection, computed for `year`.
    private nonisolated static func floatingHolidays(year: Int, _ cal: Calendar) -> [Date] {
        [ nthWeekday(year: year, month: 5, weekday: 2, ordinal: -1, cal),  // Memorial: last Mon May
          nthWeekday(year: year, month: 9, weekday: 2, ordinal: 1, cal),   // Labor: first Mon Sep
          nthWeekday(year: year, month: 11, weekday: 5, ordinal: 4, cal) ] // Thanksgiving: 4th Thu Nov
            .compactMap { $0 }
    }

    private nonisolated static func nthWeekday(year: Int, month: Int, weekday: Int, ordinal: Int, _ cal: Calendar) -> Date? {
        var c = DateComponents()
        c.year = year; c.month = month; c.weekday = weekday; c.weekdayOrdinal = ordinal
        return cal.date(from: c)
    }
}
