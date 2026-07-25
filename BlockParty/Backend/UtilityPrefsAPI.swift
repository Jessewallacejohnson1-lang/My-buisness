//
//  UtilityPrefsAPI.swift
//  Block Party — per-user Utility Row preferences over user_utility_prefs
//  (own-row RLS). Upsert uses merge-duplicates (needs the table's UPDATE policy —
//  see the migration). Hand-rolled PostgREST, like the other APIs.
//

import Foundation

struct UtilityPrefsRow: Decodable, Equatable {
    let userId: String
    let tiles: [String]
    let settings: [String: TileSettings]
    let updatedAt: Date
}

struct UtilityPrefsAPI {
    let auth: AuthStore
    init(auth: AuthStore) { self.auth = auth }

    /// The signed-in user's row, or nil if they have never saved.
    func getMine() async throws -> UtilityPrefsRow? {
        let token = try await auth.validAccessToken()
        guard let uid = auth.userId else { return nil }
        let query = "select=*&user_id=eq.\(uid)&limit=1"
        let (data, _) = try await SupabaseHTTP.rest("user_utility_prefs", query: query, accessToken: token)
        return try SupabaseCoding.decoder.decode([UtilityPrefsRow].self, from: data).first
    }

    /// Upsert the user's tiles + settings. merge-duplicates emits ON CONFLICT DO
    /// UPDATE, which requires the UPDATE RLS policy on user_utility_prefs.
    func upsert(tiles: [String], settings: [String: TileSettings]) async throws {
        let token = try await auth.validAccessToken()
        guard let uid = auth.userId else { throw SupabaseError(message: "Not signed in.", status: 401) }
        let body = try SupabaseCoding.encoder.encode(UpsertBody(userId: uid, tiles: tiles, settings: settings))
        _ = try await SupabaseHTTP.rest("user_utility_prefs", method: "POST",
                                        query: "on_conflict=user_id",
                                        accessToken: token, body: body,
                                        prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// Encoded with SupabaseCoding.encoder → userId becomes user_id; the `settings`
    /// dictionary keys (tile ids) and TileSettings keys are left as-is.
    private struct UpsertBody: Encodable {
        let userId: String
        let tiles: [String]
        let settings: [String: TileSettings]
    }
}
