//
//  MapSpots.swift
//  Hygge — the curated catalogue of Saint Joseph places shown on the map.
//
//  Six real spots with building-accurate coordinates (verified against OSM
//  footprints + published addresses — see MAP_BUILD_LOG.md FIX 5). Shared by the
//  map (pins + liveness) and the admin quick-add sheet (spot picker), so there's
//  a single source of truth. `keywords` are matched against real events' title +
//  location so an event lights the right pin; nothing here invents counts.
//

import CoreLocation
import SwiftUI

enum SpotCategory {
    case trail, park, downtown, coffee, fitness, college, chapel, `default`

    /// Non-filled, .medium-weight SF Symbol — clean line appearance.
    var symbol: String {
        switch self {
        case .trail:    return "figure.hiking"
        case .park:     return "tree"
        case .downtown: return "storefront"
        case .coffee:   return "cup.and.saucer"
        case .fitness:  return "dumbbell"
        case .college:  return "graduationcap"
        case .chapel:   return "building.columns"
        case .default:  return "mappin"
        }
    }

    /// The filled variant, used inside the small solid pin badge (a filled glyph
    /// reads cleaner than a line icon at 13pt on a colored circle).
    var filledSymbol: String {
        switch self {
        case .trail:    return "figure.hiking"
        case .park:     return "tree.fill"
        case .downtown: return "storefront.fill"
        case .coffee:   return "cup.and.saucer.fill"
        case .fitness:  return "dumbbell.fill"
        case .college:  return "graduationcap.fill"
        case .chapel:   return "building.columns.fill"
        case .default:  return "mappin"
        }
    }

    /// Pin badge tint — one job per category, reusing app tokens where they fit.
    /// The one exception is `mapGreen`: parks/trails read as green on every map
    /// (Apple, Google, Life360 included), and the map already owns its own raw
    /// cartography hexes (see BasemapPalette) — this extends that same carve-out
    /// to park iconography rather than force park pins into the coral/ink system.
    var tint: Color {
        switch self {
        case .park, .trail:        return SpotCategory.mapGreen
        case .downtown, .coffee, .fitness: return Hue.honey600
        case .college, .chapel:    return Hue.sky600
        case .default:             return Hue.mapInk
        }
    }

    /// Map-only green, pixel-sampled off the Life360 reference's park badges.
    private static let mapGreen = Color(hex: 0x6BBE52)
}

struct Spot: Identifiable, Hashable {
    let id: String
    let name: String
    let category: SpotCategory
    let coordinate: CLLocationCoordinate2D
    /// lowercase keywords matched against real events' title + location strings
    let keywords: [String]
    let blurb: String?

    static func == (lhs: Spot, rhs: Spot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum MapSpots {
    /// Recenter target — the middle of town.
    static let center = CLLocationCoordinate2D(latitude: 45.565, longitude: -94.317)

    static let all: [Spot] = [
        Spot(id: "downtown", name: "Downtown", category: .downtown,
             coordinate: .init(latitude: 45.5648, longitude: -94.3183), // Minnesota St W at College Ave
             keywords: ["downtown", "minnesota st", "local blend", "krewe", "bad habit", "college ave", "church of st"],
             blurb: "Shops & cafés on Minnesota St"),
        Spot(id: "saintbens", name: "Saint Ben's", category: .college,
             coordinate: .init(latitude: 45.5604, longitude: -94.3218), // Gorecki Center, CSB campus
             keywords: ["saint ben", "st. ben", "st ben", "csb", "benedict", "gorecki"],
             blurb: "College of Saint Benedict"),
        Spot(id: "chapel", name: "Sacred Heart Chapel", category: .chapel,
             coordinate: .init(latitude: 45.5631, longitude: -94.3189), // the chapel building itself
             keywords: ["chapel", "sacred heart", "monastery"],
             blurb: "The monastery & its dome"),
        Spot(id: "wobegon", name: "Wobegon Trail", category: .trail,
             coordinate: .init(latitude: 45.5697, longitude: -94.3180), // trailhead parking under the water tower, 610 County Rd 2
             keywords: ["wobegon", "trailhead"],
             blurb: "Bike, walk & run the trail"),
        Spot(id: "millstream", name: "Millstream Park", category: .park,
             coordinate: .init(latitude: 45.5701, longitude: -94.3287), // 725 CR-75 W
             keywords: ["millstream"],
             blurb: "Shelter, disc golf & the stream"),
        Spot(id: "saintjohns", name: "Saint John's", category: .college,
             coordinate: .init(latitude: 45.5800, longitude: -94.3923), // Abbey church, Collegeville
             keywords: ["saint john", "st. john", "st john", "sju", "abbey", "collegeville"],
             blurb: "The Abbey in Collegeville"),
    ]

    /// The curated keyword labels that actually light one of these pins (same match
    /// rule as SJMapView.spot(for:)). QuickAdd seeds from this so every happening
    /// posted from the map lands on a pin.
    static var pinnableSuggestions: [String] {
        KnownVenues.suggestions.filter { label in
            let l = label.lowercased()
            return all.contains { $0.keywords.contains { l.contains($0) } }
        }
    }
}
