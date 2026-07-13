//
//  DailyGreeting.swift
//  Hygge — the "Coffee and Claude"-style hello at the top of the Daily Almanac.
//
//  A warm, time-of-day greeting (morning / afternoon / evening), in the spirit of
//  the little text Claude shows up top — plus a few playful ones sprinkled in. On
//  the first open of the day the Almanac *writes* it in front of the neighbor
//  (see TypewriterText + AlmanacSection); every later open it's just there.
//
//  Rules that shaped the pool (curated down from 180 candidates):
//   • It's a HELLO, never a fact. No weather/temps/dates — that's the read's job.
//   • Warm, calm, neighborly. A neighbor, not a brand. No badges/streaks/emoji.
//   • `{name}` is the neighbor's first name; a name-less line is used when we have none.
//
//  The pick is deterministic per local day + part-of-day, so it's stable all day
//  and rolls over tomorrow — never a reshuffle on every glance. Weighted ~80% warm,
//  so the playful lines stay a nice surprise, not the norm.
//

import Foundation

enum DayPart: String {
    case morning = "MORNING"
    case afternoon = "AFTERNOON"
    case evening = "EVENING"
}

enum DailyGreeting {

    /// Part-of-day in the town's clock, matching the Almanac read's own time words.
    static func part(at date: Date = Date()) -> DayPart {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WeatherService.townTZ
        let h = cal.component(.hour, from: date)
        if h < 12 { return .morning }
        if h < 17 { return .afternoon }
        return .evening
    }

    /// Today's greeting — deterministic for (local day + part), name-substituted.
    static func line(name: String?, at date: Date = Date()) -> String {
        let part = part(at: date)
        let (warm, fun) = pool(for: part)
        let seed = stableHash(DateHelpers.localDate(date) + "|" + part.rawValue)

        // ~80/20 warm/fun. `seed / 5` picks within the chosen pool independently.
        var candidates = (!fun.isEmpty && seed % 5 == 0) ? fun : warm

        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !(trimmed?.isEmpty ?? true)
        if hasName {
            // Keep it personal most days: bias toward name-bearing lines (~3 in 4), but
            // let a name-less one through now and then for variety. (No-op for accounts
            // with no resolvable name — those always fall through to the name-less pool.)
            let named = candidates.filter { $0.contains("{name}") }
            if !named.isEmpty && seed % 4 != 0 { candidates = named }
        } else {
            let noName = candidates.filter { !$0.contains("{name}") }
            candidates = noName.isEmpty ? (warm + fun).filter { !$0.contains("{name}") } : noName
        }
        guard !candidates.isEmpty else { return "Hello." }

        let idx = Int((seed / 5) % UInt64(candidates.count))
        return resolve(candidates[idx], name: hasName ? trimmed : nil)
    }

    // MARK: - Name substitution

    private static func resolve(_ line: String, name: String?) -> String {
        guard let name, !name.isEmpty else {
            // Belt-and-suspenders: a name-less pool was already chosen, but if a
            // `{name}` line ever slips through with no name, drop it cleanly.
            return line
                .replacingOccurrences(of: ", {name}", with: "")
                .replacingOccurrences(of: " {name}", with: "")
                .replacingOccurrences(of: "{name}", with: "")
        }
        return line.replacingOccurrences(of: "{name}", with: name)
    }

    // MARK: - Stable hash (String.hashValue is randomized per launch — this isn't)

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }

    // MARK: - The pool

    private static func pool(for part: DayPart) -> (warm: [String], fun: [String]) {
        switch part {
        case .morning:   return (morningWarm, morningFun)
        case .afternoon: return (afternoonWarm, afternoonFun)
        case .evening:   return (eveningWarm, eveningFun)
        }
    }

    private static let morningWarm: [String] = [
        "Good morning, {name}.",
        "Morning, {name} — coffee's on.",
        "Morning in St. Joe.",
        "A slow, soft morning, {name}.",
        "Morning.",
        "Morning, {name}.",
        "The kettle's on, {name}.",
        "Ease into it.",
        "A gentle morning, {name}.",
        "Morning. First cup, no rush.",
        "Morning, neighbor.",
        "Good morning, {name}. No rush.",
        "Good morning, {name}. Ease in.",
        "Coffee's brewing, {name}.",
        "The town's just waking up.",
        "Morning's here, {name}.",
        "Mug's full, world's quiet.",
        "Take the morning gently, {name}.",
        "New day.",
        "Take the morning slow, {name}.",
        "Good morning, {name}. Coffee first.",
        "Slow start in town.",
        "Stretching into the morning.",
        "A quiet, unhurried start.",
        "Slow start.",
        "Welcome to the morning, {name}.",
        "Tea's steeping — morning, {name}.",
        "Coffee's on somewhere in town.",
        "Stay under the blanket a while.",
        "A slow morning to you, {name}.",
        "Slow morning, warm cup.",
        "Morning, {name}. Sip it slow.",
        "Hello, {name}. It's morning.",
        "Another St. Joe morning.",
        "Easing into it, {name}.",
        "Let it be a gentle one.",
        "Coffee first, {name}.",
        "Good morning. Glad you're here.",
        "Fresh pot, quiet morning.",
        "Warm and easy, {name}.",
        "A fresh one, {name}.",
        "Good morning from St. Joe, {name}.",
        "A candlelit kind of morning.",
        "Hello, morning.",
    ]

    private static let morningFun: [String] = [
        "Easy does it.",
        "Pour yourself a good one.",
        "Mug in hand yet, {name}?",
    ]

    private static let afternoonWarm: [String] = [
        "Good afternoon, {name}.",
        "Warming up the afternoon.",
        "A soft afternoon, {name}.",
        "Afternoon.",
        "Afternoon, {name}.",
        "Afternoon in St. Joe.",
        "Slow and easy, {name}.",
        "Hello, {name}.",
        "Settle in, {name}.",
        "Welcome back, {name}.",
        "Quiet afternoon in town.",
        "No rush this afternoon, {name}.",
        "Hi, {name}.",
        "Glad you're here, {name}.",
        "Hello from St. Joe, {name}.",
        "Cozy up, {name}.",
        "Hey there.",
        "Hi there, {name}.",
        "Easy afternoon, neighbor.",
        "Take it slow, {name}.",
        "Welcome back.",
        "Nice to see you, {name}.",
        "Midday in St. Joe.",
        "A slow, soft afternoon.",
        "A calm afternoon, {name}.",
        "Afternoon settles in, {name}.",
        "Ease into the afternoon.",
        "There you are.",
        "Afternoon to you, {name}.",
        "Small-town afternoon.",
        "Light a candle, breathe.",
        "There you are, {name}.",
        "Hey, {name}.",
        "Warm mug, quiet afternoon.",
        "Good afternoon from town.",
        "Stretching out the afternoon.",
        "The quiet part of the day.",
        "A gentle afternoon, {name}.",
        "Afternoon, {name}. Take it slow.",
        "Wrap up in something soft.",
        "Hi again.",
        "Easy afternoon, {name}.",
    ]

    private static let afternoonFun: [String] = [
        "Afternoon — kettle's still warm.",
        "Coasting into the afternoon, {name}.",
        "Steeping the afternoon slowly.",
        "Afternoon, {name}. Tea's steeping.",
        "The kettle's on.",
        "Puttering along nicely.",
        "Time for a refill, {name}.",
        "Letting the day amble, {name}.",
        "Afternoon. Mug's still warm.",
        "Simmering down the day.",
        "Pull up a mug, {name}.",
        "Refilling the mug, {name}.",
        "Afternoon lull — tea?",
        "Coffee's close by, {name}.",
    ]

    private static let eveningWarm: [String] = [
        "Good evening, {name}.",
        "Evening in St. Joe.",
        "Winding down gently.",
        "Evening.",
        "Evening, {name}.",
        "Dimming the lights, {name}.",
        "Settle in, {name}.",
        "Tea's steeping, {name}.",
        "Dusk in St. Joseph.",
        "Ease into the evening.",
        "Good evening.",
        "A calm evening to you, {name}.",
        "Quiet night ahead, {name}.",
        "A quiet, cozy night.",
        "Evening's settling in, {name}.",
        "Evening. Last cup of the day.",
        "Evening, neighbor.",
        "Settling in slowly.",
        "Light a candle, {name}.",
        "Winding down.",
        "Quiet evening, {name}.",
        "Good evening from St. Joe.",
        "The evening's soft and slow.",
        "You made it, {name}.",
        "Easy evening, {name}.",
        "Wind down, {name} — tea's warm.",
        "Winding down in St. Joe.",
        "Wind down, {name}.",
        "Settling in.",
        "Winding down, {name}?",
        "Settling in, {name}.",
        "Softening the day's edges.",
        "Rest easy tonight, {name}.",
        "Slow evening in St. Joseph.",
        "Easing into evening, {name}.",
        "Soft light, slow evening.",
        "The evening's yours, {name}.",
        "The town's turning in.",
        "Tucking in the day.",
        "Cozy up, {name}.",
        "Quiet hours.",
        "Hello, {name}. Evening's here.",
        "Cozy evening, {name}.",
        "Slowing to a hum.",
        "Let the day go quiet.",
        "Evening — settle in with tea.",
    ]

    private static let eveningFun: [String] = [
        "Evening — kettle's on.",
        "Decaf and a soft evening.",
        "Coasting into dusk.",
        "Evening, {name}. Mug's full.",
        "Time for a blanket.",
        "Hey there, {name}.",
        "Kettle's whistling, {name}.",
        "Good evening. Steep something.",
        "One last pour, {name}.",
    ]
}
