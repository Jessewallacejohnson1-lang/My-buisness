//
//  FakeTokenProvider.swift
//  BlockPartyTests — a stand-in for AuthStore so the API layer / Models can be tested
//  without a live Supabase session. This is the payoff of the TokenProviding seam:
//  `CommunityAPI(auth: FakeTokenProvider())` needs no Keychain, no network, no auth.
//

import Foundation
@testable import BlockParty

@MainActor
final class FakeTokenProvider: TokenProviding {
    var token = "test-access-token"
    var userId: String?
    var email: String?
    var throwOnToken = false

    init(userId: String? = "test-user", email: String? = "test@example.com") {
        self.userId = userId
        self.email = email
    }

    func validAccessToken() async throws -> String {
        if throwOnToken { throw SupabaseError(message: "Not signed in", status: 401) }
        return token
    }
}
