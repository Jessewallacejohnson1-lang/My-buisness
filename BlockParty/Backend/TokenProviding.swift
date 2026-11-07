//
//  TokenProviding.swift
//  Block Party — the slice of AuthStore that the API layer actually needs: a fresh access
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
    /// A session is open, anonymous or real.
    var isSignedIn: Bool { get }
    /// The session is the quiet anonymous one, not a real account.
    var isAnonymous: Bool { get }
    /// The one admin account: the flag in its `app_metadata`, as `public.is_admin()` reads it.
    var isAdmin: Bool { get }
    /// The server refused a token the phone still thought good (a 401): refresh it, or sign out.
    func handleUnauthorized() async
}

extension TokenProviding {
    /// An account someone made or logged into: the only way past the Welcome (Jesse, 2026-11-02:
    /// "dont allow people in app without logged in", BP app onboarding 27).
    var hasAccount: Bool { isSignedIn && !isAnonymous }
}
