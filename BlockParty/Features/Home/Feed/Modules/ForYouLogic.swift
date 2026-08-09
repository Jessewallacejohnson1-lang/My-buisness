//
//  ForYouLogic.swift
//  Block Party — the single v1 interest crosswalk and recommendation function.
//

import Foundation

struct ForYouUser: Equatable {
    let interestIDs: [String]
}

struct ForYouInterestTag: Identifiable, Hashable {
    let id: String
    let label: String
    let categories: Set<EventCategory>
}

struct ForYouCandidate: Identifiable, Hashable {
    let id: String
    let title: String
    let eventDate: String
    let startTime: String?
    let location: String?
    let category: EventCategory
    let startsAt: Date
    let rsvpd: Bool
    let saved: Bool
    let dismissed: Bool
}

struct ForYouPosting: Identifiable, Hashable {
    let id: String
    let title: String
    let eventDate: String
    let startTime: String?
    let location: String?
    let category: EventCategory
    let startsAt: Date
    let matchedInterest: ForYouInterestTag
    let overlapCount: Int

    var reason: String {
        "\(category.label) · because you follow \(matchedInterest.label)"
    }
}

enum ForYouContentState: Equatable {
    case loading
    case needsInterests
    case recommendations
    case noMatches
    case failed
}

enum ForYouRecommendations {
    /// The complete v1 crosswalk from all 18 `town_profiles.interests` ids to
    /// `club_events.category`. Empty sets are deliberate taxonomy gaps, not
    /// fallbacks: matching them to `.other` would make unrelated posts personal.
    static let categoryMapping: [String: Set<EventCategory>] = [
        "trails_hiking": [.outdoors],
        "lakes_swimming": [.outdoors],
        "parks_gardens": [.outdoors],
        "biking": [.outdoors],
        "coffee": [.food],
        "dining": [.food],
        "farmers_market": [.food],
        "breweries": [.food],
        "live_music": [.musicArts],
        "art_exhibits": [.musicArts],
        "faith": [.faith],
        "festivals": [],
        "books": [.books],
        "fitness_yoga": [.sports],
        "sports_leagues": [.sports],
        "health_wellness": [],
        "families_kids": [.families],
        "volunteering": [.service],
    ]

    static func userInterestTags(for user: ForYouUser) -> [ForYouInterestTag] {
        var seen = Set<String>()
        return user.interestIDs.compactMap { id in
            guard seen.insert(id).inserted,
                  let interest = Interests.all.first(where: { $0.id == id }),
                  let categories = categoryMapping[id]
            else { return nil }

            return ForYouInterestTag(
                id: interest.id,
                label: interest.label,
                categories: categories
            )
        }
    }

    /// V1 ranking lives entirely here: exclude prior actions, count matched
    /// profile tags, then use soonest start (and id for deterministic equality).
    static func recommendedPostings(
        for user: ForYouUser,
        from candidates: [ForYouCandidate],
        limit: Int = 5
    ) -> [ForYouPosting] {
        guard limit > 0 else { return [] }
        let tags = userInterestTags(for: user)
        guard !tags.isEmpty else { return [] }

        return candidates.compactMap { candidate -> ForYouPosting? in
            guard !candidate.rsvpd, !candidate.saved, !candidate.dismissed else {
                return nil
            }

            let matches = tags.filter { $0.categories.contains(candidate.category) }
            guard let matchedInterest = matches.first else { return nil }

            return ForYouPosting(
                id: candidate.id,
                title: candidate.title,
                eventDate: candidate.eventDate,
                startTime: candidate.startTime,
                location: candidate.location,
                category: candidate.category,
                startsAt: candidate.startsAt,
                matchedInterest: matchedInterest,
                overlapCount: matches.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.overlapCount != rhs.overlapCount {
                return lhs.overlapCount > rhs.overlapCount
            }
            if lhs.startsAt != rhs.startsAt {
                return lhs.startsAt < rhs.startsAt
            }
            return lhs.id < rhs.id
        }
        .prefix(limit)
        .map { $0 }
    }
}
