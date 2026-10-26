//
//  DateHelpers.swift
//  Block Party — timezone-correct date helpers, ported from packages/core/src/db.ts.
//
//  THE most important correctness rule: dates are computed in the device-LOCAL
//  timezone, never UTC. An evening event must stay on "today".
//

import Foundation

enum DateHelpers {
    /// Now ± n days.
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

    /// A Postgres `timestamptz` column (`club_events.end_at`) → `Date`.
    ///
    /// PostgREST emits fractional seconds only when the stored value has them, so
    /// both shapes have to parse or an event silently loses its end time. Returns
    /// nil for nil/blank/garbage rather than substituting a date — callers treat a
    /// missing end as "we were not told", never as "ends now".
    nonisolated static func timestamp(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty
        else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: s) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
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
