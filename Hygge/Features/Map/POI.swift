//
//  POI.swift
//  Hygge — a permanent town venue (food / business) read from Supabase `places` and
//  rendered as a Mapbox POI marker. The map reads these ONCE from Supabase, so there
//  is no live Google Places call per map load — categories are pre-seeded.
//

import CoreLocation

struct POI: Identifiable, Decodable, Hashable {
    let id: String              // places.id (uuid)
    let placeId: String?        // Google place_id (kept for a live photo re-fetch)
    let name: String
    let lat: Double
    let lon: Double
    let family: PlaceFamily     // food | business
    let primaryType: String?    // raw Google primaryType
    let types: [String]
    let address: String?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// SF Symbol glyph, derived from the raw `primaryType` (single source of truth =
    /// PlaceCategoryMap) so no glyph column need be stored.
    var glyph: String { PlaceCategoryMap.glyph(primaryType: primaryType, family: family) }

    static func == (l: POI, r: POI) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
