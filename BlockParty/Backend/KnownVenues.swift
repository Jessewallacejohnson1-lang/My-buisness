//
//  KnownVenues.swift
//  Block Party — curated, building-accurate coordinates for known St. Joseph places.
//
//  Runtime geocoding (Nominatim / Mapbox) routinely misses small-town venues
//  ("Millstream Park" returns nothing) or lands blocks away ("East Minnesota
//  Street" resolved ~900 m east of downtown). Known venues resolve here first,
//  verified 2026-07-04 against OpenStreetMap building footprints and the
//  venues' published street addresses. Mirrors apps/mobile/src/lib/geo.ts in
//  the Expo repo — keep the two tables in sync when adding a venue.
//
//  Order matters: specific venues before broad areas, so "Church of St.
//  Joseph, Minnesota St & College Ave" never falls through to plain downtown.
//

import CoreLocation

enum KnownVenues {
    private struct Venue {
        let kw: [String]
        let coord: CLLocationCoordinate2D
    }

    private static let venues: [Venue] = [
        // — downtown storefronts —
        Venue(kw: ["local blend"], coord: .init(latitude: 45.56483, longitude: -94.31841)),      // 19 W Minnesota St
        Venue(kw: ["bad habit"], coord: .init(latitude: 45.56557, longitude: -94.31863)),        // 25 College Ave N
        Venue(kw: ["krewe"], coord: .init(latitude: 45.56559, longitude: -94.31797)),            // 24 College Ave N
        Venue(kw: ["church of st. joseph", "church of saint joseph", "church of st joseph"],
              coord: .init(latitude: 45.5647, longitude: -94.3184)),                             // Minnesota St W at College Ave

        // — parks & trail —
        Venue(kw: ["millstream"], coord: .init(latitude: 45.57007, longitude: -94.32874)),       // 725 CR-75 W
        Venue(kw: ["klinefelter"], coord: .init(latitude: 45.5572, longitude: -94.30304)),
        Venue(kw: ["memorial park"], coord: .init(latitude: 45.56532, longitude: -94.32355)),
        Venue(kw: ["centennial park"], coord: .init(latitude: 45.56699, longitude: -94.32363)),
        Venue(kw: ["northland park"], coord: .init(latitude: 45.57285, longitude: -94.31153)),
        Venue(kw: ["wobegon", "trailhead"], coord: .init(latitude: 45.5697, longitude: -94.3180)), // Lake Wobegon trailhead parking, under the water tower off County Rd 2 (610 County Rd 2) — where the farmers market sets up

        // — the campuses & monastery —
        Venue(kw: ["sacred heart", "chapel", "monastery"], coord: .init(latitude: 45.5631, longitude: -94.3189)),
        Venue(kw: ["saint john", "st. john", "st john", "sju", "abbey", "collegeville"],
              coord: .init(latitude: 45.5800, longitude: -94.3923)),                             // Abbey church
        Venue(kw: ["saint ben", "st. ben", "st ben", "csb", "benedict", "gorecki"],
              coord: .init(latitude: 45.5604, longitude: -94.3218)),                             // Gorecki Center

        // — broad areas last —
        Venue(kw: ["downtown", "minnesota st", "minnesota street", "college ave"],
              coord: .init(latitude: 45.5648, longitude: -94.3183)),
    ]

    /// Presentable quick-pick labels — one per curated venue, each of which
    /// lowercase-contains its matching keyword above, so picking one still lights
    /// the right pin. Keep aligned with `venues` when adding a venue.
    static let suggestions: [String] = [
        "Local Blend", "Bad Habit", "Krewe", "Church of St. Joseph",
        "Millstream Park", "Klinefelter Park", "Memorial Park",
        "Centennial Park", "Northland Park", "Wobegon Trail",
        "Sacred Heart Chapel", "Saint John's", "Saint Ben's", "Downtown",
    ]

    /// Exact coordinates for a known St. Joe venue, or nil if we don't know it.
    static func coordinate(for location: String?) -> CLLocationCoordinate2D? {
        guard let t = location?.lowercased(), !t.isEmpty else { return nil }
        return venues.first { $0.kw.contains(where: t.contains) }?.coord
    }

    /// The curated anchor for something that HAPPENS at a place — the single,
    /// location-first rule every photo-lookup path shares so they can never drift.
    ///
    /// Location FIRST: the place is the `location`, and the item's own `name` (an event
    /// title, a trail's address line) is only a *rescue* for a location this table
    /// doesn't recognise. It must never override a location the table already knows —
    /// concatenating the two and matching the first keyword anywhere in the combined
    /// string is exactly the title-hijack bug this replaces (measured 2026-07-21:
    /// "Millstream Arts Festival" at "Downtown St. Joseph" anchored on Millstream Park
    /// 1,025 m away and blanked the card; location-first anchors it to 26 m and resolves).
    static func anchor(location: String?, named name: String) -> CLLocationCoordinate2D? {
        guard let location, !location.isEmpty else { return coordinate(for: name) }
        if let known = coordinate(for: location) { return known }
        return coordinate(for: "\(location) \(name)")
    }
}
