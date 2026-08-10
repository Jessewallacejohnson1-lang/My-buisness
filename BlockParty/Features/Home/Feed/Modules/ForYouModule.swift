//
//  ForYouModule.swift
//  Block Party — independently fetched interest-matched postings for Today.
//

import Combine
import SwiftUI

extension FeedModuleID {
    static let forYou: FeedModuleID = "forYou"
}

@MainActor
final class ForYouModule: FeedModule {
    typealias ProfileLoader = @MainActor (AuthStore) async throws -> TownProfile?
    typealias EventsLoader = @MainActor (AuthStore) async throws -> [UpcomingEvent]
    typealias IDsLoader = @MainActor ([String], AuthStore) async throws -> Set<String>
    typealias PostingAction = @MainActor (String, AuthStore) async throws -> Void

    let id: FeedModuleID = .forYou
    let order = 4
    let ownsFetch = true

    @Published private(set) var phase: FeedPhase = .loading
    @Published private(set) var contentState: ForYouContentState = .loading
    @Published private(set) var postings: [ForYouPosting] = []

    private let profileLoader: ProfileLoader
    private let eventsLoader: EventsLoader
    private let savedIDsLoader: IDsLoader
    private let dismissedIDsLoader: IDsLoader
    private let joinAction: PostingAction
    private let saveAction: PostingAction
    private let dismissAction: PostingAction

    init(
        profileLoader: ProfileLoader? = nil,
        eventsLoader: EventsLoader? = nil,
        savedIDsLoader: IDsLoader? = nil,
        dismissedIDsLoader: IDsLoader? = nil,
        joinAction: PostingAction? = nil,
        saveAction: PostingAction? = nil,
        dismissAction: PostingAction? = nil
    ) {
        self.profileLoader = profileLoader ?? { auth in
            try await ProfileAPI(auth: auth).getMyProfile()
        }
        self.eventsLoader = eventsLoader ?? { auth in
            try await CommunityAPI(auth: auth).getUpcomingEvents()
        }
        self.savedIDsLoader = savedIDsLoader ?? { ids, auth in
            try await SocialAPI(auth: auth).savedEventIds(in: ids)
        }
        self.dismissedIDsLoader = dismissedIDsLoader ?? { ids, auth in
            try await PostingDismissalsAPI(auth: auth).dismissedPostingIDs(in: ids)
        }
        self.joinAction = joinAction ?? { id, auth in
            try await CommunityAPI(auth: auth).rsvpEvent(id)
        }
        self.saveAction = saveAction ?? { id, auth in
            try await SocialAPI(auth: auth).saveEvent(id)
        }
        self.dismissAction = dismissAction ?? { id, auth in
            try await PostingDismissalsAPI(auth: auth).dismissPosting(id)
        }
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool {
        #if DEBUG
        return !FeedDebugFocus.isHidden(id)
        #else
        return true
        #endif
    }

    func load(_ ctx: FeedModuleContext) async {
        #if DEBUG
        if applyDebugFixtureIfRequested() { return }
        #endif

        phase = .loading
        contentState = .loading
        postings = []

        do {
            let profile = try await profileLoader(ctx.auth)
            let user = ForYouUser(interestIDs: profile?.interests ?? [])
            let tags = ForYouRecommendations.userInterestTags(for: user)

            guard !tags.isEmpty else {
                contentState = .needsInterests
                phase = .ready
                return
            }

            let events = try await eventsLoader(ctx.auth)
            let eventIDs = events.map(\.id)
            async let savedIDs = savedIDsLoader(eventIDs, ctx.auth)
            async let dismissedIDs = dismissedIDsLoader(eventIDs, ctx.auth)
            let saved = try await savedIDs
            let dismissed = try await dismissedIDs

            let candidates = events.map { event in
                ForYouCandidate(
                    id: event.id,
                    title: event.title,
                    eventDate: event.eventDate,
                    startTime: event.startTime,
                    location: event.location,
                    category: event.category,
                    startsAt: Self.startDate(for: event),
                    rsvpd: event.rsvpd,
                    saved: saved.contains(event.id),
                    dismissed: dismissed.contains(event.id)
                )
            }

            postings = ForYouRecommendations.recommendedPostings(
                for: user,
                from: candidates,
                limit: 5
            )
            contentState = postings.isEmpty ? .noMatches : .recommendations
            phase = postings.isEmpty ? .empty : .ready
        } catch {
            Log.network("for you load failed: \(error.localizedDescription)")
            contentState = .failed
            phase = .failed
        }
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            AnyView(
                ForYouSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .failed:
            AnyView(
                FeedUnavailableCard(title: FeedLowerStateCopy.forYouUnavailable) {
                    Task { await self.load(ctx) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            )

        case .ready:
            AnyView(
                ForYouSection(
                    state: contentState,
                    postings: postings,
                    onSetInterests: { ctx.navigate(.editInterests) },
                    onJoin: { postingID in
                        Task { await self.join(postingID, auth: ctx.auth) }
                    },
                    onSave: { postingID in
                        Task { await self.save(postingID, auth: ctx.auth) }
                    },
                    onDismiss: { postingID in
                        Task { await self.dismiss(postingID, auth: ctx.auth) }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(
                    3,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
            )

        case .empty:
            AnyView(EmptyView())
        }
    }

    private func join(_ postingID: String, auth: AuthStore) async {
        await perform(postingID, auth: auth, action: joinAction, verb: "join")
    }

    private func save(_ postingID: String, auth: AuthStore) async {
        await perform(postingID, auth: auth, action: saveAction, verb: "save")
    }

    private func dismiss(_ postingID: String, auth: AuthStore) async {
        await perform(postingID, auth: auth, action: dismissAction, verb: "dismiss")
    }

    /// All three actions optimistically enforce the module's exclusion contract.
    /// A failed write restores the exact card at its prior position.
    private func perform(
        _ postingID: String,
        auth: AuthStore,
        action: PostingAction,
        verb: String
    ) async {
        guard let index = postings.firstIndex(where: { $0.id == postingID }) else {
            return
        }
        let posting = postings.remove(at: index)
        if postings.isEmpty {
            contentState = .noMatches
            phase = .empty
        }

        do {
            try await action(postingID, auth)
        } catch {
            Log.network("for you \(verb) failed: \(error.localizedDescription)")
            postings.insert(posting, at: min(index, postings.endIndex))
            contentState = .recommendations
            phase = .ready
        }
    }

    private static func startDate(for event: UpcomingEvent) -> Date {
        YourDayLogic.eventStart(for: event)
            ?? BriefingDate.parse(event.eventDate)
            ?? .distantFuture
    }
}

#if DEBUG
private extension ForYouModule {
    /// All three launch flags bypass auth/network and use clearly marked fixtures.
    func applyDebugFixtureIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let isSample = arguments.contains("-foryou-sample")
        let hasNoTags = arguments.contains("-foryou-no-tags")
        let isEmpty = arguments.contains("-foryou-empty")
        guard isSample || hasNoTags || isEmpty else { return false }

        if hasNoTags {
            postings = []
            contentState = .needsInterests
            phase = .ready
            return true
        }

        if isEmpty {
            postings = []
            contentState = .noMatches
            phase = .empty
            return true
        }

        let user = ForYouUser(
            interestIDs: ["sports_leagues", "live_music", "coffee"]
        )
        postings = ForYouRecommendations.recommendedPostings(
            for: user,
            from: Self.debugCandidates,
            limit: 5
        )
        contentState = .recommendations
        phase = .ready
        return true
    }

    static var debugCandidates: [ForYouCandidate] {
        let calendar = Town.calendar
        let today = calendar.startOfDay(for: Date())

        func start(dayOffset: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        }

        func dateString(_ date: Date) -> String {
            DateHelpers.localDate(date)
        }

        let soccer = start(dayOffset: 0, hour: 18)
        let music = start(dayOffset: 1, hour: 19)
        let coffee = start(dayOffset: 2, hour: 9)
        return [
            ForYouCandidate(
                id: "foryou-debug-soccer",
                title: "DEBUG fixture · Pickup soccer at Millstream",
                eventDate: dateString(soccer),
                startTime: "6:00 PM",
                location: "Millstream Park",
                category: .sports,
                startsAt: soccer,
                rsvpd: false,
                saved: false,
                dismissed: false
            ),
            ForYouCandidate(
                id: "foryou-debug-music",
                title: "DEBUG fixture · Songwriters on the patio",
                eventDate: dateString(music),
                startTime: "7:00 PM",
                location: "Downtown",
                category: .musicArts,
                startsAt: music,
                rsvpd: false,
                saved: false,
                dismissed: false
            ),
            ForYouCandidate(
                id: "foryou-debug-coffee",
                title: "DEBUG fixture · Saturday coffee tasting",
                eventDate: dateString(coffee),
                startTime: "9:00 AM",
                location: "Local Blend",
                category: .food,
                startsAt: coffee,
                rsvpd: false,
                saved: false,
                dismissed: false
            ),
        ]
    }
}
#endif
