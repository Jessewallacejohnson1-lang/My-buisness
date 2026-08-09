//
//  ForYouTests.swift
//  BlockPartyTests — interest mapping, ranking, exclusions, and empty states.
//

import XCTest
@testable import BlockParty

@MainActor
final class ForYouTests: XCTestCase {
    func testCategoryMappingHasAnExplicitEntryForEveryCatalogueInterest() {
        XCTAssertEqual(
            Set(ForYouRecommendations.categoryMapping.keys),
            Set(Interests.all.map(\.id))
        )
    }

    func testCategoryMappingUsesTheApprovedV1CrosswalkAndKeepsGapsEmpty() {
        let expected: [String: Set<EventCategory>] = [
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

        XCTAssertEqual(ForYouRecommendations.categoryMapping, expected)
    }

    func testUserInterestTagsDropsUnknownIDsAndPreservesProfileOrder() {
        let user = ForYouUser(
            interestIDs: ["sports_leagues", "unknown", "coffee"]
        )

        let tags = ForYouRecommendations.userInterestTags(for: user)

        XCTAssertEqual(tags.map(\.id), ["sports_leagues", "coffee"])
        XCTAssertEqual(tags.map(\.label), ["Sports & leagues", "Coffee shops"])
    }

    func testRecommendationRanksHigherTagOverlapFirst() throws {
        let user = ForYouUser(
            interestIDs: ["trails_hiking", "parks_gardens", "coffee"]
        )
        let soonerFood = candidate(
            id: "food",
            category: .food,
            startsAt: Date(timeIntervalSince1970: 100)
        )
        let laterOutdoors = candidate(
            id: "outdoors",
            category: .outdoors,
            startsAt: Date(timeIntervalSince1970: 200)
        )

        let recommendations = ForYouRecommendations.recommendedPostings(
            for: user,
            from: [soonerFood, laterOutdoors]
        )

        XCTAssertEqual(recommendations.map(\.id), ["outdoors", "food"])
        XCTAssertEqual(recommendations.map(\.overlapCount), [2, 1])
    }

    func testRecommendationBreaksOverlapTieBySoonestStart() {
        let user = ForYouUser(interestIDs: ["sports_leagues"])
        let later = candidate(
            id: "later",
            category: .sports,
            startsAt: Date(timeIntervalSince1970: 200)
        )
        let sooner = candidate(
            id: "sooner",
            category: .sports,
            startsAt: Date(timeIntervalSince1970: 100)
        )

        let recommendations = ForYouRecommendations.recommendedPostings(
            for: user,
            from: [later, sooner]
        )

        XCTAssertEqual(recommendations.map(\.id), ["sooner", "later"])
    }

    func testRsvpdSavedAndDismissedCandidatesAreExcluded() {
        let user = ForYouUser(interestIDs: ["sports_leagues"])
        let candidates = [
            candidate(id: "eligible", category: .sports),
            candidate(id: "rsvpd", category: .sports, rsvpd: true),
            candidate(id: "saved", category: .sports, saved: true),
            candidate(id: "dismissed", category: .sports, dismissed: true),
        ]

        let recommendations = ForYouRecommendations.recommendedPostings(
            for: user,
            from: candidates
        )

        XCTAssertEqual(recommendations.map(\.id), ["eligible"])
    }

    func testRecommendationLimitCapsResultsAtFive() {
        let user = ForYouUser(interestIDs: ["sports_leagues"])
        let candidates = (0..<8).map { index in
            candidate(
                id: "event-\(index)",
                category: .sports,
                startsAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let recommendations = ForYouRecommendations.recommendedPostings(
            for: user,
            from: candidates,
            limit: 5
        )

        XCTAssertEqual(recommendations.map(\.id), (0..<5).map { "event-\($0)" })
    }

    func testEveryRecommendationReasonNamesTheRealMatchedInterest() throws {
        let user = ForYouUser(interestIDs: ["sports_leagues"])

        let posting = try XCTUnwrap(
            ForYouRecommendations.recommendedPostings(
                for: user,
                from: [candidate(id: "soccer", category: .sports)]
            ).first
        )

        XCTAssertEqual(posting.matchedInterest.id, "sports_leagues")
        XCTAssertEqual(
            posting.reason,
            "Sports & fitness · because you follow Sports & leagues"
        )
    }

    func testNoInterestTagsShowsSetupStateWithoutLoadingEvents() async {
        var loadedEvents = false
        let module = ForYouModule(
            profileLoader: { _ in self.profile(interests: []) },
            eventsLoader: { _ in loadedEvents = true; return [] },
            savedIDsLoader: { _, _ in [] },
            dismissedIDsLoader: { _, _ in [] }
        )

        await module.load(context())

        XCTAssertEqual(module.contentState, .needsInterests)
        XCTAssertEqual(module.phase, .ready)
        XCTAssertFalse(loadedEvents)
    }

    func testInterestTagsWithNoMatchesHideTheModule() async {
        let module = ForYouModule(
            profileLoader: { _ in self.profile(interests: ["sports_leagues"]) },
            eventsLoader: { _ in [self.upcoming(id: "coffee", category: .food)] },
            savedIDsLoader: { _, _ in [] },
            dismissedIDsLoader: { _, _ in [] }
        )

        await module.load(context())

        XCTAssertEqual(module.contentState, .noMatches)
        XCTAssertEqual(module.phase, .empty)
        XCTAssertTrue(module.postings.isEmpty)
    }

    private func candidate(
        id: String,
        category: EventCategory,
        startsAt: Date = Date(timeIntervalSince1970: 100),
        rsvpd: Bool = false,
        saved: Bool = false,
        dismissed: Bool = false
    ) -> ForYouCandidate {
        ForYouCandidate(
            id: id,
            title: "Fixture \(id)",
            eventDate: "2033-05-18",
            startTime: "7:00 PM",
            location: "Downtown",
            category: category,
            startsAt: startsAt,
            rsvpd: rsvpd,
            saved: saved,
            dismissed: dismissed
        )
    }

    private func profile(interests: [String]) -> TownProfile {
        TownProfile(
            userId: "user-1",
            displayName: "Jesse",
            avatarUrl: nil,
            interests: interests,
            onboardedAt: "2033-05-01T12:00:00Z"
        )
    }

    private func upcoming(id: String, category: EventCategory) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: "Fixture \(id)",
            eventDate: "2033-05-18",
            startTime: "7:00 PM",
            location: "Downtown",
            goingCount: 0,
            createdAt: "2033-05-01T12:00:00Z",
            category: category
        )
    }

    private func context() -> FeedModuleContext {
        FeedModuleContext(
            auth: AuthStore(),
            briefing: BriefingModel(),
            displayName: "Jesse",
            navigate: { _ in }
        )
    }
}
