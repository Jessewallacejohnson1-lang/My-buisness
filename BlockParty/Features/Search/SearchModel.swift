//
//  SearchModel.swift
//  Block Party — what the Search tab holds: the Town's places from Supabase with their
//  logos and the photos Block Party saved of them, the city's parks and trails, the neighbour's recent searches, the
//  neighbours found by name (`NeighborSearch`), the Town's groups (`get_groups`), and the Town feed's
//  Events (BP app five-tabs 04). With nothing typed it builds the resting page: the part of the
//  day's row, New in St. Joseph and Around town (`SearchAtRest`).
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
        /// One Block Party saved of the place (`public.place_photos`), drawn with its credit.
        case saved(PlacePicture)
        /// An Event's, as its Town card picks it: its own photo, else its place's with that credit.
        case card(FeedCardImageSource)

        /// A saved photo carries its credit wherever it shows (MEMORY.md, 2026-11-01).
        var credited: Bool {
            switch self {
            case .saved: true
            case .card(let source): source.attribution != nil
            case .bundled: false
            }
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
    var hours: PlaceHours? = nil
    /// A group opens onto its Group page (BP app rsvp-and-groups 05).
    var townGroup: TownGroup? = nil
    /// A place's `places.id`, which its page follows (BP app follows 02).
    var placeID: String? = nil
    /// Its name over its page's photos (`public.place_names`): lettering, or its logo landing there.
    var nameArt: PlaceName? = nil
    /// An Event's Town card: it opens the Event page (five-tabs 04).
    var card: FeedCardItem? = nil

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
        case .club: "person.2"
        case .event: "calendar"
        default: "photo"
        }
    }
}

/// A business's logo as Search draws it: cut out and centred on a square by the logo
/// pipeline, and 3D for the ones the `logo-3d` skill has made and checked. The file lives in
/// Storage (`places/<town>/<place_id>/logo-<hash>.webp`) and `places.search_logo` points at
/// it with its hue and row order, both written by BP app's `logo3d.py publish`. Images load
/// through `POILogoCache`, so a logo is fetched once and kept on disk.
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

/// The filter pills: places, businesses and events (BP app five-tabs 04). Groups and people moved to
/// the Friends tab; typing still finds them under All.
enum SearchChip: CaseIterable, Hashable {
    case all, businesses, events, parks

    var title: String {
        switch self {
        case .all: "All"
        case .businesses: "Businesses"
        case .events: "Events"
        case .parks: "Parks"
        }
    }

    var kind: SearchItem.Kind? {
        switch self {
        case .all: nil
        case .businesses: .business
        case .events: .event
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
    /// The last places and saved photos read, so a retry reads only what is missing.
    private var pois: [POI] = []
    private var savedPhotos: [String: [PlacePicture]]?
    /// Each place's name in its own lettering, by registry entry; read once, and none if it fails.
    private var names: [String: PlaceName] = [:]
    /// The Town's groups, in `get_groups`' order, and whether they have been read.
    private(set) var groups: [SearchItem] = []
    private(set) var groupsLoaded = false
    /// The Town feed's Events still to come, soonest first, and whether the feed has been read.
    private(set) var events: [SearchItem] = []
    private(set) var eventsLoaded = false
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
    /// Told every groups read, so a Group page knows who is in what (rsvp-and-groups 06).
    private let actions: RealLifeActions?
    /// Every read goes through the session's one client (`AppSession`).
    private let api: CommunityAPI
    private var fixed = SearchModel.parks()
    static let recentsKey = "search.recents"
    static let recentsMax = 8

    init(supabase: Supabase, defaults: UserDefaults = .standard, actions: RealLifeActions? = nil) {
        api = CommunityAPI(supabase)
        self.defaults = defaults
        self.actions = actions
        recentIDs = defaults.stringArray(forKey: Self.recentsKey) ?? Self.sampleRecents
    }

    var items: [SearchItem] { places + groups + events + fixed }

    /// Reads the Town's places and the photos saved of them, together, so a card's photo never
    /// lands after its logo, and the Town's groups beside them; tries again while the tab is open
    /// (2 s, 4 s, … 30 s apart) until all are in: offline, the rows wait as skeletons rather than
    /// vanish, and places read without their photos show their logos until a retry brings the photos.
    func load() async {
        var wait = 2.0
        while !(placesLoaded && photosLoaded && groupsLoaded) && !Task.isCancelled {
            let needPlaces = !placesLoaded, needPhotos = !photosLoaded, needGroups = !groupsLoaded
            async let readPlaces = needPlaces ? try? await api.getPlaces() : nil
            async let readPhotos = needPhotos ? try? await api.getPlacePhotos() : nil
            async let readGroups = needGroups ? try? await api.getGroups() : nil
            async let readNames = needPlaces ? try? await api.getPlaceNames() : nil
            let (newPlaces, newPhotos, newGroups) = await (readPlaces, readPhotos, readGroups)
            if let newNames = await readNames { names = newNames }
            if let newPlaces { pois = newPlaces }
            if let newPhotos { savedPhotos = newPhotos }
            if newPlaces != nil || (newPhotos != nil && placesLoaded) { show(pois, photos: savedPhotos) }
            if let newGroups { show(newGroups) }
            if placesLoaded && photosLoaded && groupsLoaded { return }
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 30)
        }
    }

    /// `photos` by registry entry; nil when they couldn't be read.
    func show(_ pois: [POI], photos: [String: [PlacePicture]]? = [:]) {
        places = Self.places(from: pois, photos: photos ?? [:], names: names)
        fixed = Self.parks(photos: photos ?? [:])
        placesLoaded = true
        photosLoaded = photos != nil
        let logos = places.compactMap(\.logo?.url)
        POILogoCache.shared.prefetch(logos)
        Task { await LogoReveal.shared.open(after: logos) }
    }

    func show(_ groups: [TownGroup]) {
        self.groups = Self.groups(from: groups)
        groupsLoaded = true
        actions?.read(groups)
    }

    /// The Town feed's cards once it has read them (nil before): Search's Events. The Town feed
    /// already leaves out what you hid or muted.
    func show(events cards: [FeedCardItem]?, now: Date = .now) {
        guard let cards else { return }
        events = Self.events(from: cards, now: now)
        eventsLoaded = true
    }

    /// The groups again for a new account, so whether you're in is this one's. The shelf keeps
    /// the last read meanwhile, and keeps it if this one fails.
    func readGroupsAgain() async {
        if let groups = try? await api.getGroups() { show(groups) }
    }

    // MARK: Rows

    /// One kind's row, in order. Businesses show only with a logo: the row is logos, each
    /// shown once.
    func row(_ kind: SearchItem.Kind) -> [SearchItem] {
        Self.ordered(items.filter { $0.kind == kind && (kind != .business || $0.logo?.onWall == true) })
    }

    /// Whether a kind's row is still waiting on Supabase.
    func isLoading(_ kind: SearchItem.Kind) -> Bool {
        (!placesLoaded && [.business, .restaurant, .coffee].contains(kind)) || (!groupsLoaded && kind == .club)
            || (!eventsLoaded && kind == .event)
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

    /// A place by its `places.id`, as its page opens; nil for one Search can't open (no logo) or hasn't
    /// read yet. The Town feed's places to try are drawn from here (town-feed 23).
    func place(_ id: String) -> SearchItem? {
        places.first { $0.placeID == id && $0.opens }
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
    static func places(from pois: [POI], photos: [String: [PlacePicture]] = [:],
                       names: [String: PlaceName] = [:]) -> [SearchItem] {
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
                              about: nonempty(poi.about), links: poi.links ?? [],
                              hours: poi.hours.flatMap { $0.days.allSatisfy(\.isEmpty) ? nil : $0 }, placeID: poi.id,
                              nameArt: poi.entryId.flatMap { names[$0] })
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
        [" | Italian", " - \(Town.everyday)", " Company", " Restaurant"]
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
        let trails = Town.trails
            .map { name, photo in
                SearchItem(id: "k:\(name)", kind: .park, name: name, sub: "Trail", photo: .bundled(photo),
                           group: "Trails", keywords: ["trail", "walk", "hike"])
            }
        return ranked(parks + trails)
    }

    /// The Town's groups as Search shows them, in the server's order: the cover photo, else the logo on
    /// its backdrop, else what kind of thing it is.
    static func groups(from groups: [TownGroup]) -> [SearchItem] {
        ranked(groups.map { group in
            SearchItem(id: "g:\(group.id)", kind: .club, name: group.name, sub: group.kind,
                       logo: group.photos.isEmpty ? group.logo.flatMap { FeedCardImageSource($0).logo } : nil,
                       photo: group.photos.first.map { .saved($0) },
                       keywords: ["group"] + [group.kind, group.location].compactMap { $0 },
                       townGroup: group)
        })
    }

    /// Fixed lists keep the order they are written in.
    static func ranked(_ items: [SearchItem]) -> [SearchItem] {
        items.enumerated().map { i, item in
            var item = item
            item.rank = i
            return item
        }
    }

    /// The Town feed's Events as Search shows them (five-tabs 04): what's on or still to come, not
    /// called off, soonest first, each opening its Event page. Under the Events pill they sit in
    /// Today, This week and Later.
    static func events(from cards: [FeedCardItem], now: Date) -> [SearchItem] {
        let timed = cards.compactMap { card in
            YouCalendar.event(from: card).flatMap { !card.cancelled && $0.ends > now ? $0 : nil }
        }
        return ranked(timed.sorted { $0.starts < $1.starts }.map { event in
            let card = event.item, days = Town.days(from: now, to: event.starts)
            return SearchItem(id: "e:\(card.id)", kind: .event, name: card.title,
                              // No photo: its place's logo bare on the page, as Search shows every logo.
                              sub: event.dayLine(now: now) ?? event.startTime(now: now), logo: card.image.logo,
                              photo: card.image.isPhoto ? .card(card.image) : nil,
                              group: days <= 0 ? "Today" : days < 7 ? "This week" : "Later",
                              keywords: ["event", card.what, card.hostName, card.location].compactMap { $0 },
                              card: card)
        })
    }

    // MARK: Search at rest (five-tabs 04, the mock's round 2)

    /// Most cards on a resting row, and tiles in Around town.
    static let restRowMax = 10
    static let aroundMax = 60

    /// The part of the day the first row is named for, and when it ends: morning from 5 to noon,
    /// afternoon to 5 PM, then tonight until 5 the next morning. Working words.
    static func dayPart(_ now: Date) -> (title: String, ends: Date) {
        let cal = Town.gregorian, hour = cal.component(.hour, from: now)
        func at(_ hour: Int, daysOn: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: daysOn, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? now
        }
        switch hour {
        case 5..<12: return ("This morning", at(12))
        case 12..<17: return ("This afternoon", at(17))
        case 17...: return ("Tonight", at(5, daysOn: 1))
        default: return ("Tonight", at(5))
        }
    }

    /// The first row: today's Events with a photo on now or starting before this part of the day
    /// ends, those on now first and the all-day ones last, then the places open now that have a page
    /// and a photo, `restRowMax` in all. Each says when: "Now", "6:30 PM", or how long the place
    /// stays open. A row of photos: an Event with none waits under the Events pill (picked).
    func happening(at now: Date) -> [SearchItem] {
        let ends = Self.dayPart(now).ends
        let on = events.compactMap { item -> (SearchItem, EventWhen)? in
            guard item.card?.image.isPhoto == true, let when = item.card?.when, when.end > now, when.start < ends
            else { return nil }
            var item = item
            item.sub = when.isOn(now) ? "Now" : when.timed ? Town.clock(when.start) : "All day"
            return (item, when)
        }
        .sorted { a, b in
            let order = { (w: EventWhen) in (w.timed ? 0 : 1, w.isOn(now) ? 0 : 1, w.start) }
            return order(a.1) < order(b.1)
        }
        .map(\.0)
        let open = places.filter { $0.opens && !$0.photos.isEmpty }.compactMap { place -> SearchItem? in
            guard let status = place.hours?.status(at: now) else { return nil }
            switch status {
            case .open, .closesSoon, .always:
                var place = place
                place.sub = PlaceHours.words(status)
                place.photo = place.photo ?? place.photos.first.map { .saved($0) }
                return place
            case .closed, .offSeason: return nil
            }
        }
        return Array((on + Self.ordered(open)).prefix(Self.restRowMax))
    }

    /// New in St. Joseph: the Events with a photo Block Party added in the last 7 days, newest first,
    /// leaving out games, repeating series (a school's season or a weekly class isn't news) and what
    /// the row above already shows (`without`), `restRowMax` at most; `all` gives every one, for the
    /// row's own page. Not places: the one added in October was new to Block Party, not new in town
    /// (ticket 04's comments).
    func fresh(at now: Date, without shown: [SearchItem] = [], all: Bool = false) -> [SearchItem] {
        let since = now.addingTimeInterval(-7 * 24 * 3600), shownIDs = Set(shown.map(\.id))
        let new = events.filter { item in
            guard let card = item.card, let added = card.createdAt, card.image.isPhoto else { return false }
            return added > since && card.game == nil && card.recurrence == nil && !shownIDs.contains(item.id)
        }
        .sorted { ($0.card?.createdAt ?? .distantPast) > ($1.card?.createdAt ?? .distantPast) }
        return all ? new : Array(new.prefix(Self.restRowMax))
    }

    /// Around town: Instagram's Explore of what's around town, every Event with a photo and every
    /// place with a page, by its cover, shuffled by `seed` (a new one each time Search opens),
    /// `aroundMax` at most and whole blocks of five. Only what opens: a tile never does nothing.
    func aroundTown(seed: UInt64) -> [SearchItem] {
        let shown = events.filter { $0.card?.image.isPhoto == true }
            + places.filter { $0.opens && !$0.photos.isEmpty }.map { place in
                var place = place
                place.photo = place.photos.first.map { .saved($0) }
                return place
            }
        var random = SeededRandom(seed: seed)
        let tiles = shown.shuffled(using: &random).prefix(Self.aroundMax)
        return Array(tiles.prefix(tiles.count - tiles.count % ExploreBlock.tiles))
    }

    #if DEBUG
    /// INVENTED: the mockup's starting recents (The Local Blend, "pumpkin", Lee's Ace
    /// Hardware), so the recents screen can be seen before any searching.
    /// Only when nothing was ever saved.
    static let sampleRecents = ["p:ChIJmTKJ0M9ZtFIRm7FAmBzwApc", "q:pumpkin", "p:ChIJPZImC8ZZtFIR9_fV1pe_1B8"]
    #else
    static let sampleRecents: [String] = []
    #endif
}

/// The same shuffle for the same seed (SplitMix64), so Around town holds still while Search is open
/// and through a trip to an Event page, and deals again on the next visit.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
