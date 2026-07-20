//
//  InsightsData.swift
//  Block Party — real town-calendar data shaped for the Upcoming Insights face.
//
//  The reference recording's journaling semantics (streaks, words) don't exist
//  in a town calendar, so the *layout & motion* are ported 1:1 while the content
//  is mapped to real forward-looking calendar signals, all derived from the data
//  CalendarModel already loads (per-day `counts` + the `upcoming` agenda) — no
//  new API surface, no inflated numbers ("real data only" — 0 reads as 0).
//

import Foundation

struct InsightsData {
    // Hero — how soon the next happening is (keeps the reference's "N Days" hero).
    var heroValue: String      // "3", "Today", or "—"
    var heroUnit: String       // "Days" / ""
    var heroSubtitle: String   // "Next: Farmers Market · Fri, Jul 17"

    // Entries — total upcoming + a 12-month distribution.
    var entriesTotal: Int
    var months: [Month]        // 12, current month first

    // Bento — three nested time windows.
    var bento: [Stat]          // exactly 3

    // Month calendar — the real current month.
    var grid: Grid

    var isEmpty: Bool

    struct Month { let letter: String; let count: Int }
    struct Stat { let title: String; let value: Int; let subA: Sub; let subB: Sub }
    struct Sub { let label: String; let value: Int }
    struct Grid {
        let title: String          // "July 2026"
        let leadingBlanks: Int
        let dayCount: Int
        let counts: [Int]          // per day 1…dayCount
        let todayDay: Int?
    }

    // MARK: - Build from what CalendarModel already loads

    static func from(counts: [String: Int], upcoming: [AgendaEvent], today: String) -> InsightsData {
        let cal = CalendarModel.gregorian
        let tp = today.split(separator: "-").compactMap { Int($0) }
        guard tp.count == 3,
              let base = cal.date(from: DateComponents(year: tp[0], month: tp[1])),
              let todayDate = cal.date(from: DateComponents(year: tp[0], month: tp[1], day: tp[2]))
        else { return .empty }
        let y = tp[0], m = tp[1], d = tp[2]

        // 12-month distribution (current month first).
        let letters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        var months: [Month] = []
        for off in 0..<12 {
            guard let md = cal.date(byAdding: .month, value: off, to: base) else { continue }
            let c = cal.dateComponents([.year, .month], from: md)
            let prefix = String(format: "%04d-%02d-", c.year ?? 0, c.month ?? 0)
            let cnt = counts.reduce(0) { $1.key.hasPrefix(prefix) ? $0 + $1.value : $0 }
            months.append(Month(letter: letters[(c.month ?? 1) - 1], count: cnt))
        }

        func key(_ date: Date) -> String { DateHelpers.localDate(date) }
        // This week = today … today+6.
        var week = 0
        for off in 0..<7 where cal.date(byAdding: .day, value: off, to: todayDate) != nil {
            let dd = cal.date(byAdding: .day, value: off, to: todayDate)!
            week += counts[key(dd)] ?? 0
        }
        // This month = remaining days of the current calendar month.
        let monthPrefix = String(format: "%04d-%02d-", y, m)
        let thisMonth = counts.reduce(0) { ($1.key.hasPrefix(monthPrefix) && $1.key >= today) ? $0 + $1.value : $0 }
        let total = upcoming.count

        // Hero — days until the soonest upcoming happening.
        let heroValue: String
        let heroUnit: String
        if let next = upcoming.first,
           let nd = cal.date(from: dateComponents(next.eventDate)),
           let days = cal.dateComponents([.day], from: todayDate, to: nd).day {
            if days <= 0 { heroValue = "Today"; heroUnit = "" }
            else { heroValue = "\(days)"; heroUnit = days == 1 ? "Day" : "Days" }
        } else { heroValue = "—"; heroUnit = "" }
        let heroSubtitle = upcoming.first.map { "Next: \($0.title) · \(DateHelpers.prettyDate($0.eventDate))" }
            ?? "Nothing on the calendar yet"

        let bento = [
            Stat(title: "This Week", value: week,
                 subA: Sub(label: "This Week", value: week), subB: Sub(label: "This Month", value: thisMonth)),
            Stat(title: "This Month", value: thisMonth,
                 subA: Sub(label: "This Month", value: thisMonth), subB: Sub(label: "Upcoming", value: total)),
            Stat(title: "Upcoming", value: total,
                 subA: Sub(label: "This Month", value: thisMonth), subB: Sub(label: "Upcoming", value: total)),
        ]

        let dayCount = cal.range(of: .day, in: .month, for: base)?.count ?? 30
        let leading = (cal.component(.weekday, from: base) - 1)
        var dayCounts: [Int] = []
        for dd in 1...dayCount { dayCounts.append(counts[String(format: "%04d-%02d-%02d", y, m, dd)] ?? 0) }
        let fmt = DateFormatter(); fmt.calendar = cal; fmt.locale = Locale(identifier: "en_US"); fmt.dateFormat = "MMMM yyyy"
        let grid = Grid(title: fmt.string(from: base), leadingBlanks: leading,
                        dayCount: dayCount, counts: dayCounts, todayDay: d)

        return InsightsData(heroValue: heroValue, heroUnit: heroUnit, heroSubtitle: heroSubtitle,
                            entriesTotal: total, months: months, bento: bento, grid: grid,
                            isEmpty: total == 0)
    }

    private static func dateComponents(_ ymd: String) -> DateComponents {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        if p.count == 3 { c.year = p[0]; c.month = p[1]; c.day = p[2] }
        return c
    }

    /// DEBUG sample so populated rendering can be screenshotted on a signed-out
    /// simulator (`-insights-sample`). Plausible St. Joseph data, July 2026.
    static var sample: InsightsData {
        let letters = ["J", "A", "S", "O", "N", "D", "J", "F", "M", "A", "M", "J"]
        let cnts = [9, 7, 5, 4, 2, 3, 1, 1, 1, 1, 0, 0]
        var grid = Array(repeating: 0, count: 31)
        for (d, c) in [(17, 2), (18, 1), (20, 1), (24, 1), (26, 3), (31, 1)] { grid[d - 1] = c }
        return InsightsData(
            heroValue: "3", heroUnit: "Days",
            heroSubtitle: "Next: St. Joseph Farmers Market · Fri, Jul 17",
            entriesTotal: 34,
            months: zip(letters, cnts).map { Month(letter: $0, count: $1) },
            bento: [Stat(title: "This Week", value: 4, subA: Sub(label: "This Week", value: 4), subB: Sub(label: "This Month", value: 12)),
                    Stat(title: "This Month", value: 12, subA: Sub(label: "This Month", value: 12), subB: Sub(label: "Upcoming", value: 34)),
                    Stat(title: "Upcoming", value: 34, subA: Sub(label: "This Month", value: 12), subB: Sub(label: "Upcoming", value: 34))],
            grid: Grid(title: "July 2026", leadingBlanks: 3, dayCount: 31, counts: grid, todayDay: 15),
            isEmpty: false)
    }

    static var empty: InsightsData {
        InsightsData(heroValue: "—", heroUnit: "", heroSubtitle: "Nothing on the calendar yet",
                     entriesTotal: 0, months: Array(repeating: Month(letter: "·", count: 0), count: 12),
                     bento: [Stat(title: "This Week", value: 0, subA: Sub(label: "This Week", value: 0), subB: Sub(label: "This Month", value: 0)),
                             Stat(title: "This Month", value: 0, subA: Sub(label: "This Month", value: 0), subB: Sub(label: "Upcoming", value: 0)),
                             Stat(title: "Upcoming", value: 0, subA: Sub(label: "This Month", value: 0), subB: Sub(label: "Upcoming", value: 0))],
                     grid: Grid(title: "", leadingBlanks: 0, dayCount: 30, counts: Array(repeating: 0, count: 30), todayDay: nil),
                     isEmpty: true)
    }
}
