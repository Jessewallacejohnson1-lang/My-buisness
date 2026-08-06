//
//  BriefingAnalytics.swift
//  Block Party — the only per-user event stream in the app.
//
//  Writes to `app_events` in THIS project's own database. No third-party SDK,
//  nothing sent anywhere else, own-row RLS so no neighbour can read another's
//  activity. It exists to answer one question — do people open the briefing daily
//  — plus enough context to tell which module earned the open.
//
//  Never records anything a user typed, any location, or any message body.
//
//  Fire-and-forget by design: analytics must never block the UI, never surface an
//  error, and never fail a user action. A dropped event costs a data point; a
//  failed vote costs trust.
//

import Foundation

nonisolated enum BriefingEventName {
    /// The briefing rendered for a given date. The north star: distinct users
    /// per day. Fired once per launch per briefing date.
    static let briefingOpen = "briefing_open"
    /// The almanac card stayed on screen long enough to have been read.
    static let almanacDwell = "almanac_dwell"
    /// A poll vote landed.
    static let touchVote = "touch_vote"
    /// An RSVP made from the briefing rather than from Activities.
    static let rsvpFromHome = "rsvp_from_home"
    /// Someone reached the end of the briefing — the finite-screen payoff.
    static let caughtUpReached = "caught_up_reached"
}

@MainActor
final class BriefingAnalytics {
    static let shared = BriefingAnalytics()
    private init() {}

    /// Events already sent this launch, so a tab-return does not re-count an open.
    private var sentThisLaunch: Set<String> = []

    /// Records an event. Silently does nothing when signed out.
    func record(_ name: String, payload: [String: Any]? = nil, auth: AuthStore) {
        guard let uid = auth.userId else { return }
        Task { await Self.post(name: name, payload: payload, userID: uid, auth: auth) }
    }

    /// Records at most once per launch for the given key. Used for the open and
    /// the caught-up event, where a tab-return is not a new occurrence.
    func recordOnce(_ name: String, key: String, payload: [String: Any]? = nil, auth: AuthStore) {
        let token = "\(name)#\(key)"
        guard !sentThisLaunch.contains(token) else { return }
        sentThisLaunch.insert(token)
        record(name, payload: payload, auth: auth)
    }

    private static func post(name: String, payload: [String: Any]?,
                             userID: String, auth: AuthStore) async {
        do {
            let token = try await auth.validAccessToken()
            var body: [String: Any] = ["user_id": userID, "name": name]
            if let payload { body["payload"] = payload }
            _ = try await SupabaseHTTP.rest(
                "app_events", method: "POST", accessToken: token,
                body: try JSONSerialization.data(withJSONObject: body),
                prefer: "return=minimal"
            )
        } catch {
            // Deliberately swallowed. A lost event must never become a user-facing
            // failure, and the trail already lands in Console for debugging.
            Log.network("analytics \(name) dropped: \(error.localizedDescription)")
        }
    }
}
