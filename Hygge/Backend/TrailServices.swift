//
//  TrailServices.swift
//  Hygge — Pexels photo search + Nominatim geocoding for trails.
//
//  PexelsService:   fetches landscape photos by keyword (free, no attribution req.)
//  GeocoderService: geocodes place names via OpenStreetMap Nominatim (no key needed)
//
//  Both are @MainActor singletons so their caches stay on the main actor,
//  consistent with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor in this project.
//

import Foundation
import CoreLocation

// MARK: - Pexels

@MainActor
final class PexelsService {
    static let shared = PexelsService()
    private init() {}

    private let apiKey = "Cs0h7oAJvbazuDaJjg8CAT4KgWrGLXz4xMyXVk1u8ccqyTvjCH2wXses"
    private var cache: [String: URL] = [:]

    /// Returns the URL of a landscape photo matching `query`, or nil on failure.
    func photoURL(for query: String) async -> URL? {
        if let hit = cache[query] { return hit }

        var comps = URLComponents(string: "https://api.pexels.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "query",       value: query),
            URLQueryItem(name: "per_page",    value: "1"),
            URLQueryItem(name: "orientation", value: "landscape"),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(PexelsResponse.self, from: data)
            if let src = resp.photos.first?.src.large, let result = URL(string: src) {
                cache[query] = result
                return result
            }
        } catch {}
        return nil
    }
}

private struct PexelsResponse: Decodable {
    let photos: [Photo]
    struct Photo: Decodable {
        let src: Src
        struct Src: Decodable { let large: String; let medium: String }
    }
}

// MARK: - Nominatim geocoder

@MainActor
final class GeocoderService {
    static let shared = GeocoderService()
    private init() {}

    private var cache: [String: CLLocationCoordinate2D] = [:]
    private var reverseCache: [String: String] = [:]

    /// Geocodes `query` — curated St. Joe venues first (building-accurate,
    /// see KnownVenues.swift), then OSM Nominatim. Returns nil if not found.
    func coordinate(for query: String) async -> CLLocationCoordinate2D? {
        if let known = KnownVenues.coordinate(for: query) { return known }
        if let hit = cache[query] { return hit }

        // Google Places (New) text search — real venues resolve better here than on
        // Nominatim. Cached, so an unknown venue costs at most one lookup.
        if let g = await GooglePlacesService.shared.search(query).first {
            cache[query] = g.coordinate
            return g.coordinate
        }

        // Nominatim fallback (free, no key) for anything Google didn't return.
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comps.queryItems = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit",  value: "1"),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        // Nominatim usage policy: identify your app
        req.setValue("HyggeApp/1.0 contact@hyggeapp.com", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let results = try JSONDecoder().decode([NominatimResult].self, from: data)
            if let first = results.first,
               let lat = Double(first.lat),
               let lon = Double(first.lon) {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                cache[query] = coord
                return coord
            }
        } catch {}
        return nil
    }

    /// Reverse-geocodes a coordinate to the town/city over it (OSM Nominatim).
    /// Rounded to ~0.01° so nearby pans reuse the cache; nil if nothing resolves.
    func town(lat: Double, lon: Double) async -> String? {
        let key = String(format: "%.2f,%.2f", lat, lon)
        if let hit = reverseCache[key] { return hit }

        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        comps.queryItems = [
            URLQueryItem(name: "lat",            value: String(lat)),
            URLQueryItem(name: "lon",            value: String(lon)),
            URLQueryItem(name: "format",         value: "json"),
            URLQueryItem(name: "zoom",           value: "12"),   // town / city granularity
            URLQueryItem(name: "addressdetails", value: "1"),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        // Nominatim usage policy: identify your app
        req.setValue("HyggeApp/1.0 contact@hyggeapp.com", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(NominatimReverse.self, from: data)
            if let name = result.address.place {
                reverseCache[key] = name
                return name
            }
        } catch {}
        return nil
    }
}

private struct NominatimResult: Decodable {
    let lat: String
    let lon: String
}

private struct NominatimReverse: Decodable {
    let address: Address
    struct Address: Decodable {
        let city: String?
        let town: String?
        let village: String?
        let hamlet: String?
        let municipality: String?
        let county: String?
        /// The best-available populated-place name (city → town → … → county).
        var place: String? { city ?? town ?? village ?? hamlet ?? municipality ?? county }
    }
}
