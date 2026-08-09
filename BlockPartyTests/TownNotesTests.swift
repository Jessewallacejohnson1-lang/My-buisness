//
//  TownNotesTests.swift
//  BlockPartyTests — the finite Town Notes deck contract.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownNotesTests: XCTestCase {
    func testDailySelectorHardCapsAtFive() {
        let stories = (0..<7).map { index in
            makeStory(id: "story-\(index)", publishedAt: Date(timeIntervalSince1970: Double(index)))
        }

        let selected = TownNewsAPI.dailyStories(from: stories)

        XCTAssertEqual(selected.count, 5)
    }

    func testDailySelectorExcludesCivicCategories() {
        let stories = [
            makeStory(id: "school", category: "school"),
            makeStory(id: "campus", category: "campus"),
            makeStory(id: "business", category: "business"),
            makeStory(id: "event", category: "event"),
            makeStory(id: "road", category: "road"),
            makeStory(id: "announcement", category: "announcement"),
        ]

        let selected = TownNewsAPI.dailyStories(from: stories)

        XCTAssertEqual(Set(selected.map(\.category)), ["school", "campus", "business", "event"])
    }

    func testDailySelectorOrdersNewestFirst() {
        let stories = [
            makeStory(id: "oldest", publishedAt: Date(timeIntervalSince1970: 1)),
            makeStory(id: "newest", publishedAt: Date(timeIntervalSince1970: 3)),
            makeStory(id: "middle", publishedAt: Date(timeIntervalSince1970: 2)),
        ]

        let selected = TownNewsAPI.dailyStories(from: stories)

        XCTAssertEqual(selected.map(\.id), ["newest", "middle", "oldest"])
    }

    func testZeroStoriesMakesModuleEmpty() async {
        let module = TownNotesModule(
            storiesLoader: { _, _ in [] },
            sweepLoader: { _, _ in nil }
        )

        await module.load(makeContext())

        XCTAssertEqual(module.phase, .empty)
    }

    func testStoryWithoutSourceURLHasNoReadAction() {
        let story = makeStory(id: "unlinked", sourceURL: nil)

        XCTAssertNil(story.readActionTitle)
    }

    func testNilSweepMetadataProducesNoSweepLine() async {
        let module = TownNotesModule(
            storiesLoader: { _, _ in [self.makeStory(id: "one")] },
            sweepLoader: { _, _ in nil }
        )

        await module.load(makeContext())

        XCTAssertNil(module.sweepLine)
    }

    private func makeContext() -> FeedModuleContext {
        FeedModuleContext(
            auth: AuthStore(),
            briefing: BriefingModel(),
            displayName: "Jesse",
            navigate: { _ in }
        )
    }

    private func makeStory(
        id: String,
        category: String = "school",
        publishedAt: Date = Date(timeIntervalSince1970: 10),
        sourceURL: URL? = URL(string: "https://example.com/story")
    ) -> NewsStory {
        NewsStory(
            id: id,
            headline: "Fixture headline \(id)",
            summary: "A clearly marked test summary.",
            sourceName: "Test source",
            sourceURL: sourceURL,
            publishedAt: publishedAt,
            category: category,
            imageURL: nil,
            fetchedAt: nil
        )
    }
}
