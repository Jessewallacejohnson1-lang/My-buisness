//
//  POI.swift
//  Block Party — a permanent town venue (food / business) read from Supabase `places` and
//  rendered as a Mapbox POI marker. The map reads these ONCE from Supabase, so there
//  is no live Google Places call per map load — categories are pre-seeded.
//

import CoreLocation

/// Where a place or page stands in line in Follow 3, 1 first: its `spot`, and its `fit`, where it stands for somebody
/// who picked an interest it fits. With only a `fit` it is in line for them alone. And the photo that fills its
/// circle (its logo shows without one).
struct FollowSpot: Decodable, Hashable {
    let spot: Int?
    let fit: Int?
    /// What it is in the first circles' mix ("food", "shop", "help", "outdoors", "learn"); nil for anything else.
    let group: String?
    /// Never among the first circles.
    let late: Bool
    let photo: URL?

    init(spot: Int?, fit: Int? = nil, group: String? = nil, late: Bool = false, photo: URL? = nil) {
        self.spot = spot
        self.fit = fit
        self.group = group
        self.late = late
        self.photo = photo
    }

    /// Never throws: one odd row would fail the whole read of the places, Search's and the map's too. It is in no line.
    init(from decoder: Decoder) throws {
        let row = try? decoder.container(keyedBy: CodingKeys.self)
        spot = try? row?.decode(Int.self, forKey: .spot)
        fit = try? row?.decode(Int.self, forKey: .fit)
        group = try? row?.decode(String.self, forKey: .group)
        late = (try? row?.decode(Bool.self, forKey: .late)) ?? false
        photo = try? row?.decode(URL.self, forKey: .photo)
    }

    private enum CodingKeys: String, CodingKey { case spot, fit, group, late, photo }
}

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
    /// The word it uses for itself (`places.category`): the category its owner picked on Google Maps ("Nutrition
    /// club"), live once a second check against its own site agreed (BP app search-helpful 09). nil until then.
    var category: String? = nil
    /// Its spot in line in onboarding's Follow 3 (`places.follow_spot`, BP app community-value 04); nil for many places.
    var followSpot: FollowSpot? = nil
    /// 18 and over (`places.adults_only`): not in onboarding.
    var adultsOnly: Bool? = nil

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var logoURL: URL? { logoUrl.flatMap(URL.init(string:)) }

    /// SF Symbol glyph, derived from the raw `primaryType` (single source of truth =
    /// PlaceCategoryMap) so no glyph column need be stored.
    var glyph: String { PlaceCategoryMap.glyph(primaryType: primaryType, family: family) }

    static func == (l: POI, r: POI) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
