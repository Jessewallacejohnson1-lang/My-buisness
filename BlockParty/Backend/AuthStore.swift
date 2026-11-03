//
//  AuthStore.swift
//  Block Party — session state + GoTrue auth flows. The app's single auth source.
//
//  Email + password, confirmation ON, persisted session, proactive token refresh.
//

import Foundation
import Combine

@MainActor
final class AuthStore: ObservableObject, TokenProviding {
    @Published private(set) var session: Session?
    /// The launch hasn't finished looking for a kept session: no account yet doesn't mean signed out.
    @Published private(set) var booting = true

    static let shared = AuthStore()

    /// A session exists, real or anonymous: the person can act (Join, Save, Heart).
    var isSignedIn: Bool { session != nil }
    /// The session is a quiet account an install made for itself before 2026-11-02, not one
    /// someone signed into, so there is nothing to sign out of.
    var isAnonymous: Bool { session?.user.isAnonymous == true }
    /// An account someone made or logged into: the only way past the Welcome (Jesse, 2026-11-02:
    /// "dont allow people in app without logged in", BP app onboarding 27).
    var hasAccount: Bool { isSignedIn && !isAnonymous }
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
        #if DEBUG
        // bp-build's proof_login.sh: a throwaway proof account, logged in from the launch's
        // environment. Typing on the simulator's keyboard stopped landing (2026-10-21).
        let env = ProcessInfo.processInfo.environment
        if session == nil, let email = env["BP_PROOF_EMAIL"], let password = env["BP_PROOF_PASSWORD"] {
            _ = await signIn(email: email, password: password)
        }
        // Screenshot runs pass the gate with no account (`-skip-onboarding`, `RootView`) or open one
        // onboarding step (`-onboarding`): a quiet anonymous one reads the Town feed and Follow 3's
        // places for them, as every launch did before onboarding 27. The Welcome still shows: it
        // isn't a real account. Not for tests or sample data, which make no live account.
        if session == nil, LaunchFlags.has(.skipOnboarding) || LaunchFlags.has(.onboarding), !Self.isTestRun,
           LaunchFlags.backend == .live,
           let data = try? await SupabaseHTTP.auth("signup", body: [:]) {
            try? setSession(from: data)
        }
        #endif
        booting = false
    }

    /// A unit or UI test run: it must never act for whatever account the simulator
    /// kept, so it sends no tap kept from before (`RealLifeActions`).
    static var isTestRun: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        #if DEBUG
        if LaunchFlags.has(.uiTests) { return true }
        #endif
        return false
    }

    // MARK: - Flows (return a user-facing error string, nil on success)

    func signIn(email: String, password: String) async -> String? {
        do {
            let data = try await SupabaseHTTP.auth("token?grant_type=password",
                                                   body: ["email": email, "password": password])
            try setSession(from: data)
            return nil
        } catch {
            return Self.line(for: error)
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
            return (Self.line(for: error), false)
        }
    }

    /// Deletes this account and everything tied to it on the server, then signs out: "Come back
    /// when you're 13"'s Close, so "We didn't save anything you entered" stays true (BP app onboarding
    /// 19, 27). ponytail: signs out even when the delete didn't go through (offline); the account
    /// then stays on the server with no way back in. Retry it if that ever matters.
    func deleteAccount() async {
        do { try await Supabase(auth: self).rpc("delete_my_account") } catch {
            Log.network("AuthStore: account not deleted: \(error)")
        }
        await signOut()
    }

    /// What the Log in and Create account screens say when the server says no, matched on
    /// GoTrue's code or the status, never its English (BP app backlog 08, onboarding 27).
    nonisolated static func line(for error: Error) -> String {
        if error is URLError { return Words.offline }
        let failure = error as? SupabaseError
        switch failure?.code {
        case "invalid_credentials": return Words.wrong
        case "user_already_exists", "email_exists": return Words.taken
        case "weak_password": return Words.short
        case "email_address_invalid", "validation_failed": return Words.badEmail
        case "over_request_rate_limit", "over_email_send_rate_limit": return Words.tooMany
        default: break
        }
        switch failure?.status {
        case 429: return Words.tooMany
        case let status? where status == 0 || status >= 500: return Words.offline
        default: return Words.other
        }
    }

    nonisolated enum Words {
        static let wrong = "Wrong email or password. Try again."
        static let taken = "There's already an account with this email. Log in instead."
        static let short = "Use 6 or more characters."
        static let badEmail = "Check your email address."
        static let tooMany = "Too many tries. Wait a minute, then try again."
        static let offline = "Couldn't reach Block Party. Check your connection and try again."
        static let other = "Something went wrong. Try again."
    }

    func signOut() async {
        // Invalidate any in-flight refresh and clear local state *before* the network
        // round trip, so a concurrent refresh can neither outlive nor resurrect the
        // signed-out session (see sessionGeneration).
        sessionGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        let token = session?.accessToken
        clear()
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
    /// Called by `Supabase` on a 401 (`TokenProviding`).
    func handleUnauthorized() async {
        guard session != nil else { return }
        try? await refresh()
    }

    // MARK: - Tokens

    /// A guaranteed-fresh access token for API calls. Refreshes if needed.
    func validAccessToken() async throws -> String {
        guard let s = session else {
            throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401)
        }
        if s.isExpired { try await refresh() }
        guard let token = session?.accessToken else {
            throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401)
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
            throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401)
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
                    // An anonymous account can't be signed back into: its Going goes
                    // with it. Logged so losses can be counted.
                    if isAnonymous { Log.network("AuthStore: anonymous session rejected and cleared: \(error)") }
                    clear()
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

    /// The account is gone from this phone, by sign-out or a token the server turned down: the next
    /// account inherits none of its name, interests, onboarded stamp or kept Town feed (its Going).
    /// Onboarding starts over on the Welcome (`RootView`).
    private func clear() {
        session = nil
        Keychain.clear()
        ProfileModel.forget()
        TownFeedCache.clear()
    }

    private func setSession(from data: Data) throws {
        let s = try JSONDecoder().decode(Session.self, from: data)
        session = s
        Keychain.save(s)
    }
}
