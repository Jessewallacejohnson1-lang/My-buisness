//
//  POI.swift
//  Block Party — a permanent town venue (food / business) read from Supabase `places` and
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
    /// Public URL of the curated brand logo (`places.logo_url`, Supabase Storage).
    /// Null for most places — the category glyph is the designed fallback.
    let logoUrl: String?
    /// Google's own place id for a row whose `placeId` is a local one (`stjoe-*`), found
    /// once through Locked Rule A (`scripts/resolve_google_place_ids.py`). nil when
    /// nothing cleared it, or when `placeId` is already Google's.
    var googlePlaceId: String? = nil

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var logoURL: URL? { logoUrl.flatMap(URL.init(string:)) }

    /// SF Symbol glyph, derived from the raw `primaryType` (single source of truth =
    /// PlaceCategoryMap) so no glyph column need be stored.
    var glyph: String { PlaceCategoryMap.glyph(primaryType: primaryType, family: family) }

    static func == (l: POI, r: POI) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
