//
//  SpotlightWeek.swift
//  Block Party — town-time weekly spotlight identity and presentation rules.
//

import CoreLocation
import Foundation

/// The ISO week that owns a spotlight. Payload dates are parsed as town calendar
/// dates before ISO week components are read, so a traveling phone and a UTC
/// boundary cannot rotate St. Joseph's subject early.
nonisolated enum SpotlightWeek {
    static func identifier(for briefingDate: String) -> String? {
        guard let date = BriefingDate.parse(briefingDate) else { return nil }
        return identifier(for: date)
    }

    static func identifier(for date: Date) -> String? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = Town.timeZone
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let year = components.yearForWeekOfYear,
              let week = components.weekOfYear
        else { return nil }
        return String(format: "%04d-W%02d", year, week)
    }
}

/// Executable model of the append-only server assignment table. The SQL
/// migration uses the same first-write-wins rule for one row per ISO week.
nonisolated struct SpotlightArchive {
    private var assignments: [String: String] = [:]

    mutating func assign(spotlightID: String, for briefingDate: String) {
        guard let week = SpotlightWeek.identifier(for: briefingDate),
              assignments[week] == nil
        else { return }
        assignments[week] = spotlightID
    }

    func spotlightID(for briefingDate: String) -> String? {
        guard let week = SpotlightWeek.identifier(for: briefingDate) else { return nil }
        return assignments[week]
    }
}

nonisolated enum SignOffCopy {
    static func line(for briefingDate: String) -> String {
        guard let date = BriefingDate.parse(briefingDate) else {
            return "That's St. Joe for today. See you tomorrow."
        }
        return line(for: date)
    }

    static func line(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "EEEE"
        return "That's St. Joe for \(formatter.string(from: date)). See you tomorrow."
    }
}

/// A map action exists only when the server has linked the spotlight to a
/// persisted `places.id`. Known civic subjects use their reviewed town pin;
/// future businesses fall back to an Apple Maps query until their coordinate is
/// added to the briefing contract.
nonisolated enum SpotlightMapLink {
    static func url(
        placeID: String?,
        title: String,
        coordinate: CLLocationCoordinate2D? = nil
    ) -> URL? {
        guard let placeID,
              !placeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        var components = URLComponents(string: "http://maps.apple.com/")
        var items = [URLQueryItem(name: "q", value: title)]
        if let coordinate {
            items.append(
                URLQueryItem(
                    name: "ll",
                    value: "\(coordinate.latitude),\(coordinate.longitude)"
                )
            )
        } else {
            items[0] = URLQueryItem(name: "q", value: "\(title), St. Joseph, MN")
        }
        components?.queryItems = items
        return components?.url
    }
}
