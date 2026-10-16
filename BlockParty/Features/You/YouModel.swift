//
//  YouModel.swift
//  Block Party — the You tab's three weeks: the Events the neighbour is Going to, from
//  this week's Sunday, laid out as the Calendar's days (BP app docs/plans/you-tab).
//
//  The database works out whose Going it is (`get_my_going`, the one function iOS and
//  Android call). This keeps the last list across tab switches and failed reads, as the
//  Town feed does, and the page lays the neighbour's taps from this session over it
//  (`RealLifeActions`), so a Join on a card shows here at once and one that turns back
//  never does.
//

import Foundation

@MainActor @Observable
final class YouModel {
    /// The read's Going, nil until the first read lands; the page shows its skeleton then.
    private(set) var going: [DailyEvent]?
    /// The last read failed. With no list the page shows its retry; with one, it keeps it.
    private(set) var failed = false

    /// Numbers each read, so only the newest one's answer is kept.
    @ObservationIgnored private var latestRead = 0
    private let read: (_ from: String, _ to: String) async throws -> [UpcomingEvent]

    /// `read` takes the first and last Town days, "yyyy-MM-dd", both included.
    init(read: @escaping (_ from: String, _ to: String) async throws -> [UpcomingEvent]) {
        self.read = read
    }

    /// The live read, or under DEBUG `-town-samples` sample Going, so design work has
    /// photos on the Calendar and never reads the live database; `-town-offline` fails
    /// every read.
    convenience init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-town-offline") {
            self.init(read: { _, _ in throw URLError(.notConnectedToInternet) })
            return
        }
        if arguments.contains("-town-samples") {
            self.init(read: { _, _ in YouCalendar.samples(now: Date()) })
            return
        }
        #endif
        self.init(read: { from, to in
            try await CommunityAPI(auth: AuthStore.shared).getMyGoing(from: from, to: to)
        })
    }

    /// Profile's Saved list (ticket 04), kept the same way: `get_my_saves` from this week's
    /// Sunday on (`to` is unused; saves run as far ahead as they go), and `going` holds the
    /// saves. The page leaves out what's over (`YouCalendar.saved`). Under DEBUG
    /// `-town-samples` the You samples come back saved, and `-town-offline` fails.
    static func saves() -> YouModel {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-town-offline") {
            return YouModel(read: { _, _ in throw URLError(.notConnectedToInternet) })
        }
        if arguments.contains("-town-samples") {
            return YouModel(read: { _, _ in
                YouCalendar.samples(now: Date()).map { var event = $0; event.saved = true; return event }
            })
        }
        #endif
        return YouModel(read: { from, _ in
            try await CommunityAPI(auth: AuthStore.shared).getMySaves(from: from)
        })
    }

    /// Reads the three weeks around `now` again, behind whatever is on screen.
    func refresh(now: Date = Date()) async {
        let first = YouCalendar.firstDay(of: now)
        latestRead += 1
        let mine = latestRead
        // A retry with nothing on screen shows the skeleton again while it reads.
        if going == nil { failed = false }
        do {
            let rows = try await read(Town.day(first), Town.day(YouCalendar.lastDay(from: first)))
            guard mine == latestRead else { return }
            going = rows.compactMap(YouCalendar.event(from:))
            failed = false
        } catch {
            // Leaving the tab mid-read cancels it; that says nothing about the network.
            guard mine == latestRead, !Task.isCancelled, !(error is CancellationError) else { return }
            failed = true
        }
    }

    /// A new account sees none of the last one's Going.
    func accountChanged() {
        latestRead += 1
        going = nil
        failed = false
    }
}

/// The Calendar's rules: which days, which Events fall on each, in what order. Pure, so
/// the tests drive it with fixed dates.
enum YouCalendar {
    /// Three weeks (Jesse, 2026-10-10).
    static let length = 21

    /// Gregorian in the Town's time zone, weeks from Sunday whatever the phone is set to
    /// (Jesse picked Sunday, 2026-10-10). Days are stepped, never added as 24 hours, so
    /// the Sunday the clocks go back stays one day.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Town midnight on the Sunday of `now`'s week.
    static func firstDay(of now: Date) -> Date {
        let calendar = calendar
        let today = calendar.startOfDay(for: now)
        let sinceSunday = calendar.component(.weekday, from: today) - 1
        return calendar.date(byAdding: .day, value: -sinceSunday, to: today) ?? today
    }

    static func lastDay(from first: Date) -> Date {
        calendar.date(byAdding: .day, value: length - 1, to: first) ?? first
    }

    /// The 21 Town midnights from `first`.
    static func days(from first: Date) -> [Date] {
        (0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// A row of the read as the Agenda's Event. nil when its date doesn't parse.
    static func event(from row: UpcomingEvent) -> DailyEvent? {
        var item = FeedCardItem(row)
        // An all-day Event shows no start time (schema.sql, `all_day`).
        if row.isAllDay { item.startTime = nil }
        return timed(item, day: row.eventDate, time: item.startTime, endAt: row.endAt)
    }

    /// An Event tapped Going on a card, before a read brings it back with its end.
    static func event(from item: FeedCardItem) -> DailyEvent? {
        guard let day = item.eventDate else { return nil }
        return timed(item, day: day, time: item.startTime, endAt: nil)
    }

    /// When it starts, from the organizer's free-text time on its Town day; ends at
    /// `end_at`, else two hours on, as the Town feed has it. A time the one parser
    /// can't read ("after dark") or an all-day Event runs the whole day, untimed.
    private static func timed(_ item: FeedCardItem, day: String, time: String?,
                              endAt: Date?) -> DailyEvent? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let midnight = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let minutes = YourDayLogic.minutes(from: time)
        let starts = minutes.flatMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: midnight) }
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        var event = DailyEvent(item: item, starts: starts ?? midnight,
                               ends: endAt ?? starts?.addingTimeInterval(2 * 3600) ?? nextMidnight,
                               town: "")
        event.timed = starts != nil
        return event
    }

    /// The Going on the Calendar: the read's, and the Events tapped Going this session
    /// that fall in the `days` from `first` (the three weeks; a year for the iPhone
    /// Calendar), each once (the read's details win), only those still Going and not called
    /// off (Jesse, 2026-10-15: a cancelled one leaves, and `CancelNotice` says so once); by
    /// day, a day's timed Events soonest first and then its untimed ones, then by title.
    static func going(read: [DailyEvent], tapped: [FeedCardItem], isGoing: (FeedCardItem) -> Bool,
                      first: Date, days: Int = length) -> [DailyEvent] {
        let end = calendar.date(byAdding: .day, value: days, to: first) ?? first
        return merged(read, tapped)
            .filter { isGoing($0.item) && !$0.item.cancelled && $0.starts >= first && $0.starts < end }
            .sorted { order($0) < order($1) }
    }

    /// Profile's Saved list (ticket 04), the same way: the read's and the Events saved this
    /// session, each once, only those still saved, not called off and not over by `now`, in the
    /// Calendar's order.
    static func saved(read: [DailyEvent], tapped: [FeedCardItem], isSaved: (FeedCardItem) -> Bool,
                      now: Date) -> [DailyEvent] {
        merged(read, tapped)
            .filter { isSaved($0.item) && !$0.item.cancelled && $0.ends > now }
            .sorted { order($0) < order($1) }
    }

    /// The read's Events and the tapped ones, each once; the read's details win.
    private static func merged(_ read: [DailyEvent], _ tapped: [FeedCardItem]) -> [DailyEvent] {
        var byID: [String: DailyEvent] = [:]
        for item in tapped { if let event = event(from: item) { byID[event.id] = event } }
        for event in read { byID[event.id] = event }
        return Array(byID.values)
    }

    private static func order(_ event: DailyEvent) -> (Date, Int, Date, String) {
        (calendar.startOfDay(for: event.starts), event.timed ? 0 : 1, event.starts, event.item.title)
    }

    /// The Events on one day, in the order they came.
    static func on(_ day: Date, _ going: [DailyEvent]) -> [DailyEvent] {
        going.filter { calendar.isDate($0.starts, inSameDayAs: day) }
    }

    /// The Going by Town day, once for the whole grid, each day in the order it came.
    static func byDay(_ going: [DailyEvent]) -> [Date: [DailyEvent]] {
        Dictionary(grouping: going) { calendar.startOfDay(for: $0.starts) }
    }

    /// The Places row (ticket 03): the next Event at each place, one not over by `now`,
    /// in the order they came. A place is the organizer's typed name, the same whatever
    /// its case, spacing or apostrophe; an Event with none is left out.
    static func places(_ going: [DailyEvent], now: Date) -> [DailyEvent] {
        var seen = Set<String>()
        return going.filter { event in
            guard event.ends > now, let place = place(of: event) else { return false }
            let key = place.lowercased().replacingOccurrences(of: "’", with: "'")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return seen.insert(key).inserted
        }
    }

    static func place(of event: DailyEvent) -> String? {
        let place = event.item.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return place.isEmpty ? nil : place
    }

    #if DEBUG
    /// INVENTED: Going at real St. Joseph places with the bundled town photos, spread
    /// over the three weeks around `now`, today busy, one with no photo of its own. Every
    /// title and time is made up.
    static func samples(now: Date) -> [UpcomingEvent] {
        let calendar = calendar
        let today = calendar.startOfDay(for: now)
        let first = firstDay(of: now)
        let last = lastDay(from: first)
        func day(_ offset: Int) -> Date? {
            calendar.date(byAdding: .day, value: offset, to: today).flatMap { $0 >= first && $0 <= last ? $0 : nil }
        }
        // `-town-cancelled`: today's coffee is called off, so the You tab leaves it out
        // and the app opens on the alert (ticket 12).
        let cancelledSample = ProcessInfo.processInfo.arguments.contains("-town-cancelled")
        let rows: [(Int, String, String, String?, String, EventCategory)] = [
            (-3, "10 AM", "Fall colors hike", "sju-arboretum-trail", "Saint John's Arboretum", .outdoors),
            (-1, "7 PM", "Trivia night", "bad-habit-brewing", "Bad Habit Brewing", .food),
            (0, "8 AM", "Coffee with the bike club", "the-local-blend", "The Local Blend", .food),
            (0, "7 PM", "Book club: the October pick", nil, "Great River Regional Library", .books),
            (3, "12 PM", "Rocktoberfest", "rocktoberfest", "Downtown St. Joseph", .musicArts),
            (6, "6 PM", "Bike club ride", "klinefelter-park-trail", "Klinefelter Park", .outdoors),
            (9, "7:30 PM", "Fall choir concert", "saint-bens", "Saint Ben's", .musicArts),
            (10, "8 AM", "Fall market", "farmers-market", "Centennial Park", .food),
            (15, "5 PM", "Trail cleanup", "boardwalk-loop-trail", "Boardwalk Loop Trail", .service),
        ]
        return rows.enumerated().compactMap { index, row in
            guard let date = day(row.0) else { return nil }
            let photo = row.3.flatMap { Bundle.main.url(forResource: $0, withExtension: "jpg") }
            return UpcomingEvent(id: "you-sample-\(index)", title: row.2, eventDate: Town.day(date),
                                 startTime: row.1, location: row.4, goingCount: 3, createdAt: "",
                                 imageUrl: photo?.absoluteString, rsvpd: true, category: row.5,
                                 cancelled: index == 2 && cancelledSample)
        }
    }
    #endif
}
