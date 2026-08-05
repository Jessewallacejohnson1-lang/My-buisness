//
//  BriefingAPI.swift
//  Block Party — the Today tab's whole read path, in one round trip.
//
//  `get_today_briefing` is a SECURITY DEFINER RPC granted only to `authenticated`
//  (the anon key ships in the binary, so a definer function must never be callable
//  by `anon`). It returns the entire BriefingPayload as one jsonb object.
//
//  Follows the two existing RPC call sites in SocialAPI verbatim: POST to
//  rest/v1/rpc/<name> with a JSON argument body.
//

import Foundation

enum BriefingAPIError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You need to be signed in to vote."
        }
    }
}

struct BriefingAPI {
    let auth: AuthStore
    init(auth: AuthStore) { self.auth = auth }

    /// The briefing for `date` (defaults to today, town-anchored server-side).
    /// Returns the decoded payload alongside the raw bytes so the cache can store
    /// exactly what the server sent rather than a re-encoding of it.
    func today(tz: String = Town.timeZone.identifier) async throws -> (payload: BriefingPayload, raw: Data) {
        let token = try await auth.validAccessToken()
        let body = try JSONSerialization.data(withJSONObject: ["p_tz": tz])
        let (data, _) = try await SupabaseHTTP.rest(
            "rpc/get_today_briefing", method: "POST", accessToken: token, body: body
        )
        let payload = try SupabaseCoding.decoder.decode(BriefingPayload.self, from: data)
        return (payload, data)
    }

    /// Casts the caller's vote. `touch_votes` has an own-row INSERT policy and no
    /// UPDATE policy, so this MUST use `resolution=ignore-duplicates`:
    /// `merge-duplicates` emits ON CONFLICT DO UPDATE and returns 42501. A vote is
    /// final in v1, so a duplicate is a no-op rather than an error.
    func vote(touchId: String, optionIndex: Int) async throws {
        guard let uid = auth.userId else { throw BriefingAPIError.notSignedIn }
        let token = try await auth.validAccessToken()
        let body = try JSONSerialization.data(withJSONObject: [
            "touch_id": touchId,
            "user_id": uid,
            "option_idx": optionIndex,
        ])
        _ = try await SupabaseHTTP.rest(
            "touch_votes", method: "POST",
            query: "on_conflict=touch_id,user_id",
            accessToken: token, body: body,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }
}
