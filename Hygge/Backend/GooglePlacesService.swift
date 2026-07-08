//
//  GooglePlacesService.swift
//  Hygge — Google Places API (New) client. places.googleapis.com/v1 only.
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
    let photo: PlacePhoto?          // first photo only
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
    private var confidentPhotoCache: [String: ConfidentPhoto?] = [:]   // curated name → resolved (or checked-nil)

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
        req.setValue("location,displayName,formattedAddress,currentOpeningHours,websiteUri,nationalPhoneNumber,photos.name,photos.authorAttributions",
                     forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let resp = try JSONDecoder().decode(DetailsResponse.self, from: data)
            guard let loc = resp.location else { return nil }
            let photo = resp.photos?.first.map {
                PlacePhoto(name: $0.name,
                           attributions: ($0.authorAttributions ?? []).compactMap { $0.displayName })
            }
            let details = PlaceDetails(
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                name: resp.displayName?.text ?? "",
                address: resp.formattedAddress,
                openNow: resp.currentOpeningHours?.openNow,
                hours: resp.currentOpeningHours?.weekdayDescriptions ?? [],
                website: resp.websiteUri.flatMap { URL(string: $0) },
                phone: resp.nationalPhoneNumber,
                photo: photo)
            detailsCache[placeId] = details
            return details
        } catch { return nil }
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
        req.setValue("places.id,places.location,places.displayName", forHTTPHeaderField: "X-Goog-FieldMask")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
            let results: [PlaceResult] = (resp.places ?? []).compactMap { p in
                guard let loc = p.location, let name = p.displayName?.text, !name.isEmpty else { return nil }
                return PlaceResult(placeId: p.id,
                                   name: name,
                                   coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude))
            }
            searchCache[q] = results
            return results
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
    /// lands within 75 m of the curated coordinate with an aligned name. `search()`
    /// is a fuzzy fallback; this is the ONE place that decides a match is trustworthy
    /// enough to show its photo. Cached per curated name (a small, fixed set), so
    /// repeat callers (a list row and its detail view) don't re-run the confidence
    /// check. nil if not confidently identified or the place has no photo.
    func confidentPhoto(name: String, coordinate: CLLocationCoordinate2D) async -> ConfidentPhoto? {
        if let hit = confidentPhotoCache[name] { return hit }
        guard let id = await search("\(name) St Joseph MN").first?.placeId,
              let d = await details(placeId: id),
              let photo = d.photo,
              isConfidentMatch(resolved: d, curatedName: name, curatedCoordinate: coordinate)
        else {
            confidentPhotoCache[name] = .some(nil)
            return nil
        }
        let result = ConfidentPhoto(photoName: photo.name, attributions: photo.attributions)
        confidentPhotoCache[name] = .some(result)
        return result
    }

    private func isConfidentMatch(resolved: PlaceDetails, curatedName: String, curatedCoordinate: CLLocationCoordinate2D) -> Bool {
        let a = CLLocation(latitude: resolved.coordinate.latitude, longitude: resolved.coordinate.longitude)
        let b = CLLocation(latitude: curatedCoordinate.latitude, longitude: curatedCoordinate.longitude)
        guard a.distance(from: b) <= 75 else { return false }
        return namesAlign(resolved.name, curatedName)
    }

    private func namesAlign(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }   // empty name must not "contain"-match everything
        if na.contains(nb) || nb.contains(na) { return true }
        let ta = Set(na.split(separator: " ").filter { $0.count >= 5 })
        let tb = Set(nb.split(separator: " ").filter { $0.count >= 5 })
        return !ta.isDisjoint(with: tb)
    }

    private func normalize(_ s: String) -> String {
        String(s.lowercased().map { ($0.isLetter || $0.isNumber || $0 == " ") ? $0 : " " })
    }

    // MARK: Shared

    private func locationBias() -> [String: Any] {
        ["circle": [
            "center": ["latitude": MapSpots.center.latitude, "longitude": MapSpots.center.longitude],
            "radius": Self.biasRadius,
        ]]
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
    let photos: [Photo]?

    struct OpeningHours: Decodable {
        let openNow: Bool?
        let weekdayDescriptions: [String]?
    }
    struct Photo: Decodable {
        let name: String
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
    }
}

private struct LatLng: Decodable { let latitude: Double; let longitude: Double }
private struct LocalizedText: Decodable { let text: String }
