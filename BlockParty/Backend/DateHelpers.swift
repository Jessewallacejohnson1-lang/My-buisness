//
//  DateHelpers.swift
//  Block Party — timezone-correct date helpers, ported from packages/core/src/db.ts.
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

    /// Whole-day difference between two YYYY-MM-DD strings (b − a), parsed local.
    /// nil on parse failure. Used to detect an event's recurrence cadence.
    nonisolated static func daysBetween(_ a: String, _ b: String) -> Int? {
        let pa = a.split(separator: "-").compactMap { Int($0) }
        let pb = b.split(separator: "-").compactMap { Int($0) }
        guard pa.count == 3, pb.count == 3 else { return nil }
        var ca = DateComponents(); ca.year = pa[0]; ca.month = pa[1]; ca.day = pa[2]
        var cb = DateComponents(); cb.year = pb[0]; cb.month = pb[1]; cb.day = pb[2]
        let cal = Calendar.current
        guard let da = cal.date(from: ca), let db = cal.date(from: cb) else { return nil }
        return cal.dateComponents([.day], from: cal.startOfDay(for: da), to: cal.startOfDay(for: db)).day
    }

    // MARK: Display-time parsing — ported from apps/mobile/src/lib/time.ts.
    // start_time is a free-text display string ("7am", "10 AM", "noon", nil);
    // parse to minutes-from-midnight only for sorting / liveness, never an axis.

    /// Free-text display time → minutes from midnight; undated/unparseable → end of day.
    static func minutesOf(_ s: String?) -> Int {
        guard let raw = s?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty
        else { return 24 * 60 }
        if raw.contains("noon") { return 12 * 60 }
        if raw.contains("midnight") { return 0 }
        guard let m = raw.range(of: #"(\d{1,2})(?::(\d{2}))?\s*(a|p)"#, options: .regularExpression)
        else { return 24 * 60 }
        let match = String(raw[m])
        let digits = match.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var h = digits.first else { return 24 * 60 }
        let min = digits.count > 1 ? digits[1] : 0
        let isPM = match.contains("p")
        if isPM && h < 12 { h += 12 }
        if !isPM && h == 12 { h = 0 }
        return h * 60 + min
    }

    /// Current wall-clock minutes from midnight, in the local timezone.
    /// Uses TimeZone.current explicitly — Calendar.current caches the system
    /// zone and can disagree with TimeZone.current (which honors the TZ env).
    static func nowMinutes(_ d: Date = Date()) -> Int {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Live right now: the start time has arrived and it's within the last two
    /// hours — not just "some time today." Untimed events are never live.
    static func isLiveNow(_ startTime: String?, now: Int = nowMinutes()) -> Bool {
        guard startTime != nil else { return false }
        let start = minutesOf(startTime)
        guard start < 24 * 60 else { return false } // unparseable / all-day
        return now >= start && now <= start + 120
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
