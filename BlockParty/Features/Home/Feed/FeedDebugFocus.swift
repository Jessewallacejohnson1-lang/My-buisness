//
//  FeedDebugFocus.swift
//  Block Party — DEBUG-only: bring one Today module to the top of the screen.
//
//  This simulator setup has no scroll automation, so a module's loading, error or
//  empty state is unverifiable the moment it sits below the fold. `-feed-focus
//  <moduleID>` hides the modules ABOVE the one being inspected, which lifts it to
//  the top of the real Today composition (`-briefing-preview`) instead of into a
//  hand-built gallery that could drift from the real screen.
//
//  Compiled out of Release entirely.
//

#if DEBUG
import Foundation

nonisolated enum FeedDebugFocus {
    /// `-feed-focus almanac|yourDay|townNotes`
    static var focused: FeedModuleID? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-feed-focus"), index + 1 < args.count
        else { return nil }
        return FeedModuleID(rawValue: args[index + 1])
    }

    /// True only for a module that is NOT the focused one, so an unfocused run
    /// leaves the production composition exactly as it is.
    static func isHidden(_ id: FeedModuleID) -> Bool {
        guard let focused else { return false }
        return focused != id
    }
}
#endif
