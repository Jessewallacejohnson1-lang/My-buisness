//
//  POI.swift
//  Block Party — a permanent town venue (food / business) read from Supabase `places` and
//  rendered as a Mapbox POI marker. The map reads these ONCE from Supabase, so there
//  is no live Google Places call per map load — categories are pre-seeded.
//

import CoreLocation

struct POI: Identifiable, Decodable, Hashable {
    let id: String              // places.id (uuid)
    let placeId: String?        // Google's place id, or a local one (`stjoe-*`): Search's key for it
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
    /// Search's logo for this place (`places.search_logo`): its file in Storage and how
    /// Search shows it. nil for a place with no logo in Search.
    var searchLogo: SearchLogo.Row? = nil
    /// Its registry entry (`places.entry_id`, sources/<town>-mn.md), which its saved photos are
    /// kept under. nil for a place not in the registry yet.
    var entryId: String? = nil
    /// Its page in Search, until the business has its own account: its own website's
    /// description (`places.about`) and its website and social pages (`places.links`).
    var about: String? = nil
    var links: [PlaceLink]? = nil
    /// Its weekly hours (`places.hours`), read from its own website or Facebook.
    var hours: PlaceHours? = nil

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var logoURL: URL? { logoUrl.flatMap(URL.init(string:)) }

    /// SF Symbol glyph, derived from the raw `primaryType` (single source of truth =
    /// PlaceCategoryMap) so no glyph column need be stored.
    var glyph: String { PlaceCategoryMap.glyph(primaryType: primaryType, family: family) }

    static func == (l: POI, r: POI) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
