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

/// One thing Search can show: a neighbour, a school or one of its activities, a business, a food
/// place, an event, a club or a park.
struct SearchItem: Identifiable, Hashable {
    /// Typed results come in this order under All: Schools first, as the mock's typed results (school-search 01).
    enum Kind: CaseIterable {
        case person, school, business, restaurant, coffee, event, club, park
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
    /// A school, or one of its activities, opens the school's page (`TeamPage`, school-search 01).
    var team: Game.Team? = nil
    /// An activity's star follows it, as the school page's does (school-search 01); nil for anything else.
    var activity: FollowTarget? = nil
    /// An activity's next event, its day after the school's name (school-search 06): worked out as the row is
    /// drawn, so a Search left open overnight never says Today for yesterday.
    var next: EventWhen? = nil

    /// The line under its name: `sub`, then an activity's next day ("Kennedy · Tomorrow").
    func line(_ now: Date) -> String? {
        let parts = [sub, next.flatMap { Self.day($0, now: now) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// An event's day from `now`, as the mock says it: "Today" ("Tonight" from 5 PM), "Tomorrow", the weekday within
    /// the week ("Fri"), else the date ("Nov 20"); nil once it's past.
    static func day(_ when: EventWhen, now: Date) -> String? {
        switch Town.days(from: now, to: when.start) {
        case ..<0: nil
        case 0, 1: when.dayWord(now)
        case 2..<7: Town.format(when.start, "EEE")
        default: Town.format(when.start, "MMMd")
        }
    }

    /// A school's id by its team's uuid: its crest on the row and its disc on Sports are one recent.
    static func schoolID(_ uuid: String) -> String { "s:\(uuid)" }

    /// A business or food place opens onto its own page of photos; the logo flies there (Jesse,
    /// 2026-10-04: restaurants and coffee open like logos). One with no logo yet flies its letter disc
    /// instead (Jesse, 2026-11-08, BP app place-pages: the directory is complete, logos follow).
    var opens: Bool { [.business, .restaurant, .coffee].contains(kind) }

    /// The letter its disc shows while it has no logo: the first letter of its name, as a young team's.
    var initial: String { name.first(where: \.isLetter).map { String($0).uppercased() } ?? "" }

    /// The shadow its mark casts as it flies to its page: the logo's own hue, or the studio's neutral one.
    var markShadow: Color { logo?.shadow ?? Hue.hsl(Hue.searchStudioHue, 15, 18) }

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
    var shadow: Color { Self.shadow(hue: hue, chroma: chroma) }

    /// A dark shade of `hue` (degrees), nearly neutral for a black, white or grey logo: Search's and a game's team logos.
    static func shadow(hue: Double, chroma: Bool) -> Color { Hue.hsl(hue, chroma ? 30 : 10, 18) }
}

/// The filter pills: places, businesses, the schools' sports and events (BP app five-tabs 04, school-search 04), and
/// right after All the Event calendar (five-tabs 10).
/// Groups and people moved to the Friends tab; typing still finds them under All.
enum SearchChip: CaseIterable, Hashable {
    case all, calendar, businesses, sports, events, parks

    var title: String {
        switch self {
        case .all: "All"
        case .calendar: "Event calendar"
        case .businesses: "Businesses"
        case .sports: "Sports"
        case .events: "Events"
        case .parks: "Parks"
        }
    }

    var kind: SearchItem.Kind? {
        switch self {
        case .all, .calendar: nil
        case .businesses: .business
        case .sports: .school
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
        // Typed under the calendar, words find Events.
        case .calendar: [.event]
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
    /// The Town's schools in the row's order, then their activities (school-search 01), and whether they have been read.
    private(set) var schools: [SearchItem] = []
    private(set) var schoolsLoaded = false
    /// Each activity's next event by its id, read on its own so Search never waits for it.
    private var next: [String: EventWhen] = [:]
    private var nextLoaded = false
    /// The same schools as the Sports chip's discs show them, colleges first (school-search 04).
    private(set) var schoolDiscs: [SearchItem] = []
    /// The Event calendar's year of public Events in its order (BP app five-tabs 10), nil until the first read lands,
    /// and whether the last read failed. Kept across tab switches, as the rest is.
    private(set) var calendar: [DailyEvent]?
    private(set) var calendarFailed = false
    @ObservationIgnored private var latestCalendar = 0
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

    var items: [SearchItem] { places + groups + events + schools + fixed }

    /// Reads the Town's places and the photos saved of them, together, so a card's photo never
    /// lands after its logo, and the Town's groups and schools beside them; tries again while the tab is open
    /// (2 s, 4 s, … 30 s apart) until all are in: offline, the rows wait as skeletons rather than
    /// vanish, and places read without their photos show their logos until a retry brings the photos.
    /// Reads the Event calendar on every visit to its pill and each new account, so a Not interested or Mute from
    /// the Town feed shows on the next visit. The list on screen stays through a read and a failed one. Under DEBUG
    /// `-town-samples` it is You's invented Events, and `-town-offline` fails.
    func loadCalendar() async {
        latestCalendar += 1
        let mine = latestCalendar
        if calendar == nil { calendarFailed = false }
        do {
            let rows = try await readCalendar()
            guard mine == latestCalendar else { return }
            calendar = EventCalendar.ordered(rows.compactMap(YouCalendar.event(from:)))
            calendarFailed = false
        } catch {
            // Leaving the pill mid-read cancels it; that says nothing about the network.
            guard mine == latestCalendar, !Task.isCancelled, !(error is CancellationError) else { return }
            calendarFailed = true
        }
    }

    private func readCalendar() async throws -> [UpcomingEvent] {
        #if DEBUG
        switch LaunchFlags.backend {
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples: return YouCalendar.samples(now: Date()).map { var row = $0; row.rsvpd = false; return row }
        case .live: break
        }
        #endif
        return try await api.getTownCalendar()
    }

    func load() async {
        var wait = 2.0
        while !(placesLoaded && photosLoaded && groupsLoaded && schoolsLoaded && nextLoaded) && !Task.isCancelled {
            let needPlaces = !placesLoaded, needPhotos = !photosLoaded, needGroups = !groupsLoaded
            let needSchools = !schoolsLoaded, needNext = !nextLoaded
            async let readPlaces = needPlaces ? try? await api.getPlaces() : nil
            async let readPhotos = needPhotos ? try? await api.getPlacePhotos() : nil
            async let readGroups = needGroups ? try? await api.getGroups() : nil
            async let readNames = needPlaces ? try? await api.getPlaceNames() : nil
            async let readSchools = needSchools ? try? await api.schoolsAndActivities() : nil
            async let readNext = needNext ? try? await api.activitiesNext() : nil
            let (newPlaces, newPhotos, newGroups) = await (readPlaces, readPhotos, readGroups)
            if let newSchools = await readSchools { show(schools: newSchools.schools, activities: newSchools.activities) }
            if let newNames = await readNames { names = newNames }
            if let newPlaces { pois = newPlaces }
            if let newPhotos { savedPhotos = newPhotos }
            if newPlaces != nil || (newPhotos != nil && placesLoaded) { show(pois, photos: savedPhotos) }
            if let newGroups { show(newGroups) }
            // Last, so nothing above waits for it.
            if let newNext = await readNext { show(next: newNext) }
            if placesLoaded && photosLoaded && groupsLoaded && schoolsLoaded && nextLoaded { return }
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

    /// The Town's schools (`teams.local`) and the activities each lists: the row's crests in `Town.searchSchools`'
    /// order, Kennedy first, and each activity after them under its school's place, in the school's own order.
    func show(schools: [LocalSchool], activities: [SchoolActivity]) {
        self.schools = Self.schools(schools, activities: activities).map(withNext)
        schoolDiscs = Self.schoolDiscs(schools, rows: self.schools)
        schoolsLoaded = true
        POILogoCache.shared.prefetch(schools.compactMap(\.crest?.url))
    }

    /// Each activity's next event (school-search 06), on its row whenever the schools arrive.
    func show(next rows: [ActivityNext]) {
        next = Dictionary(rows.compactMap { row in EventWhen(date: row.date, time: row.time, endAt: nil).map { (row.id, $0) } },
                          uniquingKeysWith: { a, _ in a })
        nextLoaded = true
        schools = schools.map(withNext)
    }

    private func withNext(_ item: SearchItem) -> SearchItem {
        guard let id = item.activity?.id else { return item }
        var item = item
        item.next = next[id]
        return item
    }

    /// Which activities you follow, so a typed activity's star says so (school-search 01): each account's own,
    /// read on each visit to Search. A failed read, or no account, leaves the stars as they were.
    func readStars() async {
        guard let ids = try? await api.followedActivities() else { return }
        actions?.read(following: ids.map { FollowTarget(type: .activity, id: $0) })
    }

    /// The groups again for a new account, so whether you're in is this one's. The shelf keeps
    /// the last read meanwhile, and keeps it if this one fails.
    func readGroupsAgain() async {
        if let groups = try? await api.getGroups() { show(groups) }
    }

    // MARK: Rows

    /// One kind's row, in order. Businesses show only with a logo: the row is logos, each
    /// shown once. Schools show their crests, not their activities.
    func row(_ kind: SearchItem.Kind) -> [SearchItem] {
        Self.ordered(items.filter { $0.kind == kind && (kind != .business || $0.logo?.onWall != false) && $0.activity == nil })
    }

    /// Whether a kind's row is still waiting on Supabase.
    func isLoading(_ kind: SearchItem.Kind) -> Bool {
        (!placesLoaded && [.business, .restaurant, .coffee].contains(kind)) || (!groupsLoaded && kind == .club)
            || (!eventsLoaded && kind == .event) || (!schoolsLoaded && kind == .school)
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
    /// small typos. A school's activity is found by its own name, never its school's, and sits after
    /// the schools named (school-search 01), the closest match first, then its school's place in the row:
    /// Kennedy's first.
    func results(for words: String, in chip: SearchChip) -> [(kind: SearchItem.Kind, items: [SearchItem])] {
        let q = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return chip.resultKinds.compactMap { kind in
            let hits = items.filter { $0.kind == kind }
                .compactMap { item in
                    TownSearch.score(q, name: item.name, extra: item.activity == nil ? [item.sub ?? ""] : [],
                                     aliases: item.keywords).map { (item, $0) }
                }
                .sorted { a, b in
                    let (x, y) = (a.0.activity != nil, b.0.activity != nil)
                    if x != y { return y }
                    if x && a.1 == b.1 { return a.0.rank < b.0.rank }
                    return a.1 > b.1
                }
                .map(\.0)
            return hits.isEmpty ? nil : (kind, hits)
        }
    }

    // MARK: Recents

    /// The recents a tap on the empty field shows under a pill: on Sports only the schools and activities opened
    /// there or under All (the run's review), on every other pill all of them.
    func recents(in chip: SearchChip) -> [SearchRecent] {
        guard chip == .sports else { return recents }
        return recents.filter {
            if case .item(let item) = $0 { item.kind == .school } else { false }
        }
    }

    var recents: [SearchRecent] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return recentIDs.compactMap { id in
            if id.hasPrefix("q:") { return .query(String(id.dropFirst(2))) }
            return byID[id].map { .item($0) }
        }
    }

    /// A place by its `places.id`, as its page opens; nil for one Search hasn't read yet. The Town feed's
    /// places to try are drawn from here (town-feed 23).
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
    /// food card shows the cover; a business shows its logo on the row, its photos on its page. A
    /// city park's row (place-pages 01) is left out here: Search already shows the park from
    /// `CityParks`, with its photo and features, so it isn't listed twice.
    static func places(from pois: [POI], photos: [String: [PlacePicture]] = [:],
                       names: [String: PlaceName] = [:]) -> [SearchItem] {
        pois.filter { poi in !CityParks.all.contains { $0.id == poi.entryId } }.map { poi in
            let key = poi.placeId ?? poi.id
            let logo = poi.searchLogo.map { SearchLogo(placeId: key, row: $0) }
            let type = poi.primaryType ?? ""
            let kind: SearchItem.Kind = poi.family == .business ? .business
                : coffeeTypes.contains(type) ? .coffee : .restaurant
            let saved = poi.entryId.flatMap { photos[$0] } ?? []
            return SearchItem(id: "p:\(key)", kind: kind, name: shown(poi.name), sub: label(type), logo: logo,
                              photo: kind == .business ? nil : saved.first.map { .saved($0) },
                              // Someone looking for a brewery wants a cidery too.
                              keywords: [type.replacingOccurrences(of: "_", with: " ")] + (type == "cidery" ? ["brewery"] : []),
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

    /// The schools `Town.searchSchools` names, in its order, each opening its page; then every activity they list,
    /// ranked after them by its school's place and the school's own order, found by its own name only.
    static func schools(_ schools: [LocalSchool], activities: [SchoolActivity]) -> [SearchItem] {
        let shown = Town.searchSchools.compactMap { id in schools.first { $0.id == id } }
        let rows = shown.enumerated().map { i, school in
            SearchItem(id: SearchItem.schoolID(school.uuid), kind: .school, name: school.schoolName ?? school.name, sub: school.nickname,
                       logo: school.crest,
                       keywords: [school.shortName, school.nickname].compactMap { $0 } + (school.aliases ?? []),
                       rank: i, team: Game.Team(school: school))
        }
        let byID = Dictionary(zip(shown.map(\.id), rows), uniquingKeysWith: { a, _ in a })
        let found = activities.enumerated().compactMap { order, activity -> SearchItem? in
            guard let school = byID[activity.teamId], let team = school.team else { return nil }
            // After every school; then by its school's place on the row, each school taking a block as long as the
            // whole list; then by the school's own order within that block.
            let afterSchools = rows.count, schoolBlock = school.rank * activities.count
            return SearchItem(id: "a:\(activity.id)", kind: .school, name: activity.name, sub: team.short, logo: school.logo,
                              rank: afterSchools + schoolBlock + order, team: team,
                              activity: FollowTarget(type: .activity, id: activity.id))
        }
        return rows + found
    }

    /// The Sports chip's discs (school-search 04, Jesse 2026-11-11: "college first then highschools"): the Schools
    /// row's schools, the colleges, then the high schools, then the rest (Kennedy, K-8), each A to Z by the short
    /// name under its disc. Each is its school's row, so it opens the school's page and remembers as one.
    static func schoolDiscs(_ schools: [LocalSchool], rows: [SearchItem]) -> [SearchItem] {
        func level(_ school: LocalSchool) -> DiscLevel {
            let types = Town.schoolTypes.filter { $0.schools.contains { $0.key == school.id } }
            return types.contains(where: \.isCollege) ? .college : types.contains(where: \.isHighSchool) ? .highSchool : .other
        }
        func short(_ school: LocalSchool) -> String { school.shortName ?? school.name }
        return schools
            .sorted { a, b in
                level(a) != level(b) ? level(a) < level(b)
                    : short(a).localizedStandardCompare(short(b)) == .orderedAscending
            }
            .compactMap { school in rows.first { $0.id == SearchItem.schoolID(school.uuid) } }
    }

    /// The Sports chip's levels, in the order their discs come.
    enum DiscLevel: Int, Comparable {
        case college, highSchool, other

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
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
            item.sub = item.card?.isNow(at: now) == true ? "Now" : when.timed ? Town.clock(when.start) : "All day"
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
    /// place with a page, by its cover, dealt by `seed` (a new one each time Search opens),
    /// `aroundMax` at most and whole blocks of five. Only what opens: a tile never does nothing.
    /// Each tile's spot comes from the seed and its own id, so an Event leaving the feed takes only
    /// its own tile with it and the rest hold still.
    func aroundTown(seed: UInt64) -> [SearchItem] {
        let shown = events.filter { $0.card?.image.isPhoto == true }
            + places.filter { $0.opens && !$0.photos.isEmpty }.map { place in
                var place = place
                place.photo = place.photos.first.map { .saved($0) }
                return place
            }
        let spot = { (item: SearchItem) in
            var hasher = Hasher()
            hasher.combine(seed)
            hasher.combine(item.id)
            return hasher.finalize()
        }
        let tiles = shown.map { ($0, spot($0)) }.sorted { $0.1 < $1.1 }.map(\.0).prefix(Self.aroundMax)
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
