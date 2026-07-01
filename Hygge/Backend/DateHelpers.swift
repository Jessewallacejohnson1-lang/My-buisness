//
//  DateHelpers.swift
//  Hygge — timezone-correct date helpers, ported from packages/core/src/db.ts.
//
//  THE most important correctness rule: dates are computed in the device-LOCAL
//  timezone, never UTC. An evening event must stay on "today".
//

import Foundation

enum DateHelpers {
    /// "YYYY-MM-DD" in the local timezone (mirrors localDate()'s en-CA output).
    static func localDate(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Now ± n days (callers wrap with localDate()).
    static func addDays(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
    }

    /// Friendly label ("Sat, Jul 5") for a YYYY-MM-DD string, parsed as local.
    static func prettyDate(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return ymd }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let date = Calendar.current.date(from: c) else { return ymd }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    /// Short weekday ("Sat") for a YYYY-MM-DD string, parsed as a local date.
    static func weekdayLabel(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let date = Calendar.current.date(from: c) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

/// Admin gate — mirrors isAdminEmail / DEFAULT_ADMIN_EMAIL from @hygge/core.
enum Admin {
    static let defaultEmail = "jessewallacejohnson1@icloud.com"
    static func isAdmin(_ email: String?) -> Bool {
        guard let email, !email.isEmpty else { return false }
        return email.lowercased() == defaultEmail.lowercased()
    }
}

/// firstNameFromEmail — strip trailing digits, take the first token, capitalize.
func firstNameFromEmail(_ email: String?) -> String? {
    guard let email, !email.isEmpty else { return nil }
    let local = email.split(separator: "@").first.map(String.init) ?? ""
    let noDigits = local.replacingOccurrences(of: "[0-9]+$", with: "", options: .regularExpression)
    let token = noDigits.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" }).first.map(String.init) ?? ""
    guard !token.isEmpty, token.count <= 12 else { return nil }
    return token.prefix(1).uppercased() + token.dropFirst()
}
