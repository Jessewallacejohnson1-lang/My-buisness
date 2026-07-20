//
//  Log.swift
//  Block Party — one dependency-free logging seam over Apple's os.Logger.
//
//  The app deliberately shows the user calm empty states on failure and never
//  surfaces raw errors. That's right for the neighbor — but it left the developer
//  with no way to tell a broken query (renamed column, RLS reject, decode failure)
//  apart from an honestly-empty table. This adds a quiet trail that only appears in
//  Console.app / Xcode's device log — NO third-party SDK, NO network, NO user-facing
//  surface, NO per-user tracking. It respects the calm/real-data brand exactly
//  because it changes nothing the user sees; it just stops failures being invisible.
//
//  The os.Logger interpolation lives here so call sites need no `import os` — they
//  pass a plain String:  catch { Log.network("HomeModel.load: \(error)") }
//

import OSLog

enum Log {
    private static let subsystem = "Jesse.Hygge"
    private static let net  = Logger(subsystem: subsystem, category: "network")
    private static let rt   = Logger(subsystem: subsystem, category: "realtime")
    private static let au   = Logger(subsystem: subsystem, category: "auth")
    private static let view = Logger(subsystem: subsystem, category: "ui")

    static func network(_ message: String)  { net.error("\(message, privacy: .public)") }
    static func realtime(_ message: String) { rt.error("\(message, privacy: .public)") }
    static func auth(_ message: String)     { au.error("\(message, privacy: .public)") }
    static func ui(_ message: String)       { view.error("\(message, privacy: .public)") }
}
