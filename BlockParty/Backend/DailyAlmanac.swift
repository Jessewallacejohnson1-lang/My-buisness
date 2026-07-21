//
//  DailyAlmanac.swift
//  Block Party — client for the `daily-almanac` Supabase Edge Function.
//
//  Contract (my-business repo: supabase/functions/daily-almanac/index.ts):
//    POST /functions/v1/daily-almanac  ->  { "line": String?, "format"?, "cached"? }
//  The function reads THIS user's real day server-side (sun + weather + moon + season
//  + their RSVPs + town pulse + their own history), picks a format, and returns ONE
//  warm, AI-written line personalized to them — cached one-per-user-per-day. The user
//  is identified from the Bearer JWT we send below. nil on any failure — the Almanac
//  card then keeps its honest on-device template nudge (the static weather sentence).
//
//  Same 30-min cache discipline as WeatherService (the line is stable within a session).
//  We cache only successes, so a transient failure retries on the next tab open rather
//  than sticking on the template.
//

import Foundation

enum DailyAlmanac {
    private static var cached: (line: String, day: String, at: Date)?
    private static let ttl: TimeInterval = 30 * 60  // 30 minutes, within a single town-day

    /// This user's personalized line for today, or nil to fall back to the template nudge.
    static func line(auth: AuthStore) async -> String? {
        // Serve the cache only within the SAME town-day and the TTL, so a line can never
        // carry past local midnight (the server keys its own cache by date too), and the
        // 30-min TTL lets a mid-day server refresh land on the next open.
        let today = townDayStamp()
        if let c = cached, c.day == today, Date().timeIntervalSince(c.at) < ttl { return c.line }
        guard let token = try? await auth.validAccessToken() else { return nil }

        var req = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/daily-almanac"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = (obj["line"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty
        else { return nil }

        cached = (line, today, Date())
        return line
    }

    /// Today's date (yyyy-MM-dd) in the town's timezone — matches the server's date key.
    private static func townDayStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = WeatherService.townTZ
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
