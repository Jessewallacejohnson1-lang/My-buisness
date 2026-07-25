//
//  OnboardingAPI.swift
//  Block Party — writes the six onboarding answers to `town_profiles`.
//
//  Kept separate from `ProfileAPI` for one important reason: `ProfileAPI.upsert` is a
//  FULL-ROW MERGE. It writes `display_name` and `avatar_url` unconditionally, sending
//  NSNull when they are nil, so calling it to save an answer would NULL OUT a name and
//  avatar the user had already set.
//
//  This writes only the answer columns. PostgREST's `resolution=merge-duplicates` emits
//  `ON CONFLICT DO UPDATE SET` for exactly the columns present in the payload, so the
//  columns we omit are untouched on an update — and the same call still inserts the row
//  if it does not exist yet, which a PATCH could not (a PATCH on a missing row updates
//  zero rows and reports success).
//
//  That upsert needs an own-row UPDATE policy or PostgREST returns 42501. `town_profiles`
//  has one (verified against the live project), so no policy change was required.
//
//  Columns added by `supabase/migrations/20260725000000_onboarding_answers.sql`, applied
//  and verified live on 2026-07-25.
//

import Foundation

struct OnboardingAPI {
    let auth: AuthStore

    init(auth: AuthStore) { self.auth = auth }

    /// Writes whatever answers are present. Nil answers are OMITTED from the payload
    /// rather than sent as null, so a partial flush never erases a previous one.
    ///
    /// `markOnboarded` stamps `onboarded_at`, which is the flag `RootView` reads to skip
    /// the flow on a reinstall. Stamp it only when the flow actually completed — stamping
    /// early permanently skips the remaining screens.
    func saveAnswers(connection: String?,
                     townLevel: Int?,
                     motivations: [String],
                     notifyCadence: String?,
                     foundingMember: Bool?,
                     landingChoice: String?,
                     markOnboarded: Bool) async throws {
        let token = try await auth.validAccessToken()
        guard let uid = auth.userId else {
            throw SupabaseError(message: "You need to be signed in to save your answers.", status: 401)
        }

        var body: [String: Any] = ["user_id": uid]
        if let connection { body["connection"] = connection }
        if let townLevel { body["town_level"] = townLevel }
        if !motivations.isEmpty { body["motivations"] = motivations.sorted() }
        if let notifyCadence { body["notify_cadence"] = notifyCadence }
        if let foundingMember { body["founding_member"] = foundingMember }
        if let landingChoice { body["landing_choice"] = landingChoice }

        if markOnboarded {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            body["onboarded_at"] = iso.string(from: Date())
        }

        // Only `user_id` present → nothing was answered, so there is nothing to write.
        // Returning early avoids a pointless round trip that would still bump the row.
        guard body.count > 1 else { return }

        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await SupabaseHTTP.rest("town_profiles",
                                        method: "POST",
                                        query: "on_conflict=user_id",
                                        accessToken: token,
                                        body: data,
                                        prefer: "resolution=merge-duplicates,return=minimal")
    }
}
