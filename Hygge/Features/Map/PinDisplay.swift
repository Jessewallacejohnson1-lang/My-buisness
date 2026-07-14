//
//  PinDisplay.swift
//  Hygge — the single source of truth for a map pin's visual weight.
//
//  One enum, resolved in one place, so no state logic scatters across the map
//  views. Precedence: selected > live > saved > rest. "Live wins while live" — a
//  saved∩live spot resolves to `.live` and reverts to `.saved` when the event ends
//  (there's no stacking branch; the precedence chain encodes it).
//
//  Rendering split (see docs/superpowers/specs/2026-07-13-map-pin-hierarchy-design.md):
//    • rest   → a recessive dot in the Mapbox `circle` layer
//    • saved/live → a full badge in the SwiftUI overlay + a collision label in the
//                   Mapbox `symbol` layer
//    • selected  → the overlay badge + always-on label; layered on via Mapbox
//                  feature-state, so selection never re-diffs the source.
//

import Foundation

enum PinDisplay: String {
    case rest, saved, live, selected

    /// Resolve a spot's weight from its three inputs. Pass `isSelected: false` to
    /// get the *base* state (rest/saved/live) the GeoJSON source carries — selection
    /// is layered on separately via feature-state, never a source property.
    static func resolve(isSelected: Bool, isLive: Bool, isSaved: Bool) -> PinDisplay {
        if isSelected { return .selected }
        if isLive     { return .live }        // live beats saved — "live wins while live"
        if isSaved    { return .saved }
        return .rest
    }

    /// Full 44pt badge (awake) vs. the recessive 6pt rest dot.
    var isAwake: Bool { self != .rest }

    /// Mapbox `symbol-sort-key` for label collision — LOWER wins placement, so a
    /// dropped label is always the lower-priority one. live(0) beats saved(1); rest
    /// carries no label, and selected is drawn by the overlay (out of the symbol
    /// layer), so neither is ranked here.
    var labelSortKey: Double {
        switch self {
        case .live:  return 0
        case .saved: return 1
        case .rest, .selected: return 2
        }
    }
}
