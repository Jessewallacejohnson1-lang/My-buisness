//
//  AtmosphereModel.swift
//  Hygge — owns the Living Basemap's composed atmosphere.
//
//  Time + season are computed synchronously (offline) so `current` is alive the
//  instant the map appears; cached weather fills sky immediately; a background
//  fetch refines it. Recomputes time on a 1-min heartbeat so the palette + wash
//  ease through the day. MapModel stays events/realtime — this is the clean seam.
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class AtmosphereModel: ObservableObject {
    @Published private(set) var current: TownAtmosphere = .placeholder

    private let coord = MapSpots.center
    private let weather: CachedWeatherProvider
    private let forced: [String: String]?      // DEBUG override
    private var tickTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var started = false

    init(provider: WeatherProvider = OpenMeteoWeatherProvider()) {
        self.weather = CachedWeatherProvider(base: provider)
        #if DEBUG
        self.forced = AtmosphereOverride.parse(ProcessInfo.processInfo.arguments)
        #else
        self.forced = nil
        #endif
        recompute()   // publish a live v0 immediately (or the forced mood)
    }

    func start() {
        guard !started else { return }
        started = true
        if forced != nil { return }             // frozen mood; no timers/network
        applyCached()
        scheduleRefresh()
        startTick()
    }

    func onForeground() {
        guard started, forced == nil else { return }
        recompute()
        if weather.isStale { scheduleRefresh() }
        startTick()
    }

    func stop() {
        tickTask?.cancel(); tickTask = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    // MARK: composition

    /// Recompute time + season (offline) and merge with the latest known sky.
    private func recompute() {
        let now = Date()
        let season = SeasonClock.current(now)
        var a = current
        a.dayFactor = SolarClock.dayFactor(at: now, coord: coord)
        a.phase = SolarClock.phase(at: now, coord: coord)
        a.season = season.season
        a.seasonBlend = season.blend
        if let f = forced { a = a.applying(f) }
        current = a
    }

    private func applyCached() {
        guard let s = weather.cached else { return }
        merge(s)
    }

    private func merge(_ s: WeatherSnapshot) {
        var a = current
        a.sky = s.condition; a.intensity = s.intensity; a.tempF = s.tempF; a.isDay = s.isDay
        a.resolvedAt = s.capturedAt
        if let f = forced { a = a.applying(f) }
        current = a
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let s = try await self.weather.current(at: self.coord)
                self.merge(s)
            } catch {
                // keep cached/stale; the whisper never blanks.
            }
        }
    }

    private func startTick() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)   // 1 min
                guard let self, self.started, self.forced == nil else { break }
                self.recompute()
                if self.weather.isStale { self.scheduleRefresh() }
            }
        }
    }
}
