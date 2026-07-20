//
//  ProfileAPI.swift
//  Block Party — the community-profile query layer (name · avatar · interests),
//  hand-rolled over PostgREST like CommunityAPI. Writes to `town_profiles`
//  (own-row RLS). Separate from the wellness app's `profiles` table.
//

import Foundation

struct ProfileAPI {
    let auth: AuthStore

    private func token() async throws -> String { try await auth.validAccessToken() }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    /// The signed-in user's row, or nil if they have none yet. RLS scopes the
    /// select to the caller, so no explicit user_id filter is needed.
    func getMyProfile() async throws -> TownProfile? {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("town_profiles",
            query: "select=user_id,display_name,avatar_url,interests,onboarded_at&limit=1",
            accessToken: t)
        let rows: [TownProfile] = try decode(data)
        return rows.first
    }

    /// Upsert the caller's profile. `onboarded` stamps `onboarded_at` so a
    /// reinstall/new device can skip onboarding. Idempotent (PK = user_id).
    func upsert(displayName: String?, avatarUrl: String?,
                interests: [String], onboarded: Bool) async throws {
        let t = try await token()
        guard let uid = auth.userId else { throw SupabaseError(message: "Not signed in", status: 401) }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = iso.string(from: Date())

        var b: [String: Any] = [
            "user_id": uid,
            "interests": interests,
            "updated_at": now,
        ]
        b["display_name"] = displayName ?? NSNull()
        b["avatar_url"]   = avatarUrl ?? NSNull()
        if onboarded { b["onboarded_at"] = now }

        let body = try JSONSerialization.data(withJSONObject: b)
        _ = try await SupabaseHTTP.rest("town_profiles", method: "POST",
            query: "on_conflict=user_id", accessToken: t, body: body,
            prefer: "resolution=merge-duplicates,return=minimal")
    }
}
