//
//  DailyEventOfTheDay.swift
//  Block Party — Daily's first section under the week: the event Daily puts forward for you
//  today as the Town tab's poster, and on a busy day up to three, morning, afternoon and
//  evening, side by side (`docs/plans/daily-tab/SPEC.md` §2 and ticket 18 in the BP app folder).
//

import SwiftUI

/// One event on the Daily page, with its times. The event page it opens is the Town feed's
/// own (`FeedCardItem`).
struct DailyEvent: Identifiable {
    var item: FeedCardItem
    var starts: Date
    var ends: Date
    /// False when its start couldn't be read ("after dark") or it runs all day: it
    /// starts at midnight then, and its card shows the organizer's own words.
    var timed = true

    var id: String { item.id }

    var photo: URL? {
        if case .eventPhoto(let url) = item.image { return url }
        return nil
    }

    /// The card's time: "Now" while it's on, else when it starts ("9 AM", "7:30 PM"), in
    /// the Town's time. An untimed Event shows the organizer's own words, or "All day".
    /// Working words; Jesse writes the final ones.
    func startTime(now: Date) -> String {
        guard timed else { return item.startTime ?? "All day" }
        return isOn(now) ? "Now" : Self.clock(starts)
    }

    /// Started and not yet over.
    func isOn(_ now: Date) -> Bool {
        timed && starts <= now && now < ends
    }

    /// "9 AM" or "7:30 PM" in the Town's time: minutes only when there are some.
    static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        return townTime(calendar.component(.minute, from: date) == 0 ? "h" : "hmm", date)
    }

    /// `date` written from a date template ("EEE", "d", "h"), in English, in the Town's time.
    static func townTime(_ template: String, _ date: Date) -> String {
        if let formatter = townFormatters[template] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        townFormatters[template] = formatter
        return formatter.string(from: date)
    }

    /// One formatter per template, kept: the You tab's Calendar writes 49 dates each time
    /// it draws, and building a formatter is the slow part.
    private static var townFormatters: [String: DateFormatter] = [:]

    /// What a section shows: the ones on now or still to come, soonest first, leaving out
    /// any a section above it already shows, `limit` at most. When one ends the next
    /// takes its spot; with none left the section goes.
    static func showing(_ events: [DailyEvent], now: Date, without shown: [DailyEvent] = [],
                        limit: Int) -> [DailyEvent] {
        let shownIDs = Set(shown.map(\.id))
        return Array(events.filter { $0.ends > now && !shownIDs.contains($0.id) }
            .sorted { $0.starts < $1.starts }.prefix(limit))
    }

    /// How soon it starts, as Airbnb's "In 3 months" pill says it: the You tab's next plan
    /// (you-tab 11).
    /// Working words; Jesse writes the final ones.
    func startsLabel(now: Date) -> String {
        guard starts > now else { return "Now" }
        // Another Town day counts calendar days, as people do ("In 3 days" on a Wednesday for
        // Saturday's), not hours (daily-tab 16).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: starts)).day ?? 0
        if days == 1 { return "Tomorrow" }
        if days > 1 { return "In \(days) days" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        let text = formatter.localizedString(for: starts, relativeTo: now)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Another day's when, as Daily's poster says it in yellow: the day short, since the week
    /// above already names the date, "Sat · 4 PM", or "Saturday" with no clock (Jesse at
    /// daily-tab 18's Check-in 1). nil for today's, which keeps the Town feed's "Today · 4 PM".
    func dayLine(now: Date) -> String? {
        guard Town.day(starts) > Town.day(now) else { return nil }
        return timed ? "\(Self.townTime("EEE", starts)) · \(Self.clock(starts))" : Self.townTime("EEEE", starts)
    }

    #if DEBUG
    /// INVENTED: three events today, morning, afternoon and evening, at real St. Joseph
    /// places with the bundled town photos. The titles and hosts are the Town feed's
    /// fixtures (`DailyFixtures`); the times are made up.
    static func samples(on date: Date) -> [DailyEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        return [
            sample(id: "daily-e1", title: "Farmers Market", host: "Resurrection Lutheran",
                   photo: "farmers-market", place: "Resurrection Lutheran",
                   starts: at(8), ends: at(12), category: .food, what: "Market",
                   description: "Produce, eggs, honey and bread in the church parking lot."),
            sample(id: "daily-e2", title: "Abbey organ recital", host: "Saint John's Abbey",
                   photo: "saint-johns-abbey", place: "Saint John's Abbey",
                   starts: at(16), ends: at(17), category: .musicArts, what: "Organ concert",
                   description: "An hour of Bach and a few newer pieces on the Abbey church organ. Open to everyone."),
            sample(id: "daily-e3", title: "Music in Millstream Park", host: "St. Joseph Parks & Rec",
                   photo: "memorial-park", place: "Millstream Park",
                   starts: at(19), ends: at(21), category: .musicArts, what: "Concert",
                   description: "Bring a blanket or a lawn chair and find a spot on the grass by the river. A local bluegrass trio plays two sets."),
        ]
    }

    static func sample(id: String, title: String, host: String, photo: String,
                               place: String, starts: Date, ends: Date,
                               category: EventCategory, what: String? = nil, description: String) -> DailyEvent {
        let url = Bundle.main.url(forResource: photo, withExtension: "jpg")
        // The event page's when line reads these, so it shows the day and the time.
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = Town.timeZone
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US")
        time.timeZone = Town.timeZone
        time.dateFormat = "h:mm a"
        var item = FeedCardItem(
            id: id, title: title, dateChip: "TODAY", metaLine: place,
            image: url.map { .eventPhoto($0) } ?? .fallback, recurrence: nil,
            hostName: host, goingCount: 0, goingAvatars: [],
            likeCount: 0, isLiked: false, isSaved: false, isJoined: false,
            eventDate: day.string(from: starts), startTime: time.string(from: starts),
            location: place, description: description, category: category
        )
        item.what = what
        return DailyEvent(item: item, starts: starts, ends: ends)
    }
    #endif
}

extension DailyEvent {
    /// A row of `get_event_of_the_day` (the Town feed's own row) as Daily's poster: the Town
    /// card's item, from its start until it leaves the feed. Untimed or all day, it runs the
    /// whole day, as the You tab reads it.
    init?(row: TownFeedRow) {
        // A game whose final is in is over, though the Town feed keeps its card a day (game-card 02).
        guard row.event.game?.final == nil else { return nil }
        var item = TownFeed.entry(row).card
        if row.event.isAllDay { item.startTime = nil }
        guard var event = YouCalendar.event(from: item) else { return nil }
        event.ends = row.leavesAt
        self = event
    }
}

/// Daily's Event of the day, and the Town feed's top (event-card 03): the read's picks, kept
/// across tab switches and failed reads, as the You tab keeps its Going, and on disk, so a
/// relaunch shows today's at once. The database works them out (`get_event_of_the_day`, BP app
/// daily-tab 14) from the morning's standouts. Each read works out the whole Town feed on the
/// server, so it reads again only after `rereadAfter`, on a new Town day, or once a pick is
/// over, when the next one may take its spot.
@MainActor @Observable
final class EventOfTheDay {
    /// nil until the first read lands; Daily shows paper until then.
    private(set) var events: [DailyEvent]?
    @ObservationIgnored private var readAt: Date?
    /// Numbers each read, so one an account change overtook never lands.
    @ObservationIgnored private var latestRead = 0
    @ObservationIgnored private let read: () async throws -> [DailyEvent]
    /// The picks the last session left on disk, asked for once, at the first read.
    @ObservationIgnored private let kept: () -> [DailyEvent]?
    @ObservationIgnored private var keptChecked = false

    static let rereadAfter: TimeInterval = 10 * 60

    init(read: @escaping () async throws -> [DailyEvent], kept: @escaping () -> [DailyEvent]? = { nil }) {
        self.read = read
        self.kept = kept
    }

    /// The live read, or under DEBUG `-daily-samples` the three samples.
    convenience init() {
        #if DEBUG
        if DailySamples.on {
            self.init(read: { DailyEvent.samples(on: DailyClock.now(Date())) })
            return
        }
        #endif
        self.init(read: {
            try await CommunityAPI(auth: AuthStore.shared).getEventOfTheDay().compactMap(DailyEvent.init(row:))
        }, kept: {
            guard let data = TownFeedCache.load(.eventOfTheDay),
                  let rows = try? CommunityAPI.townFeedRows(from: data) else { return nil }
            return rows.compactMap(DailyEvent.init(row:))
        })
    }

    func refresh(now: Date = Date()) async {
        // Today's kept picks show while the first read is out. Picks are the Town day's own
        // events, so one that started another day is yesterday's, even if it's still on.
        if events == nil, !keptChecked {
            keptChecked = true
            let today = Town.day(now)
            if let kept = kept()?.filter({ $0.ends > now && Town.day($0.starts) == today }), !kept.isEmpty {
                events = kept
            }
        }
        guard needsRead(now: now) else { return }
        latestRead += 1
        let mine = latestRead
        do {
            let picks = try await read()
            guard mine == latestRead else { return }
            events = picks
            readAt = now
        } catch {
            // A failed read keeps the last picks and tries again next time; with none yet, Daily
            // shows its placeholder rather than blank paper.
            guard mine == latestRead, events == nil else { return }
            events = []
        }
    }

    func needsRead(now: Date) -> Bool {
        guard let readAt, let events else { return true }
        // (A failed first read leaves `events` empty and `readAt` nil: read again.)
        return now.timeIntervalSince(readAt) >= Self.rereadAfter || Town.day(readAt) != Town.day(now)
            || events.contains { $0.ends <= now }
    }

    /// A new account gets its own picks: read again at once, keeping these on screen until they
    /// land, as the Town feed keeps its list, so the poster on top of it doesn't blink out while a
    /// saved sign-in comes back at launch (event-card 03).
    func accountChanged() {
        latestRead += 1
        readAt = nil
    }
}

/// The section: the Town tab's poster (`EventOfTheDayPoster`), or on a busy day the posters in
/// a row the finger pages through, one at a time, with the next one's edge showing. No label
/// over it: the poster's own chip says it (Jesse at daily-tab 18's Check-in 1).
struct EventOfTheDaySection: View {
    let events: [DailyEvent]
    let now: Date

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DailyMetric.eventGap) {
                ForEach(events) { event in
                    EventOfTheDayPoster(event: event, now: now)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        // Town's sides, so the poster is Town's 370 on a 402 pt phone, as on the draft Jesse
        // picked (picked: Daily's other sections sit at `DailyMetric.side`).
        .contentMargins(.horizontal, DailyFeedMetric.contentInset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollDisabled(events.count < 2)
    }
}
