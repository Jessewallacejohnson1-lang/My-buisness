//
//  SocialAPI.swift
//  Block Party — the social layer (follow / like / save / comment writes), hand-rolled
//  over PostgREST like CommunityAPI and ProfileAPI. Net-new tables introduced by
//  the Today tab remake: `town_follows`, `event_likes`, `event_comments` (all on
//  the shared Supabase project — see
//  docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §5). The feed reads
//  that went with them left with `HomeModel`: the Town feed reads `get_town_feed`.
//

import Foundation

struct SocialAPI {
    let auth: AuthStore

    private struct IdRow: Decodable { let id: String }
    private struct SaveRow: Decodable { let eventId: String }

    // MARK: - Plumbing

    private func token() async throws -> String { try await auth.validAccessToken() }

    private func uidOrThrow() async throws -> String {
        guard let uid = auth.userId else { throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401) }
        return uid
    }

    /// Dual ISO-8601 fallback (plain, then fractional-seconds) — the same
    /// pattern used at CommunityAPI.swift's `BoardRow.timeLabel` and
    /// `ProfileModel.since`, wired here into the decoder itself so every
    /// `Date` field on a decoded row parses a Postgres timestamptz string.
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let d = Self.isoPlain.date(from: raw) ?? Self.isoFractional.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Unrecognized date: \(raw)")
        }
        return try dec.decode(T.self, from: data)
    }

    private func jsonBody(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Follows

    func follow(_ target: FollowTarget) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        // ignore-duplicates, not merge: a follow is presence, with no payload to
        // merge. merge-duplicates makes PostgREST emit ON CONFLICT DO UPDATE, and
        // town_follows has no UPDATE policy (by design — the row is immutable), so
        // re-following would fail RLS 42501. DO NOTHING needs no UPDATE policy.
        _ = try await SupabaseHTTP.rest("town_follows", method: "POST",
                                        query: "on_conflict=follower_id,target_type,target_id", accessToken: t,
                                        body: try jsonBody(["follower_id": uid, "target_type": target.type.rawValue, "target_id": target.id]),
                                        prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func unfollow(_ target: FollowTarget) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("town_follows", method: "DELETE",
                                        query: "follower_id=eq.\(uid)&target_type=eq.\(target.type.rawValue)&target_id=eq.\(target.id)",
                                        accessToken: t)
    }

    func isFollowing(_ target: FollowTarget) async throws -> Bool {
        let t = try await token()
        let uid = try await uidOrThrow()
        let (data, _) = try await SupabaseHTTP.rest("town_follows",
            query: "select=id&follower_id=eq.\(uid)&target_type=eq.\(target.type.rawValue)&target_id=eq.\(target.id)&limit=1",
            accessToken: t)
        let rows: [IdRow] = try decode(data)
        return !rows.isEmpty
    }

    // MARK: - Likes

    func likeEvent(_ id: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        // ignore-duplicates: a like is presence-only and event_likes has no UPDATE
        // policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on re-like.
        _ = try await SupabaseHTTP.rest("event_likes", method: "POST", query: "on_conflict=event_id,user_id",
                                        accessToken: t, body: try jsonBody(["event_id": id, "user_id": uid]),
                                        prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func unlikeEvent(_ id: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("event_likes", method: "DELETE",
                                        query: "event_id=eq.\(id)&user_id=eq.\(uid)", accessToken: t)
    }

    func hasLiked(_ id: String) async throws -> Bool {
        let t = try await token()
        let uid = try await uidOrThrow()
        let (data, _) = try await SupabaseHTTP.rest("event_likes",
            query: "select=id&event_id=eq.\(id)&user_id=eq.\(uid)&limit=1", accessToken: t)
        let rows: [IdRow] = try decode(data)
        return !rows.isEmpty
    }

    // MARK: - Saves

    func saveEvent(_ id: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        // ignore-duplicates: a save is presence-only and event_saves has no UPDATE
        // policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on re-save.
        _ = try await SupabaseHTTP.rest("event_saves", method: "POST", query: "on_conflict=event_id,user_id",
                                        accessToken: t, body: try jsonBody(["event_id": id, "user_id": uid]),
                                        prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func unsaveEvent(_ id: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("event_saves", method: "DELETE",
                                        query: "event_id=eq.\(id)&user_id=eq.\(uid)", accessToken: t)
    }

    func hasSaved(_ id: String) async throws -> Bool {
        let t = try await token()
        let uid = try await uidOrThrow()
        let (data, _) = try await SupabaseHTTP.rest("event_saves",
            query: "select=event_id&event_id=eq.\(id)&user_id=eq.\(uid)&limit=1", accessToken: t)
        let rows: [SaveRow] = try decode(data)
        return !rows.isEmpty
    }

    // MARK: - Comments

    func deleteComment(_ id: String) async throws {
        let t = try await token()
        _ = try await SupabaseHTTP.rest("event_comments", method: "DELETE", query: "id=eq.\(id)", accessToken: t)
    }

    // MARK: - Feed

}
