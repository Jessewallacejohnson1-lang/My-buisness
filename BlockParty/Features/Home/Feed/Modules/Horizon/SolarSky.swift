//
//  SolarSky.swift
//  BlockParty
//
//  The solar model behind the "Your day" horizon card. Pure value type:
//  give it a moment plus today's sun times and it answers where the sun
//  is, which sky phase we're in, and how far through that phase.
//
//  Everything downstream (sky gradients, bloom, ground polarity) keys off
//  `solarElevation` and `phase`/`phaseBlend`, so the card self-corrects
//  across the seasons with no hardcoded clock hours anywhere.
//
//  The sun/moon disc reads `solarElevation`/`nightElevation` for its
//  height and takes its x from TimeAxis — this type owns no x mapping.
//

import Foundation

nonisolated enum SkyPhase: CaseIterable, Equatable {
    case night, dawn, day, dusk

    /// Cycle order used for cross-phase color interpolation.
    var next: SkyPhase {
        switch self {
        case .night: .dawn
        case .dawn: .day
        case .day: .dusk
        case .dusk: .night
        }
    }

    var previous: SkyPhase {
        switch self {
        case .dawn: .night
        case .day: .dawn
        case .dusk: .day
        case .night: .dusk
        }
    }
}

nonisolated struct SolarSky: Equatable {
    /// Phase boundary offsets, in seconds relative to sunrise/sunset.
    enum Boundary {
        static let dawnLead: TimeInterval = -40 * 60   // dawn starts sunrise − 40 min
        static let dawnTail: TimeInterval = 50 * 60    // dawn ends sunrise + 50 min
        static let duskLead: TimeInterval = -80 * 60   // dusk starts sunset − 80 min
        static let duskTail: TimeInterval = 40 * 60    // dusk ends sunset + 40 min
    }

    /// Fallback sun times (town time) when Open-Meteo has nothing: 6:30 AM / 8:30 PM.
    enum Fallback {
        static let sunriseMinutes = 6 * 60 + 30
        static let sunsetMinutes = 20 * 60 + 30
    }

    let now: Date
    let sunrise: Date
    let sunset: Date
    let usedFallbackSunTimes: Bool

    /// 0 at sunrise, 1 at sunset; outside that range before/after.
    let dayProgress: Double
    /// Normalized sun height: sin(π · dayProgress), clamped to 0 at night.
    let solarElevation: Double
    let phase: SkyPhase
    /// 0…1 progress through the current phase.
    let phaseBlend: Double

    /// Ground polarity keys off this, not off phase: the ground flips
    /// light ↔ dark exactly at sunrise and sunset.
    var isSunUp: Bool { now >= sunrise && now < sunset }

    /// Normalized moon height while the sun is down: the same sin arc the
    /// sun rides by day, run over the night (sunset → next sunrise). Zero
    /// while the sun is up. Clock-derived, not lunar astronomy — the disc
    /// marks *now*, so the moon rises after sunset and sets at sunrise.
    /// The ±24 h shifts are the same approximation the phase boundaries
    /// use above (sun times drift < 2 min/day; ~1 h on a DST-change night,
    /// invisible at card scale for a deliberately non-astronomical moon).
    var nightElevation: Double {
        guard !isSunUp else { return 0 }
        let nightStart = now >= sunset ? sunset : sunset.addingTimeInterval(-24 * 3600)
        let nightEnd = now >= sunset ? sunrise.addingTimeInterval(24 * 3600) : sunrise
        let length = nightEnd.timeIntervalSince(nightStart)
        guard length > 0 else { return 0 }
        let progress = min(max(now.timeIntervalSince(nightStart) / length, 0), 1)
        return max(0, sin(.pi * progress))
    }

    init(now: Date, sunrise: Date?, sunset: Date?, calendar: Calendar = Town.calendar) {
        self.now = now

        let fellBack = sunrise == nil || sunset == nil
        let rise = sunrise ?? Self.fallbackDate(minutes: Fallback.sunriseMinutes, on: now, calendar: calendar)
        var set = sunset ?? Self.fallbackDate(minutes: Fallback.sunsetMinutes, on: now, calendar: calendar)
        if set <= rise { set = rise.addingTimeInterval(12 * 3600) } // bad data guard; TimeAxis has its own
        self.sunrise = rise
        self.sunset = set
        self.usedFallbackSunTimes = fellBack

        let dayLength = set.timeIntervalSince(rise)
        let progress = now.timeIntervalSince(rise) / dayLength
        self.dayProgress = progress
        self.solarElevation = progress > 0 && progress < 1 ? max(0, sin(.pi * progress)) : 0

        // Phase boundaries. Yesterday's dusk end / tomorrow's dawn start are
        // approximated by shifting today's solar times ±24 h — sun times in
        // central MN drift under ~2 min/day, invisible at card scale.
        let dawnStart = rise.addingTimeInterval(Boundary.dawnLead)
        let dawnEnd = rise.addingTimeInterval(Boundary.dawnTail)
        let dayEnd = max(set.addingTimeInterval(Boundary.duskLead), dawnEnd)
        let duskEnd = set.addingTimeInterval(Boundary.duskTail)

        if now < dawnStart {
            phase = .night
            let nightStart = duskEnd.addingTimeInterval(-24 * 3600)
            phaseBlend = Self.fraction(of: now, from: nightStart, to: dawnStart)
        } else if now < dawnEnd {
            phase = .dawn
            phaseBlend = Self.fraction(of: now, from: dawnStart, to: dawnEnd)
        } else if now < dayEnd {
            phase = .day
            phaseBlend = Self.fraction(of: now, from: dawnEnd, to: dayEnd)
        } else if now < duskEnd {
            phase = .dusk
            phaseBlend = Self.fraction(of: now, from: dayEnd, to: duskEnd)
        } else {
            phase = .night
            let nightEnd = dawnStart.addingTimeInterval(24 * 3600)
            phaseBlend = Self.fraction(of: now, from: duskEnd, to: nightEnd)
        }

    }

    private static func fraction(of date: Date, from start: Date, to end: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / span, 0), 1)
    }

    private static func fallbackDate(minutes: Int, on day: Date, calendar: Calendar) -> Date {
        // bySettingHour, not byAdding — minutes-past-midnight arithmetic is
        // an hour off on DST-change days (the townInstant rule).
        let start = calendar.startOfDay(for: day)
        return calendar.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start
        ) ?? start
    }

    /// Re-dates a solar time onto `reference`'s town day, keeping its wall
    /// clock (DST-safe via bySettingHour, the repo's townInstant pattern).
    ///
    /// Sun times drift under ~2 min/day here, so re-dating a stale reading
    /// is honest — it keeps the sky correct when the card stays mounted
    /// across midnight and the feed hasn't refetched yet. Without this, a
    /// day-old sunset leaves the card in a permanent night window.
    static func rebase(
        _ solarTime: Date?, ontoDayOf reference: Date, calendar: Calendar = Town.calendar
    ) -> Date? {
        guard let solarTime else { return nil }
        let time = calendar.dateComponents([.hour, .minute, .second], from: solarTime)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: calendar.startOfDay(for: reference)
        )
    }
}
