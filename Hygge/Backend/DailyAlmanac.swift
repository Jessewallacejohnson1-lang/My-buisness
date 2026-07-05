//
//  DailyAlmanac.swift
//  Hygge — client for the `daily-almanac` Supabase Edge Function.
//
//  Contract (supabase/functions/daily-almanac/index.ts):
//    POST /functions/v1/daily-almanac  ->  { "line": String? }
//  The function gathers the town's real day server-side (sun + weather + today's
//  events + quest) and returns ONE calm, AI-written line the whole town shares.
//  nil on any failure — the Almanac card then keeps its honest template nudge.
//
//  Same 30-min cache discipline as WeatherService (the line is town-wide and
//  stable within a session). We cache only successes, so a transient failure
//  retries on the next tab open rather than sticking on the template.
//

import Foundation

enum DailyAlmanac {
    private static var cached: (line: String, at: Date)?
    private static let ttl: TimeInterval = 30 * 60  // 30 minutes

    /// Today's shared town summary, or nil to fall back to the template nudge.
    static func line(auth: AuthStore) async -> String? {
        if let c = cached, Date().timeIntervalSince(c.at) < ttl { return c.line }
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

        cached = (line, Date())
        return line
    }
}
