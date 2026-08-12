//
//  HorizonFixtures.swift
//  Block Party — canned days for verifying the horizon card headlessly.
//
//  Launch arguments (DEBUG only, compile out of Release):
//    -BPMockNow "2026-08-11T13:00:00-05:00"   ISO8601 instant
//    -BPMockSunTimes "06:13,21:02"            HH:mm pair, town time, on now's day
//    -BPMockDayState busy                     one of the §7 state fixtures
//
//  Items are built directly as DayItems (not through YourDayLogic) because
//  several states deliberately hold shapes the production pipeline cannot
//  emit yet — tomorrow's small-hours items, future-dated bug fixtures —
//  and the card's own guards are what's under test.
//  Every end is nil except where a state needs duration, mirroring the real
//  schema (club_events.end_at doesn't exist yet — see DayScheduleFixture).
//

#if DEBUG
import Foundation

/// The §7 states, typed — an unknown `-BPMockDayState` value fails loudly
/// instead of rendering a plausible empty card that "passes" a screenshot.
nonisolated enum HorizonDayState: String, CaseIterable {
    case empty, light, busy, overlap, edge, overflow, swap, midnight
    case solsticeSummer = "solstice-summer"
    case solsticeWinter = "solstice-winter"
    case degenerate, late, zerozero, loading, error
}

nonisolated struct HorizonMock {
    let now: Date
    let sunrise: Date?
    let sunset: Date?
    let state: HorizonDayState
    let items: [DayItem]

    /// Non-nil when any `-BPMock*` flag is present. Parsed once; the module
    /// and the section both read this so they cannot disagree.
    static let launchOverride: HorizonMock? = {
        let args = ProcessInfo.processInfo.arguments
        let flags = ["-BPMockNow", "-BPMockSunTimes", "-BPMockDayState"]
        guard args.contains(where: flags.contains) else { return nil }
        return fromArguments(args)
    }()

    /// `-BPMockNowSpeed <multiplier>` — accelerated mock clock, for
    /// recording transitions that otherwise need a real sunset.
    static let timeSpeed: Double? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-BPMockNowSpeed"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }()

    /// Reference instant for the accelerated clock.
    static let launchInstant = Date()

    static func fromArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> HorizonMock {
        let rawState = value(after: "-BPMockDayState", in: arguments)
        let state = rawState.map { raw in
            guard let parsed = HorizonDayState(rawValue: raw) else {
                assertionFailure("Unknown -BPMockDayState '\(raw)'")
                return HorizonDayState.busy
            }
            return parsed
        } ?? .busy

        var now = value(after: "-BPMockNow", in: arguments)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        var sunTimes = value(after: "-BPMockSunTimes", in: arguments).flatMap(parseSunTimes)

        // State-specific defaults, so a bare `-BPMockDayState midnight` is
        // already coherent without hand-picking a clock time.
        switch state {
        case .midnight, .swap, .late, .solsticeSummer, .solsticeWinter, .degenerate:
            now = now ?? stateDefaultNow(for: state)
            sunTimes = sunTimes ?? stateDefaultSun(for: state)
        default:
            break
        }
        let resolvedNow = now ?? townClock(2026, 8, 11, 13, 0)
        let resolvedSun = sunTimes ?? (rise: (6, 13), set: (21, 2))

        let dayOfNow = Town.calendar.startOfDay(for: resolvedNow)
        let sunrise = clock(on: dayOfNow, resolvedSun.rise.0, resolvedSun.rise.1)
        let sunset = clock(on: dayOfNow, resolvedSun.set.0, resolvedSun.set.1)

        return HorizonMock(
            now: resolvedNow,
            sunrise: sunrise,
            sunset: sunset,
            state: state,
            items: items(for: state, day: dayOfNow)
        )
    }

    // MARK: State fixtures (§7)

    /// Internal so the galleries can build a state's items on their own day.
    static func items(for state: HorizonDayState, day: Date) -> [DayItem] {
        func yours(_ id: String, _ h: Int, _ m: Int, dayOffset: Int = 0, allDay: Bool = false)
            -> DayItem {
            fixture(id, at: clock(on: day, h, m, dayOffset: dayOffset),
                    source: .committed, allDay: allDay)
        }
        func open(_ id: String, _ h: Int, _ m: Int, dayOffset: Int = 0) -> DayItem {
            fixture(id, at: clock(on: day, h, m, dayOffset: dayOffset), source: .wholeTown)
        }

        switch state {
        case .empty:
            return [
                open("o1", 8, 0), open("o2", 10, 30), open("o3", 12, 0), open("o4", 14, 0),
                open("o5", 16, 30), open("o6", 18, 0), open("o7", 19, 30),
            ]
        case .light:
            return [yours("y1", 17, 30), open("o1", 10, 0), open("o2", 13, 30), open("o3", 18, 15)]
        case .busy, .solsticeSummer, .solsticeWinter:
            return [
                yours("y1", 7, 0), yours("y2", 9, 30), yours("y3", 12, 15),
                yours("y4", 17, 30), yours("y5", 19, 0),
                open("o1", 6, 30), open("o2", 8, 0), open("o3", 8, 15), open("o4", 10, 0),
                open("o5", 11, 0), open("o6", 12, 0), open("o7", 13, 30), open("o8", 15, 0),
                open("o9", 16, 45), open("o10", 18, 15), open("o11", 20, 30),
            ]
        case .overlap:
            return [yours("y1", 14, 0), yours("y2", 14, 10), yours("y3", 14, 20)]
        case .edge:
            // Tangent to the FIXED 7a–10p window's edges (the old 6:18 /
            // 20:52 pair was tangent to the retired solar window).
            return [yours("y1", 7, 5), yours("y2", 21, 55)]
        case .overflow:
            // One item off each end of the fixed window, so this state
            // actually stages both "+N earlier/later" markers (22:00 sharp
            // is IN-window by the closed-interval rule — it was silently
            // staging nothing after the axis change).
            return [
                yours("y1", 10, 0), yours("y2", 21, 30), yours("y3", 22, 30),
                open("o1", 6, 30), open("o2", 15, 30),
            ]
        case .swap:
            return [
                yours("y1", 9, 0), yours("y2", 22, 15),
                open("o1", 12, 0), open("o2", 21, 30), open("o3", 23, 0),
            ]
        case .midnight:
            return [
                yours("tonight", 22, 30),
                yours("tomorrow-1", 0, 30, dayOffset: 1),
                open("tomorrow-2", 2, 0, dayOffset: 1),
            ]
        case .degenerate:
            return [yours("y1", 17, 30), open("o1", 10, 0), open("o2", 13, 30)]
        case .late:
            return [yours("y1", 9, 0), yours("y2", 17, 0), open("o1", 12, 0), open("o2", 19, 30)]
        case .zerozero, .loading, .error:
            return []
        }
    }

    private static func stateDefaultNow(for state: HorizonDayState) -> Date? {
        switch state {
        case .midnight: townClock(2026, 8, 11, 23, 50)
        case .swap: townClock(2026, 8, 11, 21, 0)  // sunset 21:02 − 2 min
        case .late: townClock(2026, 8, 11, 22, 45)
        case .solsticeSummer: townClock(2026, 6, 20, 13, 0)
        case .solsticeWinter: townClock(2026, 12, 21, 12, 0)
        case .degenerate: townClock(2026, 8, 11, 13, 0)
        default: nil
        }
    }

    private static func stateDefaultSun(for state: HorizonDayState) -> (rise: (Int, Int), set: (Int, Int))? {
        switch state {
        case .solsticeSummer: (rise: (5, 26), set: (21, 3))
        case .solsticeWinter: (rise: (7, 48), set: (16, 34))
        case .degenerate: (rise: (0, 10), set: (23, 50))
        default: nil
        }
    }

    // MARK: Plumbing

    private static let categories: [EventCategory] = [
        .outdoors, .musicArts, .food, .families, .faith, .games, .sports, .books, .service,
    ]

    private static func fixture(
        _ id: String, at start: Date, source: DayItemSource, allDay: Bool = false
    ) -> DayItem {
        // Deterministic category spread — stable per id ACROSS LAUNCHES
        // (String.hashValue is seed-randomized per process; screenshots
        // must be reproducible run to run).
        let stableHash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let category = categories[stableHash % categories.count]
        return DayItem(
            id: id,
            title: id,
            source: source,
            start: start,
            end: nil,
            isAllDay: allDay,
            isMultiDay: false,
            isComplete: false,
            eyebrow: "",
            location: nil,
            goingCount: 0,
            event: UpcomingEvent(
                id: id,
                title: id,
                eventDate: Town.day(start),
                startTime: nil,
                location: nil,
                goingCount: 0,
                createdAt: "fixture",
                category: category
            )
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    private static func parseSunTimes(_ raw: String) -> (rise: (Int, Int), set: (Int, Int))? {
        let parts = raw.split(separator: ",")
        guard parts.count == 2 else { return nil }
        func hm(_ s: Substring) -> (Int, Int)? {
            let bits = s.split(separator: ":")
            guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]) else { return nil }
            return (h, m)
        }
        guard let rise = hm(parts[0]), let set = hm(parts[1]) else { return nil }
        return (rise: rise, set: set)
    }

    private static func clock(on day: Date, _ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        // bySettingHour, not byAdding — wall-clock fixture times must stay
        // wall-clock on DST-change days (the townInstant rule).
        let date = Town.calendar.date(byAdding: .day, value: dayOffset, to: day) ?? day
        return Town.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    private static func townClock(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = mo
        components.day = d
        components.hour = h
        components.minute = mi
        return Town.calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
#endif
