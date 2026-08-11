//
//  CategoryGradient.swift
//  Block Party — the six category gradients, shared.
//
//  Category colour is a SYSTEM, not decoration: the same category resolves to the
//  same two stops everywhere it appears. Defined here, never as local constants
//  inside a view, so the Today rail, the day sheet, and (later) the map and
//  Activities cannot drift apart.
//

import SwiftUI

nonisolated enum CategoryGradient: String, CaseIterable, Hashable {
    case eventsFestivals
    case outdoorsTrails
    case clubsGroups
    case foodDrink
    case civicTown
    case personal

    /// Top → bottom. Exactly two stops, always.
    ///
    /// DARK MODE KEEPS THE HUE AND DROPS ~8% LIGHTNESS. A category's colour is an
    /// identity — the same event has to be recognisably the same object in either
    /// appearance — so nothing here is re-picked, only stepped down: a saturated
    /// 6pt bar at full light-mode value glares against a #141412 page, and the same
    /// bar 8 points of HSL lightness lower sits on it. Each dark hex below is its
    /// light partner with L − 8pp and H/S untouched.
    var stops: (top: Color, bottom: Color) {
        switch self {
        case .eventsFestivals:
            (Color(light: 0xE67633, dark: 0xD6601A), Color(light: 0xF2B441, dark: 0xEFA51B))
        case .outdoorsTrails:
            (Color(light: 0x2E9E86, dark: 0x257E6B), Color(light: 0x72C5B6, dark: 0x55B9A7))
        case .clubsGroups:
            (Color(light: 0x4A7BD9, dark: 0x2B63CF), Color(light: 0x72C5B6, dark: 0x55B9A7))
        case .foodDrink:
            (Color(light: 0xC9553D, dark: 0xAD4630), Color(light: 0xE67633, dark: 0xD6601A))
        case .civicTown:
            (Color(light: 0x5B6470, dark: 0x495059), Color(light: 0x8A8F98, dark: 0x757A85))
        case .personal:
            // THE ONE INVERSION, and the rule proves itself by failing here: these
            // two stops are already darker than the dark card (#1D1D1A), so −8pp
            // would take the top stop to #000000 and the bar would vanish into the
            // card it is supposed to edge. `personal` therefore steps UP by the same
            // amount instead. (It is currently unreachable — `of(_:)` never returns
            // it — but a colour system that is wrong in an unused branch is a trap
            // for whoever wires it up.)
            (Color(light: 0x111111, dark: 0x4A4A46), Color(light: 0x3A3A38, dark: 0x6E6E68))
        }
    }

    var linear: LinearGradient {
        LinearGradient(colors: [stops.top, stops.bottom], startPoint: .top, endPoint: .bottom)
    }

    /// `EventCategory` is the shipped 10-case taxonomy; these six are the colour
    /// system. `.other` resolves to `eventsFestivals` rather than `personal`
    /// because an uncategorised row on the town calendar is still a town event —
    /// and today EVERY live row is `.other`, so this mapping is what the app
    /// actually looks like until categories are backfilled.
    static func of(_ category: EventCategory) -> CategoryGradient {
        switch category {
        case .outdoors, .sports:        .outdoorsTrails
        case .musicArts:                .eventsFestivals
        case .food:                     .foodDrink
        case .families, .books, .games: .clubsGroups
        case .faith, .service:          .civicTown
        case .other:                    .eventsFestivals
        }
    }
}
