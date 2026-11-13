//
//  MeetingRule.swift
//  Block Party — when something meets, as its rule says it: a Group's (`clubs.meets`, BP app rsvp-and-groups 05) and a
//  school club's (`team_activities.meets`, nothing-scheduled 03), and the one way the app says it: "Fridays · 8 AM",
//  "Wednesdays · After school", "2nd Tuesday of each month". The weekly pattern, never a computed date: a school's
//  pattern doesn't know its days off (Jesse, 2026-11-13).
//

import Foundation

nonisolated struct MeetingRule: Decodable, Hashable, Sendable {
    /// "mon" … "sun".
    let days: [String]
    /// The weeks of the month it meets, 1 to 5 ("2nd Tuesday"); nil or empty: every week.
    let weeks: [Int]?
    /// 2: every other week.
    let every: Int?
    /// "08:00", or the school's own words when it gives no clock ("After school"); nil when it doesn't say.
    let time: String?

    private enum CodingKeys: String, CodingKey { case days, weeks, every, time }

    /// A field of the wrong kind reads as missing, and a rule that isn't an object as one with no day: one mistyped
    /// rule costs only itself, as `group_meetings`' guard has it.
    init(from decoder: Decoder) {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        days = (try? c?.decodeIfPresent([String].self, forKey: .days)) ?? []
        weeks = try? c?.decodeIfPresent([Int].self, forKey: .weeks)
        every = try? c?.decodeIfPresent(Int.self, forKey: .every)
        time = try? c?.decodeIfPresent(String.self, forKey: .time)
    }

    /// "Fridays · 8 AM", "Every other Friday · 7:45 AM", "1st and 3rd Monday of each month · 8 AM"; nil with no day it
    /// knows.
    var words: String? {
        let names = days.compactMap { Self.dayNames[String($0.prefix(3)).lowercased()] }
        guard !names.isEmpty else { return nil }
        let weeks = (weeks ?? []).filter { (1...5).contains($0) }
        let pattern = if !weeks.isEmpty {
            Self.list(weeks.map { Self.ordinals[$0 - 1] }) + " " + Self.list(names) + " of each month"
        } else if every == 2 {
            "Every other " + Self.list(names)
        } else {
            Self.list(names.map { $0 + "s" })
        }
        return [pattern, clock].compactMap { $0 }.joined(separator: " · ")
    }

    /// "8 AM" from "08:00"; words the school wrote, as written; nil when it doesn't say.
    private var clock: String? {
        guard let text = time?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return EventWhen.minutes(text).map { Town.clock(minutes: $0) } ?? text
    }

    /// "Tuesdays and Thursdays"; "1st, 2nd and 3rd".
    private static func list(_ parts: [String]) -> String {
        parts.count < 3 ? parts.joined(separator: " and ")
            : parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

    private static let ordinals = ["1st", "2nd", "3rd", "4th", "5th"]
    private static let dayNames = ["mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday",
                                   "fri": "Friday", "sat": "Saturday", "sun": "Sunday"]
}
