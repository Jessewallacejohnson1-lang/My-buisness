//
//  TownNotesModule.swift
//  Block Party — independently fetched, finite local-news module for Today.
//

import Combine
import SwiftUI

extension FeedModuleID {
    static let townNotes: FeedModuleID = "townNotes"
}

struct TownNotesSweepMetadata: Equatable, Sendable {
    let sourceCount: Int
    let lastSweptAt: Date

    var line: String {
        let noun = sourceCount == 1 ? "source" : "sources"
        return "\(sourceCount) \(noun) checked · Last sweep at \(TownNewsDate.time(lastSweptAt))"
    }
}

@MainActor
final class TownNotesModule: FeedModule {
    typealias StoriesLoader = @MainActor (Date, AuthStore) async throws -> [NewsStory]
    typealias SweepLoader = @MainActor (
        Date,
        AuthStore
    ) async throws -> (sourceCount: Int, lastSweptAt: Date)?

    let id: FeedModuleID = .townNotes
    let order = 3
    let ownsFetch = true

    @Published private(set) var phase: FeedPhase = .loading
    @Published private(set) var stories: [NewsStory] = []
    @Published private(set) var sweepMetadata: TownNotesSweepMetadata?

    private let storiesLoader: StoriesLoader
    private let sweepLoader: SweepLoader

    #if DEBUG
    private var debugInitialExpandedStoryID: String?
    private var debugStartsAtCaughtUp = false
    #endif

    init(
        storiesLoader: StoriesLoader? = nil,
        sweepLoader: SweepLoader? = nil
    ) {
        self.storiesLoader = storiesLoader ?? { date, auth in
            try await TownNewsAPI(auth: auth).fetchDailyStories(date)
        }
        self.sweepLoader = sweepLoader ?? { date, auth in
            try await TownNewsAPI(auth: auth).sweepMetadata(date)
        }
    }

    var sweepLine: String? {
        sweepMetadata?.line
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool {
        #if DEBUG
        if FeedDebugFocus.isHidden(id) { return false }
        #endif
        return true
    }

    func load(_ ctx: FeedModuleContext) async {
        #if DEBUG
        if applyDebugSeedIfRequested() { return }
        #endif

        phase = .loading
        let date = Date()

        do {
            stories = TownNewsAPI.dailyStories(
                from: try await storiesLoader(date, ctx.auth)
            )
        } catch {
            Log.network("town notes load failed: \(error.localizedDescription)")
            stories = []
            sweepMetadata = nil
            phase = .failed
            return
        }

        do {
            if let metadata = try await sweepLoader(date, ctx.auth) {
                sweepMetadata = TownNotesSweepMetadata(
                    sourceCount: metadata.sourceCount,
                    lastSweptAt: metadata.lastSweptAt
                )
            } else {
                sweepMetadata = nil
            }
        } catch {
            // Provenance is additive. A sweep-table read must never hide real
            // stories or tempt the client to invent a replacement count.
            Log.network("town notes sweep metadata failed: \(error.localizedDescription)")
            sweepMetadata = nil
        }

        phase = stories.isEmpty ? .empty : .ready
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                TownNotesSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .failed:
            return AnyView(
                FeedUnavailableCard(title: FeedStateCopy.townNotesUnavailable) {
                    Task { await self.load(ctx) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            )

        case .ready:
            #if DEBUG
            let initialExpandedStoryID = debugInitialExpandedStoryID
            let startsAtCaughtUp = debugStartsAtCaughtUp
            #else
            let initialExpandedStoryID: String? = nil
            let startsAtCaughtUp = false
            #endif

            return AnyView(
                TownNotesDeck(
                    stories: stories,
                    sweepLine: sweepLine,
                    initialExpandedStoryID: initialExpandedStoryID,
                    startsAtCaughtUp: startsAtCaughtUp
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(
                    2,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
            )

        case .empty:
            return AnyView(EmptyView())
        }
    }
}

#if DEBUG
private extension TownNotesModule {
    /// Every Town Notes launch flag bypasses auth/network and uses this visibly
    /// labelled fixture set. The production loaders remain untouched.
    func applyDebugSeedIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        let isEmpty = args.contains("-townnotes-empty")
        let isLoading = args.contains("-townnotes-loading")
        let isError = args.contains("-townnotes-error")
        let isExpanded = args.contains("-townnotes-expanded")
        let isCaughtUp = args.contains("-townnotes-caughtup")
        let isSample = args.contains("-townnotes-sample")
        guard isEmpty || isLoading || isError || isExpanded || isCaughtUp || isSample
        else { return false }

        sweepMetadata = nil
        debugInitialExpandedStoryID = nil
        debugStartsAtCaughtUp = false

        if isEmpty {
            stories = []
            phase = .empty
            return true
        }

        if isLoading {
            stories = []
            phase = .loading
            return true
        }

        if isError {
            stories = []
            phase = .failed
            return true
        }

        let fixtureStories = Self.debugStories
        stories = isCaughtUp ? Array(fixtureStories.prefix(1)) : fixtureStories
        debugInitialExpandedStoryID = isExpanded ? stories.first?.id : nil
        debugStartsAtCaughtUp = isCaughtUp
        phase = .ready
        return true
    }

    static var debugStories: [NewsStory] {
        let now = Date()
        return [
            NewsStory(
                id: "townnotes-debug-school",
                headline: "School board shares its first-week welcome plan",
                summary: "This is a clearly marked Town Notes fixture. Families will see a calmer arrival route and a short welcome window before classes begin.",
                sourceName: "DEBUG fixture",
                sourceURL: URL(string: "https://example.com/town-notes-school"),
                publishedAt: now.addingTimeInterval(-38 * 60),
                category: "school",
                imageURL: nil,
                fetchedAt: now
            ),
            NewsStory(
                id: "townnotes-debug-campus",
                headline: "Saint Ben’s opens a new student gathering room",
                summary: "This is a clearly marked Town Notes fixture. The room gives student groups a shared place for meetings, study breaks, and small campus events.",
                sourceName: "DEBUG fixture",
                sourceURL: URL(string: "https://example.com/town-notes-campus"),
                publishedAt: now.addingTimeInterval(-75 * 60),
                category: "campus",
                imageURL: Bundle.main.url(forResource: "saint-bens", withExtension: "jpg"),
                fetchedAt: now
            ),
            NewsStory(
                id: "townnotes-debug-business",
                headline: "A new lunch counter is taking shape downtown",
                summary: "This is a clearly marked Town Notes fixture. The owners plan a small weekday menu and expect to share opening hours later this month.",
                sourceName: "DEBUG fixture",
                sourceURL: nil,
                publishedAt: now.addingTimeInterval(-2 * 60 * 60),
                category: "business",
                imageURL: nil,
                fetchedAt: now
            ),
        ]
    }
}
#endif
