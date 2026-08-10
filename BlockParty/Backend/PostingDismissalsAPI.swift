//
//  PostingDismissalsAPI.swift
//  Block Party — own-row persistence for For You dismissals.
//

import Foundation

struct PostingDismissalsAPI {
    let auth: AuthStore

    private struct DismissalRow: Decodable {
        let eventId: String
    }

    private func token() async throws -> String {
        try await auth.validAccessToken()
    }

    private func userID() throws -> String {
        guard let userID = auth.userId else {
            throw SupabaseError(
                message: "Your session ended. Sign in and try again.",
                status: 401
            )
        }
        return userID
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func dismissedPostingIDs(in eventIDs: [String]) async throws -> Set<String> {
        let eventIDs = Array(Set(eventIDs)).filter { !$0.isEmpty }
        guard !eventIDs.isEmpty else { return [] }

        let accessToken = try await token()
        let userID = try userID()
        let (data, _) = try await SupabaseHTTP.rest(
            "posting_dismissals",
            query: "select=event_id&user_id=eq.\(userID)&event_id=in.(\(eventIDs.joined(separator: ",")))",
            accessToken: accessToken
        )
        let rows: [DismissalRow] = try decode(data)
        return Set(rows.map(\.eventId))
    }

    func dismissPosting(_ id: String) async throws {
        let accessToken = try await token()
        let userID = try userID()
        let body = try JSONSerialization.data(
            withJSONObject: ["event_id": id, "user_id": userID]
        )
        _ = try await SupabaseHTTP.rest(
            "posting_dismissals",
            method: "POST",
            query: "on_conflict=event_id,user_id",
            accessToken: accessToken,
            body: body,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }
}
