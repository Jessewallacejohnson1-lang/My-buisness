//
//  Models.swift
//  Hygge — data models, ported 1:1 from packages/core/src/types.ts.
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

/// A timeline row: a club event with the viewer's RSVP state + going count.
struct TimelineEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startTime: String?
    let location: String?
    var goingCount: Int
    var rsvpd: Bool
    let clubName: String?
    let fromJoinedClub: Bool
}

struct UpcomingEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let eventDate: String
    let startTime: String?
    let location: String?
    var goingCount: Int
    let createdAt: String
}

struct WeekEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let dateLabel: String
    var goingCount: Int
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

struct DailyQuest: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let date: String
}

// MARK: - Insert inputs

struct NewEventInput {
    var title: String
    var eventDate: String      // YYYY-MM-DD
    var startTime: String      // display string e.g. "7pm"
    var location: String
    var description: String?
    var imageUrl: String?
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
    let clubs: ClubRef?

    struct ClubRef: Decodable { let name: String? }
}

/// club_members row (subset).
struct MemberRow: Decodable { let clubId: String; let userId: String? }

/// event_rsvps row (subset).
struct RsvpRow: Decodable { let eventId: String; let userId: String? }

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
