//
//  SolarTable.swift
//  BlockParty
//
//  The once-per-day solar lookup table behind the scrub: 1441 one-minute
//  entries (00:00 through 24:00 inclusive) of the solar quantities every
//  appearance function keys off — built FROM `SolarSky`, so the table and
//  the model can never disagree (SolarTableTests sweeps the parity).
//
//  Sampling is O(1): index + inter-minute lerp, zero trig, zero calendar
//  math. Phase + phaseBlend are stored as ONE scalar — the phase position
//  `u` ∈ [0, 4) along night→dawn→day→dusk — because both are piecewise-
//  linear in time, so a lerp of `u` is exact inside a phase and only ever
//  approximate across the single minute containing a boundary kink.
//

import Foundation

nonisolated struct SolarTable {
    /// One minute of the day. `u` = phase index + phaseBlend.
    struct Entry {
        let u: Double
        let solarElevation: Double
        let dayProgress: Double
    }

    let dayStart: Date
    let dayEnd: Date
    let sunrise: Date
    let sunset: Date
    let usedFallbackSunTimes: Bool
    private let entries: [Entry]

    private static let minutesPerDay = 24 * 60
    private static let phaseOrder: [SkyPhase] = [.night, .dawn, .day, .dusk]

    init(day now: Date, sunrise: Date?, sunset: Date?, calendar: Calendar = Town.calendar) {
        let interval = YourDayLogic.todayInterval(now: now)
        dayStart = interval.start
        dayEnd = interval.end

        // One SolarSky resolves the fallback/bad-data guards; per-minute
        // skies reuse ITS resolved sun times so every entry shares them.
        let reference = SolarSky(now: now, sunrise: sunrise, sunset: sunset, calendar: calendar)
        self.sunrise = reference.sunrise
        self.sunset = reference.sunset
        usedFallbackSunTimes = reference.usedFallbackSunTimes

        entries = (0...Self.minutesPerDay).map { minute in
            let sky = SolarSky(
                now: interval.start.addingTimeInterval(Double(minute) * 60),
                sunrise: reference.sunrise,
                sunset: reference.sunset,
                calendar: calendar
            )
            let index = Self.phaseOrder.firstIndex(of: sky.phase) ?? 0
            return Entry(
                u: Double(index) + sky.phaseBlend,
                solarElevation: sky.solarElevation,
                dayProgress: sky.dayProgress
            )
        }
    }

    /// The sky at any instant, from the table: index + lerp, nothing else.
    /// Instants beyond the day (the rubber band's overshoot) clamp to the
    /// nearer midnight's entry while keeping their own `now` — isSunUp and
    /// the pill's readout stay truthful.
    func sample(at date: Date) -> SolarSky {
        let minutes = date.timeIntervalSince(dayStart) / 60
        let clamped = min(max(minutes, 0), Double(Self.minutesPerDay))
        let index = min(Int(clamped), Self.minutesPerDay - 1)
        let fraction = clamped - Double(index)
        let a = entries[index]
        let b = entries[index + 1]

        // `u` wraps 4 → 0 across the dusk→night boundary; unwrap before
        // lerping (adjacent-minute deltas are tiny, so a gap > 2 can only
        // be the wrap).
        var ub = b.u
        if ub - a.u < -2 { ub += 4 }
        let u = (a.u + (ub - a.u) * fraction).truncatingRemainder(dividingBy: 4)
        let phase = Self.phaseOrder[Int(u)]

        return SolarSky(
            sampledNow: date,
            sunrise: sunrise,
            sunset: sunset,
            usedFallbackSunTimes: usedFallbackSunTimes,
            dayProgress: a.dayProgress + (b.dayProgress - a.dayProgress) * fraction,
            solarElevation: a.solarElevation + (b.solarElevation - a.solarElevation) * fraction,
            phase: phase,
            phaseBlend: u - u.rounded(.down)
        )
    }
}

nonisolated extension SolarSky {
    /// Table-injected constructor: every solar quantity arrives sampled,
    /// so building a sky per scrub frame costs an assignment, not trig.
    /// (`nightElevation` stays the computed property — one guarded sin.)
    init(
        sampledNow: Date,
        sunrise: Date,
        sunset: Date,
        usedFallbackSunTimes: Bool,
        dayProgress: Double,
        solarElevation: Double,
        phase: SkyPhase,
        phaseBlend: Double
    ) {
        self.now = sampledNow
        self.sunrise = sunrise
        self.sunset = sunset
        self.usedFallbackSunTimes = usedFallbackSunTimes
        self.dayProgress = dayProgress
        self.solarElevation = solarElevation
        self.phase = phase
        self.phaseBlend = phaseBlend
    }
}

/// The once-per-day memo. The card asks every frame; only a new town day
/// or changed sun times rebuild (~1.4k SolarSky inits, once).
@MainActor
enum SolarTableCache {
    private struct Key: Equatable {
        let dayStart: Date
        let sunrise: Date?
        let sunset: Date?
    }

    private static var cached: (key: Key, table: SolarTable)?

    static func table(day now: Date, sunrise: Date?, sunset: Date?) -> SolarTable {
        let key = Key(
            dayStart: Town.calendar.startOfDay(for: now), sunrise: sunrise, sunset: sunset)
        if let cached, cached.key == key { return cached.table }
        let table = SolarTable(day: now, sunrise: sunrise, sunset: sunset)
        cached = (key, table)
        return table
    }
}
