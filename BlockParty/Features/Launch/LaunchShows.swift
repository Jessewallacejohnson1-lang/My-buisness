//
//  LaunchShows.swift
//  Block Party — which launch a cold start plays. The day's first two play the whole show; the
//  rest its short cut (Jesse, 2026-11-08: "yes, if you're saying the first few times a day", then
//  "2"). Kept on the phone as "yyyy-mm-dd n".
//

import Foundation

nonisolated enum LaunchShows {
    static let fullShowsADay = 2
    static let key = "launch.fullShows"

    /// The kind this start plays, counting it, and the record to keep.
    static func next(now: Date, calendar: Calendar, record: String?) -> (kind: LaunchMotion.Kind, record: String) {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        var shown = 0
        if let record, record.hasPrefix(day + " ") { shown = Int(record.dropFirst(day.count + 1)) ?? 0 }
        let kind: LaunchMotion.Kind = shown < fullShowsADay ? .full : .short
        return (kind, "\(day) \(shown + 1)")
    }

    /// This start's kind, counted on the phone.
    static func kind(now: Date = .now, defaults: UserDefaults = .standard) -> LaunchMotion.Kind {
        let pick = next(now: now, calendar: .current, record: defaults.string(forKey: key))
        defaults.set(pick.record, forKey: key)
        return pick.kind
    }
}
