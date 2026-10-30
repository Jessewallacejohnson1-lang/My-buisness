//
//  ProfileAPI.swift
//  Block Party — the community-profile query layer (name · avatar · interests),
//  hand-rolled over PostgREST like CommunityAPI. Writes to `town_profiles`
//  (own-row RLS) and its photos to the public `avatars` bucket. Separate from the
//  wellness app's `profiles` table.
//

import Foundation

struct ProfileAPI {
    let db: Supabase

    init(auth: any TokenProviding, send: Supabase.Send = .live) { db = Supabase(auth: auth, send: send) }

    /// The signed-in user's row, or nil if they have none yet. RLS scopes the
    /// select to the caller, so no explicit user_id filter is needed.
    func getMyProfile() async throws -> TownProfile? {
        let rows: [TownProfile] = try Supabase.decode(await db.rest("town_profiles", [
            ("select", "user_id,display_name,avatar_url,interests,onboarded_at,plans_to_friends,suggest_me,bio,cover_url,created_at"),
            ("limit", "1"),
        ]))
        return rows.first
    }

    /// One profile's page extras (`get_profile`), yours or a neighbour's; nil for someone you
    /// may not find. Only a real account may ask.
    func getProfile(_ userId: String) async throws -> ProfileExtras? {
        let rows: [ProfileExtras] = try Supabase.decode(await db.rpc("get_profile", ["p_user": userId]))
        return rows.first
    }

    /// Upload a photo to the public `avatars` bucket at `{userId}/avatar-{ts}.jpg`
    /// (folder-scoped RLS), or a profile's cover at `{userId}/cover-{ts}.jpg` with `name`
    /// "cover", and answer its public URL. A refused upload, or no answer, throws, so the
    /// caller never saves a profile without the photo someone picked.
    func uploadPhoto(_ data: Data, name: String = "avatar") async throws -> String {
        let uid = try db.userID
        let path = "\(uid)/\(name)-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        return try await db.upload(bucket: "avatars", path: path, data, type: "image/jpeg").absoluteString
    }

    /// Upsert the caller's profile. `onboarded` stamps `onboarded_at` so a
    /// reinstall/new device can skip onboarding. Idempotent (PK = user_id).
    /// `bio` and `coverUrl` travel only when given: an anonymous account may set neither, so
    /// its Edit profile leaves them out (an empty bio goes as nil, "" clears it).
    func upsert(displayName: String?, avatarUrl: String?,
                interests: [String], onboarded: Bool,
                bio: String? = nil, coverUrl: String? = nil) async throws {
        let uid = try db.userID

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
        if let bio { b["bio"] = bio.isEmpty ? NSNull() : bio }
        if let coverUrl { b["cover_url"] = coverUrl }

        try await db.rest("town_profiles", method: "POST", [("on_conflict", "user_id")], body: b,
                          prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// Stamp `onboarded_at` on the caller's row, making it if there is none yet (the quiet
    /// anonymous account has none). Only these columns travel, so a name or photo already there
    /// is left alone (BP app onboarding 16).
    func markOnboarded(birthday: Date? = nil, interests: [String] = []) async throws {
        let uid = try db.userID
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var row: [String: Any] = ["user_id": uid, "onboarded_at": iso.string(from: Date())]
        // Onboarding's birthday (ticket 19), private to this account, and its picks (20): the two
        // answers the Town feed sorts by, in the same write, so its first read has them (24).
        if let birthday { row["birthday"] = OnboardingAge.day.format(birthday) }
        if !interests.isEmpty { row["interests"] = interests }
        try await db.rest("town_profiles", method: "POST", [("on_conflict", "user_id")], body: row,
                          prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// Onboarding's name, photo and interests (BP app onboarding 18, 20) on the caller's row,
    /// making it if there is none yet. Only the answers given travel, so the onboarded stamp and
    /// anything left blank are left alone.
    func setNameAndPhoto(displayName: String?, avatarUrl: String?, interests: [String] = []) async throws {
        var b: [String: Any] = ["user_id": try db.userID]
        if let displayName { b["display_name"] = displayName }
        if let avatarUrl { b["avatar_url"] = avatarUrl }
        if !interests.isEmpty { b["interests"] = interests }
        try await db.rest("town_profiles", method: "POST", [("on_conflict", "user_id")], body: b,
                          prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// One of Profile's switches, "plans_to_friends" (town-feed 28) or "suggest_me" (daily-tab
    /// 22): only that column of the caller's own row, so a tap never touches their name or photo.
    func setSwitch(_ column: String, _ on: Bool) async throws {
        let uid = try db.userID
        try await db.rest("town_profiles", method: "PATCH", [("user_id", "eq.\(uid)")], body: [column: on],
                          prefer: "return=minimal")
    }
}
