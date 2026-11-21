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
        return prettyFormatter.string(from: date)
    }

    /// Display only (text on screen), built once: "Sat, Jul 5" in the phone's own zone.
    private static let prettyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

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

    // MARK: - Reading the server's dates
    //
    // The one owner of turning the server's date strings into `Date`s, and of writing the
    // timestamps the app sends back. Every caller goes through these; nobody builds their
    // own `ISO8601DateFormatter` to read a server string. Shapes the server sends:
    //
    //   timestamptz  "2026-10-24T18:21:32.123456+00:00", "2026-10-24T18:21:32+00:00",
    //                "2026-10-24T18:21:32Z"                         → `timestamp(_:)`
    //   date         "2026-10-31" (`club_events.event_date`)        → `townDay(_:)`
    //   free time    "7:00 PM", "19:00" (`club_events.start_time`)  → `EventWhen.minutes`
    //
    // `nonisolated`: the module defaults to MainActor, and these run off it (decoders,
    // `CommunityAPI`). The ISO 8601 styles are Sendable values, so one copy serves every thread.

    /// A Postgres `timestamptz` (`club_events.end_at`, `created_at`, a live score's `at`) → `Date`.
    ///
    /// PostgREST emits fractional seconds only when the stored value has them, so
    /// both shapes have to parse or an event silently loses its end time. Either a `Z` or a
    /// numeric offset (`+00:00`, `-05:00`). Returns nil for nil/blank/garbage rather than
    /// substituting a date — callers treat a missing end as "we were not told", never as
    /// "ends now".
    nonisolated static func timestamp(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty
        else { return nil }
        return (try? fractional.parse(s)) ?? (try? whole.parse(s))
    }

    /// Foundation's Swift readers and writer: the strings `ISO8601DateFormatter` read and wrote, 0.4 us each where it
    /// took 60 to 100 on the Mac. The feed's read of hundreds of rows lands on the main thread, and froze a tap there
    /// (BP app tab-lag 02).
    private nonisolated static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private nonisolated static let whole = Date.ISO8601FormatStyle()

    /// A `Date` as the timestamp the app sends the server ("2026-11-01T17:05:09Z"): UTC,
    /// whole seconds, the same string a default ISO 8601 formatter writes.
    nonisolated static func timestampString(_ date: Date) -> String {
        whole.format(date)
    }

    /// A Postgres `date` ("2026-10-31") → that day's midnight on the Town's clock
    /// (America/Chicago), wherever the phone is. nil when it isn't a real calendar day:
    /// "2026-02-30" or "Oct 31" read as nothing, never as a neighbouring day.
    ///
    /// Read from its numbers with `Town.gregorian`, not a `DateFormatter`, so a phone set to
    /// a non-Gregorian calendar cannot shift the year.
    nonisolated static func townDay(_ s: String?) -> Date? {
        guard let s else { return nil }
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, (1...2).contains(parts[1].count),
              (1...2).contains(parts[2].count), parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let calendar = Town.gregorian
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        // The calendar rolls an impossible day over ("Feb 30" → Mar 2); refuse it instead.
        let read = calendar.dateComponents([.year, .month, .day], from: date)
        guard read.year == year, read.month == month, read.day == day else { return nil }
        return date
    }
}
