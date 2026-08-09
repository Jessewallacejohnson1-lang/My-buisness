//
//  FeedLowerModuleStatesTests.swift
//  BlockPartyTests — the For You reason line, the lower modules' four-state
//  matrix, the "+" press Reduce-Motion branch, and the spotlight's week copy.
//

import XCTest
@testable import BlockParty

@MainActor
final class FeedLowerModuleStatesTests: XCTestCase {

    // MARK: - A. The reason line

    /// The defect: both halves were written from the same taxonomy, so the line
    /// read "Sports & fitness · because you follow Sports & leagues".
    func testReasonLineNeverRepeatsAWordAcrossItsTwoHalves() {
        for interest in Interests.all {
            let categories = ForYouRecommendations.categoryMapping[interest.id] ?? []
            for category in categories {
                let tag = ForYouInterestTag(
                    id: interest.id,
                    label: interest.label,
                    categories: categories
                )
                let line = ForYouReason.line(category: category, matchedInterest: tag)

                if ForYouReason.overlaps(category.label, interest.label) {
                    XCTAssertFalse(
                        line.contains("·"),
                        "\(interest.id): overlapping halves must collapse, got \(line)"
                    )
                } else {
                    XCTAssertTrue(
                        line.hasPrefix("\(category.label) · "),
                        "\(interest.id): distinct halves must both render, got \(line)"
                    )
                }
            }
        }
    }

    /// Non-negotiable in both forms: the line names the tag the user actually
    /// chose. It is never made generic to dodge the repetition.
    func testEveryReasonLineNamesTheUsersRealMatchedTag() {
        for interest in Interests.all {
            let categories = ForYouRecommendations.categoryMapping[interest.id] ?? []
            for category in categories {
                let tag = ForYouInterestTag(
                    id: interest.id,
                    label: interest.label,
                    categories: categories
                )
                let line = ForYouReason.line(category: category, matchedInterest: tag)

                // Sentence case differs between the two forms ("Because…" when the
                // line collapses), so compare case-insensitively.
                XCTAssertTrue(
                    line.lowercased()
                        .hasSuffix("because you follow \(interest.label.lowercased())"),
                    "\(interest.id) produced \(line)"
                )
            }
        }
    }

    func testTheTwoHalfFormSurvivesWhenTheHalvesDiffer() {
        let coffee = ForYouInterestTag(id: "coffee", label: "Coffee shops", categories: [.food])

        XCTAssertEqual(
            ForYouReason.line(category: .food, matchedInterest: coffee),
            "Food & drink · because you follow Coffee shops"
        )
    }

    func testTheCarriedDefectLineIsGone() {
        let leagues = ForYouInterestTag(
            id: "sports_leagues",
            label: "Sports & leagues",
            categories: [.sports]
        )
        let line = ForYouReason.line(category: .sports, matchedInterest: leagues)

        XCTAssertEqual(line, "Because you follow Sports & leagues")
        XCTAssertNotEqual(line, "Sports & fitness · because you follow Sports & leagues")
    }

    /// The posting's own `reason` must route through the same rule — the card
    /// renders that property, not the function.
    func testPostingReasonUsesTheSharedRule() throws {
        let posting = try XCTUnwrap(
            ForYouRecommendations.recommendedPostings(
                for: ForYouUser(interestIDs: ["live_music"]),
                from: [candidate(id: "gig", category: .musicArts)]
            ).first
        )

        XCTAssertEqual(posting.reason, "Because you follow Live music")
    }

    /// "Music & arts" against "Art & exhibits" is a repeat; "Outdoors" against
    /// "Trails & hiking" is not. The stemmer only has to get this vocabulary right.
    func testWordOverlapIsStemInsensitiveButNotOverEager() {
        XCTAssertTrue(ForYouReason.overlaps("Music & arts", "Art & exhibits"))
        XCTAssertTrue(ForYouReason.overlaps("Sports & fitness", "Fitness & yoga"))
        XCTAssertTrue(ForYouReason.overlaps("Families & kids", "Families & kids"))
        XCTAssertFalse(ForYouReason.overlaps("Outdoors", "Trails & hiking"))
        XCTAssertFalse(ForYouReason.overlaps("Food & drink", "Farmers market"))
        XCTAssertFalse(ForYouReason.overlaps("Faith", "Live music"))
    }

    // MARK: - B. The four-state matrix

    func testSpotlightResolvesAllFourStates() {
        XCTAssertEqual(
            SpotlightPhaseRule.phase(hasSpotlight: false, hasPayload: false, loadFailed: false),
            .loading
        )
        XCTAssertEqual(
            SpotlightPhaseRule.phase(hasSpotlight: false, hasPayload: false, loadFailed: true),
            .failed
        )
        XCTAssertEqual(
            SpotlightPhaseRule.phase(hasSpotlight: false, hasPayload: true, loadFailed: false),
            .empty,
            "a published edition with no spotlight row renders nothing"
        )
        XCTAssertEqual(
            SpotlightPhaseRule.phase(hasSpotlight: true, hasPayload: true, loadFailed: false),
            .ready
        )
    }

    func testSignOffNeverFailsAndDisappearsInstead() {
        XCTAssertEqual(SignOffPhaseRule.phase(hasPayload: false, loadFailed: false), .loading)
        XCTAssertEqual(
            SignOffPhaseRule.phase(hasPayload: false, loadFailed: true),
            .empty,
            "there is no edition to sign off on, so the module leaves rather than errors"
        )
        XCTAssertEqual(SignOffPhaseRule.phase(hasPayload: true, loadFailed: true), .ready)
    }

    func testTriviaIsEmptyOnlyWhenNothingWasClaimedForToday() {
        XCTAssertEqual(TriviaPhaseRule.phase(trivia: .empty, hasTouch: false), .empty)
        XCTAssertEqual(TriviaPhaseRule.phase(trivia: .loading, hasTouch: false), .loading)
        XCTAssertEqual(TriviaPhaseRule.phase(trivia: .failed, hasTouch: false), .failed)
        XCTAssertEqual(
            TriviaPhaseRule.phase(trivia: .failed, hasTouch: true),
            .ready,
            "a failed trivia fetch must not hide a poll that arrived fine"
        )
    }

    func testForYouLoadFailureReachesTheErrorState() async {
        let module = ForYouModule(
            profileLoader: { _ in self.profile(interests: ["sports_leagues"]) },
            eventsLoader: { _ in throw ForYouTestError.offline },
            savedIDsLoader: { _, _ in [] },
            dismissedIDsLoader: { _, _ in [] }
        )

        await module.load(context())

        XCTAssertEqual(module.phase, .failed)
        XCTAssertEqual(module.contentState, .failed)
        XCTAssertTrue(module.postings.isEmpty)
    }

    /// Below ten responses the town line is absent, not a placeholder. Real data
    /// only: no dash, no "0%", no "not enough answers yet".
    func testTriviaRevealOmitsTheTownLineBelowTenResponses() throws {
        let reveal = try XCTUnwrap(
            TriviaReveal.make(
                for: question(
                    myAnswer: 1,
                    stats: TriviaStats(correctAnswerPercentage: 67, responseCount: 9)
                )
            )
        )

        XCTAssertEqual(reveal.answerLine, "Correct.")
        XCTAssertNil(reveal.townLine)
        XCTAssertNil(reveal.streakLine)
    }

    func testTriviaRevealShowsTheTownLineAtTenResponses() throws {
        let reveal = try XCTUnwrap(
            TriviaReveal.make(
                for: question(
                    myAnswer: 0,
                    stats: TriviaStats(correctAnswerPercentage: 54, responseCount: 10)
                )
            )
        )

        XCTAssertEqual(reveal.answerLine, "Not quite. Watab River is the answer.")
        XCTAssertEqual(reveal.townLine, "54% of St. Joe got this right.")
    }

    func testTriviaHasNoRevealBeforeAnAnswerLands() {
        XCTAssertNil(TriviaReveal.make(for: question()))
    }

    /// A single streak day is not a streak, so it renders nothing rather than "1".
    func testTriviaStreakLineOnlyAppearsFromTwoDays() throws {
        let one = try XCTUnwrap(
            TriviaReveal.make(for: question(myAnswer: 1, stats: nil, streakCount: 1))
        )
        let four = try XCTUnwrap(
            TriviaReveal.make(for: question(myAnswer: 1, stats: nil, streakCount: 4))
        )

        XCTAssertNil(one.streakLine)
        XCTAssertEqual(four.streakLine, "4 days in a row")
    }

    // MARK: - C. Motion

    /// The showcase press. Reduce Motion must degrade it to a cross-fade: no
    /// spring, no scale, no offset — the same contract every quiet feed press has.
    func testTheMarkPressCrossFadesUnderReduceMotion() {
        let reduced = FeedMarkPress.spec(reduceMotion: true)

        XCTAssertTrue(reduced.isCrossFade)
        XCTAssertFalse(reduced.usesSpring)
        XCTAssertFalse(reduced.usesScale)
        XCTAssertEqual(reduced.duration, FeedMotion.crossFade, accuracy: 0.0001)
        XCTAssertEqual(FeedMarkPress.scale(isPressed: true, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(
            FeedMarkPress.opacity(isPressed: true, reduceMotion: true),
            FeedMotion.pressOpacity(isPressed: true, reduceMotion: true),
            accuracy: 0.0001
        )
    }

    func testTheMarkPressKeepsItsSpringWhenMotionIsAllowed() {
        let full = FeedMarkPress.spec(reduceMotion: false)

        XCTAssertTrue(full.usesSpring)
        XCTAssertTrue(full.usesScale)
        XCTAssertFalse(full.isCrossFade)
        XCTAssertEqual(
            FeedMarkPress.scale(isPressed: true, reduceMotion: false),
            FeedMarkPress.pressedScale,
            accuracy: 0.0001
        )
        XCTAssertEqual(FeedMarkPress.pressedScale, 0.88, accuracy: 0.0001)
        XCTAssertEqual(FeedMarkPress.opacity(isPressed: true, reduceMotion: false), 1, accuracy: 0.0001)
    }

    /// One language: the showcase press and every quiet press degrade identically.
    func testEveryFeedPressSharesOneReducedMotionContract() {
        XCTAssertEqual(
            FeedMarkPress.spec(reduceMotion: true),
            FeedMotion.quietPressSpec(reduceMotion: true)
        )
    }

    // MARK: - D. The week identifier

    func testTheWeekLabelIsSaidInPlainEnglish() {
        XCTAssertEqual(SpotlightWeekLabel.label(forBriefingDate: "2026-08-03"), "week of August 3")
    }

    /// Fixed for all seven days, so the card cannot read stale on a Friday.
    func testTheWeekLabelHoldsStillFromMondayThroughSunday() {
        XCTAssertEqual(SpotlightWeekLabel.label(forBriefingDate: "2026-08-07"), "week of August 3")
        XCTAssertEqual(SpotlightWeekLabel.label(forBriefingDate: "2026-08-09"), "week of August 3")
    }

    func testTheWeekLabelTurnsOverOnMonday() {
        XCTAssertEqual(SpotlightWeekLabel.label(forBriefingDate: "2026-08-10"), "week of August 10")
    }

    func testTheWeekLabelIsAbsentRatherThanGuessedForABadDate() {
        XCTAssertNil(SpotlightWeekLabel.label(forBriefingDate: "not-a-date"))
        XCTAssertNil(SpotlightWeekLabel.label(forBriefingDate: ""))
    }

    /// The machine key is untouched: it is the server's archive key, and it should
    /// still look like one. Only the card's copy changed.
    func testTheArchiveKeyStaysMachineReadable() {
        XCTAssertEqual(SpotlightWeek.identifier(for: "2026-08-07"), "2026-W32")
    }

    // MARK: - Fixtures

    private func question(
        myAnswer: Int? = nil,
        stats: TriviaStats? = nil,
        streakCount: Int? = nil
    ) -> TriviaQuestion {
        TriviaQuestion(
            id: "states-trivia",
            prompt: "Which river runs through Millstream Park?",
            options: ["Sauk River", "Watab River", "Mississippi River", "Rum River"],
            correctIndex: 1,
            myAnswer: myAnswer,
            stats: stats,
            streakCount: streakCount
        )
    }

    private func candidate(id: String, category: EventCategory) -> ForYouCandidate {
        ForYouCandidate(
            id: id,
            title: "Fixture \(id)",
            eventDate: "2033-05-18",
            startTime: "7:00 PM",
            location: "Downtown",
            category: category,
            startsAt: Date(timeIntervalSince1970: 100),
            rsvpd: false,
            saved: false,
            dismissed: false
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

    private func context() -> FeedModuleContext {
        FeedModuleContext(
            auth: AuthStore(),
            briefing: BriefingModel(),
            displayName: "Jesse",
            navigate: { _ in }
        )
    }
}

private enum ForYouTestError: Error {
    case offline
}
