//
//  FeedModuleID.swift
//  Block Party — stable identity for Today feed modules.
//
//  String-backed rather than a closed enum so an id persisted or served by a
//  newer build still decodes and can be skipped safely by FeedRegistry.
//
//  This architecture deliberately uses `AnyView` through `FeedModule.makeView`.
//  That overrides BriefingModuleID.swift's earlier argument against type erasure:
//  the accepted cost buys the stronger contract that adding a module edits only
//  FeedRegistry, never the Today screen.
//

import Foundation

nonisolated struct FeedModuleID: RawRepresentable, Hashable, Codable,
                                 ExpressibleByStringLiteral, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let almanac: FeedModuleID = "almanac"
    static let yourDay: FeedModuleID = "yourDay"
    static let trivia: FeedModuleID = "trivia"
    static let spotlight: FeedModuleID = "spotlight"
    static let signOff: FeedModuleID = "signOff"
}

// MARK: - Date label

nonisolated enum BriefingDate {
    /// "WEDNESDAY, AUGUST 5" for a payload's `briefing_date`, via the app's
    /// single date-string definition so the footer and almanac cannot disagree.
    static func eyebrow(for briefingDate: String) -> String? {
        guard let date = parse(briefingDate) else { return nil }
        return TodayHeader.eyebrow(for: date)
    }

    /// Parses "YYYY-MM-DD" against the town's Gregorian calendar.
    static func parse(_ briefingDate: String) -> Date? {
        let parts = briefingDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components).flatMap {
            calendar.component(.day, from: $0) == parts[2] ? $0 : nil
        }
    }
}
