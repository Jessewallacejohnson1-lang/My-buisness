//
//  SupabaseConfig.swift
//  Block Party — Supabase project coordinates.
//
//  The publishable key is public by design (it only grants what Row-Level Security
//  allows), so it's safe to ship in the app. It goes on `apikey` only, never as a Bearer token.
//

import Foundation

// nonisolated: these are immutable config constants (the module defaults to
// MainActor isolation), so off-main callers can read the derived URLs without
// hopping to the main actor.
nonisolated enum SupabaseConfig {
    static let url = URL(string: "https://lxdgwhvqjqmqliobwjpi.supabase.co")!
    static let publishableKey = "sb_publishable_9nPNN3sjU2jgwFaC9fvnMg_KIPaF40a"  // gitleaks:allow (public by design)

    static var restURL: URL { url.appendingPathComponent("rest/v1") }
    static var authURL: URL { url.appendingPathComponent("auth/v1") }
    static var storageURL: URL { url.appendingPathComponent("storage/v1") }

    /// Realtime (Phoenix) WebSocket endpoint: wss with the publishable apikey + protocol
    /// version baked into the query. RLS still governs which rows a subscriber
    /// receives — the socket joins with the signed-in user's access token.
    static var realtimeURL: URL {
        var comps = URLComponents(url: url.appendingPathComponent("realtime/v1/websocket"),
                                  resolvingAgainstBaseURL: false)!
        comps.scheme = "wss"
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: publishableKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        return comps.url!
    }
}
