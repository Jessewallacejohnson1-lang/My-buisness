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
            query: "select=user_id,display_name,avatar_url,interests,onboarded_at,plans_to_friends,suggest_me&limit=1",
            accessToken: t)
        let rows: [TownProfile] = try decode(data)
        return rows.first
    }

    /// Upsert the caller's profile. `onboarded` stamps `onboarded_at` so a
    /// reinstall/new device can skip onboarding. Idempotent (PK = user_id).
    func upsert(displayName: String?, avatarUrl: String?,
                interests: [String], onboarded: Bool) async throws {
        let t = try await token()
        guard let uid = auth.userId else { throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401) }

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

    /// Stamp `onboarded_at` on the caller's row, making it if there is none yet (the quiet
    /// anonymous account has none). Only those two columns travel, so a name, photo or
    /// interests already there are left alone (BP app onboarding 16).
    func markOnboarded(birthday: Date? = nil) async throws {
        let t = try await token()
        guard let uid = auth.userId else { throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var row = ["user_id": uid, "onboarded_at": iso.string(from: Date())]
        // Onboarding's birthday (ticket 19), private to this account.
        if let birthday { row["birthday"] = OnboardingAge.day.format(birthday) }
        let body = try JSONSerialization.data(withJSONObject: row)
        _ = try await SupabaseHTTP.rest("town_profiles", method: "POST",
            query: "on_conflict=user_id", accessToken: t, body: body,
            prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// Onboarding's name, photo and interests (BP app onboarding 18, 20) on the caller's row,
    /// making it if there is none yet. Only the answers given travel, so the onboarded stamp and
    /// anything left blank are left alone.
    func setNameAndPhoto(displayName: String?, avatarUrl: String?, interests: [String] = []) async throws {
        let t = try await token()
        guard let uid = auth.userId else { throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401) }
        var b: [String: Any] = ["user_id": uid]
        if let displayName { b["display_name"] = displayName }
        if let avatarUrl { b["avatar_url"] = avatarUrl }
        if !interests.isEmpty { b["interests"] = interests }
        let body = try JSONSerialization.data(withJSONObject: b)
        _ = try await SupabaseHTTP.rest("town_profiles", method: "POST",
            query: "on_conflict=user_id", accessToken: t, body: body,
            prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// One of Profile's switches, "plans_to_friends" (town-feed 28) or "suggest_me" (daily-tab
    /// 22): only that column of the caller's own row, so a tap never touches their name or photo.
    func setSwitch(_ column: String, _ on: Bool) async throws {
        let t = try await token()
        guard let uid = auth.userId else { throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401) }
        let body = try JSONSerialization.data(withJSONObject: [column: on])
        _ = try await SupabaseHTTP.rest("town_profiles", method: "PATCH", query: "user_id=eq.\(uid)",
                                        accessToken: t, body: body, prefer: "return=minimal")
    }
}
