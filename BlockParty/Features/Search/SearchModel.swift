//
//  SearchModel.swift
//  Block Party — what the Search tab holds: the Town's places from Supabase with their
//  bundled logos, the city's parks and trails, the neighbour's recent searches, and,
//  in DEBUG until their reads exist, sample neighbours, events and clubs.
//
//  Reference: Jesse's Search mockup v7 (claude.ai/artifact/Vqb74LLMXipRV8uhpefTo9) and
//  its five Figma frames, 2026-10-02. Row orders, names and labels follow the mockup.
//

import CoreLocation
import SwiftUI
import UIKit

/// One thing Search can show: a neighbour, a business, a food place, an event, a club
/// or a park.
struct SearchItem: Identifiable, Hashable {
    enum Kind: CaseIterable {
        case person, business, restaurant, coffee, event, club, park
    }

    /// Where its photo comes from.
    enum Photo: Hashable {
        /// A photo in `Resources/Images`, by base name.
        case bundled(String)
        /// An image in the asset catalog.
        case asset(String)
        /// Google Maps, cleared by Locked Rule A against the name and coordinate.
        case google
    }

    let id: String
    let kind: Kind
    /// As shown: "Krewe", not "Krewe Restaurant".
    let name: String
    /// As Google knows it, for the photo lookup's name check.
    var fullName: String? = nil
    var sub: String? = nil
    var logo: SearchLogo? = nil
    var photo: Photo? = nil
    /// The heading it sits under on its filter: Parks or Trails, Festivals or Markets.
    var group: String? = nil
    var keywords: [String] = []
    var lat: Double? = nil
    var lon: Double? = nil
    /// Google's own place id, when Supabase carries one (`ChIJ…`).
    var googleId: String? = nil
    /// Its place on its row: the mockup's order first, then by name.
    var rank = Int.max

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// A business or food place with a logo opens onto its own page of photos; the
    /// logo flies there (Jesse, 2026-10-04: restaurants and coffee open like logos).
    var opens: Bool { [.business, .restaurant, .coffee].contains(kind) && logo != nil }

    /// Its photos from Google Maps, shared by its card and its business page. With a
    /// Google id it asks for the photos alone (the cheap tier); without one, its name
    /// and coordinate must clear Locked Rule A first. Empty when there are none or the
    /// ask failed.
    func googlePhotos() async -> PlacePhotos {
        let places = GooglePlacesService.shared
        if let googleId, let photos = await places.photos(placeId: googleId) { return photos }
        if googleId == nil, let coordinate,
           let details = await places.confidentDetails(name: fullName ?? name, coordinate: coordinate) {
            return PlacePhotos(all: details.photos, best: details.photo)
        }
        return PlacePhotos(all: [], best: nil)
    }

    /// What kind of place it is, drawn where there is no logo and no photo.
    var glyph: String {
        switch kind {
        case .park: "tree"
        case .business: "storefront"
        case .coffee: "cup.and.saucer"
        case .restaurant: "fork.knife"
        default: "photo"
        }
    }
}

/// A business's logo as Search draws it: cut out and centred on a square by the logo
/// pipeline (`designs/artifacts/search-tab/build.py`), and 3D for the ones the
/// `logo-3d` skill has made and checked. Bundled in `Resources/SearchLogos`, keyed by
/// `places.place_id`; `search-logos.json` carries each one's hue and row order.
struct SearchLogo: Hashable {
    let placeId: String
    let hue: Double
    /// A colourful logo; a black, white or grey one gets a nearly neutral backdrop.
    let chroma: Bool
    let is3D: Bool
    let rank: Int?

    /// The photo-shoot backdrop in the logo's own hue, light at the centre top where
    /// the light hits and a little deeper at the edges.
    var backdrop: [Color] {
        let s: Double = chroma ? 30 : 9
        return [Hue.hsl(hue, s, 94), Hue.hsl(hue, s, 87), Hue.hsl(hue, max(5, s - 6), 76)]
    }

    /// The cast shadow's colour: a dark shade of the logo's hue, never grey.
    var shadow: Color { Hue.hsl(hue, chroma ? 30 : 10, 18) }

    var image: UIImage? {
        if let hit = Self.cache[placeId] { return hit }
        guard let url = Bundle.main.url(forResource: "searchlogo-\(placeId)", withExtension: "webp"),
              let image = UIImage(contentsOfFile: url.path()) else { return nil }
        Self.cache[placeId] = image
        return image
    }

    static let all: [String: SearchLogo] = {
        struct Row: Decodable { let hue: Double; let chroma: Bool; let d3: Bool?; let rank: Int? }
        guard let url = Bundle.main.url(forResource: "search-logos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([String: Row].self, from: data) else { return [:] }
        return rows.reduce(into: [:]) { all, row in
            all[row.key] = SearchLogo(placeId: row.key, hue: row.value.hue, chroma: row.value.chroma,
                                      is3D: row.value.d3 ?? false, rank: row.value.rank)
        }
    }()

    private static var cache: [String: UIImage] = [:]

    /// Decodes every logo off the main thread, so the first look at the wall doesn't
    /// stall while 51 of them decode at once.
    static func warm() async {
        let ids = all.keys.filter { cache[$0] == nil }
        let decoded = await Task.detached(priority: .utility) {
            ids.compactMap { id -> (String, UIImage)? in
                guard let url = Bundle.main.url(forResource: "searchlogo-\(id)", withExtension: "webp"),
                      let image = UIImage(contentsOfFile: url.path())?.preparingForDisplay() else { return nil }
                return (id, image)
            }
        }.value
        for (id, image) in decoded { cache[id] = image }
    }
}

/// The filter pills, in the mockup's order.
enum SearchChip: CaseIterable, Hashable {
    case all, people, businesses, events, clubs, parks

    var title: String {
        switch self {
        case .all: "All"
        case .people: "People"
        case .businesses: "Businesses"
        case .events: "Events"
        case .clubs: "Clubs"
        case .parks: "Parks"
        }
    }

    var kind: SearchItem.Kind? {
        switch self {
        case .all: nil
        case .people: .person
        case .businesses: .business
        case .events: .event
        case .clubs: .club
        case .parks: .park
        }
    }

    /// The sections a typed search shows under this pill. Businesses takes the food
    /// places too: a restaurant is a business to whoever is looking for one.
    var resultKinds: [SearchItem.Kind] {
        switch self {
        case .all: SearchItem.Kind.allCases
        case .businesses: [.business, .restaurant, .coffee]
        default: kind.map { [$0] } ?? []
        }
    }
}

/// A recent search: something opened, or words typed and searched.
enum SearchRecent: Identifiable {
    case item(SearchItem)
    case query(String)

    var id: String {
        switch self {
        case .item(let item): item.id
        case .query(let words): SearchModel.queryID(words)
        }
    }
}

@MainActor @Observable
final class SearchModel {
    private(set) var places: [SearchItem] = []
    private(set) var placesLoaded = false
    /// What the tab was showing, kept across tab switches as Instagram keeps it.
    var chip = SearchChip.all
    var words = ""
    /// From the field's first tap until Cancel: Cancel shows, and so do the recents.
    var searching = false
    /// Ids, newest first: an item's id, or `q:` and the words.
    private(set) var recentIDs: [String]

    private let defaults: UserDefaults
    private let fixed = SearchModel.parks() + SearchModel.samples()
    static let recentsKey = "search.recents"
    static let recentsMax = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentIDs = defaults.stringArray(forKey: Self.recentsKey) ?? Self.sampleRecents
    }

    var items: [SearchItem] { places + fixed }

    /// Reads the Town's places, trying again while the tab is open (2 s, 4 s, … 30 s
    /// apart) until it can: offline, the rows wait as skeletons rather than vanish.
    func load() async {
        var wait = 2.0
        while !placesLoaded && !Task.isCancelled {
            if let pois = try? await CommunityAPI(auth: AuthStore.shared).getPlaces() {
                show(pois)
                return
            }
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 30)
        }
    }

    func show(_ pois: [POI]) {
        places = Self.places(from: pois)
        placesLoaded = true
    }

    // MARK: Rows

    /// One kind's row, in order. Businesses show only with a logo: the row is logos.
    func row(_ kind: SearchItem.Kind) -> [SearchItem] {
        Self.ordered(items.filter { $0.kind == kind && (kind != .business || $0.logo != nil) })
    }

    /// Whether a kind's row is still waiting on Supabase.
    func isLoading(_ kind: SearchItem.Kind) -> Bool {
        !placesLoaded && [.business, .restaurant, .coffee].contains(kind)
    }

    /// The pills worth showing: All, and every filter with something behind it.
    var chips: [SearchChip] {
        SearchChip.allCases.filter { chip in
            guard let kind = chip.kind else { return true }
            return isLoading(kind) || !row(kind).isEmpty
        }
    }

    // MARK: Typed search

    /// Results for typed words, section by section in the mockup's order, best match
    /// first. Matching is the app's own reference-aware search: prefixes, word starts,
    /// small typos.
    func results(for words: String, in chip: SearchChip) -> [(kind: SearchItem.Kind, items: [SearchItem])] {
        let q = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return chip.resultKinds.compactMap { kind in
            let hits = items.filter { $0.kind == kind }
                .compactMap { item in
                    TownSearch.score(q, name: item.name, extra: [item.sub ?? ""], aliases: item.keywords).map { (item, $0) }
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
            return hits.isEmpty ? nil : (kind, hits)
        }
    }

    // MARK: Recents

    var recents: [SearchRecent] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return recentIDs.compactMap { id in
            if id.hasPrefix("q:") { return .query(String(id.dropFirst(2))) }
            return byID[id].map { .item($0) }
        }
    }

    func remember(_ id: String) {
        recentIDs = Array(([id] + recentIDs.filter { $0 != id }).prefix(Self.recentsMax))
        defaults.set(recentIDs, forKey: Self.recentsKey)
    }

    func forget(_ id: String) {
        recentIDs.removeAll { $0 == id }
        defaults.set(recentIDs, forKey: Self.recentsKey)
    }

    static func queryID(_ words: String) -> String {
        "q:" + words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Building items

    static func ordered(_ items: [SearchItem]) -> [SearchItem] {
        items.sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    static let coffeeTypes: Set<String> = ["coffee_shop", "cafe", "bakery"]

    static func places(from pois: [POI]) -> [SearchItem] {
        pois.map { poi in
            let key = poi.placeId ?? poi.id
            let logo = SearchLogo.all[key]
            let type = poi.primaryType ?? ""
            let kind: SearchItem.Kind = poi.family == .business ? .business
                : coffeeTypes.contains(type) ? .coffee : .restaurant
            return SearchItem(id: "p:\(key)", kind: kind, name: shown(poi.name), fullName: poi.name,
                              sub: label(type), logo: logo, photo: kind == .business ? nil : .google,
                              keywords: [type.replacingOccurrences(of: "_", with: " ")],
                              lat: poi.lat, lon: poi.lon, googleId: key.hasPrefix("ChIJ") ? key : poi.googlePlaceId,
                              rank: logo?.rank ?? .max)
        }
    }

    /// The name on a card: the mockup drops what only repeats the kind of place.
    static func shown(_ name: String) -> String {
        [" | Italian", " - St. Joseph", " Company", " Restaurant"]
            .reduce(name) { $0.replacingOccurrences(of: $1, with: "") }
    }

    /// The line under a name, from Google's place type.
    static func label(_ type: String) -> String? {
        let named = ["brewery": "Brewery", "cajun_restaurant": "Cajun", "italian_restaurant": "Italian",
                     "pizza_restaurant": "Pizza", "restaurant": "Restaurant", "sandwich_shop": "Deli",
                     "bar_and_grill": "Bar & grill", "ice_cream_shop": "Ice cream", "coffee_shop": "Coffee shop",
                     "bakery": "Bakery", "bar": "Bar"]
        if let hit = named[type] { return hit }
        guard let first = type.first else { return nil }
        return first.uppercased() + type.dropFirst().replacingOccurrences(of: "_", with: " ")
    }

    /// The city's parks, and the trails the app has a bundled photo of.
    static func parks() -> [SearchItem] {
        let parks = CityParks.all.map { park in
            SearchItem(id: "k:\(park.id)", kind: .park, name: park.title, sub: "Park",
                       photo: KnownLocalPhoto.name(forTitle: park.title).map { .bundled($0) } ?? .google,
                       group: "Parks", keywords: ["park"] + park.features, lat: park.lat, lon: park.lon)
        }
        let trails = [("Lake Wobegon Trail", "wobegon-trail"), ("Saint John's Abbey Arboretum", "sju-arboretum-trail"),
                      ("Stella Maris Chapel Trail", "chapel-trail-stella-maris"), ("Boardwalk Loop Trail", "boardwalk-loop-trail")]
            .map { name, photo in
                SearchItem(id: "k:\(name)", kind: .park, name: name, sub: "Trail", photo: .bundled(photo),
                           group: "Trails", keywords: ["trail", "walk", "hike"])
            }
        return ranked(parks + trails)
    }

    /// Fixed lists keep the order they are written in.
    static func ranked(_ items: [SearchItem]) -> [SearchItem] {
        items.enumerated().map { i, item in
            var item = item
            item.rank = i
            return item
        }
    }

    #if DEBUG
    /// INVENTED, as Jesse asked (2026-10-02, "just mock it up"): neighbours, events and
    /// clubs, until their reads exist. Neighbours' profiles are private to each person
    /// today, and the Town has no events or clubs yet. Names and photos are the mockup's;
    /// the faces are town photos, since there is no real face to show.
    static func samples() -> [SearchItem] {
        let people = [("Marlene Ostendorf", "memorial-park"), ("Bea Lindgren", "farmers-market"),
                      ("Dale Brunner", "wobegon-trail"), ("Hal Pedersen", "rivers-bend-park"),
                      ("Junie Okonkwo", "millstream-arts-festival"), ("Kesia Vue", "sju-arboretum-trail"),
                      ("Marcus Whitefeather", "klinefelter-park-trail"), ("Maya Chen", "saint-bens"),
                      ("Sam Rivera", "centennial-park")]
            .map { name, photo in SearchItem(id: "u:\(name)", kind: .person, name: name, photo: .bundled(photo)) }
        let events = [("Rocktoberfest", "rocktoberfest", "Festivals"), ("Millstream Arts Festival", "millstream-arts-festival", "Festivals"),
                      ("Farmers Market", "farmers-market", "Markets")]
            .map { name, photo, group in
                SearchItem(id: "e:\(name)", kind: .event, name: name, sub: "Event", photo: .bundled(photo),
                           group: group, keywords: ["event", "festival", group.lowercased()])
            }
        let clubs = [("Book Club", "interest-books"), ("Morning Pages", "interest-coffee"), ("Riverside Potluck", "interest-dining")]
            .map { name, photo in
                SearchItem(id: "c:\(name)", kind: .club, name: name, sub: "Club", photo: .asset(photo), keywords: ["club"])
            }
        return ranked(people) + ranked(events) + ranked(clubs)
    }

    /// INVENTED: the mockup's starting recents (Marlene, The Local Blend, "pumpkin",
    /// Lee's Ace Hardware, Rocktoberfest), so the recents screen can be seen before any
    /// searching. Only when nothing was ever saved.
    static let sampleRecents = ["u:Marlene Ostendorf", "p:ChIJmTKJ0M9ZtFIRm7FAmBzwApc", "q:pumpkin",
                                "p:ChIJPZImC8ZZtFIR9_fV1pe_1B8", "e:Rocktoberfest"]
    #else
    static func samples() -> [SearchItem] { [] }
    static let sampleRecents: [String] = []
    #endif
}
