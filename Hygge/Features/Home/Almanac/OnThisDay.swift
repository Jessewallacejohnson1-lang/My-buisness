//
//  OnThisDay.swift
//  Hygge — client for the curated `town_almanac` table.
//
//  Contract: town_almanac(md text PK 'MM-DD', fact text, source text, link text),
//  seeded sparsely (real, cited St. Joe facts) via the Supabase migration in
//  supabase/migrations/. Looked up by today's calendar day (MM-dd, in the given
//  timezone) — most days have no row, which is expected: the Almanac card hides
//  the on-this-day line when this returns nil.
//
//  Never throws to the caller — a network/decoding failure swallows to nil for
//  calm degradation, same discipline as DailyAlmanac. Same once-per-day cache
//  shape as DailyAlmanac, but keyed by the MM-dd string rather than a TTL: a
//  successful lookup (row or no row) is cached until the calendar day rolls
//  over, while an outright network failure is left uncached so the next call
//  can retry instead of sticking on a false "no fact today".
//

import Foundation

/// A single curated, cited "on this day in St. Joe" fact.
struct AlmanacFact {
    let fact: String
    let source: String?
    let link: String?
}

/// In-memory once-per-day cache, keyed by the `MM-dd` string being looked up.
private enum OnThisDayCache {
    static var cached: (key: String, fact: AlmanacFact?)?
}

/// Fixed `MM-dd` formatter — `en_US_POSIX` so the day string never reflects the
/// user's locale/calendar settings, only the calendar day in the given timezone.
private let mdFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MM-dd"
    return f
}()

/// Today's curated almanac fact for `date` in `tz`, or nil when `town_almanac`
/// has no row for that calendar day (the common case while the table is
/// sparsely seeded) or the lookup failed. Never throws.
func onThisDay(_ date: Date = Date(), tz: TimeZone = .current, auth: AuthStore) async -> AlmanacFact? {
    mdFormatter.timeZone = tz
    let md = mdFormatter.string(from: date)

    if let cached = OnThisDayCache.cached, cached.key == md {
        return cached.fact
    }

    guard let token = try? await auth.validAccessToken() else { return nil }

    struct Row: Decodable {
        let fact: String
        let source: String?
        let link: String?
    }

    guard let (data, _) = try? await SupabaseHTTP.rest(
        "town_almanac",
        query: "select=md,fact,source,link&md=eq.\(md)&limit=1",
        accessToken: token
    ), let rows = try? JSONDecoder().decode([Row].self, from: data) else {
        return nil   // network/decode failure — leave uncached so the next call retries
    }

    let result = rows.first.map { AlmanacFact(fact: $0.fact, source: $0.source, link: $0.link) }
    OnThisDayCache.cached = (md, result)
    return result
}
