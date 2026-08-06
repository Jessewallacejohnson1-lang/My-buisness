//
//  BriefingPayload.swift
//  Block Party — the Today tab briefing contract, in Swift.
//
//  One RPC (`get_today_briefing`) returns this whole object, so the home screen
//  is a single round trip. Decode with `SupabaseCoding.decoder`: snake_case
//  converts automatically and the dual-ISO date strategy handles PostgREST
//  timestamps with or without fractional seconds. There are deliberately NO
//  CodingKeys here — the whole model layer relies on `.convertFromSnakeCase`.
//
//  Spec: docs/superpowers/specs/2026-08-05-today-briefing-contract.md
//  Fixtures: fixtures/briefing_*.json
//
//  EVERY module is optional. A failure composing one module must not take the
//  briefing down with it — the same rule the old feed followed, where an outage
//  left the rest of Today intact.
//

import Foundation

// MARK: - Root

nonisolated struct BriefingPayload: Codable, Equatable {
    let briefingDate: String        // "YYYY-MM-DD", town-anchored. Never a Date.
    let tz: String
    let status: BriefingStatus
    let publishedAt: Date?
    let almanac: BriefingAlmanac?
    let weather: BriefingWeather?
    let featured: [BriefingEvent]
    let featuredFallback: BriefingFallback?
    let touch: BriefingTouch?
    let spotlight: BriefingSpotlight?
    let caughtUp: BriefingCaughtUp
}

/// `none` means the routine has not published a briefing for this date. Unknown
/// values from a newer server decode to `.none` rather than failing the payload.
nonisolated enum BriefingStatus: String, Codable {
    case published
    case none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BriefingStatus(rawValue: raw) ?? .none
    }
}

// MARK: - Modules

nonisolated struct BriefingAlmanac: Codable, Equatable {
    /// The caller's personalized line from `almanac_daily`. Nil on a cache miss,
    /// in which case the client falls back to the `daily-almanac` edge function
    /// exactly as it does today.
    let line: String?
    let format: String?
    let source: String?
    /// Town-wide copy from `daily_briefings.almanac_md`. Always present.
    let townLine: String

    /// What to render right now: the personal line if it arrived, else the town's.
    var displayLine: String { line ?? townLine }
    var isPersonal: Bool { line != nil }
}

nonisolated struct BriefingWeather: Codable, Equatable {
    let condition: String?
    let tempF: Double?
    let feelsLikeF: Double?
    let highF: Double?
    let lowF: Double?
    let sunrise: String?
    let sunset: String?
    let observedAt: Date?
}

nonisolated struct BriefingEvent: Codable, Equatable, Identifiable {
    let rank: Int
    let id: String
    let title: String
    let eventDate: String           // "YYYY-MM-DD"
    let startTime: String?          // free text — the column is text ("7pm")
    let location: String?
    let imageUrl: String?
    let clubName: String?
    let category: String
    let goingCount: Int
    let goingAvatars: [String]
    let likeCount: Int
    let commentCount: Int
    let rsvpd: Bool
    let saved: Bool
    let liked: Bool

    /// Parsed lazily and defensively: one malformed avatar URL must not fail the
    /// whole briefing decode.
    var avatarURLs: [URL] { goingAvatars.compactMap(URL.init(string:)) }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
}

nonisolated struct BriefingFallback: Codable, Equatable {
    let kind: String
    let title: String?
    let body: String
    let deeplink: String?
}

nonisolated struct BriefingTouch: Codable, Equatable, Identifiable {
    nonisolated enum Kind: String, Codable {
        case poll
        case history

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .history
        }
    }

    let id: String
    let kind: Kind
    let prompt: String
    let options: [String]?
    let body: String?
    /// Index-aligned with `options`, zeros included. Guaranteed by the RPC.
    let voteCounts: [Int]
    let totalVotes: Int
    /// The caller's own choice, or nil if they have not voted.
    let myVote: Int?

    var hasVoted: Bool { myVote != nil }
    var choices: [String] { options ?? [] }

    /// Share of the vote for an option, 0...1. Returns 0 rather than dividing by
    /// zero on an unvoted poll.
    func share(at index: Int) -> Double {
        guard totalVotes > 0, voteCounts.indices.contains(index) else { return 0 }
        return Double(voteCounts[index]) / Double(totalVotes)
    }

    func count(at index: Int) -> Int {
        voteCounts.indices.contains(index) ? voteCounts[index] : 0
    }
}

nonisolated struct BriefingSpotlight: Codable, Equatable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let blurb: String
    let imageUrl: String?
    let placeId: String?

    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
}

nonisolated struct BriefingCaughtUp: Codable, Equatable {
    let nextBriefingAt: Date
    let label: String
}

// MARK: - Convenience

nonisolated extension BriefingPayload {
    /// True when there is genuinely nothing composed for this date. The screen
    /// still renders — header, utility row, and the caught-up footer.
    var isUnavailable: Bool { status == .none }

    /// The Happening Soon module renders the fallback when there are no events.
    /// Exactly one of these is ever non-empty.
    var hasFeaturedEvents: Bool { !featured.isEmpty }
}
