//
//  FakeTokenProvider.swift
//  BlockPartyTests — stand-ins for AuthStore and the network, so the API layer and Models can be
//  tested with no live Supabase session and nothing sent: `CommunityAPI(auth: FakeTokenProvider(),
//  send: FakeServer().send)` needs no Keychain, no network, no auth.
//

import Foundation
@testable import BlockParty

@MainActor
final class FakeTokenProvider: TokenProviding {
    var token = "test-access-token"
    var userId: String?
    var email: String?
    var throwOnToken = false
    /// How many 401s the client reported.
    var unauthorized = 0

    init(userId: String? = "test-user", email: String? = "test@example.com") {
        self.userId = userId
        self.email = email
    }

    func validAccessToken() async throws -> String {
        if throwOnToken { throw SupabaseError(message: "Not signed in", status: 401) }
        return token
    }

    func handleUnauthorized() async { unauthorized += 1 }
}

/// Supabase as a test sees it: every request kept in order, each answered from `answers` by its
/// path after the version (`rpc/get_town_feed`, `event_likes`, `object/avatars/…` matched by
/// prefix), else 200 with `[]`. `failure` makes every request throw instead, as with no signal.
@MainActor
final class FakeServer {
    struct Answer { var status = 200; var body = "[]" }

    private(set) var requests: [URLRequest] = []
    var answers: [String: Answer] = [:]
    var failure: Error?

    var send: Supabase.Send {
        Supabase.Send { @MainActor [self] request in
            requests.append(request)
            if let failure { throw failure }
            let path = request.url!.path
            let answer = answers.first { path.contains("/v1/\($0.key)") }?.value ?? Answer()
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
            return (Data(answer.body.utf8), response)
        }
    }

    /// The last request's body as JSON.
    var lastBody: Any? {
        requests.last?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
}
