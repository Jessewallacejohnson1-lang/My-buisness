//
//  SupabaseConfig.swift
//  Hygge — Supabase project coordinates.
//
//  The anon key is public by design (it only grants what Row-Level Security
//  allows), so it's safe to ship in the app. Same project as the Expo app —
//  values mirror apps/mobile/.env.
//

import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://lxdgwhvqjqmqliobwjpi.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx4ZGd3aHZxanFtcWxpb2J3anBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjU3MTEsImV4cCI6MjA5NjcwMTcxMX0.WrwYA1NN8pOy5iOqljBJHys15CqpVAbUEFeqiriwmb0"

    static var restURL: URL { url.appendingPathComponent("rest/v1") }
    static var authURL: URL { url.appendingPathComponent("auth/v1") }
    static var storageURL: URL { url.appendingPathComponent("storage/v1") }

    /// Realtime (Phoenix) WebSocket endpoint: wss with the anon apikey + protocol
    /// version baked into the query. RLS still governs which rows a subscriber
    /// receives — the socket joins with the signed-in user's access token.
    static var realtimeURL: URL {
        var comps = URLComponents(url: url.appendingPathComponent("realtime/v1/websocket"),
                                  resolvingAgainstBaseURL: false)!
        comps.scheme = "wss"
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: anonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        return comps.url!
    }
}
