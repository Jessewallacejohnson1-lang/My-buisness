//
//  UtilityRowEntrance.swift
//  Block Party — the Utility Row's first-appearance cascade: each tile fades in and
//  rises `riseOffset` into place, one `stagger` behind the tile to its left, on
//  `Motion.tileEntrance`.
//
//  The LATCH is the reason this file exists. `.onAppear` fires every time the row
//  comes back on screen — every tab switch back to Today, every scroll-back — so an
//  entrance driven straight off it replays forever and a calm row starts to twitch.
//  This gates the cascade to ONCE PER APP SESSION, the same way
//  `AlmanacReveal.hasWrittenThisLaunch` gates the Almanac's write: an in-memory flag
//  with no persisted day-stamp, so opening the app greets you and nothing else does.
//  The row plays the cascade only when `hasPlayedThisLaunch` is false, then calls
//  `markPlayed()`; every later appearance renders in its final state instantly.
//
//  Isolation: the latch is main-actor state (it is mutated from the SwiftUI view
//  lifecycle, exactly like AlmanacReveal). The pure arithmetic is `nonisolated` so a
//  delay can be computed from any context without an actor hop — and so the module's
//  MainActor-by-default isolation doesn't leak into a value that is just a number.
//

import CoreGraphics
import Foundation

@MainActor
enum UtilityRowEntrance {

    // MARK: - Geometry & timing (pure — safe from any isolation)

    /// Seconds between one tile's rise and the next. Quick enough that a five-tile
    /// row is fully in under 0.2s: a cascade you notice, not one you wait through.
    nonisolated static let stagger: TimeInterval = 0.04

    /// How far a tile travels on the way in. A settle, not a fly-in — the sheet
    /// cascade's `StaggeredAppear` uses the same idea at 8pt, and the utility tile is
    /// the larger object, so it gets slightly more travel.
    nonisolated static let riseOffset: CGFloat = 10

    /// Ceiling on the cascade, matching `StaggeredAppear`'s cap. The row is
    /// user-customizable, so the tile count is not fixed and an uncapped linear delay
    /// is a latent slow tail: a neighbour who enables everything would watch the last
    /// tile arrive long after the first. 0.24s is above the delay of every tile the
    /// default row can produce, so the pinned indices are unaffected — this only ever
    /// bites the long, customized row it exists for.
    nonisolated static let maxDelay: TimeInterval = 0.24

    /// When the tile at `index` starts its rise, measured from the row's first
    /// appearance. A function of POSITION, never of when a tile happened to appear,
    /// so the cascade reads left-to-right no matter what order SwiftUI builds in.
    nonisolated static func delay(forTileAt index: Int) -> TimeInterval {
        min(Double(max(index, 0)) * stagger, maxDelay)
    }

    // MARK: - The once-per-launch latch

    /// Whether this launch has already played the cascade. Read-only outside the
    /// enum: the only way to set it is `markPlayed()`, so no caller can invent a
    /// second entrance.
    private(set) static var hasPlayedThisLaunch = false

    /// Retire the entrance for the rest of this app session. Idempotent — a second
    /// row instance or a re-render can call it freely.
    static func markPlayed() {
        hasPlayedThisLaunch = true
    }

    #if DEBUG
    /// Clear the latch so a test case starts from a fresh-launch state. DEBUG-only:
    /// the latch is process-global, so this is a real un-shipping hazard in release,
    /// and the test target is app-hosted against a Debug build.
    static func resetForTesting() {
        hasPlayedThisLaunch = false
    }
    #endif
}
