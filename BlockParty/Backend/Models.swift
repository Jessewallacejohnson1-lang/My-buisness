//
//  Models.swift
//  Block Party — data models, ported 1:1 from packages/core/src/types.ts.
//
//  Decoding uses .convertFromSnakeCase, so Swift camelCase ↔ DB snake_case
//  (event_date ↔ eventDate, image_url ↔ imageUrl, …).
//

import Foundation

enum ClubStatus: String, Codable { case pending, approved, rejected }
/// A `club_events` row's kind: an Event, a trail, or a neighbour's post (BP app town-feed 29).
enum PostKind: String, Codable { case event, trail, post }

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
        /// Read from the group's own calendar and outside St. Joseph (a St. Cloud club's other runs): it shows on
        /// the Group page, but the hello leaves it out.
        var away: Bool? = nil

        private enum CodingKeys: String, CodingKey { case what, day, time, place = "where", away }
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

/// nonisolated: a plain value the pure `nonisolated` rules build and compare
/// (`EventWhen`, `FeedCardItem`). Without this its synthesized Hashable is
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
    /// "photo of this event", from its card; nil when none.
    var imageUrl: String? = nil
    /// The viewer's RSVP state. Defaulted so activities and profile callers that
    /// only need the event summary remain source-compatible.
    var rsvpd: Bool = false
    /// Every account's hearts, and whether the viewer gave one: the Event card's (inside-cards 16), so a heart
    /// shows the same from every door. A heart is a save: You's Liked lists them.
    var heartCount: Int = 0
    var hearted: Bool = false
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
    /// The page it was found on (`club_events.source_url`, ADR-021), the Event page's link under
    /// About. Every Event read's card sends it; nil for a neighbour's own event.
    var sourceURL: URL? = nil
    /// Up to three of the caller's friends Going, newest Going first: every Event read's card sends them
    /// (`private.event_cards`; BP app you-tab 07, town-feed 28 and friends-on-event-page).
    var friendsGoing: [FeedFriend] = []
    /// A real happening (`private.is_live_kind`, town-feed 41): what "Now" and live mean on every screen.
    /// A row with no card to say so isn't (`init(from:)`, `TownPage`).
    var liveKind: Bool = true
    /// How its series repeats ("Every Tuesday"; `private.series_repeats`), the Event page's day row from every
    /// door (BP app inside-cards 23). nil for a one-off, no clear pattern, a called-off week, and a row with no card.
    var recurrence: String? = nil
}

/// Where an event happens, as a picture (`public.place_picture`, BP app
/// docs/plans/place-photos): the place's own photo, or its logo when we have no photo of
/// it. Saved once in Block Party's Storage, so showing it costs no lookup (Jesse,
/// 2026-11-01, MEMORY.md).
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
    /// This is the place's cover, not a photo of the Event (`public.event_picture`, BP app town-feed
    /// 40): its Town card goes white, its page still shows it. nil on every other picture.
    var cover: Bool? = nil
    /// This is a flyer or event graphic: its words matter, so it shows whole rather than cropped (BP app
    /// event-photos 16). nil on every other picture.
    var whole: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case url, kind, credit, site, hue, cover, whole
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

/// One row of `get_town_feed` (`supabase/migrations/*_town_feed*.sql`): an event (its card, which says how
/// it repeats), when it leaves the Town feed, why it's there (the recipe's top reason and the one name it
/// needs), for the admin the points behind its place, and its hearts (everyone's, and
/// whether you hearted it), which its card carries too: a feed kept from before the card had them
/// still shows them. Rows kept from before the recipe have no reason, and from before hearts, none.
nonisolated struct TownFeedRow: Hashable {
    let event: UpcomingEvent
    let leavesAt: Date
    var reason: String? = nil
    var reasonName: String? = nil
    var heartCount = 0
    var hearted = false
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
    /// Its headline, over its picture on the Town card (found-posts); nil where only the words are known.
    var title: String? = nil
    /// The interest it shares with you, by id, for its ••• sheet's why line (news-menu); nil when none.
    var interest: String? = nil

    /// What the Town card sets as its title: the headline, else the facts stand in for it.
    var headline: String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? words : title
    }

    /// The facts under the headline, only when they add something to it and its place's name
    /// (`NewsWords`). `words` stays whole for the hello pill and sharing.
    var facts: String? {
        words == headline || !NewsWords.adds(words, to: "\(headline) \(place)") ? nil : words
    }
}

/// Whether News's second line says something its headline doesn't (Jesse, 2026-11-06, BP app
/// inside-cards 07 and 12): at least 2 in 5 of its real words are new. It counts words and can't
/// read, and the numbers and lists were set on one day's 31 stories (`assets/07-words/rule.py`),
/// so tune them here.
nonisolated enum NewsWords {
    static let new = 2, of = 5
    /// Words that say nothing alone ("m" and "p" are what's left of "p.m.").
    static let filler: Set<String> = ["a", "an", "and", "are", "as", "at", "be", "been", "by", "can", "for", "from",
                                      "has", "have", "in", "into", "is", "it", "its", "of", "on", "or", "that", "the",
                                      "their", "this", "to", "up", "was", "were", "will", "with", "who", "m", "p"]
    /// Words that say the same thing ("wins", "gets" and "gives" are already their word, as plurals are).
    static let same = ["won": "win", "elected": "win", "received": "get"]

    static func adds(_ line: String, to known: String) -> Bool {
        let said = Set(real(known)), words = real(line)
        return !words.isEmpty && words.count(where: { !said.contains($0) }) * of >= words.count * new
    }

    /// Lowercased, without "'s", split on anything but a to z and 0 to 9, filler out, a plural as its word.
    static func real(_ text: String) -> [String] {
        text.lowercased().replacing("'s", with: "").replacing("’s", with: "")
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .map(String.init)
            .filter { !filler.contains($0) }
            .map { same[$0] ?? plural($0) }
    }

    /// "classes" is "class" and "clubs" is "club"; "class" stays.
    private static func plural(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s") else { return word }
        if word.hasSuffix("sses") { return String(word.dropLast(2)) }
        return word.hasSuffix("ss") ? word : String(word.dropLast())
    }
}

/// A neighbour's post in the Town feed (BP app town-feed 29, references/post-screen): their own words,
/// maybe one photo in its own shape and a Place, who posted it and the friends they tagged. It stays
/// 7 days. Friends-only ones reach only the poster's friends: the server sends them to no one else.
nonisolated struct TownPost: Hashable, Identifiable, Sendable {
    struct Person: Hashable, Sendable {
        let id: String
        let name: String
    }

    let id: String
    let poster: Person
    var posterPhoto: URL? = nil
    /// Their words; empty for a photo alone.
    let words: String
    var photo: URL? = nil
    /// The photo's shape, width over height, inside Instagram's limits (4:5 to 1.91:1); nil when
    /// unknown.
    var aspect: Double? = nil
    var place: String? = nil
    var tagged: [Person] = []
    /// Only the poster's friends see it.
    var friendsOnly = false
    let posted: Date
    let leavesAt: Date
    var heartCount = 0
    var hearted = false
    /// From you or someone you follow (friends follow each other), as the feed's row says: the Block
    /// Party tab's Following shows it (daily-tab 23).
    var followed = false

    /// "Jesse is with Sam Lee at Sal's.", Facebook's line, or the name alone.
    var line: String { Self.line(name: poster.name, with: tagged.map(\.name), at: place) }

    /// The name line New post and its card share: "Jesse is with Sam Lee and 2 others at Sal's."
    static func line(name: String, with friends: [String], at place: String?) -> String {
        let place = place?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let with = switch friends.count {
        case 0: ""
        case 1: " is with \(friends[0])"
        case 2: " is with \(friends[0]) and \(friends[1])"
        default: " is with \(friends[0]) and \(friends.count - 1) others"
        }
        if with.isEmpty && place.isEmpty { return name }
        return name + (with.isEmpty ? " is" : with) + (place.isEmpty ? "" : " at \(place)") + "."
    }

    /// The card's shape for the photo: its own, inside the limits; 4:5 when unknown.
    var photoAspect: Double {
        guard let aspect, aspect.isFinite, aspect > 0 else { return 4.0 / 5.0 }
        return min(max(aspect, 4.0 / 5.0), 1.91)
    }
}

/// One line of `get_town_feed`, in its order: an Event, news (town-feed 35), or a neighbour's post
/// (town-feed 29).
nonisolated enum TownFeedLine: Hashable {
    case event(TownFeedRow)
    case news(TownNews)
    case post(TownPost)
}

/// One line of a round past the Town feed's later Events (`get_town_more`, town-feed 23): a place to
/// try, or an Event or News item from the ranked list, again. An unknown kind is never drawn.
nonisolated struct TownMoreRow: Decodable, Hashable, Sendable {
    enum Kind: String, Decodable, Sendable { case place, again, unknown }
    let kind: Kind
    let id: String
}

nonisolated extension TownMoreRow {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .unknown
        id = try c.decode(String.self, forKey: .id)
    }

    private enum CodingKeys: String, CodingKey { case kind, id }
}

/// A friend Going to an Event, as the Town feed names them: first name, and their photo when
/// they have one in our bucket. Only friends who show their plans to friends (town-feed 28).
nonisolated struct FeedFriend: Hashable, Sendable {
    let name: String
    let photo: URL?
}

// MARK: - Social layer (follow / like / comment / feed) — Today tab remake.
// New tables (town_follows, event_likes, event_comments) live on the shared
// Supabase project; see docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §5.

/// What a follow points at: a club, a community member's town_profile, or a Place
/// (`public.places`, BP app docs/plans/follows ticket 02), a local team, or one of its activities
/// (`team_activities`, BP app school-activities 02), or the City's or the Town's own page and one of
/// the City's boards (`town_pages`, `city_boards`, follows 04).
enum FollowTargetType: String, Codable { case club, profile, place, team, activity, page, board }

struct FollowTarget: Hashable, Codable {
    let type: FollowTargetType
    let id: String
}

/// One upcoming Event as Popular and Follow 3 read it (`CommunityAPI.upcomingTags`): what it's about,
/// and whose it is: its Place's registry entry, the schools (`teams.id`) it's a game or activity of,
/// and the source it came from, which a Town page names.
struct UpcomingTags: Equatable {
    var interests: [String]
    var place: String? = nil
    var teams: [String] = []
    var source: String? = nil
}

/// A school of the Town's own (`teams.local`), followed by its `uuid`.
struct LocalSchool: Decodable, Equatable {
    let id: String
    let uuid: String
    let name: String
    /// "Sartell High School", where `name` is the team's "Sartell".
    let schoolName: String?
    let logoUrl: String?
}

/// One of the Town's pages (`town_pages`): the Town's own, its City's, a campus calendar's.
struct TownPageRow: Decodable, Equatable {
    let id: String
    let slug: String
    let name: String
    let kind: String?
    let sourceName: String?
    let picture: String?
    let pictureKind: String?
}

/// A local team's page (`team_page`, hello-drop 03).
struct TeamProfile: Decodable, Hashable {
    let id: String
    let name: String
    let short: String
    let logo: String?
    let colors: [String]?
    let games: [Game]
    /// Every activity the school lists, in its order (school-activities 02); empty from an older read.
    var activities: [Activity] = []

    private enum CodingKeys: String, CodingKey { case id, name, short, logo, colors, games, activities }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        short = try c.decode(String.self, forKey: .short)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        colors = try c.decodeIfPresent([String].self, forKey: .colors)
        games = try c.decode([Game].self, forKey: .games)
        activities = (try? c.decodeIfPresent([Activity].self, forKey: .activities)) ?? []
    }

    /// One of the school's activities: "Girls Soccer", its note ("St. Cloud Crush co-op"), whether
    /// you follow it, and its next event, nil until one is read ("No events yet").
    struct Activity: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
        let note: String?
        let kind: String
        let following: Bool
        let next: Next?

        struct Next: Decodable, Hashable {
            let title: String
            let date: String
            let time: String?
        }
    }

    /// One of an activity's coming events (`activity_events`).
    struct ActivityEvent: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
        let date: String
        let time: String?
        let location: String?
    }

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

    /// "Johnnies beat Gusties 33–23", "Johnnies lost to Gusties 23–33", "Johnnies tied Gusties 7–7",
    /// "Bennies beat Macalester 5–4 on penalties": your team's score first, each by its nickname when it has one.
    var text: String? {
        guard let final = game.final, let team, let other else { return nil }
        let score = game.shootout.map { "\($0.score[mine])–\($0.score[1 - mine]) on penalties" } ?? "\(final[mine])–\(final[1 - mine])"
        guard let winner = game.winner else { return "\(team.called) tied \(other.called) \(score)" }
        return winner == mine ? "\(team.called) beat \(other.called) \(score)" : "\(team.called) lost to \(other.called) \(score)"
    }
}

#if DEBUG
extension TeamFinal {
    /// `-hello-final`: Saint John's 33–23 over Gustavus, or the other way round; with `-town-shootout`, 1–1 and won
    /// 5–4 on penalties (game-card 15).
    static func sample(won: Bool) -> TeamFinal {
        let score = LaunchFlags.has(.townShootout)
            ? #"[1, 1], "live": {"score": [1, 1], "period": "OT", "shootout": {"score": [5, 4], "who": "SJU"}}"#
            : won ? "[33, 23]" : "[23, 33]"
        // Saint John's logo colours, as hex without the mark (colour literals stay in Hue).
        let red = "BC0E33", blue = "02A2E2"
        let json = """
        {"event_id": "debug", "mine": 0, "game": {"sport": "Football", "occasion": null, "final": \(score),
          "teams": [{"name": "Saint John's", "short": "Saint John's",
                     "logo": "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/teams/saint-johns/logo-36d1a2aa13.png",
                     "color": "#\(red)", "local": true, "id": "65ff8993-eb57-4c99-bdf9-94e8523ce960", "colors": ["#\(red)", "#\(blue)"],
                     "nickname": "Johnnies"},
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

// MARK: - Insert inputs

struct NewEventInput {
    /// Made by the phone, so a retried insert can't post the Event twice (BP app town-plus).
    var id: String? = nil
    var title: String
    var eventDate: String      // YYYY-MM-DD
    var startTime: String      // display string e.g. "7pm"
    var location: String
    var description: String?
    var imageUrl: String?
    var category: String = EventCategory.other.rawValue   // club_events.category text
}

/// A neighbour's post as New post sends it (BP app town-feed 29).
nonisolated struct NewPostInput: Equatable {
    /// Made by the phone, so a retried insert can't post it twice.
    let id: String
    let words: String
    var imageURL: String? = nil
    /// Width over height, inside 4:5 to 1.91:1.
    var aspect: Double? = nil
    var place: String? = nil
    var friendsOnly = false
    /// Friends' ids, in the order tagged.
    var tagged: [String] = []
}

struct NewTrailInput {
    var title: String
    var location: String
    var length: String?
    var difficulty: String?
    var description: String?
    var imageUrl: String?
}

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
    /// Profile's bio and cover photo (BP app references/profile-remake).
    var bio: String? = nil
    var coverUrl: String? = nil
    /// When the row was made: "Neighbor since" for an account that never onboarded.
    var createdAt: String? = nil
}

/// A profile's page beyond its name and photo (`get_profile`): the bio, the cover, how many
/// friends, the groups they're in, and for a friend, the Events you're both Going to.
struct ProfileExtras: Decodable, Equatable {
    var bio: String? = nil
    var coverUrl: String? = nil
    var friends = 0
    var groupIds: [String] = []
    var bothGoing: [String] = []
}
