//
//  FeedStatesGallery.swift
//  Block Party — DEBUG-only coverage for every state of the lower feed modules.
//
//  For You, the spotlight, trivia and the sign-off all sit below the fold at
//  orders 4–7, and this simulator setup has no scroll or gesture automation, so
//  their loading / empty / error faces cannot be reached from the real Today
//  composition. `-feed-gallery` mounts them directly.
//
//  `-feed-state <key[,key…]>` narrows to matching states so a tall one can be
//  screenshotted on its own; a key matches on prefix, so `-feed-state foryou`
//  brings up the whole For You family and `-feed-state foryou-error` just the one.
//

#if DEBUG
import SwiftUI

struct FeedStatesGallery: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                forYouStates
                spotlightStates
                triviaStates
                signOffStates
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
        }
        .background(Hue.paper.ignoresSafeArea())
    }

    // MARK: - For You

    @ViewBuilder
    private var forYouStates: some View {
        state("foryou-loading", "FOR YOU · LOADING") {
            ForYouSkeleton()
        }

        state("foryou-ready", "FOR YOU · MATCHED POSTINGS") {
            ForYouSection(
                state: .recommendations,
                postings: samplePostings,
                onSetInterests: {},
                onJoin: { _ in },
                onSave: { _ in },
                onDismiss: { _ in }
            )
        }

        state("foryou-notags", "FOR YOU · NO INTEREST TAGS") {
            ForYouSection(
                state: .needsInterests,
                postings: [],
                onSetInterests: {},
                onJoin: { _ in },
                onSave: { _ in },
                onDismiss: { _ in }
            )
        }

        state("foryou-empty", "FOR YOU · EMPTY") {
            rendersNothing("Interests are set, but no upcoming posting maps to any of them.")
        }

        state("foryou-error", "FOR YOU · ERROR") {
            FeedUnavailableCard(title: FeedLowerStateCopy.forYouUnavailable) {}
        }

        state("foryou-reasons", "FOR YOU · EVERY REASON LINE") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(everyReasonLine, id: \.self) { line in
                    Text(line)
                        .font(.sansMedium(12))
                        .foregroundStyle(Hue.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Spotlight

    @ViewBuilder
    private var spotlightStates: some View {
        state("spotlight-loading", "SPOTLIGHT · LOADING") {
            SpotlightCardSkeleton()
        }

        state("spotlight-ready", "SPOTLIGHT · READY") {
            SpotlightCard(
                spotlight: sampleSpotlight,
                weekLabel: SpotlightWeekLabel.label(forBriefingDate: "2026-08-07"),
                onOpen: {}
            )
        }

        state("spotlight-empty", "SPOTLIGHT · EMPTY") {
            rendersNothing("The edition published with no active spotlight row.")
        }

        state("spotlight-error", "SPOTLIGHT · ERROR") {
            FeedUnavailableCard(title: FeedLowerStateCopy.spotlightUnavailable) {}
        }
    }

    // MARK: - Trivia

    @ViewBuilder
    private var triviaStates: some View {
        state("trivia-loading", "TRIVIA · LOADING") {
            TriviaCardSkeleton()
        }

        state("trivia-unanswered", "TRIVIA · UNANSWERED") {
            TriviaCard(question: triviaQuestion(), onAnswer: { _ in })
        }

        state("trivia-answered", "TRIVIA · ANSWERED") {
            TriviaCard(
                question: triviaQuestion(
                    myAnswer: 1,
                    stats: TriviaStats(correctAnswerPercentage: 54, responseCount: 37)
                )
            )
        }

        state("trivia-wrong", "TRIVIA · ANSWERED WRONG") {
            TriviaCard(
                question: triviaQuestion(
                    myAnswer: 0,
                    stats: TriviaStats(correctAnswerPercentage: 54, responseCount: 37),
                    streakCount: nil
                )
            )
        }

        state("trivia-lowsample", "TRIVIA · UNDER TEN RESPONSES") {
            TriviaCard(
                question: triviaQuestion(
                    myAnswer: 1,
                    stats: TriviaStats(correctAnswerPercentage: 67, responseCount: 9)
                )
            )
        }

        state("trivia-empty", "TRIVIA · EMPTY") {
            rendersNothing("No question is claimed for today.")
        }

        state("trivia-error", "TRIVIA · ERROR") {
            FeedUnavailableCard(title: FeedLowerStateCopy.triviaUnavailable) {}
        }
    }

    // MARK: - Sign-off

    @ViewBuilder
    private var signOffStates: some View {
        state("signoff-loading", "SIGN-OFF · LOADING") {
            SignOffSkeleton()
        }

        state("signoff-ready", "SIGN-OFF · READY") {
            CaughtUpFooter(
                caughtUp: sampleCaughtUp,
                briefingDateLabel: "Friday, August 7",
                briefingDate: "2026-08-07"
            )
        }

        state("signoff-empty", "SIGN-OFF · EMPTY") {
            rendersNothing("The briefing never arrived, so there is no edition to close.")
        }
    }

    // MARK: - Gallery plumbing

    private var selectedKeys: [String] {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-feed-state"),
              index + 1 < arguments.count
        else { return [] }

        return arguments[index + 1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func isShown(_ key: String) -> Bool {
        let keys = selectedKeys
        guard !keys.isEmpty else { return true }
        return keys.contains { key.hasPrefix($0) }
    }

    @ViewBuilder
    private func state<Content: View>(
        _ key: String,
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isShown(key) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.monoMedium(10))
                    .tracking(1)
                    .foregroundStyle(Hue.inkSecondary)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The empty phase draws nothing in production. The gallery has to draw
    /// SOMETHING or the screenshot is unreadable, so it draws a labelled note that
    /// is obviously not the module.
    private func rendersNothing(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Renders nothing")
                .font(.displaySemi(18))
                .foregroundStyle(Hue.ink)

            Text(reason)
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(Hue.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    // MARK: - Fixtures

    private var everyReasonLine: [String] {
        Interests.all.flatMap { interest -> [String] in
            let categories = ForYouRecommendations.categoryMapping[interest.id] ?? []
            let tag = ForYouInterestTag(
                id: interest.id,
                label: interest.label,
                categories: categories
            )
            return categories
                .sorted { $0.rawValue < $1.rawValue }
                .map { ForYouReason.line(category: $0, matchedInterest: tag) }
        }
    }

    /// Deliberately ordered so the first visible card carries the two-half form and
    /// the second carries the collapsed form — both are on screen at once.
    private var samplePostings: [ForYouPosting] {
        [
            posting(
                id: "gallery-coffee",
                title: "Saturday coffee tasting",
                time: "9:00 AM",
                location: "Local Blend",
                category: .food,
                interestID: "coffee"
            ),
            posting(
                id: "gallery-soccer",
                title: "Pickup soccer at Millstream",
                time: "6:00 PM",
                location: "Millstream Park",
                category: .sports,
                interestID: "sports_leagues"
            ),
        ]
    }

    private func posting(
        id: String,
        title: String,
        time: String,
        location: String,
        category: EventCategory,
        interestID: String
    ) -> ForYouPosting {
        let interest = Interests.all.first { $0.id == interestID }
        return ForYouPosting(
            id: id,
            title: title,
            eventDate: "2026-08-08",
            startTime: time,
            location: location,
            category: category,
            startsAt: Date(timeIntervalSince1970: 1_786_000_000),
            matchedInterest: ForYouInterestTag(
                id: interestID,
                label: interest?.label ?? interestID,
                categories: [category]
            ),
            overlapCount: 1
        )
    }

    private var sampleSpotlight: BriefingSpotlight {
        BriefingSpotlight(
            id: "gallery-spotlight",
            slug: "wobegon-trailhead",
            title: "Wobegon Trailhead",
            blurb: "A shady starting point for an easy evening ride, with downtown coffee and a quiet bench only a few blocks away.",
            imageUrl: nil,
            placeId: "wobegon"
        )
    }

    private var sampleCaughtUp: BriefingCaughtUp {
        BriefingCaughtUp(
            nextBriefingAt: Date(timeIntervalSince1970: 1_786_003_200),
            label: "New briefing at 6 AM"
        )
    }

    private func triviaQuestion(
        myAnswer: Int? = nil,
        stats: TriviaStats? = nil,
        streakCount: Int? = nil
    ) -> TriviaQuestion {
        TriviaQuestion(
            id: "gallery-trivia",
            prompt: "Which river runs through Millstream Park?",
            options: ["Sauk River", "Watab River", "Mississippi River", "Rum River"],
            correctIndex: 1,
            myAnswer: myAnswer,
            stats: stats,
            streakCount: streakCount
        )
    }
}
#endif
