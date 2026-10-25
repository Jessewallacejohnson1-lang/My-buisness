//
//  PlaceHours.swift
//  Block Party — a place's weekly hours (`places.hours`) and what its business page says about
//  them right now: a green dot "Open till 9 PM", an orange "Closes soon · 9 PM" in its last half
//  hour, a red "Closed till Tue 4 PM" (Jesse, 2026-10-25; Reference Google Maps and Facebook,
//  BP app references/business-hours). Saved once from Google Maps, else the place's own website or
//  Facebook (Jesse: hours are a fact). Times are the Town's clock (`Town.calendar`), not the phone's.
//

import Foundation

/// `{"mon": [["16:00", "22:00"]], ..., "sun": []}`: each day's ranges, "HH:MM", an empty list
/// closed. A range that ends at or before its start runs past midnight ("16:00"–"01:00").
nonisolated struct PlaceHours: Decodable, Hashable, Sendable {
    /// Sunday first, as `Calendar` numbers weekdays (1 = Sunday).
    static let keys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    static let day = 24 * 60
    static let week = 7 * day
    /// The last half hour before closing says "Closes soon".
    static let soon = 30

    /// Minutes from local midnight, per weekday, Sunday first.
    let days: [[Range<Int>]]

    init(days: [[Range<Int>]]) { self.days = days }

    init(from decoder: Decoder) throws {
        // A day it can't read is a closed day, so one bad entry never costs the week.
        struct Day: Decodable {
            let pairs: [[String]]
            init(from decoder: Decoder) { pairs = (try? [[String]](from: decoder)) ?? [] }
        }
        let raw = (try? [String: Day](from: decoder)) ?? [:]
        days = Self.keys.map { key in
            (raw[key]?.pairs ?? []).compactMap { pair in
                guard pair.count == 2, let start = Self.minutes(pair[0]), let end = Self.minutes(pair[1]) else { return nil }
                return start ..< (end <= start ? end + Self.day : end)
            }
        }
    }

    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        let minutes = parts[0] * 60 + parts[1]
        return minutes <= day ? minutes : nil
    }

    enum Status: Equatable {
        case open(closes: Int)
        case closesSoon(closes: Int)
        /// `weekday` only when it isn't today, or tomorrow morning after a day it was open: on a
        /// closed Monday, "Closed till 9 AM" would read as this morning.
        case closed(opens: Int, weekday: Int?)
        case always
    }

    /// Open ranges across the week in minutes from Sunday midnight, joined where one runs into
    /// the next, so a bar open till 2 AM Saturday closes at 2, not at midnight.
    private var spans: [Range<Int>] {
        Self.join(days.enumerated().flatMap { day, ranges in
            ranges.map { ($0.lowerBound + day * Self.day) ..< ($0.upperBound + day * Self.day) }
        })
    }

    private static func join(_ spans: [Range<Int>]) -> [Range<Int>] {
        var joined: [Range<Int>] = []
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = joined.last, span.lowerBound <= last.upperBound {
                joined[joined.count - 1] = last.lowerBound ..< max(last.upperBound, span.upperBound)
            } else {
                joined.append(span)
            }
        }
        return joined
    }

    /// nil when the week has no opening at all.
    func status(at now: Date = .now, calendar: Calendar = Town.calendar) -> Status? {
        let spans = spans
        guard !spans.isEmpty else { return nil }
        if spans.count == 1, spans[0].count >= Self.week { return .always }
        let weekday = calendar.component(.weekday, from: now) - 1
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let t = weekday * Self.day + minute
        // A span from late Saturday reaches into the next week; lay last week and next week beside
        // this one and join them again, so Saturday night runs on into Sunday.
        let shifted = Self.join(spans.flatMap { span in
            [-Self.week, 0, Self.week].map { (span.lowerBound + $0) ..< (span.upperBound + $0) }
        })
        if let span = shifted.first(where: { $0.contains(t) }) {
            let closes = span.upperBound % Self.day
            return span.upperBound - t <= Self.soon ? .closesSoon(closes: closes) : .open(closes: closes)
        }
        guard let next = shifted.map(\.lowerBound).filter({ $0 > t }).min() else { return nil }
        let opens = next % Self.day
        let ahead = next / Self.day - t / Self.day
        let sameDay = ahead == 0 || (ahead == 1 && opens < 12 * 60 && !days[weekday].isEmpty)
        return .closed(opens: opens, weekday: sameDay ? nil : (next / Self.day) % 7 + 1)
    }

    /// The row's words after its dot: "Open till 9 PM", "Closes soon · 9 PM", "Closed till Tue 4 PM".
    static func words(_ status: Status) -> String {
        switch status {
        case .open(let closes): "Open till \(clock(closes))"
        case .closesSoon(let closes): "Closes soon · \(clock(closes))"
        case .closed(let opens, let weekday):
            "Closed till " + (weekday.map { shortDays[$0 - 1] + " " } ?? "") + clock(opens)
        case .always: "Open 24 hours"
        }
    }

    static let shortDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let longDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "9 PM", "9:30 PM", "12 AM".
    static func clock(_ minutes: Int) -> String {
        let m = minutes % day
        let hour = m / 60 % 12 == 0 ? 12 : m / 60 % 12
        let tail = m % 60 == 0 ? "" : String(format: ":%02d", m % 60)
        return "\(hour)\(tail) \(m < 12 * 60 ? "AM" : "PM")"
    }

    /// "4 – 10 PM", "11 AM – 9 PM", "4 PM – 1 AM"; one day's ranges joined with commas.
    static func line(_ ranges: [Range<Int>]) -> String {
        guard !ranges.isEmpty else { return "Closed" }
        if ranges.count == 1, ranges[0].lowerBound == 0, ranges[0].upperBound >= day { return "Open 24 hours" }
        return ranges.map { r in
            let start = clock(r.lowerBound), end = clock(r.upperBound)
            let samePart = (r.lowerBound < 12 * 60) == (r.upperBound % day < 12 * 60) && r.upperBound <= day
            return (samePart ? String(start.dropLast(3)) : start) + " – " + end
        }.joined(separator: ", ")
    }

    /// The week from today: ("Saturday", "12 – 9 PM", today?).
    func week(from now: Date = .now, calendar: Calendar = Town.calendar) -> [(day: String, hours: String, today: Bool)] {
        let today = calendar.component(.weekday, from: now) - 1
        return (0..<7).map { offset in
            let d = (today + offset) % 7
            return (Self.longDays[d], Self.line(days[d]), offset == 0)
        }
    }
}
