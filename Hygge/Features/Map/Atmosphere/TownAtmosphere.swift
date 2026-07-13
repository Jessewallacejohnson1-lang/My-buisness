//
//  TownAtmosphere.swift
//  Hygge — the composed environment value for the Living Basemap.
//
//  TownAtmosphere = f(time-of-day, season, sky). Computed on-device; time+season
//  are synchronous/offline so the map is alive on the first frame, sky (weather)
//  refines it a moment later. Pure Foundation — never import SwiftUI here (keeps
//  the unit harnessable and the seam clean).
//

import Foundation

enum TimePhase: String { case dawn, day, golden, dusk, night }

enum Season: String { case winter, spring, summer, autumn }

enum SkyCondition: String, Codable {
    case clear, cloudy, overcast, fog, rain, snow, storm
    var isPrecip: Bool { self == .rain || self == .snow || self == .storm }
}

enum WeatherIntensity: String, Codable { case light, moderate, heavy }

struct WeatherSnapshot: Codable, Equatable {
    let tempF: Int
    let condition: SkyCondition
    let intensity: WeatherIntensity
    let isDay: Bool
    let capturedAt: Date
}

struct TownAtmosphere: Equatable {
    var dayFactor: Double        // 0 (deep night) … 1 (solar noon)
    var phase: TimePhase
    var season: Season
    var seasonBlend: Double       // 0…1 toward the next season
    var sky: SkyCondition
    var intensity: WeatherIntensity
    var tempF: Int?
    var isDay: Bool
    var resolvedAt: Date?         // nil until weather loads

    static let placeholder = TownAtmosphere(
        dayFactor: 1, phase: .day, season: .summer, seasonBlend: 0,
        sky: .clear, intensity: .light, tempF: nil, isDay: true, resolvedAt: nil
    )

    /// Human condition text. Intensity qualifies precip only.
    var conditionText: String {
        switch sky {
        case .clear:    return "clear"
        case .cloudy:   return "partly cloudy"
        case .overcast: return "overcast"
        case .fog:      return "fog"
        case .storm:    return "thunderstorms"
        case .rain:     return intensity == .light ? "light rain" : intensity == .heavy ? "heavy rain" : "rain"
        case .snow:     return intensity == .light ? "light snow" : intensity == .heavy ? "heavy snow" : "snow"
        }
    }

    /// SF Symbol for the whisper glyph. Muted-tinted at the call site — never coral.
    var glyph: String {
        switch sky {
        case .clear:    return isDay ? "sun.max" : "moon.stars"
        case .cloudy:   return isDay ? "cloud.sun" : "cloud.moon"
        case .overcast: return "cloud"
        case .fog:      return "cloud.fog"
        case .rain:     return "cloud.rain"
        case .snow:     return "snowflake"
        case .storm:    return "cloud.bolt.rain"
        }
    }

    private func clockLabel(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm"
        return f.string(from: now)
    }

    /// "38° · light snow · 4:15" — nil until weather resolves.
    func whisperLine(now: Date) -> String? {
        guard resolvedAt != nil, let t = tempF else { return nil }
        return "\(t)° · \(conditionText) · \(clockLabel(now))"
    }

    var accessibilityText: String? {
        guard resolvedAt != nil, let t = tempF else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return "Currently \(t) degrees, \(conditionText), \(f.string(from: Date())) in Saint Joseph."
    }

    /// DEBUG override: overlay parsed key/values onto this atmosphere.
    func applying(_ o: [String: String]) -> TownAtmosphere {
        var a = self
        if let v = o["season"], let s = Season(rawValue: v) { a.season = s }
        if let v = o["phase"], let p = TimePhase(rawValue: v) { a.phase = p }
        if let v = o["sky"], let s = SkyCondition(rawValue: v) { a.sky = s; a.resolvedAt = Date() }
        if let v = o["intensity"], let i = WeatherIntensity(rawValue: v) { a.intensity = i }
        if let v = o["temp"], let t = Int(v) { a.tempF = t; a.resolvedAt = Date() }
        if let v = o["daylight"], let d = Double(v) { a.dayFactor = min(max(d, 0), 1) }
        if let v = o["isday"] { a.isDay = (v == "1" || v == "true") }
        return a
    }
}
