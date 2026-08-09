//
//  SpotlightWeekLabel.swift
//  Block Party — how a week is said out loud on the spotlight card.
//
//  `SpotlightWeek.identifier` stays exactly as it is: "2026-W32" is the archive
//  key the server writes one row against, and it should look like a key. It was
//  also being printed on the card, where no resident would ever say it — nobody
//  in St. Joe calls this "week thirty-two".
//
//  The eyebrow instead names the Monday the week started: "week of August 3".
//  That keeps three things true at once — it is plainly a WEEK (so the card does
//  not read stale on a Friday), it is a real date a neighbour would use, and it
//  is fixed for all seven days, so the spotlight never looks like it changed.
//

import Foundation

nonisolated enum SpotlightWeekLabel {
    static func label(forBriefingDate briefingDate: String) -> String? {
        guard let date = BriefingDate.parse(briefingDate) else { return nil }
        return label(for: date)
    }

    static func label(for date: Date) -> String? {
        guard let monday = weekStart(for: date) else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "MMMM d"
        return "week of \(formatter.string(from: monday))"
    }

    /// The ISO week's Monday, resolved in town time for the same reason the
    /// identifier is: a traveling phone must not roll the subject over early.
    private static func weekStart(for date: Date) -> Date? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = Town.timeZone
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
