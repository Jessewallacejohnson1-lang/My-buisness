//
//  PinDisplay.swift
//  Block Party — the single source of truth for a map pin's badge coloring.
//
//  One enum, resolved in one place. Precedence: live > saved > rest. "Live wins
//  while live" — a saved∩live spot resolves to `.live` and reverts to `.saved`
//  when the event ends (there's no stacking branch; the precedence chain encodes it).
//
//  Every curated spot always renders its small badge (MapPinBadge in SJMapView) —
//  `rest` just means "no accent": category tint, no pulse, no bookmark corner.
//
//  Selection is deliberately NOT a case here — it's tracked as a separate `Bool` at
//  the call site (`SJMapView`'s `selectedSpot?.id == spot.id`, passed to MapPinBadge
//  alongside this enum) because it's a scale/shadow accent layered on TOP of
//  whichever color this resolves to, not a fourth color of its own; a selected+live
//  spot must keep its live coral/pulse, which a `.selected` case would have to
//  re-derive or lose. An earlier version threaded selection through this enum too
//  (`resolve(isSelected:isLive:isSaved:)` / `.selected` case) but every call site
//  always passed `isSelected: false` — dead precedence a future edit could "fix"
//  with zero effect. Removed rather than left as a trap.
//

import Foundation

enum PinDisplay: String {
    case rest, saved, live

    static func resolve(isLive: Bool, isSaved: Bool) -> PinDisplay {
        if isLive  { return .live }   // live beats saved — "live wins while live"
        if isSaved { return .saved }
        return .rest
    }
}
