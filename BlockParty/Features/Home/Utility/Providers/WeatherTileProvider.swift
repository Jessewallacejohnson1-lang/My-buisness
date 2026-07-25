//
//  WeatherTileProvider.swift
//  Block Party — the weather Utility Row tile. Wraps the extended WeatherService
//  (current temp, feels-like, gust, precip-next-2h, AQI). Caches 15 min inside
//  WeatherService.
//

import Foundation

@MainActor
final class WeatherTileProvider: UtilityTileProvider {
    let id: UtilityTileID = .weather
    let refreshPolicy: UtilityRefreshPolicy = .cached(ttl: 15 * 60)

    func fetch(settings: TileSettings) async throws -> UtilityTileValue {
        guard let w = await WeatherService.current() else { throw UtilityTileError.unavailable }
        return UtilityTileValue(content: content(for: w))
    }

    private func content(for w: Weather) -> UtilityTileContent {
        // Compact shows just the temperature (fits the big bento value cleanly);
        // feels-like lives in the expanded detail below. Matches the design mockup.
        let primary = "\(w.tempF)°"
        return UtilityTileContent(symbol: symbol(for: w.state),
                                  primary: primary,
                                  secondary: secondary(for: w),
                                  expanded: expanded(for: w),
                                  // Live, contrast-darkened gradient from the current condition.
                                  gradientHex: UtilityTileGradient.weather(for: w.state))
    }

    /// Priority: AQI ≥ 100 > precip ≥ 40% > gust ≥ 20 > a short calm line.
    private func secondary(for w: Weather) -> String? {
        if let aqi = w.aqi, aqi >= 100 { return "AQI \(aqi) · \(aqiBand(aqi))" }
        if let p = w.precipProbNext2h, p >= 40 {
            if let t = w.precipPeakTime { return "Rain \(p)% by \(UtilityFormat.shortTime(t))" }
            return "Rain \(p)% soon"
        }
        if let gust = w.windGustMph, gust >= 20 { return "Wind \(gust) mph" }
        return calmLine(for: w)
    }

    private func expanded(for w: Weather) -> [UtilityDetailRow] {
        // Short labels/values so nothing wraps in the narrow (148pt) expanded tile.
        var rows: [UtilityDetailRow] = [
            UtilityDetailRow(symbol: "thermometer.medium", label: "Feels", value: "\(w.feelsLikeF)°"),
            UtilityDetailRow(symbol: "arrow.up.arrow.down", label: "Hi / Lo", value: "\(w.highF)° / \(w.lowF)°"),
        ]
        if let gust = w.windGustMph {
            rows.append(UtilityDetailRow(symbol: "wind", label: "Gusts", value: "\(gust) mph"))
        }
        if let p = w.precipProbNext2h {
            rows.append(UtilityDetailRow(symbol: "cloud.rain", label: "Rain 2h", value: "\(p)%"))
        }
        if let aqi = w.aqi {
            rows.append(UtilityDetailRow(symbol: "aqi.medium", label: "Air", value: "\(aqi)"))
        }
        return rows
    }

    private func symbol(for state: WeatherState) -> String {
        switch state {
        case .clearDay:   return "sun.max.fill"
        case .clearNight: return "moon.stars.fill"
        case .cloudy:     return "cloud.fill"
        case .rain:       return "cloud.rain.fill"
        case .snow:       return "snowflake"
        case .storm:      return "cloud.bolt.rain.fill"
        }
    }

    private func calmLine(for w: Weather) -> String {
        switch w.state {
        case .clearDay:   return "Clear skies"
        case .clearNight: return "Clear night"
        case .cloudy:     return "Cloudy"
        case .rain:       return "Light rain"
        case .snow:       return "Snow"
        case .storm:      return "Storms"
        }
    }

    /// US AQI band word (kept short for the tile). Only reached for AQI ≥ 100.
    private func aqiBand(_ aqi: Int) -> String {
        switch aqi {
        case ..<101: return "moderate"
        case ..<201: return "unhealthy"
        case ..<301: return "very unhealthy"
        default:     return "hazardous"
        }
    }
}
