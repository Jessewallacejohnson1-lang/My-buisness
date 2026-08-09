//
//  LibraryHours.swift
//  Block Party — static hours table + open/closed math for the library Utility
//  Row tile. Pure, `nonisolated`, no network.
//
//  St. Joseph, MN has NO Great River Regional Library branch (33 branches,
//  Albany→Waite Park; source griver.org/locations). The nearest is the St. Cloud
//  headquarters (1300 W St Germain St, ~5 mi). Hours below are St. Cloud's, per
//  griver.org/locations/st-cloud. TODO(jesse): confirm which branch to surface
//  (St. Cloud vs Waite Park vs the CSB Clemens college library).
//

import Foundation

enum LibraryHours {
    /// Open intervals per weekday (Apple numbering 1=Sun … 7=Sat), in minutes from
    /// local midnight. An empty array = closed all day.
    nonisolated static let table: [Int: [Range<Int>]] = [
        1: [],                          // Sun — closed
        2: [9 * 60 ..< 20 * 60],        // Mon 9 AM – 8 PM
        3: [9 * 60 ..< 20 * 60],        // Tue 9 AM – 8 PM
        4: [9 * 60 ..< 20 * 60],        // Wed 9 AM – 8 PM
        5: [9 * 60 ..< 20 * 60],        // Thu 9 AM – 8 PM
        6: [9 * 60 ..< 17 * 60],        // Fri 9 AM – 5 PM
        7: [9 * 60 ..< 16 * 60],        // Sat 9 AM – 4 PM
    ]

    enum Status: Equatable, Sendable {
        case open(closesAt: Int, weekday: Int)          // minutes-from-midnight
        case closed(opensAt: Int?, weekday: Int?)       // nil/nil = no known next opening
    }

    /// The branch is in St. Cloud, MN, so its hours are Central — `Town.calendar`,
    /// NOT `Calendar.current`: a traveling user still wants the library's clock,
    /// not their hotel's. An explicit calendar (tests) still overrides.
    nonisolated static func status(at now: Date = Date(), calendar cal: Calendar = Town.calendar) -> Status {
        let weekday = cal.component(.weekday, from: now)
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        if let todays = table[weekday] {
            for r in todays where r.contains(minutes) {
                return .open(closesAt: r.upperBound, weekday: weekday)
            }
            // A later opening still to come today?
            if let next = todays.map({ $0.lowerBound }).filter({ $0 > minutes }).min() {
                return .closed(opensAt: next, weekday: weekday)
            }
        }
        // Otherwise scan forward for the next day that opens.
        for offset in 1...7 {
            let wd = ((weekday - 1 + offset) % 7) + 1
            if let ranges = table[wd], let first = ranges.map({ $0.lowerBound }).min() {
                return .closed(opensAt: first, weekday: wd)
            }
        }
        return .closed(opensAt: nil, weekday: nil)
    }
}
