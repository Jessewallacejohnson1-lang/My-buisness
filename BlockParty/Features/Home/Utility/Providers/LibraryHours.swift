//
//  LibraryHours.swift
//  Block Party — static hours table + open/closed math for the library Utility
//  Row tile. Pure, `nonisolated`, no network.
//
//  Great River Regional Library — St. Joseph branch.
//  TODO(jesse): VERIFY these hours. The values below are placeholder typical
//  small-branch hours so the tile renders honestly until confirmed.
//

import Foundation

enum LibraryHours {
    /// Open intervals per weekday (Apple numbering 1=Sun … 7=Sat), in minutes from
    /// local midnight. An empty array = closed all day.
    nonisolated static let table: [Int: [Range<Int>]] = [
        1: [],                          // Sun — closed
        2: [10 * 60 ..< 20 * 60],       // Mon 10 AM – 8 PM
        3: [10 * 60 ..< 20 * 60],       // Tue 10 AM – 8 PM
        4: [10 * 60 ..< 20 * 60],       // Wed 10 AM – 8 PM
        5: [10 * 60 ..< 20 * 60],       // Thu 10 AM – 8 PM
        6: [10 * 60 ..< 18 * 60],       // Fri 10 AM – 6 PM
        7: [10 * 60 ..< 17 * 60],       // Sat 10 AM – 5 PM
    ]

    enum Status: Equatable, Sendable {
        case open(closesAt: Int, weekday: Int)          // minutes-from-midnight
        case closed(opensAt: Int?, weekday: Int?)       // nil/nil = no known next opening
    }

    nonisolated static func status(at now: Date = Date(), calendar cal: Calendar = .current) -> Status {
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
