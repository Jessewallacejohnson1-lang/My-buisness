//
//  BriefingModuleID.swift
//  Block Party — what the Today briefing is made of, and in what order.
//
//  `order` is the single source of truth for the screen's composition. Adding a
//  v2 module is one constant, one entry in that array, and one case in
//  HomeView's `module(_:)` switch — no other file changes.
//
//  String-backed rather than a closed enum, for the same reason `UtilityTileID`
//  is: an id persisted or served by a newer build must decode and be skipped,
//  not crash the tab.
//
//  Deliberately NOT a descriptor registry like `UtilityTileRegistry`. That one
//  carries providers and a settings editor because tiles are data-driven and
//  user-reorderable. Briefing modules are neither — they are a fixed editorial
//  running order — so an ordered array plus one switch is the honest amount of
//  structure, and it avoids paying for AnyView on the app's most-seen screen.
//

import Foundation

nonisolated struct BriefingModuleID: RawRepresentable, Hashable, Codable,
                                     ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    var description: String { rawValue }

    // MARK: - The v1 modules

    /// The existing almanac card. Stays at the top; it is the thing people open for.
    static let almanac: BriefingModuleID = "almanac"
    /// The existing utility row, unchanged. It owns its own loading, caching and
    /// realtime, and is not fed by the briefing payload.
    static let utility: BriefingModuleID = "utility"
    /// 1-3 curated events, or the evergreen fallback when there are none.
    static let happeningSoon: BriefingModuleID = "happeningSoon"
    /// The daily poll.
    static let dailyTouch: BriefingModuleID = "dailyTouch"
    /// One place worth noticing today.
    static let spotlight: BriefingModuleID = "spotlight"
    /// The end of the briefing. This is what makes the screen finite.
    static let caughtUp: BriefingModuleID = "caughtUp"

    /// Top to bottom. The whole running order lives here.
    static let order: [BriefingModuleID] = [
        .almanac, .utility, .happeningSoon, .dailyTouch, .spotlight, .caughtUp,
    ]
}

// MARK: - Date label

nonisolated enum BriefingDate {
    /// "WEDNESDAY, AUGUST 5" for a payload's `briefing_date`, via the app's single
    /// date-string definition (`TodayHeader.eyebrow`), so the footer and the
    /// almanac card cannot disagree about what day it is.
    static func eyebrow(for briefingDate: String) -> String? {
        guard let date = parse(briefingDate) else { return nil }
        return TodayHeader.eyebrow(for: date)
    }

    /// "YYYY-MM-DD" in the town's timezone. The briefing is anchored to the town,
    /// so the string is parsed against `Town.calendar`, never the device's.
    static func parse(_ briefingDate: String) -> Date? {
        let parts = briefingDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }

        // A Gregorian calendar explicitly, NOT `Town.calendar` — that is
        // `Calendar.current` with only the timezone replaced, so it keeps the
        // user's calendar IDENTIFIER. Feeding a Gregorian "YYYY-MM-DD" to a
        // Buddhist or Japanese calendar yields a date centuries off, or nil.
        // `DateHelpers.localDate` and `BriefingModel.townToday` both pin Gregorian
        // for the same reason.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Town.timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12          // midday, so no DST edge can roll the date
        // Strict, so "2026-13-45" fails instead of rolling into the next year.
        return cal.date(from: components).flatMap {
            cal.component(.day, from: $0) == parts[2] ? $0 : nil
        }
    }
}
