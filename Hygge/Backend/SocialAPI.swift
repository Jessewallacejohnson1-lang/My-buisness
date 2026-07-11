//
//  SocialAPI.swift
//  Hygge — the social layer (follow / like / comment / feed reads), hand-rolled
//  over PostgREST like CommunityAPI and ProfileAPI. Net-new tables introduced by
//  the Today tab remake: `town_follows`, `event_likes`, `event_comments` (all on
//  the shared Supabase project — see
//  docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §5).
//
//  `getFeedPostings` / `comments` call Postgres RPCs (`get_feed_postings`,
//  `get_event_comments`) so a card's counts come back in one round trip instead
//  of N+1 queries per posting. Per-user state (did *I* like/follow this) is
//  fetched separately and merged client-side via `hydrateUserState(_:)`, so the
//  RPC itself stays user-agnostic and cacheable (spec §5.3).
//

import Foundation

struct SocialAPI {
    let auth: AuthStore

    private struct IdRow: Decodable { let id: String }
    private struct LikeRow: Decodable { let eventId: String }
    private struct FollowRow: Decodable { let targetType: FollowTargetType; let targetId: String }

    /// `get_event_comments` RPC row shape.
    private struct CommentRPCRow: Decodable {
        let id: String
        let body: String
        let createdAt: Date
        let authorId: String
        let authorName: String
        let authorAvatar: String?
    }

    /// `event_comments` insert (`return=representation`) row shape — no author
    /// columns live on the table itself; those come only from the RPC join.
    private struct InsertedCommentRow: Decodable {
        let id: String
        let body: String
        let createdAt: Date
    }

    /// `get_feed_postings` RPC row shape.
    private struct FeedRow: Decodable {
        let id: String
        let title: String
        let eventDate: String?
        let startTime: String?
        let location: String?
        let imageUrl: String?
        let createdAt: Date
        let posterType: FollowTargetType
        let posterId: String
        let posterName: String
        let posterAvatar: String?
        let likeCount: Int
        let commentCount: Int
        let goingCount: Int
        let followerCount: Int
    }

    // MARK: - Plumbing

    private func token() async throws -> String { try await auth.validAccessToken() }

    private func uidOrThrow() async throws -> String {
        guard let uid = auth.userId else { throw SupabaseError(message: "Not signed in", status: 401) }
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
        _ = try await SupabaseHTTP.rest("town_follows", method: "POST",
                                        query: "on_conflict=follower_id,target_type,target_id", accessToken: t,
                                        body: try jsonBody(["follower_id": uid, "target_type": target.type.rawValue, "target_id": target.id]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
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
        _ = try await SupabaseHTTP.rest("event_likes", method: "POST", query: "on_conflict=event_id,user_id",
                                        accessToken: t, body: try jsonBody(["event_id": id, "user_id": uid]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
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

    // MARK: - Comments

    /// Moderates through the existing Claude edge function (same discipline as
    /// event submission), then inserts. Author fields come from the caller's
    /// own `town_profile` (falling back to a first-name-from-email, matching
    /// the app's existing "Neighbor" naming voice) since the insert response
    /// carries only the raw comment columns, not the author join.
    func addComment(eventId: String, body: String) async throws -> EventComment {
        let uid = try await uidOrThrow()
        let check = await Moderation(auth: auth).check(kind: "comment", title: body, location: nil,
                                                        length: nil, description: nil, imageUrl: nil)
        guard check.ok else {
            let reason = check.reason == Moderation.queueSentinel
                ? "Couldn't post that comment right now — try again in a moment."
                : check.reason
            throw SupabaseError(message: reason, status: nil)
        }

        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("event_comments", method: "POST", accessToken: t,
                                                     body: try jsonBody(["event_id": eventId, "user_id": uid, "body": body]),
                                                     prefer: "return=representation")
        let rows: [InsertedCommentRow] = try decode(data)
        guard let row = rows.first else { throw SupabaseError(message: "Insert returned no row", status: nil) }

        let profile = try? await ProfileAPI(auth: auth).getMyProfile()
        let authorName = profile?.displayName ?? firstNameFromEmail(auth.email) ?? "A neighbor"
        return EventComment(id: row.id, body: row.body, createdAt: row.createdAt,
                            authorId: uid, authorName: authorName, authorAvatar: profile?.avatarUrl)
    }

    func deleteComment(_ id: String) async throws {
        let t = try await token()
        _ = try await SupabaseHTTP.rest("event_comments", method: "DELETE", query: "id=eq.\(id)", accessToken: t)
    }

    func comments(eventId: String) async throws -> [EventComment] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_event_comments", method: "POST", accessToken: t,
                                                     body: try jsonBody(["e_id": eventId]))
        let rows: [CommentRPCRow] = try decode(data)
        return rows.map { EventComment(id: $0.id, body: $0.body, createdAt: $0.createdAt,
                                       authorId: $0.authorId, authorName: $0.authorName, authorAvatar: $0.authorAvatar) }
    }

    // MARK: - Feed

    func getFeedPostings(limit: Int = 30) async throws -> [FeedPosting] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_feed_postings", method: "POST", accessToken: t,
                                                     body: try jsonBody(["limit_n": limit]))
        let rows: [FeedRow] = try decode(data)
        return rows.map { r in
            FeedPosting(id: r.id, title: r.title, eventDate: r.eventDate, startTime: r.startTime,
                       location: r.location, imageUrl: r.imageUrl, createdAt: r.createdAt,
                       posterName: r.posterName, posterAvatar: r.posterAvatar,
                       posterTarget: FollowTarget(type: r.posterType, id: r.posterId),
                       followerCount: r.followerCount, likeCount: r.likeCount,
                       commentCount: r.commentCount, goingCount: r.goingCount,
                       liked: false, following: false, rsvpd: false)
        }
    }

    /// Fills in `liked`/`following`/`rsvpd` for the signed-in user via three
    /// small own-rows queries, merged client-side — keeps `get_feed_postings`
    /// itself user-agnostic and cacheable (spec §5.3).
    func hydrateUserState(_ postings: [FeedPosting]) async throws -> [FeedPosting] {
        guard !postings.isEmpty else { return postings }
        let t = try await token()
        let uid = try await uidOrThrow()
        let ids = postings.map(\.id)
        let idList = ids.joined(separator: ",")

        async let likedCall = SupabaseHTTP.rest("event_likes",
            query: "select=event_id&user_id=eq.\(uid)&event_id=in.(\(idList))", accessToken: t)
        async let followCall = SupabaseHTTP.rest("town_follows",
            query: "select=target_type,target_id&follower_id=eq.\(uid)", accessToken: t)
        async let rsvpCall = SupabaseHTTP.rest("event_rsvps",
            query: "select=event_id&user_id=eq.\(uid)&event_id=in.(\(idList))", accessToken: t)

        let likedRows: [LikeRow] = try decode(try await likedCall.0)
        let followRows: [FollowRow] = try decode(try await followCall.0)
        let rsvpRows: [RsvpRow] = try decode(try await rsvpCall.0)

        let likedIds = Set(likedRows.map(\.eventId))
        let followedTargets = Set(followRows.map { FollowTarget(type: $0.targetType, id: $0.targetId) })
        let rsvpIds = Set(rsvpRows.map(\.eventId))

        return postings.map { p in
            var p = p
            p.liked = likedIds.contains(p.id)
            p.following = followedTargets.contains(p.posterTarget)
            p.rsvpd = rsvpIds.contains(p.id)
            return p
        }
    }
}
