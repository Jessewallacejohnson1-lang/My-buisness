//
//  EventWhen.swift
//  Block Party — when an event happens, the one rule every screen reads: the Town
//  card, the map, Daily and You (codebase-health 10 in the BP app folder).
//
//  Built from the row's own fields: its Town day (`event_date`), the organizer's
//  free-text start (`start_time`: "7 PM", "7:00 p.m.", "7pm-9pm", "19:00", "noon",
//  "after dark"), `end_at` and `all_day`. All in the Town's time, whatever the phone's.
//

import Foundation

nonisolated struct EventWhen: Hashable {
    /// When it starts; Town midnight when it isn't `timed`.
    let start: Date
    /// `end_at`, else two hours on (three for a game); an untimed one runs to the next
    /// midnight.
    let end: Date
    /// False when it gives no time we can read ("after dark") or runs all day.
    let timed: Bool

    /// Started and not over. An untimed one is on only when it runs over days (the
    /// Johanna Kiln, Oct 16 to 25): a one-day all-day listing gives no hours.
    func isOn(_ now: Date) -> Bool {
        guard start <= now, now < end else { return false }
        return timed || end > (Town.gregorian.date(byAdding: .day, value: 1, to: start) ?? end)
    }

    /// "Today", "Tonight" (from 5 PM) or "Tomorrow"; nil any other day.
    func dayWord(_ now: Date) -> String? {
        switch Town.days(from: now, to: start) {
        case 0: return timed && Town.gregorian.component(.hour, from: start) >= 17 ? "Tonight" : "Today"
        case 1: return "Tomorrow"
        default: return nil
        }
    }
}

extension EventWhen {
    /// nil when `date` isn't a "YYYY-MM-DD" day.
    init?(date: String?, time: String?, endAt: Date?, allDay: Bool = false, game: Bool = false) {
        guard let date, let day = Town.midnight(date) else { return nil }
        if !allDay, let minutes = Self.minutes(time),
           let start = Town.gregorian.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) {
            self.init(start: start, end: endAt ?? start.addingTimeInterval((game ? 3 : 2) * 3600), timed: true)
        } else {
            let next = Town.gregorian.date(byAdding: .day, value: 1, to: day) ?? day
            self.init(start: day, end: endAt ?? next, timed: false)
        }
    }

    /// The organizer's free-text time → minutes after midnight; nil when it can't be read.
    /// A 12-hour clock first, wherever it sits ("7pm-9pm" is 7 PM, "7 PM - midnight" too);
    /// then a 24-hour one, only with two hour digits or past 12 ("19:00", "07:30", not a
    /// bare "7:00", which could be either); then "noon" or "midnight". A word before any
    /// digit wins over all of them.
    static func minutes(_ raw: String?) -> Int? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty
        else { return nil }
        // A word ahead of any digit starts it: "noon-2pm" is noon, "midnight to 2 AM" midnight.
        let firstDigit = text.firstIndex(where: \.isNumber) ?? text.endIndex
        for (word, minutes) in [("noon", 12 * 60), ("midnight", 0)] {
            if let found = text.range(of: word), found.lowerBound < firstDigit { return minutes }
        }
        if let m = text.firstMatch(of: #/(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s*m?\.?(?![a-z])/#) {
            guard var hour = Int(m.1), (1...12).contains(hour) else { return nil }
            let minute = m.2.flatMap { Int($0) } ?? 0
            guard minute < 60 else { return nil }
            if m.3 == "p", hour < 12 { hour += 12 }
            if m.3 == "a", hour == 12 { hour = 0 }
            return hour * 60 + minute
        }
        if let m = text.wholeMatch(of: #/(\d{1,2}):(\d{2})(?::\d{2})?/#),
           let hour = Int(m.1), let minute = Int(m.2),
           m.1.count == 2 || hour > 12, hour < 24, minute < 60 {
            return hour * 60 + minute
        }
        if text.contains("noon") { return 12 * 60 }
        if text.contains("midnight") { return 0 }
        return nil
    }
}
