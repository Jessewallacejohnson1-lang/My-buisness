//
//  TownStatusAPI.swift
//  Block Party — reads town_status notices for the Utility Row (roads today; any
//  `kind` in future). Hand-rolled PostgREST via SupabaseHTTP, like the other APIs.
//  Writes are service-role only (the daily content routine), so there is no write
//  method here.
//

import Foundation

struct TownStatusNotice: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let town: String
    let kind: String
    let status: String
    let headline: String
    let detail: String?
    let link: String?
    let active: Bool
    let updatedAt: Date
}

struct TownStatusAPI {
    let auth: AuthStore
    init(auth: AuthStore) { self.auth = auth }

    /// Active notices for a town + kind, newest first. The Utility Row's fallback
    /// fetch on appear; the realtime subscription triggers a re-fetch on change.
    func activeNotices(town: String = "st-joseph-mn", kind: String) async throws -> [TownStatusNotice] {
        let token = try await auth.validAccessToken()
        let query = "select=*&town=eq.\(town)&kind=eq.\(kind)&active=is.true&order=updated_at.desc"
        let (data, _) = try await SupabaseHTTP.rest("town_status", query: query, accessToken: token)
        return try SupabaseCoding.decoder.decode([TownStatusNotice].self, from: data)
    }
}
