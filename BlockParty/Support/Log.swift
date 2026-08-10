//
//  Log.swift
//  Block Party — one dependency-free logging seam over Apple's os.Logger.
//
//  The app deliberately shows the user calm empty states on failure and never
//  surfaces raw errors. That's right for the neighbor — but it left the developer
//  with no way to tell a broken query (renamed column, RLS reject, decode failure)
//  apart from an honestly-empty table. This adds a quiet trail that only appears in
//  Console.app / Xcode's device log — NO third-party SDK, NO network, NO user-facing
//  surface. It changes nothing the user sees; it just stops failures being invisible.
//
//  SCOPE: those guarantees are about THIS FILE, not about the app. Block Party does
//  use a neighbour's own activity, and deliberately:
//
//    · `almanac_daily` — the daily line is written per user, from their RSVPs and
//      their last seven days, by the daily-almanac edge function.
//    · place + event recommendations — what gets surfaced is tailored to the
//      person, from their interests, saves and RSVPs (`Interests`, `town_profiles`,
//      `event_rsvps` / `event_saves` / `event_likes`, `town_follows`).
//    · `user_utility_prefs` — which utility tiles they chose, and in what order.
//    · `app_events` — first-party product analytics (see BriefingAnalytics).
//
//  What holds across all of it: it is all FIRST-PARTY. Every row lives in Block
//  Party's own Supabase project, no third-party SDK ships in the binary, nothing is
//  sold or shared, and own-row RLS means one neighbour can never read another's
//  activity. Personalization is the product — the app is supposed to know the town
//  and know you. Say so plainly in the privacy policy rather than implying the app
//  collects nothing.
//
//  The logger itself still records no user identity and sends nothing anywhere.
//
//  The os.Logger interpolation lives here so call sites need no `import os` — they
//  pass a plain String:  catch { Log.network("HomeModel.load: \(error)") }
//

import OSLog

enum Log {
    private static let subsystem = "Jesse.BlockParty"
    private static let net  = Logger(subsystem: subsystem, category: "network")
    private static let rt   = Logger(subsystem: subsystem, category: "realtime")
    private static let au   = Logger(subsystem: subsystem, category: "auth")
    private static let view = Logger(subsystem: subsystem, category: "ui")

    static func network(_ message: String)  { net.error("\(message, privacy: .public)") }
    static func realtime(_ message: String) { rt.error("\(message, privacy: .public)") }
    static func auth(_ message: String)     { au.error("\(message, privacy: .public)") }
    static func ui(_ message: String)       { view.error("\(message, privacy: .public)") }
}
