//
//  TokenProviding.swift
//  Hygge — the slice of AuthStore that the API layer actually needs: a fresh access
//  token + the signed-in identity. Extracting it as a protocol lets CommunityAPI
//  (and every feature Model that funnels through it) be exercised against a fake in
//  unit tests, with no live Supabase session. AuthStore is the only production
//  conformer. @MainActor because AuthStore is.
//

import Foundation

@MainActor
protocol TokenProviding {
    func validAccessToken() async throws -> String
    var userId: String? { get }
    var email: String? { get }
}
