//
//  DailyGreeting.swift
//  Block Party — the "Coffee and Claude"-style hello at the top of the Daily Almanac.
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
        #if DEBUG
        // `-almanac-part morning|afternoon|evening` pins the part so the greeting +
        // its sun/moon glyph can be captured headlessly at any hour (mirrors
        // `-almanac-write`). No effect in release or without the flag.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-almanac-part"), i + 1 < args.count,
           let forced = DayPart(rawValue: args[i + 1].uppercased()) {
            return forced
        }
        #endif
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
        "Morning on the block, {name}.",
        "Morning starts on your block, {name}.",
        "St. Joe is starting the day.",
        "The block is waking up.",
        "The day starts here.",
        "First stop, {name}?",
        "See you on the sidewalk, {name}.",
        "A new day on the block.",
        "Hello from your block.",
        "What's first, {name}?",
        "Good morning from St. Joe.",
        "Morning light on the porches.",
        "See what's happening today.",
        "Start where you are, {name}.",
        "The day is getting started.",
        "Daylight's here, {name}.",
        "First look at the day.",
        "A fresh start, {name}.",
        "The street is waking.",
        "Take the long way, {name}.",
        "Morning along Minnesota Street.",
        "The block is up.",
        "See you around town.",
        "First steps on the sidewalk.",
        "Start here, {name}.",
        "Wave if you see a neighbor.",
        "Morning in the neighborhood.",
        "Check the calendar, then head out.",
        "Today starts here, {name}.",
        "What's on your street today?",
        "Morning, {name}. Step outside when you're ready.",
        "St. Joe has the day ahead.",
        "The trail is there, {name}.",
        "Make room for some fresh air.",
        "Good to see you.",
        "Town is getting started.",
        "Step onto the porch, {name}.",
        "The sidewalk is a good start.",
        "Morning from the block, {name}.",
        "What's happening today?",
        "A lap around town, {name}?",
        "See you out there.",
        "Pick a direction, {name}.",
        "Find your first stop.",
    ]

    private static let morningFun: [String] = [
        "See who waves first.",
        "Porch check, {name}?",
        "Take the scenic block.",
    ]

    private static let afternoonWarm: [String] = [
        "Afternoon on the block, {name}.",
        "Afternoon starts here, {name}.",
        "St. Joe after noon.",
        "The block's in motion.",
        "The day rolls on.",
        "Back on the block, {name}.",
        "See what's happening after five.",
        "Take the sidewalk home, {name}.",
        "Hello from the block, {name}.",
        "The town is still moving.",
        "You're back on the block, {name}.",
        "Still time for the trail.",
        "A quick hello, {name}.",
        "Good to cross paths, {name}.",
        "Afternoon from St. Joe, {name}.",
        "Step outside, {name}.",
        "Good to have you here.",
        "Catch you around town, {name}.",
        "The street has room for a lap.",
        "What's happening tonight?",
        "Back in town.",
        "Back for another look, {name}.",
        "Midday on the block.",
        "Plenty of day left.",
        "See what's around the corner, {name}.",
        "Afternoon on Minnesota Street.",
        "Take the long way, {name}.",
        "Back for another look.",
        "A St. Joe afternoon, {name}.",
        "The block between stops.",
        "The porch is a good place to start.",
        "Good to find you here, {name}.",
        "What's next, {name}?",
        "Walk a block and look around.",
        "Hello from Minnesota Street.",
        "One more stop around town.",
        "The trail is still there.",
        "Afternoon, {name}. Look around.",
        "Take a lap past the neighbors.",
        "Back on the block.",
        "Meet you on the block, {name}.",
        "The day has more in it.",
    ]

    private static let afternoonFun: [String] = [
        "Take the long block home.",
        "What's happening after five, {name}?",
        "One block, then back to it.",
        "A trail break counts, {name}.",
        "Seen any neighbors yet?",
        "One more stop, then home.",
        "Street first, screen later.",
        "Make plans on the block.",
        "Take the scenic way, {name}.",
        "See who's out.",
        "Minnesota Street or the trail?",
        "Make a round, {name}.",
        "Tonight starts soon.",
        "The next block looks promising.",
    ]

    private static let eveningWarm: [String] = [
        "Evening on the block, {name}.",
        "Hello from the evening block, {name}.",
        "St. Joe after five.",
        "The day's wrapping up.",
        "End of day on the block.",
        "Tonight's taking shape, {name}.",
        "Porches, sidewalks, one more round.",
        "See what's happening tonight.",
        "After five in St. Joseph.",
        "The sidewalk has one more lap.",
        "Hello from the block tonight.",
        "Tonight on the block, {name}.",
        "See who's out front, {name}.",
        "Evening on Minnesota Street.",
        "The street is still awake.",
        "Hello from St. Joe tonight.",
        "Night's ahead, {name}.",
        "After five, neighbor.",
        "The trail at day's end.",
        "See who's around.",
        "Take the long way home.",
        "What's on tonight, {name}?",
        "Evening in the neighborhood.",
        "Back on your block, {name}.",
        "The block after five.",
        "See you around town.",
        "One more walk, {name}?",
        "Evening is here.",
        "Sidewalks after five.",
        "See what's happening nearby.",
        "End the day outside, {name}.",
        "Pick tonight's route, {name}.",
        "Around town tonight.",
        "Last lap around the block.",
        "Meet you on the porch, {name}.",
        "Evening plans?",
        "One more turn on the trail.",
        "The town's still here.",
        "Take the block home, {name}.",
        "What's happening on your street?",
        "Good evening, neighbor.",
        "Come see what's on, {name}.",
        "Tonight starts here.",
        "Out for a walk, {name}?",
        "Hello, evening.",
        "Take one more look, {name}.",
    ]

    private static let eveningFun: [String] = [
        "Last one home takes the long block.",
        "Porch round, {name}?",
        "See who's still out.",
        "One more loop around town.",
        "What's happening after dark, {name}?",
        "Take the scenic block home.",
        "Streetlights and one more block.",
        "Meet you at the corner, {name}.",
        "One last look around.",
    ]
}
