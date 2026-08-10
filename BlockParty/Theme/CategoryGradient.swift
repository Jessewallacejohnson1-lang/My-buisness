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
    var stops: (top: Color, bottom: Color) {
        switch self {
        case .eventsFestivals: (Color(hex: 0xE67633), Color(hex: 0xF2B441))
        case .outdoorsTrails:  (Color(hex: 0x2E9E86), Color(hex: 0x72C5B6))
        case .clubsGroups:     (Color(hex: 0x4A7BD9), Color(hex: 0x72C5B6))
        case .foodDrink:       (Color(hex: 0xC9553D), Color(hex: 0xE67633))
        case .civicTown:       (Color(hex: 0x5B6470), Color(hex: 0x8A8F98))
        case .personal:        (Color(hex: 0x111111), Color(hex: 0x3A3A38))
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
