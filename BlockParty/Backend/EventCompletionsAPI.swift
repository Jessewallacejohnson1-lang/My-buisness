//
//  EventCompletionsAPI.swift
//  Block Party — "I did this today", stored per user.
//
//  `public.event_completions (user_id, event_id, completed_at)`, PK
//  `(user_id, event_id)`, RLS on with own-row select / insert / delete policies —
//  no UPDATE policy, because there is nothing to update.
//
//  PRESENCE-ONLY, AND THAT IS THE WHOLE CONTRACT: a row means done, and unticking
//  DELETES the row rather than writing a false. That is why the insert mirrors
//  `CommunityAPI.rsvpEvent` exactly — `resolution=ignore-duplicates`, never
//  merge-duplicates, since an ON CONFLICT DO UPDATE needs an UPDATE policy this
//  table deliberately does not have, and re-ticking a row that already exists is
//  the normal path whenever an optimistic flip drifts from the server.
//
//  Hand-rolled over `SupabaseHTTP.rest` like every other read in this app. There is
//  no Supabase SDK here; see `CommunityAPI` for the house pattern this follows.
//

import Foundation

/// The three calls `DayCompletionStore` needs, as a protocol, so the store can be
/// exercised against a fake — including a fake that FAILS, which is the only way to
/// assert the optimistic rollback. `EventCompletionsAPI` is the only production
/// conformer, exactly as `TokenProviding` is for `AuthStore`.
@MainActor
protocol EventCompletionStoring {
    func completedEventIDs(among ids: [String]) async throws -> Set<String>
    func complete(_ eventId: String) async throws
    func uncomplete(_ eventId: String) async throws
}

struct EventCompletionsAPI: EventCompletionStoring {
    let auth: any TokenProviding

    private struct CompletionRow: Decodable { let eventId: String }

    private func token() async throws -> String { try await auth.validAccessToken() }

    private func uidOrThrow() throws -> String {
        guard let uid = auth.userId else {
            throw SupabaseError(
                message: "Your session ended. Sign in and try again.",
                status: 401
            )
        }
        return uid
    }

    /// Which of these events the signed-in neighbour has already ticked.
    ///
    /// SCOPED BY EVENT ID, NOT BY `completed_at`. A day-window read looks like the
    /// obvious one — this is "today's day sheet" — and it is wrong for the case the
    /// rail explicitly supports: a multi-day festival ticked on Saturday is still
    /// on Sunday's rail, and a `completed_at >= today` filter would drop its row and
    /// silently un-tick it overnight. The ids are the rail's own, so the list is
    /// bounded by the day it is asked about anyway.
    ///
    /// RLS restricts the rows to this user; the explicit `user_id` filter is belt
    /// and braces, and it keeps the query readable next to its policy.
    func completedEventIDs(among ids: [String]) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let t = try await token()
        let uid = try uidOrThrow()

        let (data, _) = try await SupabaseHTTP.rest(
            "event_completions",
            query: "select=event_id&user_id=eq.\(uid)"
                + "&event_id=in.(\(ids.joined(separator: ",")))",
            accessToken: t
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([CompletionRow].self, from: data)
        return Set(rows.map(\.eventId))
    }

    /// Tick. `completed_at` is left to the column default so the timestamp is the
    /// server's, not a device clock that may be minutes out.
    func complete(_ eventId: String) async throws {
        let t = try await token()
        let uid = try uidOrThrow()
        let body = try JSONSerialization.data(
            withJSONObject: ["event_id": eventId, "user_id": uid]
        )

        _ = try await SupabaseHTTP.rest(
            "event_completions",
            method: "POST",
            query: "on_conflict=user_id,event_id",
            accessToken: t,
            body: body,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }

    /// Untick — the row goes away. There is no "completed = false" to write.
    func uncomplete(_ eventId: String) async throws {
        let t = try await token()
        let uid = try uidOrThrow()

        _ = try await SupabaseHTTP.rest(
            "event_completions",
            method: "DELETE",
            query: "event_id=eq.\(eventId)&user_id=eq.\(uid)",
            accessToken: t
        )
    }
}
