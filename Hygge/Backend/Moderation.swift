//
//  Moderation.swift
//  Hygge — client for the `moderate-post` Supabase Edge Function (Claude review).
//
//  Contract (supabase/functions/moderate-post/index.ts):
//    POST /functions/v1/moderate-post  { kind, title, location, length, description, image_url }
//    -> { ok: Bool, reason: String }
//  Fail-open-to-queue: on any transport/5xx failure, return the queue sentinel so
//  the caller posts with status .pending rather than blocking the neighbor.
//

import Foundation

struct Moderation {
    let auth: AuthStore
    static let queueSentinel = "__queue__"

    /// `kind` is the free-form label the edge function shows Claude:
    /// "event", "trail", or "club".
    func check(kind: String, title: String, location: String?, length: String?,
               description: String?, imageUrl: String?) async -> (ok: Bool, reason: String) {
        guard let token = try? await auth.validAccessToken() else { return (false, Self.queueSentinel) }

        var payload: [String: Any] = ["kind": kind, "title": title]
        if let location { payload["location"] = location }
        if let length { payload["length"] = length }
        if let description { payload["description"] = description }
        if let imageUrl { payload["image_url"] = imageUrl }

        var req = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/moderate-post"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else {
            return (false, Self.queueSentinel)
        }
        guard (200..<300).contains(code),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, Self.queueSentinel)   // 5xx / bad body → queue, don't block
        }
        let ok = (obj["ok"] as? Bool) ?? false
        let reason = (obj["reason"] as? String) ?? ""
        return (ok, reason)
    }
}
