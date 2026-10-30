//
//  SocialAPI.swift
//  Block Party — the social layer (like / save / comment writes), hand-rolled
//  over PostgREST like CommunityAPI and ProfileAPI. Net-new tables introduced by
//  the Today tab remake: `town_follows`, `event_likes`, `event_comments` (all on
//  the shared Supabase project — see
//  docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §5). The feed reads
//  that went with them left with `HomeModel`: the Town feed reads `get_town_feed`.
//

import Foundation

struct SocialAPI {
    let db: Supabase

    init(auth: any TokenProviding, send: Supabase.Send = .live) { db = Supabase(auth: auth, send: send) }

    // MARK: - Likes

    func likeEvent(_ id: String) async throws {
        let uid = try db.userID
        // ignore-duplicates: a like is presence-only and event_likes has no UPDATE
        // policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on re-like.
        try await db.rest("event_likes", method: "POST", [("on_conflict", "event_id,user_id")],
                          body: ["event_id": id, "user_id": uid],
                          prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func unlikeEvent(_ id: String) async throws {
        let uid = try db.userID
        try await db.rest("event_likes", method: "DELETE", [("event_id", "eq.\(id)"), ("user_id", "eq.\(uid)")])
    }

    // MARK: - Saves

    func saveEvent(_ id: String) async throws {
        let uid = try db.userID
        // ignore-duplicates: a save is presence-only and event_saves has no UPDATE
        // policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on re-save.
        try await db.rest("event_saves", method: "POST", [("on_conflict", "event_id,user_id")],
                          body: ["event_id": id, "user_id": uid],
                          prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func unsaveEvent(_ id: String) async throws {
        let uid = try db.userID
        try await db.rest("event_saves", method: "DELETE", [("event_id", "eq.\(id)"), ("user_id", "eq.\(uid)")])
    }
}
