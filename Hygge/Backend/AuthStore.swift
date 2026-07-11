//
//  AuthStore.swift
//  Hygge — session state + GoTrue auth flows. The app's single auth source.
//
//  Mirrors apps/mobile/src/lib/auth.tsx: email + password, confirmation ON,
//  persisted session, proactive token refresh.
//

import Foundation
import Combine

@MainActor
final class AuthStore: ObservableObject, TokenProviding {
    @Published private(set) var session: Session?
    @Published private(set) var booting = true

    static let shared = AuthStore()

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user.email }
    var userId: String? { session?.user.id }

    private var refreshTask: Task<Void, Error>?
    /// Bumped whenever the signed-in identity intentionally changes (sign-out). An
    /// in-flight refresh captures this at start and refuses to write a session whose
    /// generation is stale — so a refresh resolving after sign-out can't resurrect
    /// the ended session.
    private var sessionGeneration = 0

    /// Restore a persisted session on launch, refreshing if it's stale. A hard
    /// refresh failure (revoked/expired/rotated token) clears the session so the
    /// app routes back to Login rather than wedging signed-in-but-broken.
    func restore() async {
        if let saved = Keychain.load() {
            session = saved
            if saved.isExpired {
                // refresh() clears the session only on a definitive token rejection;
                // a transient/offline failure leaves the stale session in place so a
                // later call can retry — don't sign the user out just for being offline.
                try? await refresh()
            }
        }
        booting = false
    }

    // MARK: - Flows (return a user-facing error string, nil on success)

    func signIn(email: String, password: String) async -> String? {
        do {
            let data = try await SupabaseHTTP.auth("token?grant_type=password",
                                                   body: ["email": email, "password": password])
            try setSession(from: data)
            return nil
        } catch {
            return (error as? SupabaseError)?.message ?? error.localizedDescription
        }
    }

    /// Returns (error, needsConfirm). When confirmation is required there's no
    /// session yet — the user must confirm via email first.
    func signUp(email: String, password: String) async -> (error: String?, needsConfirm: Bool) {
        do {
            let data = try await SupabaseHTTP.auth("signup",
                                                   body: ["email": email, "password": password])
            if (try? JSONDecoder().decode(Session.self, from: data)) != nil {
                try setSession(from: data)
                return (nil, false)
            }
            return (nil, true) // user returned but no session → confirm email
        } catch {
            return ((error as? SupabaseError)?.message ?? error.localizedDescription, false)
        }
    }

    /// Send a password-reset email via GoTrue's recover endpoint. Returns a
    /// user-facing error string, nil on success. Mirrors @hygge/core's reset flow.
    func resetPassword(email: String) async -> String? {
        do {
            _ = try await SupabaseHTTP.auth("recover", body: ["email": email])
            return nil
        } catch {
            return (error as? SupabaseError)?.message ?? error.localizedDescription
        }
    }

    func signOut() async {
        // Invalidate any in-flight refresh and clear local state *before* the network
        // round trip, so a concurrent refresh can neither outlive nor resurrect the
        // signed-out session (see sessionGeneration).
        sessionGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        let token = session?.accessToken
        session = nil
        Keychain.clear()
        Interests.clearMirror()   // don't let the next account inherit this user's name/interests/onboarded
        if let token {
            _ = try? await SupabaseHTTP.auth("logout", bearer: token)
        }
    }

    /// A REST call came back 401 — the access token was rejected server-side even
    /// though the local clock still thinks it's valid (e.g. the session was revoked
    /// from another device, or the JWT secret rotated). Force a refresh: if the
    /// refresh token is also dead, refresh() clears the session and the auth gate
    /// routes back to Login; if the token had merely expired in a network-latency
    /// window, this silently re-arms a valid one instead of signing the user out.
    /// Wired via SupabaseHTTP.onUnauthorized (set once at launch).
    func handleUnauthorized() async {
        guard session != nil else { return }
        try? await refresh()
    }

    // MARK: - Tokens

    /// A guaranteed-fresh access token for API calls. Refreshes if needed.
    func validAccessToken() async throws -> String {
        guard let s = session else {
            throw SupabaseError(message: "Not signed in", status: 401)
        }
        if s.isExpired { try await refresh() }
        guard let token = session?.accessToken else {
            throw SupabaseError(message: "Not signed in", status: 401)
        }
        return token
    }

    /// Refresh the access token. Concurrent callers coalesce onto a single
    /// in-flight request — GoTrue rotates the refresh token on use, so firing
    /// several at once would invalidate all but the first. A hard failure clears
    /// the session (the token family is dead) and rethrows.
    private func refresh() async throws {
        if let task = refreshTask {
            try await task.value
            return
        }
        guard let refreshToken = session?.refreshToken else {
            throw SupabaseError(message: "Not signed in", status: 401)
        }
        let generation = sessionGeneration
        let task = Task { () throws -> Void in
            do {
                let data = try await SupabaseHTTP.auth("token?grant_type=refresh_token",
                                                       body: ["refresh_token": refreshToken])
                // A sign-out during the round trip bumps the generation — don't write
                // a session the user has already ended.
                guard generation == sessionGeneration else { return }
                try setSession(from: data)
            } catch {
                // Only a definitive token rejection (GoTrue 4xx) means the token family
                // is dead; a transient/offline error must NOT destroy a still-valid
                // session. Skip the clear if we've since signed out, too.
                if generation == sessionGeneration, isTokenRejected(error) {
                    session = nil
                    Keychain.clear()
                }
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    /// True only for a definitive token rejection (GoTrue 400/401/403, e.g.
    /// invalid_grant / expired), not a transient transport error (offline, timeout,
    /// 5xx, rate-limit). Only a definitive failure clears the session.
    private func isTokenRejected(_ error: Error) -> Bool {
        switch (error as? SupabaseError)?.status {
        case 400, 401, 403: return true
        default: return false
        }
    }

    private func setSession(from data: Data) throws {
        let s = try JSONDecoder().decode(Session.self, from: data)
        session = s
        Keychain.save(s)
    }
}
