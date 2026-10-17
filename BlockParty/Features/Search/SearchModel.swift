//
//  SearchModel.swift
//  Block Party — what the Search tab holds: the Town's places from Supabase with their
//  logos and the photos Block Party saved of them, the city's parks and trails, the neighbour's recent searches, the
//  neighbours found by name (`NeighborSearch`), and, in DEBUG until their reads exist,
//  sample events and clubs.
//
//  Reference: Jesse's Search mockup v7 (claude.ai/artifact/Vqb74LLMXipRV8uhpefTo9) and
//  its five Figma frames, 2026-10-02. Row orders, names and labels follow the mockup.
//

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
        /// One Block Party saved of the place (`public.place_photos`), drawn with its credit.
        case saved(PlacePicture)

        /// A saved photo carries its credit wherever it shows (MEMORY.md, 2026-10-16).
        var credited: Bool {
            if case .saved = self { true } else { false }
        }
    }

    let id: String
    let kind: Kind
    /// As shown: "Krewe", not "Krewe Restaurant".
    let name: String
    var sub: String? = nil
    var logo: SearchLogo? = nil
    var photo: Photo? = nil
    /// The heading it sits under on its filter: Parks or Trails, Festivals or Markets.
    var group: String? = nil
    var keywords: [String] = []
    /// Its place on its row: the mockup's order first, then by name.
    var rank = Int.max
    /// What its business page shows (`BusinessPage`, like the Event page: Jesse, 2026-10-17):
    /// every photo Block Party saved of it, cover first, its street, its own words, its links.
    var photos: [PlacePicture] = []
    var street: String? = nil
    var about: String? = nil
    var links: [PlaceLink] = []

    /// A business or food place with a logo opens onto its own page of photos; the
    /// logo flies there (Jesse, 2026-10-04: restaurants and coffee open like logos).
    var opens: Bool { [.business, .restaurant, .coffee].contains(kind) && logo != nil }

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
/// pipeline, and 3D for the ones the `logo-3d` skill has made and checked. The file lives in
/// Storage (`places/<town>/<place_id>/logo-<hash>.webp`) and `places.search_logo` points at
/// it with its hue and row order, both written by BP app's `logo3d.py publish`. Images load
/// through `POILogoCache`, the map pins' cache, so a logo is fetched once and kept on disk.
struct SearchLogo: Hashable {
    /// `places.search_logo` as stored.
    struct Row: Decodable, Hashable {
        let url: URL
        let hue: Double
        let chroma: Bool
        var d3: Bool? = nil
        var rank: Int? = nil
        var wall: Bool? = nil
    }

    let placeId: String
    let url: URL
    let hue: Double
    /// A colourful logo; a black, white or grey one gets a nearly neutral backdrop.
    let chroma: Bool
    let is3D: Bool
    let rank: Int?
    /// Off the logo wall when another place shows the same logo there (Coborn's Pharmacy
    /// and Coborn's): it still opens from a search.
    let onWall: Bool

    init(placeId: String, row: Row) {
        self.placeId = placeId
        url = row.url
        hue = row.hue
        chroma = row.chroma
        is3D = row.d3 ?? false
        rank = row.rank
        onWall = row.wall ?? true
    }

    /// The photo-shoot backdrop in the logo's own hue, light at the centre top where
    /// the light hits and a little deeper at the edges.
    var backdrop: [Color] {
        let s: Double = chroma ? 30 : 9
        return [Hue.hsl(hue, s, 94), Hue.hsl(hue, s, 87), Hue.hsl(hue, max(5, s - 6), 76)]
    }

    /// The cast shadow's colour: a dark shade of the logo's hue, never grey.
    var shadow: Color { Hue.hsl(hue, chroma ? 30 : 10, 18) }
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
    /// Whether the saved photos have been read; until then a retry reads them again.
    private(set) var photosLoaded = false
    /// What the tab was showing, kept across tab switches as Instagram keeps it.
    var chip = SearchChip.all
    var words = ""
    /// From the field's first tap until Cancel: Cancel shows, and so do the recents.
    var searching = false
    /// Ids, newest first: an item's id, or `q:` and the words.
    private(set) var recentIDs: [String]
    /// Neighbours for the typed words, asked of the server. Kept here, not on the page,
    /// which is rebuilt on every tab switch while the words stay.
    let people = NeighborSearch()

    private let defaults: UserDefaults
    private var fixed = SearchModel.parks() + SearchModel.samples()
    static let recentsKey = "search.recents"
    static let recentsMax = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentIDs = defaults.stringArray(forKey: Self.recentsKey) ?? Self.sampleRecents
    }

    var items: [SearchItem] { places + fixed }

    /// Reads the Town's places and the photos saved of them, together, so a card's photo never
    /// lands after its logo; tries again while the tab is open (2 s, 4 s, … 30 s apart) until
    /// both are in: offline, the rows wait as skeletons rather than vanish, and places read
    /// without their photos show their logos until a retry brings the photos.
    func load() async {
        let api = CommunityAPI(auth: AuthStore.shared)
        var wait = 2.0
        while !(placesLoaded && photosLoaded) && !Task.isCancelled {
            async let readPlaces = try? api.getPlaces()
            async let readPhotos = try? api.getPlacePhotos()
            let (pois, photos) = await (readPlaces, readPhotos)
            if let pois { show(pois, photos: photos) }
            if placesLoaded && photosLoaded { return }
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 30)
        }
    }

    /// `photos` by registry entry; nil when they couldn't be read.
    func show(_ pois: [POI], photos: [String: [PlacePicture]]? = [:]) {
        places = Self.places(from: pois, photos: photos ?? [:])
        fixed = Self.parks(photos: photos ?? [:]) + Self.samples()
        placesLoaded = true
        photosLoaded = photos != nil
        POILogoCache.shared.prefetch(places.compactMap(\.logo?.url))
    }

    // MARK: Rows

    /// One kind's row, in order. Businesses show only with a logo: the row is logos, each
    /// shown once.
    func row(_ kind: SearchItem.Kind) -> [SearchItem] {
        Self.ordered(items.filter { $0.kind == kind && (kind != .business || $0.logo?.onWall == true) })
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

    /// `photos`: what Block Party saved of each place, by registry entry (`places.entry_id`). A
    /// food card shows the cover; a business shows its logo on the row, its photos on its page.
    static func places(from pois: [POI], photos: [String: [PlacePicture]] = [:]) -> [SearchItem] {
        pois.map { poi in
            let key = poi.placeId ?? poi.id
            let logo = poi.searchLogo.map { SearchLogo(placeId: key, row: $0) }
            let type = poi.primaryType ?? ""
            let kind: SearchItem.Kind = poi.family == .business ? .business
                : coffeeTypes.contains(type) ? .coffee : .restaurant
            let saved = poi.entryId.flatMap { photos[$0] } ?? []
            return SearchItem(id: "p:\(key)", kind: kind, name: shown(poi.name), sub: label(type), logo: logo,
                              photo: kind == .business ? nil : saved.first.map { .saved($0) },
                              keywords: [type.replacingOccurrences(of: "_", with: " ")],
                              rank: logo?.rank ?? .max, photos: saved, street: street(poi.address),
                              about: nonempty(poi.about), links: poi.links ?? [])
        }
    }

    /// An address's first part, its street: "21 1st Ave NW" of "21 1st Ave NW, St. Joseph, MN 56374".
    static func street(_ address: String?) -> String? {
        nonempty(address?.split(separator: ",", maxSplits: 1).first.map(String.init))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
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

    /// The city's parks, and the trails the app has a bundled photo of. A park's photo is one
    /// Block Party saved of it (by the park's id, BP app place-photos 04), else its bundled
    /// one; with neither, Search shows what kind of place it is (Jesse, 2026-10-17).
    static func parks(photos: [String: [PlacePicture]] = [:]) -> [SearchItem] {
        let parks = CityParks.all.map { park in
            let photo: SearchItem.Photo? = photos[park.id]?.first.map { .saved($0) }
                ?? KnownLocalPhoto.name(forTitle: park.title).map { .bundled($0) }
            return SearchItem(id: "k:\(park.id)", kind: .park, name: park.title, sub: "Park", photo: photo,
                              group: "Parks", keywords: ["park"] + park.features)
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
    /// INVENTED, as Jesse asked (2026-10-02, "just mock it up"): events and clubs, until
    /// their reads exist; the Town has none yet. Names and photos are the mockup's. People
    /// are real now (`people`), found by name once something is typed.
    static func samples() -> [SearchItem] {
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
        return ranked(events) + ranked(clubs)
    }

    /// INVENTED: the mockup's starting recents (The Local Blend, "pumpkin", Lee's Ace
    /// Hardware, Rocktoberfest), so the recents screen can be seen before any searching.
    /// Only when nothing was ever saved.
    static let sampleRecents = ["p:ChIJmTKJ0M9ZtFIRm7FAmBzwApc", "q:pumpkin",
                                "p:ChIJPZImC8ZZtFIR9_fV1pe_1B8", "e:Rocktoberfest"]
    #else
    static func samples() -> [SearchItem] { [] }
    static let sampleRecents: [String] = []
    #endif
}
