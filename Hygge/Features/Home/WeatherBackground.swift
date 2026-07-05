//
//  WeatherBackground.swift
//  Hygge — looping video backdrop for the Today weather bar.
//
//  Six weather-state clips live in the public `weather-loops` Supabase bucket
//  (clear-day.mp4 … storm.mp4). On first use a clip is downloaded to the Caches
//  directory and played from there after. While a clip is loading, missing, or
//  motion is reduced, a matched static gradient shows so the bar never looks
//  broken. Muted, looping, cover-fit, non-interactive; pauses when the Today
//  tab isn't focused or the app is backgrounded.
//
//  Native SwiftUI/AVFoundation port of the Expo spec (expo-video +
//  expo-file-system). See docs/superpowers/specs/2026-07-05-weather-background-design.md.
//

import SwiftUI
import AVFoundation

// MARK: - State

enum WeatherState: String, CaseIterable {
    case clearDay   = "clear-day"
    case clearNight = "clear-night"
    case cloudy
    case rain
    case snow
    case storm

    /// Open-Meteo WMO code + day flag → state. Fog → cloudy, drizzle → rain,
    /// unknown → nearest clear.
    static func from(code: Int, isDay: Bool) -> WeatherState {
        switch code {
        case 0:                return isDay ? .clearDay : .clearNight
        case 1, 2, 3, 45, 48:  return .cloudy
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86:  return .snow
        case 95, 96, 99:       return .storm
        default:               return isDay ? .clearDay : .clearNight
        }
    }

    /// Two sky-toned stops (top → bottom). Bespoke colors: sky tints aren't a
    /// Hue token, so — like the map's allowed base-map hexes — they live here.
    var gradient: [Color] {
        switch self {
        case .clearDay:   return [Color(hex: 0x6FB4E8), Color(hex: 0xBFE0F5)]
        case .clearNight: return [Color(hex: 0x1B2A4A), Color(hex: 0x33415E)]
        case .cloudy:     return [Color(hex: 0x8A97A6), Color(hex: 0xB9C2CC)]
        case .rain:       return [Color(hex: 0x4E5A66), Color(hex: 0x74818C)]
        case .snow:       return [Color(hex: 0xAEB8C2), Color(hex: 0xDDE4EA)]
        case .storm:      return [Color(hex: 0x2C2E3A), Color(hex: 0x4A4E63)]
        }
    }
}

// MARK: - Clip cache

/// Resolves a weather state to a local, playable clip URL: returns the cached
/// file if present, otherwise downloads it once from the public bucket (dupes
/// coalesced) and caches it. Returns nil on any failure — the caller then
/// simply stays on the gradient.
actor WeatherClipCache {
    static let shared = WeatherClipCache()

    private var inFlight: [WeatherState: Task<URL?, Never>] = [:]

    private var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("weather-loops", isDirectory: true)
    }

    private func remoteURL(for state: WeatherState) -> URL {
        SupabaseConfig.url
            .appendingPathComponent("storage/v1/object/public/weather-loops/\(state.rawValue).mp4")
    }

    func localURL(for state: WeatherState) async -> URL? {
        let dest = folder.appendingPathComponent("\(state.rawValue).mp4")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        if let task = inFlight[state] { return await task.value }

        let remote = remoteURL(for: state)
        let dir = folder
        let task = Task<URL?, Never> {
            do {
                let (tmp, resp) = try await URLSession.shared.download(from: remote)
                guard let code = (resp as? HTTPURLResponse)?.statusCode,
                      (200..<300).contains(code) else { return nil }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                return dest
            } catch {
                return nil
            }
        }
        inFlight[state] = task
        let result = await task.value
        inFlight[state] = nil
        return result
    }
}
