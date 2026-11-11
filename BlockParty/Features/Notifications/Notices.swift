//
//  Notices.swift
//  Block Party — what the Town bar's bell holds (BP app docs/plans/school-activities, ticket 04):
//  an Event you follow (an activity starred, or its whole school) or are Going to that was
//  canceled, or moved more than 15 minutes or to another place, and one you hearted that was
//  canceled (BP app inside-cards 16; a heart never hears of a move) (`get_my_changes`). Nothing pops
//  up (Jesse, 2026-10-26: "dont pop up on screen unless pressed just move to notifications"): the
//  bell gets a dot, as the Friends tab does for a request, and its page lists them. The free Apple team can't send a
//  push; that is ticket 06. Grew out of ticket 12's alert for a called-off Event (watch-every-place).
//

import SwiftUI

/// One change on the page.
nonisolated struct Notice: Identifiable, Hashable {
    /// The Event as it stands now.
    let event: UpcomingEvent
    let changedAt: Date
    /// Where it stood before it moved; nil when it was canceled.
    let movedFrom: Was?
    /// What you follow that it is of ("Kennedy Volleyball"), and that school's logo; nil when
    /// you're only Going.
    let followed: String?
    let followedLogo: URL?

    nonisolated struct Was: Decodable, Hashable {
        let eventDate: String?
        let startTime: String?
        let location: String?
    }

    /// A cancel is keyed by its Event, as ticket 12 told it, so an Event already told there is
    /// seen; a move by its Event and when, so a second move is news again.
    var id: String { movedFrom == nil ? event.id : "\(event.id)@\(Int(changedAt.timeIntervalSince1970))" }

    var cancelled: Bool { movedFrom == nil }

    /// In bold at the front: what you follow, else the Event's own name.
    var name: String { followed ?? event.title }

    /// After the name: "Tonight's game vs Sartell moved to 7 PM." for what you follow (Jesse's
    /// words, 2026-10-26), "moved to Sat, Oct 31 · 7 PM." or "is canceled." after an Event's name.
    @MainActor func words(now: Date) -> String {
        let what = cancelled ? "is canceled." : "moved to \(movedTo(now: now))."
        guard followed != nil else { return what }
        return "\(subject(now: now)) \(what)"
    }

    /// "Tonight's game vs Sartell", "Thursday's Fall Concert", "The Nov 7 game vs Tech": the day it
    /// stood on before it moved.
    @MainActor private func subject(now: Date) -> String {
        let card = FeedCardItem(event)
        let thing: String
        if let teams = event.game?.teams, let name = followed,
           let other = teams.first(where: { !name.hasPrefix($0.short) }) {
            thing = "game vs \(other.short)"
        } else {
            thing = card.title
        }
        guard let when = EventWhen(date: movedFrom?.eventDate ?? event.eventDate,
                                   time: movedFrom?.startTime ?? event.startTime, endAt: nil) else { return thing }
        if let word = when.dayWord(now) { return "\(word)'s \(thing)" }
        if (0..<7).contains(Town.days(from: now, to: when.start)) {
            return "\(Town.format(when.start, "EEEE"))'s \(thing)"
        }
        return "The \(Town.format(when.start, "MMMd")) \(thing)"
    }

    /// What it moved to: its new time alone on the same day, its new day and time, its new place,
    /// or both ("7 PM at Sartell High School").
    @MainActor private func movedTo(now: Date) -> String {
        let was = movedFrom
        let newDay = was?.eventDate != event.eventDate
        let oldMinutes = EventWhen.minutes(was?.startTime), newMinutes = EventWhen.minutes(event.startTime)
        let newTime = oldMinutes != nil && newMinutes != nil && oldMinutes != newMinutes
        let place = Self.nonempty(event.location)
        let newPlace = place != nil && Self.nonempty(was?.location) != nil && place != Self.nonempty(was?.location)
        var when: String?
        if newDay {
            when = FeedWhenLine(eventDate: event.eventDate, startTime: event.startTime, now: now)?.text
        } else if newTime, let newMinutes {
            when = Town.clock(minutes: newMinutes)
        }
        switch (when, newPlace ? place : nil) {
        case let (when?, place?): return "\(when) at \(place)"
        case let (when?, nil): return when
        case let (nil, place?): return place
        case (nil, nil): return FeedWhenLine(eventDate: event.eventDate, startTime: event.startTime, now: now)?.text ?? ""
        }
    }

    /// The round picture: the school's logo, else the Event's own picture.
    @MainActor var picture: URL? {
        if let followedLogo { return followedLogo }
        switch FeedCardItem(event).image {
        case .eventPhoto(let url), .placePhoto(let url, _, _): return url
        case .placeLogo(let picture): return picture.url
        case .fallback: return nil
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A post that names you with `@` or tags you (BP app town-feed 60): "**Marlene Ostendorf** mentioned you in a post."
/// It opens the post. Read from the server on every visit, so a post deleted since is gone from the bell too.
nonisolated struct NamedNotice: Identifiable, Hashable {
    let post: TownPost
    /// Tagged with Tag friends, not named with `@`.
    let tagged: Bool

    var id: String { "named:\(post.id)" }

    /// Instagram's words.
    var words: String { tagged ? "tagged you in a post." : "mentioned you in a post." }
}

/// One row on the bell's page: an Event that changed, a post that names you, or something the hello pill said
/// (hello-drop 05).
enum BellRow: Identifiable {
    case change(Notice)
    case named(NamedNotice)
    case item(HelloItem)

    var id: String {
        switch self {
        case .change(let notice): "change:\(notice.id)"
        case .named(let named): named.id
        case .item(let item): item.id
        }
    }

    var at: Date {
        switch self {
        case .change(let notice): notice.changedAt
        case .named(let named): named.post.posted
        case .item(let item): item.at
        }
    }

    /// All of them, newest first.
    static func merged(_ changes: [Notice], _ items: [HelloItem], named: [NamedNotice] = []) -> [BellRow] {
        (changes.map(BellRow.change) + named.map(BellRow.named) + items.map(BellRow.item)).sorted { $0.at > $1.at }
    }
}

@Observable
final class Notices {
    /// What the page lists, newest change first; nil until the first read answers.
    private(set) var list: [Notice]?
    /// The posts that name or tag you, newest first (town-feed 60); empty until their read answers.
    private(set) var named: [NamedNotice] = []
    /// The last read failed with nothing read before it: the page says so.
    private(set) var failed = false
    /// Seen on this phone, by `Notice.id`.
    private var seen: Set<String>

    private let read: () async throws -> [Notice]
    private let readNamed: () async throws -> [NamedNotice]
    private let keep: UserDefaults
    /// Ticket 12's told Events, so one already told there is seen here.
    static let seenKey = "bp.cancelled.told"

    init(read: @escaping () async throws -> [Notice], named: @escaping () async throws -> [NamedNotice] = { [] },
         keep: UserDefaults = .standard) {
        self.read = read
        self.readNamed = named
        self.keep = keep
        seen = Set(keep.stringArray(forKey: Self.seenKey) ?? [])
    }

    /// Your changes from `get_my_changes` through `supabase`, the session's one client
    /// (`AppSession`), or under DEBUG `-notice-samples` the samples.
    convenience init(supabase: Supabase, keep: UserDefaults = .standard) {
        #if DEBUG
        if LaunchFlags.has(.noticeSamples) {
            self.init(read: { Notices.samples(now: Date()) }, named: { Notices.namedSamples(now: Date()) },
                      keep: UserDefaults(suiteName: "NoticeSamples") ?? .standard)
            return
        }
        #endif
        self.init(read: { try await CommunityAPI(supabase).getMyChanges() },
                  named: { try await CommunityAPI(supabase).getMyMentions() }, keep: keep)
    }

    /// The bell's dot: something on the page you haven't opened it to.
    var dot: Bool {
        (list?.contains { !seen.contains($0.id) } ?? false) || named.contains { !seen.contains($0.id) }
    }

    /// Reads again, changes and names together. A failed read keeps what it had and waits for the next.
    func refresh(now: Date = Date()) async {
        async let changes = try? read()
        async let names = try? readNamed()
        let (fresh, freshNames) = await (changes, names)
        // Animated, so the bell's dot grows in rather than pops.
        withAnimation(.snappy) {
            if let freshNames { named = freshNames }
            if let fresh { list = Self.showing(fresh, now: now) }
        }
        failed = fresh == nil && list == nil
    }

    /// The page drew them: the dot goes.
    func opened() {
        guard list != nil || !named.isEmpty else { return }
        seen.formUnion((list ?? []).map(\.id) + named.map(\.id))
        keep.set(Array(seen).sorted(), forKey: Self.seenKey)
    }

    /// Signed out or another account: nothing until its own read.
    func reset() {
        list = nil
        named = []
        failed = false
    }

    /// The ones not over by `now`, in the read's order.
    static func showing(_ notices: [Notice], now: Date) -> [Notice] {
        notices.filter { YouCalendar.event(from: $0.event).map { $0.ends > now } ?? true }
    }

    /// Instagram's sections: Today, Yesterday, Last 7 days, then Earlier (an Event you're Going
    /// to, canceled weeks ago), by when it changed or was found.
    static func sections(_ rows: [BellRow], now: Date) -> [(title: String, rows: [BellRow])] {
        let titles = ["Today", "Yesterday", "Last 7 days", "Earlier"]
        let grouped = Dictionary(grouping: rows) { row -> Int in
            switch Town.days(from: row.at, to: now) {
            case ...0: 0
            case 1: 1
            case 2..<7: 2
            default: 3
            }
        }
        return grouped.keys.sorted().map { (titles[$0], grouped[$0] ?? []) }
    }

    #if DEBUG
    /// INVENTED: Marlene's sample post naming you with `@`, 5 minutes old (town-feed 60's mock).
    static func namedSamples(now: Date) -> [NamedNotice] {
        guard case .post(let post)? = TownFixtures.postSamples(now: now, posted: 5 * 60).first?.item else { return [] }
        return [NamedNotice(post: post, tagged: false)]
    }

    /// INVENTED: the mock's changes (BP app references/moved-alert), with Kennedy's and Apollo's real
    /// logos from Block Party's Storage and a bundled photo. Every game, time and word is made up.
    static func samples(now: Date) -> [Notice] {
        let day = Town.gregorian.startOfDay(for: now)
        func date(_ days: Int) -> String {
            Town.day(Town.gregorian.date(byAdding: .day, value: days, to: day) ?? day)
        }
        let logos = "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/"
        let kennedy = URL(string: logos + "kennedy-community-school/logo-14e0e9e7e8.webp")
        let apollo = URL(string: logos + "apollo-high-school/logo-c0d84cbf01.webp")
        func game(_ sport: String, _ teams: [String]) -> Game? {
            let list = teams.map { #"{"name":"\#($0)","short":"\#($0)"}"# }.joined(separator: ",")
            return try? JSONDecoder().decode(Game.self, from: Data(#"{"sport":"\#(sport)","teams":[\#(list)]}"#.utf8))
        }
        func event(_ id: String, _ title: String, _ days: Int, _ time: String, _ place: String,
                   game: Game? = nil, photo: String? = nil) -> UpcomingEvent {
            var event = UpcomingEvent(id: id, title: title, eventDate: date(days), startTime: time, location: place,
                                      goingCount: 0, createdAt: "")
            event.game = game
            event.imageUrl = photo.flatMap { Bundle.main.url(forResource: $0, withExtension: "jpg")?.absoluteString }
            return event
        }
        let hour: TimeInterval = 3600
        return [
            Notice(event: event("n1", "Kennedy Volleyball vs Sartell", 0, "7 PM", "Kennedy Community School",
                                game: game("Volleyball", ["Kennedy", "Sartell"])),
                   changedAt: now - 2 * hour,
                   movedFrom: .init(eventDate: date(0), startTime: "6 PM", location: "Kennedy Community School"),
                   followed: "Kennedy Volleyball", followedLogo: kennedy),
            Notice(event: event("n2", "Fall Concert", 1, "7 PM", "Apollo High School"),
                   changedAt: now - 5 * hour, movedFrom: nil, followed: "Apollo Choir", followedLogo: apollo),
            Notice(event: event("n3", "Music in Millstream Park", 5, "7 PM", "Millstream Park",
                                photo: "millstream-arts-festival"),
                   changedAt: now - 26 * hour,
                   movedFrom: .init(eventDate: date(4), startTime: "6 PM", location: "Millstream Park"),
                   followed: nil, followedLogo: nil),
            Notice(event: event("n4", "Kennedy Volleyball vs Sartell", 3, "7 PM", "Sartell High School",
                                game: game("Volleyball", ["Kennedy", "Sartell"])),
                   changedAt: now - 96 * hour,
                   movedFrom: .init(eventDate: date(3), startTime: "7 PM", location: "Kennedy Community School"),
                   followed: "Kennedy Volleyball", followedLogo: kennedy),
        ]
    }
    #endif
}
