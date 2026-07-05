//
//  TrailServices.swift
//  Hygge — Nominatim geocoding for trails.
//
//  GeocoderService: geocodes place names via OpenStreetMap Nominatim (no key needed)
//
//  A @MainActor singleton so its cache stays on the main actor, consistent with
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor in this project.
//

import Foundation
import CoreLocation

// MARK: - Nominatim geocoder

@MainActor
final class GeocoderService {
    static let shared = GeocoderService()
    private init() {}

    private var cache: [String: CLLocationCoordinate2D] = [:]

    /// Geocodes `query` via OSM Nominatim. Returns nil if not found.
    func coordinate(for query: String) async -> CLLocationCoordinate2D? {
        if let hit = cache[query] { return hit }

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
}

private struct NominatimResult: Decodable {
    let lat: String
    let lon: String
}
