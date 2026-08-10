//
//  BPOnboardingCompletion.swift
//  Block Party — the pre-auth → signed-in handoff.
//
//  The flow runs before there is an account, so the six answers cannot be written when
//  they are given. This owns the seam:
//
//    S20 "Join the party"  →  flowDone = true  →  LoginView (sign up / sign in)
//                                                      ↓
//                                     first successful sign-in for this identity
//                                                      ↓
//                                  flush buffered answers → town_profiles → clear buffer
//
//  Why a flush rather than writing per screen: `ProfileAPI.upsert` is a full-row merge,
//  and there is no account to write to for most of the flow anyway. One write, once, when
//  an identity exists.
//
//  Why the buffer is NOT cleared until the write succeeds: a failed flush (offline at the
//  moment of sign-in, expired token, RLS surprise) must not silently discard twenty
//  screens of answers. It stays buffered and is retried on the next launch, so the worst
//  case is a delay rather than data loss.
//
//  Email confirmation is ON for this project, so signing up does NOT return a session —
//  the user has to leave, confirm, come back and log in. The buffer is what makes that
//  survivable, and it is persisted (not in-memory) for exactly that reason.
//

import Foundation

@MainActor
enum BPOnboardingCompletion {

    private static let flowDoneKey = "bp.onboarding.flowDone"
    private static let defaults = UserDefaults.standard

    /// True once the user has either finished S20 or chosen "I already have an account".
    /// Gates whether a signed-out launch shows the flow or the login screen.
    static var flowDone: Bool {
        get { defaults.bool(forKey: flowDoneKey) }
        set { defaults.set(newValue, forKey: flowDoneKey) }
    }

    /// The user reached the end of the flow, or skipped it via the sign-in button.
    static func markFlowDone() { flowDone = true }

    /// Which tab to land on, from S19. Nil until answered.
    static func landingTab(_ answers: BPAnswers) -> Tab? {
        switch answers.landingChoice {
        case BPLandingScreen.week: return .home     // "Today" — the app's front page
        case BPLandingScreen.map:  return .map
        default: return nil
        }
    }

    /// Flush the buffered answers for the now-signed-in user. Safe to call on every
    /// launch: it no-ops when the buffer is empty.
    ///
    /// Returns true if a write happened (or there was nothing to write); false if a write
    /// was attempted and failed, in which case the buffer is deliberately left intact.
    /// `auth` is resolved INSIDE the body, not as a default argument: a default argument
    /// is evaluated in a nonisolated context, and `AuthStore.shared` is MainActor-isolated,
    /// which trips the repo's 0-warning bar (and is an error under Swift 6).
    @discardableResult
    static func flushIfNeeded(_ answers: BPAnswers, auth store: AuthStore? = nil) async -> Bool {
        let auth = store ?? AuthStore.shared
        guard auth.userId != nil else { return true }
        guard hasBufferedAnswers(answers) else { return true }

        do {
            try await OnboardingAPI(auth: auth).saveAnswers(
                connection: answers.connection,
                townLevel: answers.townLevel,
                motivations: Array(answers.motivations),
                notifyCadence: answers.notifyCadence,
                foundingMember: answers.foundingMember,
                landingChoice: answers.landingChoice,
                // Stamp onboarded_at only when every answer is in — NOT on `flowDone`.
                //
                // `flowDone` is also set by "I already have an account", which is reachable
                // AFTER answering (S05 → back → S02). Gating on it stamped a user who had
                // answered one question and bailed to sign-in as fully onboarded, which
                // then skipped the name/interests wizard too and lost that capture.
                markOnboarded: answers.isComplete
            )
            // Landing choice is read from the buffer immediately after sign-in to route
            // the first screen, so clear only after it has been used.
            answers.clear()
            Log.network("onboarding: flushed answers to town_profiles")
            return true
        } catch {
            // Keep the buffer. Retried next launch.
            Log.network("onboarding: answer flush failed, keeping buffer — \(error)")
            return false
        }
    }

    private static func hasBufferedAnswers(_ a: BPAnswers) -> Bool {
        a.connection != nil || a.townLevel != nil || !a.motivations.isEmpty
            || a.notifyCadence != nil || a.foundingMember != nil || a.landingChoice != nil
    }
}
