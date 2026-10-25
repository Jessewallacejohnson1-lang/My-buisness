//
//  Models.swift
//  Block Party — data models, ported 1:1 from packages/core/src/types.ts.
//
//  Decoding uses .convertFromSnakeCase, so Swift camelCase ↔ DB snake_case
//  (event_date ↔ eventDate, image_url ↔ imageUrl, …).
//

import Foundation

enum ClubStatus: String, Codable { case pending, approved, rejected }
enum PostKind: String, Codable { case event, trail }

// MARK: - Public view models (some fields derived client-side)

struct ClubRow: Codable, Identifiable, Hashable {
    let id: String
    let submittedBy: String?
    let status: ClubStatus
    let name: String
    let host: String?
    let schedule: String?
    let location: String?
    let vibe: String?
    let description: String?
    let expectations: String?
    let createdAt: String
}

/// One group as `get_groups` sends it (supabase/migrations/*_groups.sql, BP app
/// docs/plans/rsvp-and-groups ticket 05): what the Search tab's Groups shelf and a Group page
/// show. Its pictures are worked out on the server: its own photos, else its meeting place's,
/// and a logo for when there is none. A photo or meeting that doesn't decode is left out; it
/// never costs the group.
nonisolated struct TownGroup: Decodable, Hashable, Identifiable, Sendable {
    /// A get-together `get_groups` worked out from the group's meeting rules.
    struct Meeting: Decodable, Hashable, Sendable {
        let what: String
        /// The town day, "2026-10-20".
        let day: String
        /// "18:00"; nil when the group doesn't say.
        var time: String? = nil
        /// Only when it isn't the group's usual place.
        var place: String? = nil

        private enum CodingKeys: String, CodingKey { case what, day, time, place = "where" }
    }

    let id: String
    let name: String
    var kind: String? = nil
    var schedule: String? = nil
    var location: String? = nil
    var about: String? = nil
    var pageUrl: String? = nil
    var photos: [PlacePicture] = []
    var logo: PlacePicture? = nil
    var meetings: [Meeting] = []
    var memberCount = 0
    var joined = false

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, schedule, location, about, pageUrl, photos, logo, meetings, memberCount, joined
    }

    init(id: String, name: String, kind: String? = nil, photos: [PlacePicture] = [], logo: PlacePicture? = nil,
         meetings: [Meeting] = [], memberCount: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.photos = photos
        self.logo = logo
        self.meetings = meetings
        self.memberCount = memberCount
    }

    init(from decoder: Decoder) throws {
        struct Lenient<T: Decodable>: Decodable {
            let value: T?
            init(from decoder: Decoder) { value = try? T(from: decoder) }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        schedule = try? c.decodeIfPresent(String.self, forKey: .schedule)
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        about = try? c.decodeIfPresent(String.self, forKey: .about)
        pageUrl = try? c.decodeIfPresent(String.self, forKey: .pageUrl)
        photos = ((try? c.decodeIfPresent([Lenient<PlacePicture>].self, forKey: .photos)) ?? [])
            .compactMap(\.value).filter { $0.kind == .photo }
        logo = (try? c.decodeIfPresent(Lenient<PlacePicture>.self, forKey: .logo))?.value
        meetings = ((try? c.decodeIfPresent([Lenient<Meeting>].self, forKey: .meetings)) ?? []).compactMap(\.value)
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        joined = (try? c.decodeIfPresent(Bool.self, forKey: .joined)) ?? false
    }
}

/// A timeline row: a club event, for the map's Today list and search.
struct TimelineEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startTime: String?
    let location: String?
    let clubName: String?
    let fromJoinedClub: Bool
    /// The organizer's blurb (club_events.description) — surfaced when a calendar
    /// day row is tapped. Defaulted so the two existing constructors need not change.
    var details: String? = nil
    /// The event's category → its calendar icon (tint + glyph). Defaults to `.other`
    /// so existing constructors compile unchanged and null/legacy rows read cleanly.
    var category: EventCategory = .other
    /// The event's own photo (club_events.image_url) and its place's registry entry
    /// (club_events.place_entry_id), which the map's bubbles read for a picture.
    var imageURL: URL? = nil
    var placeEntryId: String? = nil
}

/// nonisolated: a plain value carried by `DayItem`, which the pure `nonisolated`
/// Your Day rules build and compare. Without this its synthesized Hashable is
/// MainActor-isolated and every nonisolated comparison trips the 0-warning bar.
nonisolated struct UpcomingEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let eventDate: String
    let startTime: String?
    let location: String?
    var goingCount: Int
    let createdAt: String
    /// The organizer's own uploaded photo (club_events.image_url) — the truest
    /// "photo of this event". Threaded through from RawEvent; nil when none.
    var imageUrl: String? = nil
    /// The viewer's RSVP state. Defaulted so activities and profile callers that
    /// only need the event summary remain source-compatible.
    var rsvpd: Bool = false
    /// The viewer's save. Only Profile's Saved read (`get_my_saves`) sets it.
    var saved: Bool = false
    /// The organizing club, when this event belongs to one.
    var clubName: String? = nil
    /// The event category, with legacy/null rows falling back to the neutral icon.
    var category: EventCategory = .other
    /// When the event ends, parsed from `club_events.end_at`. Nil is the norm
    /// until that column ships — and it stays legitimate afterwards, because the
    /// column is nullable. Consumers must degrade to the start instant, never
    /// invent an end.
    var endAt: Date? = nil
    /// `club_events.all_day`. Defaults false, which is also what every row reads
    /// before the column exists.
    var isAllDay: Bool = false
    /// Who announced a found event (ADR-021), shown where a club's name would be.
    var sourceName: String? = nil
    /// Called off: its source's schedule dropped it (`club_events.cancelled_at`, BP app
    /// docs/plans/watch-every-place, ticket 12). Rows from before the reads said so are on.
    var cancelled: Bool = false
    /// The picture of where it happens, from the photos Block Party keeps itself
    /// (`public.place_picture`): nil for an event at no known place, and on rows read
    /// before the feeds sent it.
    var placePicture: PlacePicture? = nil
    /// Who puts it on, as a picture beside its name on the Town card: the logo of the place it was
    /// found on, else its photo (`private.host_picture`). nil for an unknown host, and on rows read
    /// before the feed sent it.
    var hostPicture: PlacePicture? = nil
    /// The organizer's own words (`club_events.description`), the Event page's About: nil for
    /// an event without them (a game), and on rows read before the feeds sent them.
    var description: String? = nil
    /// A game between two teams (BP app docs/plans/game-card, ticket 01): its Town card shows
    /// the teams instead of a photo. nil for any other event, and on rows read before the feed
    /// sent it.
    var game: Game? = nil
    /// What it is in one to three words, the morning tagger's ("Lecture"; BP app event-card 05).
    /// nil until it's tagged, and on rows read before the feed sent it.
    var what: String? = nil
    /// Up to three of the caller's friends Going, newest Going first: only the You tab's read
    /// sends them (`get_my_going`, BP app docs/plans/you-tab, ticket 07). The Town feed's ride
    /// `TownFeedRow`.
    var friendsGoing: [FeedFriend] = []
}

/// A game between two teams, as `get_town_feed` sends it (`private.event_game`): the sport
/// ("Girls Soccer"), its special night ("Homecoming") and both schools, the host's first, its live
/// score while it's on, and its final once it's in.
nonisolated struct Game: Decodable, Hashable, Sendable {
    let sport: String
    let occasion: String?
    let teams: [Team]
    /// The final score in `teams` order (BP app docs/plans/game-card, ticket 02); nil before it's in,
    /// and for one that doesn't read, so the card stays VS. A live score that says complete counts
    /// as the final at once, before the server's second read makes it one (ticket 03).
    private(set) var final: [Int]?
    /// The score while it's being played (ticket 03); nil before, after, and for a high school game.
    private(set) var live: Live?

    /// SIDEARM's score as `club_events.live_score` keeps it (`private.sidearm_live`): `teams` order,
    /// the period as the sport says it ("Q3", "2nd half", "Set 3"), and the clock ("4:12", "67'").
    nonisolated struct Live: Decodable, Hashable, Sendable {
        let score: [Int]
        let period: String
        let clock: String?
        let complete: Bool
        /// When the server last wrote it: a clock older than `staleAfter` is hidden, not frozen.
        let at: Date?

        static let staleAfter: TimeInterval = 120

        /// "Q3 · 4:12", or just the period once the clock is stale or the sport has none.
        func line(at now: Date) -> String {
            guard let clock, let at, now.timeIntervalSince(at) < Self.staleAfter else { return period }
            return "\(period) · \(clock)"
        }

        private enum CodingKeys: String, CodingKey { case score, period, clock, complete, at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            score = try c.decode([Int].self, forKey: .score)
            guard score.count == 2, score.allSatisfy({ $0 >= 0 }) else {
                throw DecodingError.dataCorruptedError(forKey: .score, in: c, debugDescription: "two scores")
            }
            period = try c.decode(String.self, forKey: .period)
            clock = (try? c.decodeIfPresent(String.self, forKey: .clock)) ?? nil
            complete = ((try? c.decodeIfPresent(Bool.self, forKey: .complete)) ?? nil) ?? false
            at = ((try? c.decodeIfPresent(String.self, forKey: .at)) ?? nil).flatMap(Self.parse)
        }

        /// Postgres's timestamptz in JSON: "2026-10-24T18:21:32.123456+00:00".
        private static func parse(_ text: String) -> Date? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: text) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: text)
        }
    }

    private enum CodingKeys: String, CodingKey { case sport, occasion, teams, final, live }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sport = try c.decode(String.self, forKey: .sport)
        occasion = try c.decodeIfPresent(String.self, forKey: .occasion)
        teams = try c.decode([Team].self, forKey: .teams)
        let final = (try? c.decodeIfPresent([Int].self, forKey: .final)) ?? nil
        setScores(final: final, live: (try? c.decodeIfPresent(Live.self, forKey: .live)) ?? nil)
    }

    /// The same game with a realtime update's scores (`club_events.final_score`, `live_score`).
    func with(final: [Int]?, live: Live?) -> Game {
        var game = self
        game.setScores(final: final, live: live)
        return game
    }

    private mutating func setScores(final: [Int]?, live: Live?) {
        let final = final.flatMap { $0.count == 2 && $0.allSatisfy { $0 >= 0 } ? $0 : nil }
        self.final = final ?? (live?.complete == true ? live?.score : nil)
        self.live = self.final == nil ? live : nil
    }

    /// The side with more, 0 or 1; nil before the final and on a tie, which fades neither side.
    var winner: Int? {
        guard let final, final[0] != final[1] else { return nil }
        return final[0] > final[1] ? 0 : 1
    }

    nonisolated struct Team: Decodable, Hashable, Sendable {
        let name: String
        /// As neighbours say it ("Gustavus", not "Gustavus Adolphus").
        let short: String
        /// The school's logo in Block Party's Storage; nil until one is found (BP app
        /// docs/plans/game-card): the card shows the first letter.
        let logo: URL?
        /// The school's color as 0xRRGGBB; nil until it's known, or misread.
        let rgb: UInt32?
        /// The team's uuid, what a follow keys it by (hello-drop 03); nil for an old read.
        var id: String? = nil
        /// A team around St. Joseph: only these have a page and a Follow.
        var local = false
        /// Up to three colours read from its logo, most used first.
        var colors: [UInt32] = []
        /// What neighbours call it ("Johnnies"); nil when it has none.
        var nickname: String? = nil

        /// The name the pill says: its nickname, else its short name.
        var called: String { nickname ?? short }

        private enum CodingKeys: String, CodingKey { case name, short, logo, color, id, local, colors, nickname }

        /// A logo or color that doesn't read is none: it never costs the card.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            short = (try? c.decodeIfPresent(String.self, forKey: .short)) ?? name
            logo = (try? c.decodeIfPresent(String.self, forKey: .logo)).flatMap(URL.init(string:))
            rgb = (try? c.decodeIfPresent(String.self, forKey: .color)).flatMap(Self.rgb(hex:))
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
            local = ((try? c.decodeIfPresent(Bool.self, forKey: .local)) ?? nil) ?? false
            colors = (((try? c.decodeIfPresent([String].self, forKey: .colors)) ?? nil) ?? []).compactMap(Self.rgb(hex:))
            nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? nil
        }

        /// The page and the Follow: a local team the server named.
        var hasPage: Bool { local && id != nil }

        /// "#C20430" as 0xC20430; nil for anything else.
        static func rgb(hex: String) -> UInt32? {
            guard hex.count == 7, hex.first == "#" else { return nil }
            return UInt32(hex.dropFirst(), radix: 16)
        }

        /// What the disc shows until the logo lands, or instead of one: the first letter.
        var initial: String { short.first(where: \.isLetter).map { String($0).uppercased() } ?? "" }
    }

    /// The card's title as VoiceOver says it, naming the teams the discs show: "Football,
    /// Saint John's versus Gustavus", and once it's over "Football, Saint John's 33, Concordia 23, final".
    /// While it's on: "Football, Saint John's 14, Concordia 7, Q3, live".
    var spoken: String {
        guard teams.count == 2 else { return sport }
        if let final { return "\(sport), \(teams[0].short) \(final[0]), \(teams[1].short) \(final[1]), final" }
        if let live {
            return "\(sport), \(teams[0].short) \(live.score[0]), \(teams[1].short) \(live.score[1]), \(live.period), live"
        }
        return "\(sport), \(teams.map(\.short).joined(separator: " versus "))"
    }

    /// Only a game with exactly two teams: anything else is no game, and the card stays a
    /// photo card.
    struct Lenient: Decodable, Hashable {
        let value: Game?
        init(from decoder: Decoder) {
            let game = try? Game(from: decoder)
            value = game?.teams.count == 2 ? game : nil
        }
    }
}

/// Where an event happens, as a picture (`public.place_picture`, BP app
/// docs/plans/place-photos): the place's own photo, or its logo when we have no photo of
/// it. Saved once in Block Party's Storage, so showing it costs no lookup (Jesse,
/// 2026-10-16, MEMORY.md).
nonisolated struct PlacePicture: Decodable, Hashable, Sendable {
    enum Kind: String, Decodable, Sendable { case photo, logo }

    let url: URL
    let kind: Kind
    /// A freely licensed photo's author and licence ("Tomruen · CC BY-SA 4.0"); nil for a
    /// photo from the place's own website, which is credited to that site.
    var credit: String? = nil
    /// The page the photo came from.
    var site: URL? = nil
    /// A logo's backdrop hue, as Search's (`SearchLogo`); nil for a black, white or grey one.
    var hue: Double? = nil
    /// The photo's size in pixels, so a card takes its shape before it loads (BP app
    /// docs/plans/event-card, ticket 01); nil for a logo.
    var width: Int? = nil
    var height: Int? = nil
    /// The place's other live photos, after this cover, as they came (ticket 02): read
    /// through `more`, so one that doesn't decode never costs the cover.
    var others: [Lenient]? = nil

    private enum CodingKeys: String, CodingKey {
        case url, kind, credit, site, hue
        case width = "w", height = "h", others = "more"
    }

    /// The place's other photos, in order, for a card to swipe to and its Event page to show.
    var more: [PlacePicture] { others?.compactMap(\.value) ?? [] }

    /// Width over height; nil without a size.
    var aspect: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }

    /// What the photo's chip says: its author and licence, else the site's name without
    /// "www." or its ending ("krewemn", not "krewemn.com": Jesse, 2026-10-19, to keep the
    /// chip small). nil for a logo.
    var creditLine: String? {
        guard kind == .photo else { return nil }
        if let credit, !credit.isEmpty { return credit }
        guard let host = site?.host() else { return nil }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// One that doesn't decode is no picture: a bad row never costs the feed.
    struct Lenient: Decodable, Hashable {
        let value: PlacePicture?
        init(from decoder: Decoder) { value = try? PlacePicture(from: decoder) }
    }
}

/// A row on a business's page in Search (`places.links`, BP app docs/plans/place-photos): its
/// website or one of its social pages. Strings, so a link the app doesn't know never costs the
/// place list; `BusinessPage.rows` keeps the ones it can draw.
nonisolated struct PlaceLink: Decodable, Hashable, Sendable {
    /// website, facebook or instagram.
    let kind: String
    let url: String
}

/// One row of `get_town_feed` (`supabase/migrations/*_town_feed*.sql`): an event, how its
/// series repeats ("Every Tuesday"; nil for a one-off or no clear pattern), when it
/// leaves the Town feed, why it's there (the recipe's top reason and the one name it
/// needs), for the admin the points behind its place, its hearts (everyone's, and
/// whether you hearted it) and whether you saved it. Rows kept from before the recipe
/// have no reason, and from before hearts or saves, none of those.
nonisolated struct TownFeedRow: Hashable {
    let event: UpcomingEvent
    let recurrence: String?
    let leavesAt: Date
    var reason: String? = nil
    var reasonName: String? = nil
    var score: FeedScore? = nil
    var heartCount = 0
    var hearted = false
    var saved = false
    /// Up to three of the caller's friends Going, newest Going first (town-feed 28).
    var friendsGoing: [FeedFriend] = []
    /// The approved group putting it on, and whether the caller is in it (rsvp-and-groups 07).
    var groupID: String? = nil
    var inGroup = false
}

/// Town news in the Town feed (BP app town-feed 35): a place's special, deal or new thing, or town
/// news, in Block Party's words, with the post it came from to open. Its place's logo (else its
/// photo) is its avatar; with neither, the place's first letter.
nonisolated struct TownNews: Hashable, Identifiable, Sendable {
    let id: String
    let place: String
    /// Its one line of facts, else its title.
    let words: String
    let post: URL
    var picture: PlacePicture? = nil
    let leavesAt: Date
    /// When Block Party added it (the morning watch's read, not the post's own date); the hello pill
    /// says news added since your last open (hello-drop 03).
    var published: Date? = nil
}

/// One line of `get_town_feed`, in its order: an Event, or news under them (town-feed 35).
nonisolated enum TownFeedLine: Hashable {
    case event(TownFeedRow)
    case news(TownNews)
}

/// A friend Going to an Event, as the Town feed names them: first name, and their photo when
/// they have one in our bucket. Only friends who show their plans to friends (town-feed 28).
nonisolated struct FeedFriend: Hashable, Sendable {
    let name: String
    let photo: URL?
}

/// The points behind a card's place in the Town feed, as `get_town_feed` sends them to
/// the admin only: each lift in points, each multiplier, and the spot they add up to.
nonisolated struct FeedScore: Decodable, Hashable, Sendable {
    let interest: Double
    let friend: Double
    let follow: Double
    let popular: Double
    let size: Double
    /// 1 small, 2 medium, 3 big.
    let sizeStep: Int
    let daysAway: Double
    let soon: Double
    let acted: Double
    let spacing: Double
    let newSpot: Bool
    let total: Double
    /// Where the card sits; `TownFeed.cards` sets it to the card's place on screen, which
    /// a read that keeps the order on screen can leave different from the database's.
    var spot: Int
    var of: Int
    /// Newer terms, absent from a breakdown read before them: points for a host you've been
    /// into (town-feed 30), for how much it draws the town out (34), and the multiplier for an
    /// interest placed again (32).
    var tapped: Double? = nil
    var draw: Double? = nil
    var topicSpacing: Double? = nil
    /// Like something you said Not interested to: × 0.3 fading to × 1 over 90 days (ticket 21).
    var notInterested: Double? = nil
}

struct AgendaEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let eventDate: String
    let startTime: String?
    let location: String?
}

struct Trail: Identifiable, Hashable {
    let id: String
    let title: String
    let location: String?
    let length: String?
    let difficulty: String?
    let description: String?
    let imageUrl: String?
    let status: ClubStatus
    let createdAt: String
}

// MARK: - Social layer (follow / like / comment / feed) — Today tab remake.
// New tables (town_follows, event_likes, event_comments) live on the shared
// Supabase project; see docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §5.

/// What a follow points at: a club, a community member's town_profile, or a Place
/// (`public.places`, BP app docs/plans/follows ticket 02).
enum FollowTargetType: String, Codable { case club, profile, place, team }

struct FollowTarget: Hashable, Codable {
    let type: FollowTargetType
    let id: String
}

/// A local team's page (`team_page`, hello-drop 03).
struct TeamProfile: Decodable, Hashable {
    let id: String
    let name: String
    let short: String
    let logo: String?
    let colors: [String]?
    let games: [Game]

    struct Game: Decodable, Hashable, Identifiable {
        let id: String
        let sport: String?
        let date: String
        let time: String?
        let location: String?
        let other: String
    }
}

/// A final one of your followed teams played (`my_team_finals`). `mine` is its side in `game.teams`.
struct TeamFinal: Decodable, Hashable {
    let eventId: String
    let game: Game
    let mine: Int

    var team: Game.Team? { game.teams.indices.contains(mine) ? game.teams[mine] : nil }
    var other: Game.Team? { game.teams.indices.contains(1 - mine) ? game.teams[1 - mine] : nil }
    var won: Bool { game.winner == mine }

    /// "Johnnies beat Gusties 33–23", "Johnnies lost to Gusties 23–33", "Johnnies tied Gusties 7–7":
    /// your team's score first, each by its nickname when it has one.
    var text: String? {
        guard let final = game.final, let team, let other else { return nil }
        let score = "\(final[mine])–\(final[1 - mine])"
        guard let winner = game.winner else { return "\(team.called) tied \(other.called) \(score)" }
        return winner == mine ? "\(team.called) beat \(other.called) \(score)" : "\(team.called) lost to \(other.called) \(score)"
    }
}

#if DEBUG
extension TeamFinal {
    /// `-hello-final`: Saint John's 33–23 over Gustavus, or the other way round.
    static func sample(won: Bool) -> TeamFinal {
        let score = won ? "[33, 23]" : "[23, 33]"
        // Saint John's logo colours, as hex without the mark (colour literals stay in Hue).
        let red = "BC0E33", blue = "02A2E2"
        let json = """
        {"event_id": "debug", "mine": 0, "game": {"sport": "Football", "occasion": null, "final": \(score),
          "teams": [{"name": "Saint John's", "short": "Saint John's",
                     "logo": "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/saint-johns/logo-36d1a2aa13.png",
                     "color": "#\(red)", "local": true, "colors": ["#\(red)", "#\(blue)"], "nickname": "Johnnies"},
                    {"name": "Gustavus Adolphus", "short": "Gustavus", "logo": null, "color": null, "nickname": "Gusties"}]}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(TeamFinal.self, from: Data(json.utf8))
    }
}
#endif

/// What a page shows of a Place or person it can follow (`follow_card`): whether you follow it,
/// how many do (nil for a person, who never shows a count), and up to three of your friends who
/// follow it, with how many in all.
struct FollowCard: Decodable, Equatable {
    struct Friend: Decodable, Equatable {
        let name: String
        let avatarUrl: String?
    }

    let following: Bool
    let followers: Int?
    let friends: [Friend]
    let friendsCount: Int
}

/// A place's name over its photo (`public.place_names`, BP app follows 02): its own lettering, a white
/// picture tinted to read on the photo, or, where its letters couldn't be cut, its logo in its own colours.
struct PlaceName: Hashable, Sendable {
    let url: URL
    /// The logo, untinted, rather than lettering.
    let emblem: Bool
}

/// Something you follow, in Profile's Following list (`my_follows`), or an Event's host
/// (`event_host`): its name, a Place's Google type, and its picture, a photo or a logo.
struct FollowRow: Decodable, Identifiable, Hashable {
    let targetType: FollowTargetType
    let targetId: String
    let name: String
    let kind: String?
    let picture: String?
    let pictureKind: String?

    var id: String { targetId }
    var target: FollowTarget { FollowTarget(type: targetType, id: targetId) }
}

/// A flat comment ("note") on a posting (club_events row). No threading — see
/// spec §3 ("No threaded/nested comments").
struct EventComment: Identifiable {
    let id: String
    let body: String
    let createdAt: Date
    let authorId: String
    let authorName: String
    let authorAvatar: String?
}

/// Up to three public identities for an event's going facepile. Counts remain
/// authoritative on `FeedPosting`; this is only the lightweight display sample.
struct GoingPreview {
    let avatars: [URL]
}

/// One komoot-style feed card's worth of data — a posting (club_events row)
/// with its poster identity + real social counts + the viewer's own state.
/// `liked`/`following`/`rsvpd` say what the viewer has done. Only DEBUG previews
/// build these now (the legacy posting pipeline).
struct FeedPosting: Identifiable {
    let id: String
    let title: String
    let eventDate: String?
    let startTime: String?
    let location: String?
    let imageUrl: String?
    let createdAt: Date
    let posterName: String
    let posterAvatar: String?
    let posterTarget: FollowTarget
    var followerCount: Int
    var likeCount: Int
    var commentCount: Int
    var goingCount: Int
    var liked: Bool
    var following: Bool
    var rsvpd: Bool
}

// MARK: - Insert inputs

struct NewEventInput {
    var title: String
    var eventDate: String      // YYYY-MM-DD
    var startTime: String      // display string e.g. "7pm"
    var location: String
    var description: String?
    var imageUrl: String?
    var category: String = EventCategory.other.rawValue   // club_events.category text
}

struct NewTrailInput {
    var title: String
    var location: String
    var length: String?
    var difficulty: String?
    var description: String?
    var imageUrl: String?
}

struct ClubInput {
    var name: String
    var host: String?
    var schedule: String?
    var location: String?
    var vibe: String?
    var description: String?
    var expectations: String?
}

// MARK: - Raw decode shapes (PostgREST responses)

/// A raw club_events row (select=* or with clubs(name) embedded).
struct RawEvent: Decodable {
    let id: String
    let title: String
    let eventDate: String?
    let startTime: String?
    let location: String?
    let length: String?
    let difficulty: String?
    let description: String?
    let imageUrl: String?
    let kind: String?
    let status: ClubStatus?
    let clubId: String?
    let createdAt: String?
    /// club_events.category (nullable). Absent/legacy rows decode to nil → `.other`.
    let category: String?
    /// club_events.end_at (`timestamptz NULL`) and club_events.all_day
    /// (`boolean NOT NULL DEFAULT false`).
    ///
    /// BOTH ARE OPTIONAL ON PURPOSE. The migration that adds them is approved but
    /// **not yet applied**, so `select=*` does not return these keys today and a
    /// non-optional field here would fail every event decode in the app. Optional
    /// decoding makes the client correct on both sides of the migration: today
    /// every row reads `endAt == nil` / `allDay == nil`, and the moment the columns
    /// land the same code starts honouring them with no further change.
    ///
    /// `endAt` stays a raw string like every other timestamp on this shape
    /// (`createdAt`); `DateHelpers.timestamp(_:)` parses it at the API boundary.
    let endAt: String?
    let allDay: Bool?
    /// Who announced a found event and where it was read (`club_events.source_name`,
    /// `source_url`; ADR-021). Nil for events a club or neighbour posted.
    let sourceName: String?
    let sourceUrl: String?
    /// club_events.place_entry_id: the registry entry this event happens at, when known.
    let placeEntryId: String?
    let clubs: ClubRef?

    struct ClubRef: Decodable { let name: String? }
}

/// club_members row (subset).
struct MemberRow: Decodable { let clubId: String; let userId: String? }

/// event_rsvps row (subset).
/// Just an event_date column (month dot queries).
struct DateRow: Decodable { let eventDate: String }

/// Lightweight agenda row (getEventsForRange select).
struct AgendaRow: Decodable {
    let id: String
    let title: String
    let eventDate: String
    let startTime: String?
    let location: String?
}

/// The authed user, from GET /auth/v1/user.
struct CurrentUser: Decodable { let id: String; let email: String? }

// MARK: - Town profile (this community app's per-user identity; separate from the
// wellness app's `profiles` table). Decoded with convertFromSnakeCase.
struct TownProfile: Decodable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let interests: [String]
    let onboardedAt: String?
    /// "Show my plans to friends" (town-feed 28): nil when the read didn't carry it.
    var plansToFriends: Bool? = nil
    /// "Suggest me to people I may know" (daily-tab 22): nil when the read didn't carry it.
    var suggestMe: Bool? = nil
}
