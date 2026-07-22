//
//  GooglePlacesService.swift
//  Block Party — Google Places API (New) client. places.googleapis.com/v1 only.
//
//  Same shape as GeocoderService (TrailServices.swift): a
//  @MainActor singleton whose caches stay on the main actor, hand-rolled over
//  URLSession, failing soft (nil / []) so the UI never sees an error.
//
//  Cost discipline (keep it frugal, no hard cap):
//   • autocomplete carries a per-typing-session token so Google bills the whole
//     autocomplete→details exchange as one session; inputs are cached too.
//   • details / searchText send a minimal X-Goog-FieldMask — the fields we ask
//     for ARE the cost. No rating fields, ever (brand rule).
//   • details are cached hard by place_id (the main spend lever).
//
//  Locked Rule A — the trust gate that clears a photo for display — lives in the
//  `RuleA` enum at the bottom of this file. An aligned name is always required; the
//  radius allowed around the curated coordinate is sized by how exact the name match
//  is and how large the place's footprint is (90 m fuzzy / 400 m exact / 2 km exact
//  on a park·arboretum·trail·campus type). Measured, not guessed — see RuleA's docs.
//
//  Google ToS: place_ids may be persisted (do that in Supabase); photo names may
//  NOT be persisted — they live only in this in-memory session cache and must be
//  re-fetched from a fresh details() call. Any photo authorAttributions must be
//  displayed wherever the image appears (surfaced on PlacePhoto).
//

import Foundation
import CoreLocation

// MARK: - Public models

struct PlaceSuggestion: Identifiable, Equatable {
    let placeId: String
    let primaryText: String     // the venue name
    let secondaryText: String   // the address / context line
    var id: String { placeId }
}

struct PlaceResult: Identifiable {
    let placeId: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let primaryType: String?        // Google category (e.g. "cafe") — nil if absent
    let types: [String]             // raw Google types[]
    var id: String { placeId }
}

struct PlacePhoto: Equatable {
    let name: String                // "places/{id}/photos/{ref}" — never persist
    let attributions: [String]      // author names; must be shown with the image
}

struct PlaceDetails {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let address: String?
    let openNow: Bool?
    let hours: [String]             // human-readable weekday lines
    let website: URL?
    let phone: String?
    let primaryType: String?        // Google category (e.g. "cafe") — nil if absent
    let types: [String]             // raw Google types[]
    let photo: PlacePhoto?          // first photo only
}

/// A place discovered by a Nearby Search sweep — carries the category type data the
/// POI seeder maps onto a family. Nearby Search (New) caps at 20 results per call and
/// has no pagination, so the seeder sweeps several `includedTypes` groups.
struct NearbyPlace: Identifiable {
    let placeId: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let primaryType: String?
    let types: [String]
    let address: String?
    let isOperational: Bool
    var id: String { placeId }
}

/// A photo cleared by Locked Rule A's confidence check — safe to display.
struct ConfidentPhoto {
    let photoName: String           // pass to photoURL(name:maxWidth:)
    let attributions: [String]
}

// MARK: - Service

@MainActor
final class GooglePlacesService {
    static let shared = GooglePlacesService()
    private init() {}

    private var autocompleteCache: [String: [PlaceSuggestion]] = [:]
    private var searchCache: [String: [PlaceResult]] = [:]
    private var detailsCache: [String: PlaceDetails] = [:]
    private var confidentPhotoCache: [String: ConfidentPhoto?] = [:]   // "name|lat,lon" → resolved (or checked-nil)
    private var confidentPhotoInFlight: [String: Task<ConfidentPhoto?, Never>] = [:]  // coalesce concurrent callers per key

    private static let base = "https://places.googleapis.com/v1"
    private static let biasRadius = 15_000.0   // ~15 km around town

    /// A fresh autocomplete session token. The caller holds one while the user
    /// types, passes it to every autocomplete(_:) call and the final
    /// details(placeId:) call, then discards it — one billed session.
    func newSessionToken() -> String { UUID().uuidString }

    // MARK: Autocomplete

    /// Type-ahead suggestions biased to St. Joseph, MN. Returns [] on any failure.
    func autocomplete(_ input: String, sessionToken: String? = nil) async -> [PlaceSuggestion] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        if let hit = autocompleteCache[query] { return hit }

        var body: [String: Any] = [
            "input": query,
            "includedRegionCodes": ["us"],
            "locationBias": locationBias(),
        ]
        if let sessionToken { body["sessionToken"] = sessionToken }

        var req = URLRequest(url: URL(string: "\(Self.base)/places:autocomplete")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(GOOGLE_PLACES_API_KEY, forHTTPHeaderField: "X-Goog-Api-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            // A non-2xx returns a JSON error body that decodes as an all-nil "success";
            // bail before caching so a transient 429 doesn't poison the query.
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let resp = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
            let suggestions: [PlaceSuggestion] = (resp.suggestions ?? []).compactMap { s in
                guard let p = s.placePrediction else { return nil }
                let primary = p.structuredFormat?.mainText?.text ?? p.text?.text ?? ""
                guard !primary.isEmpty else { return nil }
                return PlaceSuggestion(placeId: p.placeId,
                                       primaryText: primary,
                                       secondaryText: p.structuredFormat?.secondaryText?.text ?? "")
            }
            autocompleteCache[query] = suggestions
            return suggestions
        } catch { return [] }
    }

    // MARK: Details

    /// Full details for a place_id. Field mask is minimal + rating-free. Passing
    /// the autocomplete sessionToken here closes that billed session. nil on failure.
    func details(placeId: String, sessionToken: String? = nil) async -> PlaceDetails? {
        if let hit = detailsCache[placeId] { return hit }

        var comps = URLComponents(string: "\(Self.base)/places/\(placeId)")!
        if let sessionToken {
            comps.queryItems = [URLQueryItem(name: "sessionToken", value: sessionToken)]
        }
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue(GOOGLE_PLACES_API_KEY, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("location,displayName,formattedAddress,currentOpeningHours,websiteUri,nationalPhoneNumber,photos.name,photos.widthPx,photos.heightPx,photos.authorAttributions,primaryType,types",
                     forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let resp = try JSONDecoder().decode(DetailsResponse.self, from: data)
            guard let loc = resp.location else { return nil }
            let photo = Self.bestScenicPhoto(resp.photos)
            let details = PlaceDetails(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                name: resp.displayName?.text ?? "",
                address: resp.formattedAddress,
                openNow: resp.currentOpeningHours?.openNow,
                hours: resp.currentOpeningHours?.weekdayDescriptions ?? [],
                website: resp.websiteUri.flatMap { URL(string: $0) },
                phone: resp.nationalPhoneNumber,
                primaryType: resp.primaryType,
                types: resp.types ?? [],
                photo: photo)
            detailsCache[placeId] = details
            return details
        } catch { return nil }
    }

    // MARK: Scenic photo pick

    /// Choose the most SCENIC of a place's up-to-10 photos using only the metadata
    /// Google gives us (pixel dimensions + array order — never the pixels). Google
    /// returns `photos[0]` as a conventional "cover" but the array isn't relevance-
    /// ranked, and `.first` is often a logo, a menu, or an interior close-up. We
    /// prefer a large, landscape-ish exterior shot (the kind that reads as "scenery
    /// of the place"): drop near-square / portrait / tiny frames, then score what's
    /// left on resolution, closeness to a ~1.6 hero aspect, and a mild early-index
    /// bonus. If nothing clears the filter, fall back to Google's cover photo so we
    /// never show nothing when a photo does exist.
    private static func bestScenicPhoto(_ photos: [DetailsResponse.Photo]?) -> PlacePhoto? {
        guard let photos, !photos.isEmpty else { return nil }
        func make(_ p: DetailsResponse.Photo) -> PlacePhoto {
            PlacePhoto(name: p.name, attributions: (p.authorAttributions ?? []).compactMap { $0.displayName })
        }
        var best: (score: Double, photo: DetailsResponse.Photo)?
        for (i, p) in photos.enumerated() {
            guard let w = p.widthPx, let h = p.heightPx, w > 0, h > 0 else { continue }
            let aspect = Double(w) / Double(h)
            let minDim = Double(min(w, h))
            // Reject square/portrait (logos, menus, food/interior close-ups),
            // ultra-panoramas (banners, floorplans), and anything too small to
            // stay crisp when blown up to a hero.
            guard aspect >= 1.15, aspect <= 2.4, minDim >= 480 else { continue }
            let resolutionScore = min(Double(w), 2400) / 2400 * 40
            let aspectScore = 30 - abs(aspect - 1.6) * 20
            let positionScore = max(0, 10 - Double(i) * 1.5)
            let score = resolutionScore + aspectScore + positionScore
            if best == nil || score > best!.score { best = (score, p) }
        }
        return make(best?.photo ?? photos[0])
    }

    // MARK: Text search (geocode fallback only)

    /// St-Joe-biased text search — used ONLY as a geocode fallback (Phase 3).
    /// A place_id from here is a fuzzy match: never source a photo from it. [] on failure.
    func search(_ query: String) async -> [PlaceResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        if let hit = searchCache[q] { return hit }

        let body: [String: Any] = [
            "textQuery": q,
            "regionCode": "us",
            "locationBias": locationBias(),
        ]

        var req = URLRequest(url: URL(string: "\(Self.base)/places:searchText")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(GOOGLE_PLACES_API_KEY, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.id,places.location,places.displayName,places.primaryType,places.types", forHTTPHeaderField: "X-Goog-FieldMask")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
            let results: [PlaceResult] = (resp.places ?? []).compactMap { p in
                guard let loc = p.location, let name = p.displayName?.text, !name.isEmpty else { return nil }
                return PlaceResult(placeId: p.id,
                                   name: name,
                                   coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                                   primaryType: p.primaryType,
                                   types: p.types ?? [])
            }
            searchCache[q] = results
            return results
        } catch { return [] }
    }

    // MARK: Nearby search (POI seeding — one-time, never on a map load)

    /// Nearby Search (New) around `center`, restricted to `includedTypes`. Returns up
    /// to `maxResults` places (Google caps this at 20 and offers NO pagination, so the
    /// seeder sweeps several `includedTypes` groups) with their category type data.
    /// [] on any failure. Used ONLY by PlaceSeeder to populate Supabase.
    func nearby(includedTypes: [String],
                center: CLLocationCoordinate2D? = nil,
                radius: Double = 2500,
                maxResults: Int = 20) async -> [NearbyPlace] {
        guard !includedTypes.isEmpty else { return [] }
        let center = center ?? MapSpots.center
        let body: [String: Any] = [
            "includedTypes": includedTypes,
            "maxResultCount": max(1, min(maxResults, 20)),
            "rankPreference": "POPULARITY",
            "locationRestriction": ["circle": [
                "center": ["latitude": center.latitude, "longitude": center.longitude],
                "radius": radius,
            ]],
        ]

        var req = URLRequest(url: URL(string: "\(Self.base)/places:searchNearby")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(GOOGLE_PLACES_API_KEY, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.id,places.displayName,places.location,places.primaryType,places.types,places.formattedAddress,places.businessStatus",
                     forHTTPHeaderField: "X-Goog-FieldMask")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let resp = try JSONDecoder().decode(NearbyResponse.self, from: data)
            return (resp.places ?? []).compactMap { p in
                guard let loc = p.location, let name = p.displayName?.text, !name.isEmpty else { return nil }
                return NearbyPlace(placeId: p.id,
                                   name: name,
                                   coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                                   primaryType: p.primaryType,
                                   types: p.types ?? [],
                                   address: p.formattedAddress,
                                   isOperational: (p.businessStatus ?? "OPERATIONAL") == "OPERATIONAL")
            }
        } catch { return [] }
    }

    // MARK: Photo

    /// Loadable media URL for a photo `name` from details(). The endpoint 302s to
    /// the image, so AsyncImage / URLSession can load it directly.
    func photoURL(name: String, maxWidth: Int = 800) -> URL {
        var comps = URLComponents(string: "\(Self.base)/\(name)/media")!
        comps.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(maxWidth)),
            URLQueryItem(name: "key", value: GOOGLE_PLACES_API_KEY),
        ]
        return comps.url!
    }

    // MARK: Confident-match photo for free text (events, trails, clubs)

    /// Like `confidentPhoto(name:coordinate:)`, but for a free-text venue name that
    /// has no curated coordinate of its own (a community-submitted trail, event, or
    /// club). Only attempts a match when `title`/`hint` resolves against KnownVenues
    /// — Rule A needs an independent, human-verified coordinate to check Google's
    /// text-search result against, and KnownVenues is the only source of one outside
    /// the fixed MapSpots set. No KnownVenues match → nil, never a guess.
    func confidentPhoto(forFreeText title: String, hint: String?) async -> ConfidentPhoto? {
        let query = [title, hint].compactMap { $0 }.joined(separator: " ")
        guard let coord = KnownVenues.coordinate(for: query) else { return nil }
        return await confidentPhoto(name: title, coordinate: coord)
    }

    // MARK: Confident-match photo (Locked Rule A)

    /// A photo for a KNOWN/curated place — but only if Google's text-search match
    /// clears the Locked Rule A gate (`RuleA.clears`): the names must line up, and how
    /// far the match may sit from the curated coordinate depends on how strong that
    /// name evidence is and how big the place's footprint is — 90 m for a merely
    /// similar name, 400 m for an exact one, 2 km for an exact name on a large-footprint
    /// type (park · arboretum · trail · campus). `search()` is a fuzzy fallback; this is
    /// the ONE place that decides a match is trustworthy enough to show its photo.
    /// Cached per curated name (a small, fixed set), so repeat callers (a list row and
    /// its detail view) don't re-run the confidence check. nil if not confidently
    /// identified or the place has no photo.
    func confidentPhoto(name: String, coordinate: CLLocationCoordinate2D) async -> ConfidentPhoto? {
        // Key on name + coordinate: a generic reused label ("Community Room") can
        // resolve to different curated coordinates per caller, and each must run its
        // own Rule A check rather than inherit the first caller's result.
        let key = "\(name)|\(coordinate.latitude),\(coordinate.longitude)"
        if let hit = confidentPhotoCache[key] { return hit }
        // Coalesce concurrent callers for the same venue (e.g. several list cards
        // sharing one location) onto a single billed Places round-trip.
        if let inFlight = confidentPhotoInFlight[key] { return await inFlight.value }

        let task = Task { () -> ConfidentPhoto? in
            // Google's first hit isn't always the right place — a "Monument Park"
            // query can rank the (wrong) "Memorial Park" first and the real one
            // third. Scan the top few and gate each with Rule A using the cheap
            // search result: it already carries primaryType + types, so the
            // large-footprint tier costs no extra billed field and no extra call.
            // Only a candidate that has cleared the gate is worth a details() call.
            for candidate in await self.search("\(name) St Joseph MN").prefix(5) {
                guard RuleA.clears(resolvedName: candidate.name,
                                   resolvedCoordinate: candidate.coordinate,
                                   types: candidate.types,
                                   primaryType: candidate.primaryType,
                                   curatedName: name,
                                   curatedCoordinate: coordinate)
                else { continue }
                guard let d = await self.details(placeId: candidate.placeId), let photo = d.photo else { continue }
                return ConfidentPhoto(photoName: photo.name, attributions: photo.attributions)
            }
            return nil
        }
        confidentPhotoInFlight[key] = task
        let result = await task.value
        confidentPhotoInFlight[key] = nil
        confidentPhotoCache[key] = .some(result)
        return result
    }

    // MARK: Shared

    private func locationBias() -> [String: Any] {
        ["circle": [
            "center": ["latitude": MapSpots.center.latitude, "longitude": MapSpots.center.longitude],
            "radius": Self.biasRadius,
        ]]
    }
}

// MARK: - Locked Rule A (the confidence gate)

/// Decides whether a Google text-search hit is the SAME PLACE as one of our curated
/// venues. It is the only gate that clears a photo for display, so it errs toward
/// showing nothing: no name agreement means no photo, at any distance.
///
/// Stateless and `nonisolated` so it can be evaluated from any isolation (the module
/// defaults to MainActor isolation).
///
/// THREE TIERS — the strength of the name evidence buys the radius:
///
///   1. EXACT normalized name + a large-footprint type → `largeFootprintRadiusMeters`
///   2. EXACT normalized name, any type                → `exactNameRadiusMeters`
///   3. Names merely ALIGN (substring / shared 5+-char token) → `fuzzyRadiusMeters`
///
/// Why tiers at all: Google's pin for a large-footprint place is a centroid or a main
/// entrance, which legitimately sits hundreds of metres — for a 2,700-acre arboretum,
/// kilometres — from the trailhead or door we curated. One flat radius therefore has to
/// choose between blanking those cards and letting a same-named place in the next town
/// through. Splitting on name strength + footprint type lets us do neither.
///
/// The radii are MEASURED, not guessed: every Block Party venue (events, trails, city
/// parks, KnownVenues, map spots) was resolved against the live Places API on
/// 2026-07-21 and every candidate Google returned was replayed through these tiers.
private nonisolated enum RuleA {

    /// Tier 3 — the safety floor for a name that only *resembles* the curated one
    /// ("Lake Wobegon Trailhead" → "Lake Wobegon Visitor Center"). This was 75 m, which
    /// missed by a hair: the two venues that fail on nothing but a small centroid offset
    /// measure 81.0 m (St Joseph Catholic Church) and 81.9 m (Lake Wobegon Visitor
    /// Center — the Farmers Market's home, the only recurring event card in the app).
    /// 90 m is the smallest round number that clears both. The band above it is empty:
    /// the next CORRECT fuzzy candidate in town is 151.8 m and the nearest WRONG one is
    /// 199.4 m ("Memorial Park" returned for a "Monument Park" query, which the name
    /// check rejects anyway).
    static let fuzzyRadiusMeters: CLLocationDistance = 90

    /// Tier 2 — an exact normalized name is strong evidence, but it must stay bounded:
    /// `locationBias` is a bias, not a restriction, so "Rivers Bend Park" comes back
    /// exact-named, with 10 photos, from 76 km away in a different town. The largest
    /// CORRECT exact-name offset measured is 195.2 m (Klinefelter Park, whose Google pin
    /// is the parking lot); 400 m is ~2x that and 190x inside that wrong match.
    static let exactNameRadiusMeters: CLLocationDistance = 400

    /// Tier 1 — exact name AND a type whose pin is a centroid rather than a door. Must
    /// cover Saint John's Abbey Arboretum at 1535 m from the abbey anchor (a 2,700-acre
    /// woodland). The nearest measured candidate past that is 2781.6 m, and every
    /// candidate beyond 2 km in the whole dataset is the wrong place — so this keeps
    /// ~460 m of headroom over the largest correct distance and still stops ~780 m short
    /// of the first wrong one.
    static let largeFootprintRadiusMeters: CLLocationDistance = 2_000

    /// Google types that mark a place whose pin is a centroid/entrance rather than a
    /// door. Every one of these was RETURNED BY GOOGLE for a real Block Party venue:
    ///  • `city_park` / `park` — the pin is usually the parking lot or main entrance;
    ///    measured offsets from our curated pins run 0.5 m to 195 m.
    ///  • `nature_preserve` — Saint John's Abbey Arboretum, 1535 m out and legitimately so.
    ///  • `route` — a LINEAR feature with no meaningful centroid at all; Google's point
    ///    for the 100+ km Lake Wobegon Trail lands 1637 m from our trailhead.
    ///  • `hiking_area` — what Google calls a trail loop ("Park Walking Loop | Klinefelter Park").
    ///  • `university` — a campus centroid is legitimately far from any one building (CSB/SJU).
    ///
    /// Deliberately NOT here, each for a measured reason:
    ///  • `locality` / `political` ("Saint Joseph") — genuinely large-footprint, but at 2 km
    ///    any venue whose name shares a token with the town's would inherit the town's
    ///    photo. The locality pin is 26 m from downtown anyway, so it never needs relief.
    ///  • `tourist_attraction` — the loosest label Google hands out, and the venues carrying
    ///    it (Centennial Park at 53.8 m) already clear a tighter tier on their own.
    ///  • `church` / `historical_landmark` / `visitor_center` / `coffee_shop` / `brewery` /
    ///    `restaurant` — all measured, all small-footprint, all inside the fuzzy floor.
    ///
    /// Do not add a type on faith. If Google never returned it for a Block Party venue,
    /// there is no measurement behind it.
    static let largeFootprintTypes: Set<String> = [
        "park",
        "city_park",
        "nature_preserve",
        "hiking_area",
        "route",
        "university",
    ]

    /// Shortest word that counts as shared evidence between two names. Below this,
    /// filler ("park", "the", "st") would align almost anything with anything.
    static let minSharedTokenLength = 5

    /// True when `resolved` (a Google text-search hit) is confidently the same place as
    /// `curated`. `types`/`primaryType` come straight off the search result — no extra
    /// billed field, no details() call.
    static func clears(resolvedName: String,
                       resolvedCoordinate: CLLocationCoordinate2D,
                       types: [String],
                       primaryType: String?,
                       curatedName: String,
                       curatedCoordinate: CLLocationCoordinate2D) -> Bool {
        let resolved = normalize(resolvedName)
        let curated = normalize(curatedName)
        // An empty name must not "contain"-match everything.
        guard !resolved.isEmpty, !curated.isEmpty else { return false }

        let metres = distance(from: resolvedCoordinate, to: curatedCoordinate)

        if resolved == curated {
            let limit = hasLargeFootprint(types: types, primaryType: primaryType)
                ? largeFootprintRadiusMeters
                : exactNameRadiusMeters
            return metres <= limit
        }

        guard namesAlign(resolved, curated) else { return false }
        return metres <= fuzzyRadiusMeters
    }

    /// Loose name agreement — one name contains the other, or they share a substantial
    /// word. Both arguments must already be `normalize`d.
    static func namesAlign(_ a: String, _ b: String) -> Bool {
        if a.contains(b) || b.contains(a) { return true }
        return !tokens(a).isDisjoint(with: tokens(b))
    }

    static func hasLargeFootprint(types: [String], primaryType: String?) -> Bool {
        if let primaryType, largeFootprintTypes.contains(primaryType) { return true }
        return types.contains { largeFootprintTypes.contains($0) }
    }

    /// Lowercased, punctuation flattened to spaces — "St. Joseph's" → "st  joseph s".
    static func normalize(_ s: String) -> String {
        String(s.lowercased().map { ($0.isLetter || $0.isNumber || $0 == " ") ? $0 : " " })
    }

    private static func tokens(_ normalized: String) -> Set<Substring> {
        Set(normalized.split(separator: " ").filter { $0.count >= minSharedTokenLength })
    }

    private static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

// MARK: - Wire models (Places API New JSON)

private struct AutocompleteResponse: Decodable {
    let suggestions: [Suggestion]?
    struct Suggestion: Decodable { let placePrediction: PlacePrediction? }
    struct PlacePrediction: Decodable {
        let placeId: String
        let text: LocalizedText?
        let structuredFormat: StructuredFormat?
    }
    struct StructuredFormat: Decodable {
        let mainText: LocalizedText?
        let secondaryText: LocalizedText?
    }
}

private struct DetailsResponse: Decodable {
    let location: LatLng?
    let displayName: LocalizedText?
    let formattedAddress: String?
    let currentOpeningHours: OpeningHours?
    let websiteUri: String?
    let nationalPhoneNumber: String?
    let primaryType: String?
    let types: [String]?
    let photos: [Photo]?

    struct OpeningHours: Decodable {
        let openNow: Bool?
        let weekdayDescriptions: [String]?
    }
    struct Photo: Decodable {
        let name: String
        let widthPx: Int?
        let heightPx: Int?
        let authorAttributions: [Attribution]?
    }
    struct Attribution: Decodable { let displayName: String? }
}

private struct SearchResponse: Decodable {
    let places: [Place]?
    struct Place: Decodable {
        let id: String
        let displayName: LocalizedText?
        let location: LatLng?
        let primaryType: String?
        let types: [String]?
    }
}

private struct NearbyResponse: Decodable {
    let places: [Place]?
    struct Place: Decodable {
        let id: String
        let displayName: LocalizedText?
        let location: LatLng?
        let primaryType: String?
        let types: [String]?
        let formattedAddress: String?
        let businessStatus: String?
    }
}

private struct LatLng: Decodable { let latitude: Double; let longitude: Double }
private struct LocalizedText: Decodable { let text: String }
