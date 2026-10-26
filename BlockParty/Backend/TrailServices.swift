//
//  TrailServices.swift
//  Block Party — Nominatim reverse geocoding: the town name over the map.
//
//  GeocoderService: reverse-geocodes a coordinate via OpenStreetMap Nominatim (no key needed)
//
//  A @MainActor singleton so its caches stay on the main actor, consistent with
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor in this project.
//

import Foundation

// MARK: - Nominatim geocoder

@MainActor
final class GeocoderService {
    static let shared = GeocoderService()
    private init() {}

    private var reverseCache: [String: String] = [:]

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
        req.setValue("BlockPartyApp/1.0 contact@blockpartyapp.com", forHTTPHeaderField: "User-Agent")

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
