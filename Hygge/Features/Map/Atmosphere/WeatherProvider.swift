//
//  WeatherProvider.swift
//  Hygge — the sky dimension: real weather behind a swappable protocol.
//
//  OpenMeteoWeatherProvider is a keyless URLSession GET matching the app's
//  hand-rolled backend. CachedWeatherProvider persists the last snapshot in
//  UserDefaults so the whisper is instant on open and survives offline.
//
//  WEATHERKIT SWAP (later, paid dev account): add WeatherKitWeatherProvider
//  conforming to WeatherProvider (map WeatherKit conditions → SkyCondition),
//  change the one `OpenMeteoWeatherProvider()` in AtmosphereModel, add the
//  capability/entitlement + " Weather" attribution. No other change.
//

import Foundation
import CoreLocation

protocol WeatherProvider {
    func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot
}

enum WMO {
    /// WMO weather interpretation code → our condition + intensity.
    static func map(code: Int, isDay: Bool) -> (SkyCondition, WeatherIntensity) {
        switch code {
        case 0:                  return (.clear, .light)
        case 1, 2:               return (.cloudy, .light)
        case 3:                  return (.overcast, .moderate)
        case 45, 48:             return (.fog, .moderate)
        case 51, 53, 55, 56, 57: return (.rain, .light)
        case 61, 63:             return (.rain, .moderate)
        case 65, 66, 67:         return (.rain, .heavy)
        case 71, 73, 77:         return (.snow, .moderate)
        case 75:                 return (.snow, .heavy)
        case 80, 81:             return (.rain, .moderate)
        case 82:                 return (.rain, .heavy)
        case 85:                 return (.snow, .moderate)
        case 86:                 return (.snow, .heavy)
        case 95, 96, 99:         return (.storm, .heavy)
        default:                 return (.cloudy, .light)
        }
    }
}

struct OpenMeteoWeatherProvider: WeatherProvider {
    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        let current: Current
    }

    static func decode(_ data: Data) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let isDay = r.current.is_day == 1
        let (cond, inten) = WMO.map(code: r.current.weather_code, isDay: isDay)
        return WeatherSnapshot(tempF: Int(r.current.temperature_2m.rounded()),
                               condition: cond, intensity: inten, isDay: isDay, capturedAt: Date())
    }

    func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(coord.latitude)),
            .init(name: "longitude", value: String(coord.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "timezone", value: "America/Chicago"),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 8
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decode(data)
    }
}

final class CachedWeatherProvider {
    private let base: WeatherProvider
    private let defaults: UserDefaults
    private let ttl: TimeInterval
    private let key = "hygge.atmosphere.weather"

    init(base: WeatherProvider, defaults: UserDefaults = .standard, ttlSeconds: TimeInterval = 1200) {
        self.base = base; self.defaults = defaults; self.ttl = ttlSeconds
    }

    /// Last snapshot regardless of age (for instant paint + offline). nil if none.
    var cached: WeatherSnapshot? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: d)
    }

    var isStale: Bool {
        guard let c = cached else { return true }
        return Date().timeIntervalSince(c.capturedAt) > ttl
    }

    func store(_ s: WeatherSnapshot) {
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: key) }
    }

    /// Fetch fresh, store, return.
    func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        let s = try await base.current(at: coord)
        store(s)
        return s
    }
}
