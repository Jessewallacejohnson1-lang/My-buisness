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
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var booting = true

    static let shared = AuthStore()

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user.email }
    var userId: String? { session?.user.id }

    private var refreshTask: Task<Void, Error>?

    /// Restore a persisted session on launch, refreshing if it's stale. A hard
    /// refresh failure (revoked/expired/rotated token) clears the session so the
    /// app routes back to Login rather than wedging signed-in-but-broken.
    func restore() async {
        if let saved = Keychain.load() {
            session = saved
            if saved.isExpired {
                do { try await refresh() }
                catch { session = nil; Keychain.clear() }
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

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await SupabaseHTTP.auth("logout", bearer: token)
        }
        session = nil
        Keychain.clear()
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
        let task = Task { () throws -> Void in
            do {
                let data = try await SupabaseHTTP.auth("token?grant_type=refresh_token",
                                                       body: ["refresh_token": refreshToken])
                try setSession(from: data)
            } catch {
                session = nil
                Keychain.clear()
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func setSession(from data: Data) throws {
        let s = try JSONDecoder().decode(Session.self, from: data)
        session = s
        Keychain.save(s)
    }
}
