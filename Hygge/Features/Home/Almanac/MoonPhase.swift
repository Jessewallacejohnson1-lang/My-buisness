//
//  MoonPhase.swift
//  Hygge — pure, local moon-phase math for the Almanac header. No network, no
//  ephemeris library: a synodic-month approximation is plenty accurate for a
//  "what does the sky look like tonight" chip (good to well under a day).
//
//  Method: age (days) = time since a known new moon, modulo the synodic month.
//  Reference new moon: 2000-01-06 18:14 UTC (a standard almanac epoch).
//  Synodic month: 29.530588853 days (mean New-moon-to-New-moon period).
//

import Foundation

struct MoonInfo {
    let phaseName: String
    /// SF Symbol name. `illumination` is 0...1 — round only at display time.
    let symbol: String
    let illumination: Double
}

/// The moon's phase for the given instant, read as of local noon on `date`'s
/// calendar day in `tz` — so the phase stays stable across a single day
/// instead of drifting hour to hour as the fractional age ticks over.
func moonInfo(for date: Date, tz: TimeZone = .current) -> MoonInfo {
    let synodicMonth = 29.530588853

    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
    var epochComponents = DateComponents()
    epochComponents.year = 2000; epochComponents.month = 1; epochComponents.day = 6
    epochComponents.hour = 18; epochComponents.minute = 14
    let epoch = utc.date(from: epochComponents) ?? Date(timeIntervalSince1970: 0)

    var local = Calendar(identifier: .gregorian)
    local.timeZone = tz
    var noon = local.dateComponents([.year, .month, .day], from: date)
    noon.hour = 12
    let normalized = local.date(from: noon) ?? date

    let daysSinceEpoch = normalized.timeIntervalSince(epoch) / 86_400
    var age = daysSinceEpoch.truncatingRemainder(dividingBy: synodicMonth)
    if age < 0 { age += synodicMonth }

    let illumination = (1 - cos(2 * .pi * age / synodicMonth)) / 2
    let (phaseName, symbol) = phase(forAge: age, synodicMonth: synodicMonth)

    return MoonInfo(phaseName: phaseName, symbol: symbol, illumination: illumination)
}

/// Maps a synodic age (days, 0..<synodicMonth) to one of the 8 named phases.
/// The 4 principal phases (New/First quarter/Full/Last quarter) get a narrow
/// ~±1 day window centered on their exact age; crescent/gibbous fill the rest.
private func phase(forAge age: Double, synodicMonth: Double) -> (name: String, symbol: String) {
    let firstQuarter = synodicMonth / 4
    let full = synodicMonth / 2
    let lastQuarter = synodicMonth * 3 / 4
    let window = 1.0 // days either side of a principal phase

    if age < window || age >= synodicMonth - window {
        return ("New moon", "moonphase.new.moon")
    } else if age < firstQuarter - window {
        return ("Waxing crescent", "moonphase.waxing.crescent")
    } else if age < firstQuarter + window {
        return ("First quarter", "moonphase.first.quarter")
    } else if age < full - window {
        return ("Waxing gibbous", "moonphase.waxing.gibbous")
    } else if age < full + window {
        return ("Full moon", "moonphase.full.moon")
    } else if age < lastQuarter - window {
        return ("Waning gibbous", "moonphase.waning.gibbous")
    } else if age < lastQuarter + window {
        return ("Last quarter", "moonphase.last.quarter")
    } else {
        return ("Waning crescent", "moonphase.waning.crescent")
    }
}

#if DEBUG
/// Self-consistency check, not a hard proof — two illustrative 2026 dates
/// verified against this file's own formula (see the header comment for the
/// epoch/synodic constants), just enough to catch a sign or scale error.
/// Call `MoonPhaseSelfCheck.run()` from a debug entry point if needed.
enum MoonPhaseSelfCheck {
    static func run() {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc

        // 2026-01-03 ⇒ age ≈ 14.42 days — inside the Full-moon window (13.77...15.77).
        var c = DateComponents(year: 2026, month: 1, day: 3)
        let nearFull = cal.date(from: c) ?? Date()
        let full = moonInfo(for: nearFull, tz: utc)
        assert(full.phaseName == "Full moon", "expected Full moon, got \(full.phaseName)")
        assert(full.illumination > 0.95, "expected near-full illumination, got \(full.illumination)")

        // 2026-01-18 ⇒ age ≈ 29.42 days — wraps into the New-moon window (>= 28.53).
        c = DateComponents(year: 2026, month: 1, day: 18)
        let nearNew = cal.date(from: c) ?? Date()
        let new = moonInfo(for: nearNew, tz: utc)
        assert(new.phaseName == "New moon", "expected New moon, got \(new.phaseName)")
        assert(new.illumination < 0.05, "expected near-zero illumination, got \(new.illumination)")
    }
}
#endif
