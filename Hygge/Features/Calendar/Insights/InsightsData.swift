//
//  InsightsData.swift
//  Hygge — real town-calendar data shaped for the Upcoming Insights face, now
//  PERSONAL: driven by the signed-in user's RSVPs + on-device onboarding interests
//  layered over the town's calendar. The reference recording's journaling
//  semantics don't exist in a town calendar, so the *layout & motion* are ported
//  1:1 while the content is real, forward-looking, personal signals:
//
//    1 · Spotlight wheel — your soonest event, then the town's most-loved, then
//        the town's next happening (paged, deduped).
//    2 · "Your Year Ahead" — a 12-month distribution of events matching YOUR
//        interests, with the town's totals as ghost bars for context.
//    3 · Interest bento — three of your onboarding interests, each a live count.
//    4 · Mini month grid — neutral dots for town happenings, coral for YOUR days.
//
//  `from(...)` is a pure function over what CalendarModel already loads plus two
//  small personal reads (myRsvps, rsvpCounts) and the on-device interests — no new
//  API surface, no inflated numbers. Real data only: 0 reads as 0. Countdown
//  framing is reserved for the spotlight; everything else names its rhythm.
//  Design spec: docs/superpowers/specs/2026-07-16-upcoming-insights-personal-design.md
//

import Foundation

struct InsightsData {
    // 1 · Spotlight wheel — 1…3 deduped pages (never empty; empty calendar → one dash page).
    var spotlight: [SpotlightPage]

    // 2 · "Your Year Ahead" chart.
    var yearTotal: Int                 // upcoming events matching your interests (town total if none picked)
    var months: [YearMonth]            // 12, current month first — yours (foreground) + town (ghost)
    var yearMarkerIndex: Int           // the highlighted peak column
    var yearCaption: String            // "August is your fullest month ahead." / "Pick interests to make this yours."
    var hasInterests: Bool

    // 3 · Interest bento — exactly 3 tiles.
    var bento: [InterestTile]

    // 4 · Mini month grid + its quiet, forward caption.
    var grid: Grid
    var gridCaption: String            // "Your next full day: Friday."

    var isEmpty: Bool                  // nothing upcoming on the whole town calendar

    // MARK: - Slot value types

    /// One page of the spotlight wheel — a giant countdown numeral + one starred event.
    struct SpotlightPage: Identifiable {
        enum Kind { case yours, town, next, empty }
        let id: Int
        let kind: Kind
        let label: String              // header, top-left: "Yours" / "In town" / "Next up" / "Up next"
        let value: String              // countdown numeral, "Today", or "—"
        let unit: String               // "Days" / "Day" / ""
        let subtitle: String           // "Trivia at the Middy · you're going"
    }

    /// One month column of the year-ahead chart.
    struct YearMonth: Identifiable {
        let id: Int
        let letter: String             // "J" "F" "M" …
        let yours: Int                 // your interest-matched count (foreground bar)
        let town: Int                  // the town's total that month (ghost bar behind)
    }

    /// One interest category tile in the bento.
    struct InterestTile: Identifiable {
        let id: String                 // interest id (or a synthetic town-fill id)
        let title: String              // Interest.label — "Live Music"
        let count: Int                 // upcoming keyword matches (0 renders honestly)
        let picked: Bool               // did the user actually pick this interest?
        let thisWeek: Int              // sub-stat A: matches in the next 7 days
        let nextDayPart: String?       // sub-stat B doorway: "Friday evening" (nil at zero)
        let nextDayKey: String?        // YYYY-MM-DD the doorway opens (nil at zero)
        let emptyLine: String?         // "A quiet stretch for trails." (only when count == 0)
    }

    struct Grid {
        let title: String              // "July 2026"
        let leadingBlanks: Int
        let dayCount: Int
        let counts: [Int]              // town happenings per day 1…dayCount (neutral dot when > 0)
        let mineDays: Set<Int>         // days that are YOURS (coral dot) — RSVP'd or interest-matched
        let todayDay: Int?
    }

    // MARK: - Build from what CalendarModel loads + the personal reads

    /// Pure, testable. Inputs:
    /// - counts:     YYYY-MM-DD → town happenings that day (CalendarModel.counts)
    /// - upcoming:   the town's upcoming agenda, today onward, date+time order
    /// - myRsvps:    the user's RSVP'd upcoming events (empty when signed-out/degraded)
    /// - rsvpCounts: eventId → going count, for the upcoming ids (empty when degraded)
    /// - interests:  picked onboarding interest ids (UserDefaults; may be empty)
    /// - today:      YYYY-MM-DD, timezone-pinned by the caller
    static func from(counts: [String: Int],
                     upcoming: [AgendaEvent],
                     myRsvps: [UpcomingEvent],
                     rsvpCounts: [String: Int],
                     interests: [String],
                     today: String) -> InsightsData {
        let cal = CalendarModel.gregorian
        let tp = today.split(separator: "-").compactMap { Int($0) }
        guard tp.count == 3,
              let base = cal.date(from: DateComponents(year: tp[0], month: tp[1])),
              let todayDate = cal.date(from: DateComponents(year: tp[0], month: tp[1], day: tp[2]))
        else { return .empty }
        let ctx = Context(cal: cal, base: base, todayDate: todayDate, today: today,
                          year: tp[0], month: tp[1], day: tp[2],
                          upcoming: upcoming, counts: counts, myRsvps: myRsvps,
                          rsvpCounts: rsvpCounts, interests: interests)

        let (months, marker, yearTotal, yearCaption) = buildYear(ctx)
        let bento = buildBento(ctx)
        let grid = buildGrid(ctx)

        return InsightsData(
            spotlight: buildSpotlight(ctx),
            yearTotal: yearTotal, months: months, yearMarkerIndex: marker,
            yearCaption: yearCaption, hasInterests: !interests.isEmpty,
            bento: bento,
            grid: grid, gridCaption: buildGridCaption(ctx, grid: grid),
            isEmpty: upcoming.isEmpty)
    }

    // MARK: - Shared build context

    private struct Ev { let id: String; let title: String; let date: String; let start: String? }

    private struct Context {
        let cal: Calendar
        let base: Date          // first of the current month
        let todayDate: Date
        let today: String
        let year: Int
        let month: Int
        let day: Int
        let upcoming: [AgendaEvent]
        let counts: [String: Int]
        let myRsvps: [UpcomingEvent]
        let rsvpCounts: [String: Int]
        let interests: [String]

        var weekEndKey: String {
            guard let d = cal.date(byAdding: .day, value: 6, to: todayDate) else { return today }
            return DateHelpers.localDate(d)
        }
        func matches(_ e: AgendaEvent, _ ids: [String]) -> Bool {
            guard !ids.isEmpty else { return false }
            return Interests.matches("\(e.title) \(e.location ?? "")", ids)
        }
    }

    // MARK: - 1 · Spotlight wheel

    private static func buildSpotlight(_ c: Context) -> [SpotlightPage] {
        guard !c.upcoming.isEmpty else {
            return [SpotlightPage(id: 0, kind: .empty, label: "Up next", value: "—",
                                  unit: "", subtitle: "Nothing on the calendar yet")]
        }

        var pages: [SpotlightPage] = []
        var seen = Set<String>()

        // Page 1 — Yours: soonest RSVP'd; else soonest matching a picked interest.
        if let rsvp = c.myRsvps.first {
            let ev = Ev(id: rsvp.id, title: rsvp.title, date: rsvp.eventDate, start: rsvp.startTime)
            pages.append(page(.yours, "Yours", ev, reason: "you're going", c))
            seen.insert(ev.id)
        } else if let m = c.upcoming.first(where: { c.matches($0, c.interests) }) {
            let ev = Ev(id: m.id, title: m.title, date: m.eventDate, start: m.startTime)
            pages.append(page(.yours, "Yours", ev, reason: whenPhrase(ev), c))
            seen.insert(ev.id)
        }

        // Page 2 — In town: the most-RSVP'd upcoming event (only when someone's going).
        if let top = mostLoved(c), !seen.contains(top.id) {
            let n = c.rsvpCounts[top.id] ?? 0
            pages.append(page(.town, "In town", top, reason: neighborsLine(n), c))
            seen.insert(top.id)
        }

        // Page 3 — Next up: the town's soonest happening, so the wheel always has a page.
        if let first = c.upcoming.first {
            let ev = Ev(id: first.id, title: first.title, date: first.eventDate, start: first.startTime)
            if !seen.contains(ev.id) {
                pages.append(page(.next, "Next up", ev, reason: whenPhrase(ev), c))
                seen.insert(ev.id)
            }
        }

        return pages.isEmpty ? [SpotlightPage(id: 0, kind: .next, label: "Up next", value: "—",
                                              unit: "", subtitle: "Nothing on the calendar yet")]
                             : pages
    }

    /// The upcoming event with the most RSVPs — nil unless at least one neighbor is going,
    /// so the "In town" page never appears on empty social proof.
    private static func mostLoved(_ c: Context) -> Ev? {
        var best: (Ev, Int)?
        for e in c.upcoming {
            let n = c.rsvpCounts[e.id] ?? 0
            guard n > 0 else { continue }
            if best == nil || n > best!.1 {
                best = (Ev(id: e.id, title: e.title, date: e.eventDate, start: e.startTime), n)
            }
        }
        return best?.0
    }

    private static func page(_ kind: SpotlightPage.Kind, _ label: String, _ ev: Ev,
                             reason: String?, _ c: Context) -> SpotlightPage {
        let (value, unit) = countdown(ev.date, c)
        let subtitle = reason.map { "\(ev.title) · \($0)" } ?? ev.title
        return SpotlightPage(id: kind.hashValue, kind: kind, label: label,
                             value: value, unit: unit, subtitle: subtitle)
    }

    /// Count-based social proof, honest and singular-aware — nil (absent) at zero.
    private static func neighborsLine(_ n: Int) -> String? {
        switch n {
        case ..<1:  return nil
        case 1:     return "1 neighbor is going"
        default:    return "\(n) neighbors are going"
        }
    }

    // MARK: - 2 · Your Year Ahead

    private static func buildYear(_ c: Context) -> (months: [YearMonth], marker: Int, total: Int, caption: String) {
        let letters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        let hasInterests = !c.interests.isEmpty

        var months: [YearMonth] = []
        for off in 0..<12 {
            guard let md = c.cal.date(byAdding: .month, value: off, to: c.base) else { continue }
            let comps = c.cal.dateComponents([.year, .month], from: md)
            let prefix = String(format: "%04d-%02d-", comps.year ?? 0, comps.month ?? 0)
            let mk = String(prefix.dropLast())                                  // "YYYY-MM"
            let town = c.counts.reduce(0) { $1.key.hasPrefix(prefix) ? $0 + $1.value : $0 }
            let yours = hasInterests
                ? c.upcoming.filter { $0.eventDate.hasPrefix(mk) && c.matches($0, c.interests) }.count
                : town                                                          // no interests → town IS the foreground
            months.append(YearMonth(id: off, letter: letters[(comps.month ?? 1) - 1], yours: yours, town: town))
        }

        // Total the big number reports: your matches, or the town's upcoming when none picked.
        let yourTotal = hasInterests
            ? c.upcoming.filter { c.matches($0, c.interests) }.count
            : c.upcoming.count

        // Peak column: your fullest month (town's fullest when none picked / no matches).
        let series = hasInterests && yourTotal > 0 ? months.map(\.yours) : months.map(\.town)
        let marker = series.enumerated().max { $0.element < $1.element }?.offset ?? 0

        let caption: String
        if !hasInterests {
            caption = "Pick interests to make this yours."
        } else if yourTotal == 0 {
            caption = "Nothing matching your interests yet."
        } else {
            caption = "\(monthName(c, offset: marker)) is your fullest month ahead."
        }
        return (months, marker, yourTotal, caption)
    }

    // MARK: - 3 · Interest bento

    private static func buildBento(_ c: Context) -> [InterestTile] {
        func matchCount(_ id: String) -> Int { c.upcoming.filter { c.matches($0, [id]) }.count }

        // Choose the 3 interest ids: the user's (most-active first when they picked >3),
        // topped up with the town's most-active categories when they picked fewer than 3.
        let pickedByActivity = c.interests.sorted { matchCount($0) > matchCount($1) }
        var chosen: [(id: String, picked: Bool)] = pickedByActivity.prefix(3).map { ($0, true) }
        if chosen.count < 3 {
            let pickedSet = Set(c.interests)
            let fill = Interests.all.map(\.id)
                .filter { !pickedSet.contains($0) }
                .sorted { matchCount($0) > matchCount($1) }
            for id in fill where chosen.count < 3 { chosen.append((id, false)) }
        }

        return chosen.map { pick in
            let label = Interests.all.first { $0.id == pick.id }?.label ?? pick.id
            let count = matchCount(pick.id)
            let week = c.upcoming.filter {
                $0.eventDate >= c.today && $0.eventDate <= c.weekEndKey && c.matches($0, [pick.id])
            }.count
            let next = c.upcoming.first { c.matches($0, [pick.id]) }
            let ev = next.map { Ev(id: $0.id, title: $0.title, date: $0.eventDate, start: $0.startTime) }
            return InterestTile(
                id: pick.id, title: label, count: count, picked: pick.picked,
                thisWeek: week,
                nextDayPart: ev.map { whenPhrase($0) },
                nextDayKey: ev?.date,
                emptyLine: count == 0 ? "A quiet stretch for \(shortNoun(label))." : nil)
        }
    }

    // MARK: - 4 · Mini month grid

    private static func buildGrid(_ c: Context) -> Grid {
        let dayCount = c.cal.range(of: .day, in: .month, for: c.base)?.count ?? 30
        let leading = c.cal.component(.weekday, from: c.base) - 1
        var dayCounts: [Int] = []
        for d in 1...dayCount {
            dayCounts.append(c.counts[String(format: "%04d-%02d-%02d", c.year, c.month, d)] ?? 0)
        }

        // "Yours" days this month: RSVP'd, or matching a picked interest.
        var mine = Set<Int>()
        let monthPrefix = String(format: "%04d-%02d-", c.year, c.month)
        for r in c.myRsvps where r.eventDate.hasPrefix(monthPrefix) {
            if let d = dayOf(r.eventDate) { mine.insert(d) }
        }
        if !c.interests.isEmpty {
            for e in c.upcoming where e.eventDate.hasPrefix(monthPrefix) && c.matches(e, c.interests) {
                if let d = dayOf(e.eventDate) { mine.insert(d) }
            }
        }

        let fmt = DateFormatter()
        fmt.calendar = c.cal; fmt.locale = Locale(identifier: "en_US"); fmt.dateFormat = "MMMM yyyy"
        return Grid(title: fmt.string(from: c.base), leadingBlanks: leading,
                    dayCount: dayCount, counts: dayCounts, mineDays: mine, todayDay: c.day)
    }

    /// Quiet, forward caption — names what happens FOR the user, never the negative space.
    private static func buildGridCaption(_ c: Context, grid: Grid) -> String {
        if c.upcoming.isEmpty { return "Nothing on the calendar yet." }
        // The soonest "yours" day (this month), by weekday.
        let next = c.myRsvps.map(\.eventDate)
            + (c.interests.isEmpty ? [] : c.upcoming.filter { c.matches($0, c.interests) }.map(\.eventDate))
        if let soonest = next.filter({ $0 >= c.today }).min() {
            return "Your next full day: \(fullWeekday(soonest))."
        }
        return "Nothing of yours on the calendar yet."
    }

    // MARK: - Small pure helpers

    /// Days until an event, framed for the spotlight numeral. Today → "Today".
    private static func countdown(_ ymd: String, _ c: Context) -> (value: String, unit: String) {
        guard let d = DateHelpers.daysBetween(c.today, ymd) else { return ("—", "") }
        if d <= 0 { return ("Today", "") }
        return ("\(d)", d == 1 ? "Day" : "Days")
    }

    /// "Friday evening" — weekday + day-part; weekday alone for untimed events
    /// (day-parts beat clock times; an untimed event never guesses "evening").
    private static func whenPhrase(_ ev: Ev) -> String {
        let weekday = fullWeekday(ev.date)
        let mins = DateHelpers.minutesOf(ev.start)
        guard let start = ev.start, !start.isEmpty, mins < 24 * 60 else { return weekday }
        return "\(weekday) \(dayPart(mins))"
    }

    private static func dayPart(_ minutes: Int) -> String {
        if minutes < 12 * 60 { return "morning" }
        if minutes < 17 * 60 { return "afternoon" }
        return "evening"
    }

    private static func fullWeekday(_ ymd: String) -> String {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return "" }
        var comps = DateComponents(); comps.year = p[0]; comps.month = p[1]; comps.day = p[2]
        guard let date = Calendar(identifier: .gregorian).date(from: comps) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private static func monthName(_ c: Context, offset: Int) -> String {
        guard let d = c.cal.date(byAdding: .month, value: offset, to: c.base) else { return "" }
        let f = DateFormatter(); f.calendar = c.cal; f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMMM"
        return f.string(from: d)
    }

    private static func dayOf(_ ymd: String) -> Int? {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? p[2] : nil
    }

    /// A short lowercase noun for a category, for the honest empty line:
    /// "Trails & Hiking" → "trails", "Live Music" → "live music".
    private static func shortNoun(_ label: String) -> String {
        let lower = label.lowercased()
        return lower.components(separatedBy: " & ").first ?? lower
    }
}

// MARK: - DEBUG samples — every card state, screenshot-able on a signed-out sim

#if DEBUG
extension InsightsData {
    /// Fully populated: interests picked, three spotlight pages, a zero bento tile,
    /// both grid dot kinds, yours+town chart. `-insights-sample`.
    static var sample: InsightsData {
        let letters = ["J", "A", "S", "O", "N", "D", "J", "F", "M", "A", "M", "J"]
        let town = [9, 7, 5, 6, 4, 3, 2, 2, 1, 1, 1, 0]
        let yours = [3, 4, 1, 2, 1, 0, 1, 0, 0, 0, 0, 0]
        var counts = Array(repeating: 0, count: 31)
        for (d, n) in [(17, 2), (18, 1), (20, 1), (24, 2), (26, 3), (31, 1)] { counts[d - 1] = n }
        return InsightsData(
            spotlight: [
                SpotlightPage(id: 0, kind: .yours, label: "Yours", value: "3", unit: "Days",
                              subtitle: "Trivia at the Middy · you're going"),
                SpotlightPage(id: 1, kind: .town, label: "In town", value: "12", unit: "Days",
                              subtitle: "Joetown Rocks · 24 neighbors are going"),
                SpotlightPage(id: 2, kind: .next, label: "Next up", value: "1", unit: "Day",
                              subtitle: "Farmers Market · Friday morning"),
            ],
            yearTotal: 12,
            months: (0..<12).map { YearMonth(id: $0, letter: letters[$0], yours: yours[$0], town: town[$0]) },
            yearMarkerIndex: 1, yearCaption: "August is your fullest month ahead.", hasInterests: true,
            bento: [
                InterestTile(id: "live_music", title: "Live Music", count: 3, picked: true, thisWeek: 1,
                             nextDayPart: "Friday evening", nextDayKey: "2026-07-17", emptyLine: nil),
                InterestTile(id: "trails_hiking", title: "Trails & Hiking", count: 2, picked: true, thisWeek: 1,
                             nextDayPart: "Saturday morning", nextDayKey: "2026-07-18", emptyLine: nil),
                InterestTile(id: "breweries", title: "Breweries & Taprooms", count: 0, picked: true, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for breweries."),
            ],
            grid: Grid(title: "July 2026", leadingBlanks: 3, dayCount: 31, counts: counts,
                       mineDays: [17, 24, 26], todayDay: 15),
            gridCaption: "Your next full day: Friday.",
            isEmpty: false)
    }

    /// No interests picked: chart falls back to town totals + the pick-interests line,
    /// bento fills with the town's most active categories, a real RSVP still stars page 1.
    static var sampleNoInterests: InsightsData {
        let letters = ["J", "A", "S", "O", "N", "D", "J", "F", "M", "A", "M", "J"]
        let town = [9, 7, 5, 6, 4, 3, 2, 2, 1, 1, 1, 0]
        var counts = Array(repeating: 0, count: 31)
        for (d, n) in [(17, 2), (18, 1), (20, 1), (24, 2), (26, 3), (31, 1)] { counts[d - 1] = n }
        return InsightsData(
            spotlight: [
                SpotlightPage(id: 0, kind: .yours, label: "Yours", value: "3", unit: "Days",
                              subtitle: "Farmers Market · you're going"),
                SpotlightPage(id: 1, kind: .town, label: "In town", value: "12", unit: "Days",
                              subtitle: "Joetown Rocks · 24 neighbors are going"),
            ],
            yearTotal: 46,
            months: (0..<12).map { YearMonth(id: $0, letter: letters[$0], yours: town[$0], town: town[$0]) },
            yearMarkerIndex: 0, yearCaption: "Pick interests to make this yours.", hasInterests: false,
            bento: [
                InterestTile(id: "festivals", title: "Festivals & Fairs", count: 4, picked: false, thisWeek: 1,
                             nextDayPart: "Saturday afternoon", nextDayKey: "2026-07-18", emptyLine: nil),
                InterestTile(id: "farmers_market", title: "Farmers Market", count: 3, picked: false, thisWeek: 1,
                             nextDayPart: "Friday morning", nextDayKey: "2026-07-17", emptyLine: nil),
                InterestTile(id: "live_music", title: "Live Music", count: 2, picked: false, thisWeek: 0,
                             nextDayPart: "Saturday evening", nextDayKey: "2026-07-25", emptyLine: nil),
            ],
            grid: Grid(title: "July 2026", leadingBlanks: 3, dayCount: 31, counts: counts,
                       mineDays: [17], todayDay: 15),
            gridCaption: "Your next full day: Friday.",
            isEmpty: false)
    }

    /// Sparse: one small thing on the town calendar, honest zeros everywhere else.
    static var sampleSparse: InsightsData {
        let letters = ["J", "A", "S", "O", "N", "D", "J", "F", "M", "A", "M", "J"]
        let town = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        var counts = Array(repeating: 0, count: 31)
        counts[20] = 1
        return InsightsData(
            spotlight: [
                SpotlightPage(id: 0, kind: .next, label: "Next up", value: "6", unit: "Days",
                              subtitle: "Parish Pancake Breakfast · Monday morning"),
            ],
            yearTotal: 0,
            months: (0..<12).map { YearMonth(id: $0, letter: letters[$0], yours: 0, town: town[$0]) },
            yearMarkerIndex: 0, yearCaption: "Nothing matching your interests yet.", hasInterests: true,
            bento: [
                InterestTile(id: "trails_hiking", title: "Trails & Hiking", count: 0, picked: true, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for trails."),
                InterestTile(id: "live_music", title: "Live Music", count: 0, picked: true, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for live music."),
                InterestTile(id: "coffee", title: "Coffee Shops", count: 0, picked: true, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for coffee shops."),
            ],
            grid: Grid(title: "July 2026", leadingBlanks: 3, dayCount: 31, counts: counts,
                       mineDays: [], todayDay: 15),
            gridCaption: "Nothing of yours on the calendar yet.",
            isEmpty: false)
    }

    static var empty: InsightsData {
        InsightsData(
            spotlight: [SpotlightPage(id: 0, kind: .empty, label: "Up next", value: "—", unit: "",
                                      subtitle: "Nothing on the calendar yet")],
            yearTotal: 0,
            months: (0..<12).map { YearMonth(id: $0, letter: "·", yours: 0, town: 0) },
            yearMarkerIndex: 0, yearCaption: "Pick interests to make this yours.", hasInterests: false,
            bento: [
                InterestTile(id: "a", title: "Live Music", count: 0, picked: false, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for live music."),
                InterestTile(id: "b", title: "Trails & Hiking", count: 0, picked: false, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for trails."),
                InterestTile(id: "c", title: "Farmers Market", count: 0, picked: false, thisWeek: 0,
                             nextDayPart: nil, nextDayKey: nil, emptyLine: "A quiet stretch for farmers market."),
            ],
            grid: Grid(title: "", leadingBlanks: 0, dayCount: 30, counts: Array(repeating: 0, count: 30),
                       mineDays: [], todayDay: nil),
            gridCaption: "Nothing on the calendar yet.",
            isEmpty: true)
    }
}
#else
extension InsightsData {
    static var empty: InsightsData {
        InsightsData(
            spotlight: [SpotlightPage(id: 0, kind: .empty, label: "Up next", value: "—", unit: "",
                                      subtitle: "Nothing on the calendar yet")],
            yearTotal: 0,
            months: (0..<12).map { YearMonth(id: $0, letter: "·", yours: 0, town: 0) },
            yearMarkerIndex: 0, yearCaption: "Pick interests to make this yours.", hasInterests: false,
            bento: (0..<3).map { InterestTile(id: "\($0)", title: "", count: 0, picked: false, thisWeek: 0,
                                              nextDayPart: nil, nextDayKey: nil, emptyLine: nil) },
            grid: Grid(title: "", leadingBlanks: 0, dayCount: 30, counts: Array(repeating: 0, count: 30),
                       mineDays: [], todayDay: nil),
            gridCaption: "Nothing on the calendar yet.",
            isEmpty: true)
    }
}
#endif
