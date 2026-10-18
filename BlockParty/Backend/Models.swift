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

/// ClubRow + member_count + joined (both derived from club_members).
struct ClubView: Identifiable, Hashable {
    let row: ClubRow
    var memberCount: Int
    var joined: Bool

    var id: String { row.id }
    var name: String { row.name }
    var host: String? { row.host }
    var schedule: String? { row.schedule }
    var location: String? { row.location }
    var vibe: String? { row.vibe }
    var about: String? { row.description }
    var expectations: String? { row.expectations }
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

    /// What the photo's chip says: its author and licence, else the site's name without
    /// "www.". nil for a logo.
    var creditLine: String? {
        guard kind == .photo else { return nil }
        if let credit, !credit.isEmpty { return credit }
        guard let host = site?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// One that doesn't decode is no picture: a bad row never costs the feed.
    struct Lenient: Decodable, Hashable {
        let value: PlacePicture?
        init(from decoder: Decoder) { value = try? PlacePicture(from: decoder) }
    }
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

/// What a follow points at: a club, or a community member's town_profile.
enum FollowTargetType: String, Codable { case club, profile }

struct FollowTarget: Hashable, Codable {
    let type: FollowTargetType
    let id: String
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
}
