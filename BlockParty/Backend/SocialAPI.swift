//
//  SocialAPI.swift
//  Block Party — the social layer (follow / like / comment / feed reads), hand-rolled
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
    private struct SaveRow: Decodable { let eventId: String }
    private struct FollowRow: Decodable { let targetType: FollowTargetType; let targetId: String }
    private struct GoingProfileRow: Decodable {
        let userId: String
        let displayName: String?
        let avatarUrl: String?
    }

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

    // MARK: - Saves

    func saveEvent(_ id: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("event_saves", method: "POST", query: "on_conflict=event_id,user_id",
                                        accessToken: t, body: try jsonBody(["event_id": id, "user_id": uid]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
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

    /// Batched: which of these events the signed-in user has saved, in one query
    /// (mirrors the liked-state read in `hydrateUserState`; no N+1).
    func savedEventIds(in ids: [String]) async throws -> Set<String> {
        let ids = Array(Set(ids)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [] }
        let t = try await token()
        let uid = try await uidOrThrow()
        let idList = ids.joined(separator: ",")
        let (data, _) = try await SupabaseHTTP.rest("event_saves",
            query: "select=event_id&user_id=eq.\(uid)&event_id=in.(\(idList))", accessToken: t)
        let rows: [SaveRow] = try decode(data)
        return Set(rows.map(\.eventId))
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
                ? "Couldn't post your comment. Wait a moment and try again."
                : check.reason
            throw SupabaseError(message: reason, status: nil)
        }

        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("event_comments", method: "POST", accessToken: t,
                                                     body: try jsonBody(["event_id": eventId, "user_id": uid, "body": body]),
                                                     prefer: "return=representation")
        let rows: [InsertedCommentRow] = try decode(data)
        guard let row = rows.first else { throw SupabaseError(message: "The server didn't return the new comment. Refresh before posting it again.", status: nil) }

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

    /// Fetches the visible feed's facepile identities in two batched queries:
    /// all RSVP pairs first, then all matching public profile fields.
    func goingPreviews(eventIds: [String]) async throws -> [String: GoingPreview] {
        let eventIds = Array(Set(eventIds)).filter { !$0.isEmpty }
        guard !eventIds.isEmpty else { return [:] }

        let t = try await token()
        let eventIdList = eventIds.joined(separator: ",")
        let (rsvpData, _) = try await SupabaseHTTP.rest(
            "event_rsvps",
            query: "select=event_id,user_id&event_id=in.(\(eventIdList))",
            accessToken: t
        )
        let rsvpRows: [RsvpRow] = try decode(rsvpData)

        var seenUserIds = Set<String>()
        let userIds = rsvpRows.compactMap(\.userId).filter {
            seenUserIds.insert($0).inserted
        }
        guard !userIds.isEmpty else { return [:] }

        let userIdList = userIds.joined(separator: ",")
        let (profileData, _) = try await SupabaseHTTP.rest(
            "town_profiles",
            query: "select=user_id,display_name,avatar_url&user_id=in.(\(userIdList))",
            accessToken: t
        )
        let profileRows: [GoingProfileRow] = try decode(profileData)
        let profilesByUserId = Dictionary(
            uniqueKeysWithValues: profileRows.map { ($0.userId, $0) }
        )

        var userIdsByEvent: [String: [String]] = [:]
        for row in rsvpRows {
            guard let userId = row.userId,
                  userIdsByEvent[row.eventId, default: []].count < 3
            else { continue }
            userIdsByEvent[row.eventId, default: []].append(userId)
        }

        return eventIds.reduce(into: [:]) { previews, eventId in
            let profiles = userIdsByEvent[eventId, default: []].compactMap {
                profilesByUserId[$0]
            }
            let names = profiles.compactMap { row -> String? in
                guard let name = row.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty
                else { return nil }
                return name
            }
            let avatars = profiles.compactMap { row -> URL? in
                guard let raw = row.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty
                else { return nil }
                return URL(string: raw)
            }
            previews[eventId] = GoingPreview(names: names, avatars: avatars)
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
        // Phase 5 (staged): batch event_saves here once the migration is applied.
        // async let savedCall = SupabaseHTTP.rest("event_saves",
        //     query: "select=event_id&user_id=eq.\(uid)&event_id=in.(\(idList))", accessToken: t)

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
