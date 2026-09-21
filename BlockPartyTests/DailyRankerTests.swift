//
//  DailyRankerTests.swift
//  Block Party — the Daily feed's ordering.
//

import XCTest
@testable import BlockParty

@MainActor
final class DailyRankerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Builders

    private func posting(
        _ id: String,
        hoursAgo: Double = 1,
        likes: Int = 0,
        comments: Int = 0,
        saves: Int = 0,
        followed: Bool = false,
        friend: Bool = false,
        followedLikers: Int = 0,
        followedCount: Int = 20
    ) -> DailyFeedItem {
        .posting(
            PostingItem(
                id: id,
                authorName: id,
                authorAvatar: nil,
                createdAt: now.addingTimeInterval(-hoursAgo * 3600),
                image: .fallback,
                caption: "",
                likeCount: likes,
                commentCount: comments,
                isLiked: false,
                isSaved: false,
                signals: FeedSignals(
                    isFollowed: followed,
                    isFriend: friend,
                    followedLikerCount: followedLikers,
                    followedCount: followedCount,
                    saveCount: saves
                )
            )
        )
    }

    private func event(
        _ id: String,
        hoursUntil: Double,
        postedHoursAgo: Double = 24,
        likes: Int = 0,
        followed: Bool = false
    ) -> DailyFeedItem {
        let item = FeedCardItem(
            id: id,
            title: id,
            dateChip: "",
            metaLine: "",
            image: .fallback,
            recurrence: nil,
            goingCount: 0,
            goingAvatars: [],
            goingSummary: "",
            likeCount: 0,
            isLiked: false,
            isSaved: false,
            isJoined: false
        )
        return .event(
            item,
            signals: FeedSignals(
                isFollowed: followed,
                followedCount: 20,
                createdAt: now.addingTimeInterval(-postedHoursAgo * 3600),
                likeCount: likes,
                startsAt: now.addingTimeInterval(hoursUntil * 3600)
            )
        )
    }

    private func ids(_ items: [DailyFeedItem]) -> [String] {
        DailyRanker.rank(items, now: now).map(\.id)
    }

    // MARK: - Tests

    func testFriendsOlderPostOutranksAStrangersNewerPost() {
        let friend = posting("friend", hoursAgo: 6, likes: 10, friend: true)
        let stranger = posting("stranger", hoursAgo: 1, likes: 10)

        XCTAssertEqual(ids([stranger, friend]), ["posting:friend", "posting:stranger"])
    }

    func testHeavySocialProofOutranksAFriendWithNone() {
        // A stranger 8 of your 10 follows have thumbed, against a friend nobody did.
        let proven = posting(
            "proven", hoursAgo: 3, likes: 12,
            followedLikers: 8, followedCount: 10
        )
        let friend = posting("friend", hoursAgo: 3, likes: 12, friend: true)

        XCTAssertEqual(ids([friend, proven]), ["posting:proven", "posting:friend"])
    }

    func testFinishedEventIsDropped() {
        let over = event("over", hoursUntil: -2)
        let soon = event("soon", hoursUntil: 4)

        XCTAssertEqual(ids([over, soon]), ["event:soon"])
    }

    func testTonightsEventOutranksTheSameEventThreeWeeksOut() {
        // Identical but for when they happen — and both posted at the same moment,
        // so recency cannot be what separates them.
        let tonight = event("tonight", hoursUntil: 5, postedHoursAgo: 10, likes: 30)
        let later = event("later", hoursUntil: 24 * 21, postedHoursAgo: 10, likes: 30)

        XCTAssertEqual(ids([later, tonight]), ["event:tonight", "event:later"])
    }

    func testEqualScoresKeepInputOrder() {
        // Two identical postings: the ranking must not reshuffle them, or a refresh
        // that changed nothing would visibly jump the screen.
        let first = posting("first", hoursAgo: 2, likes: 5)
        let second = posting("second", hoursAgo: 2, likes: 5)

        XCTAssertEqual(ids([first, second]), ["posting:first", "posting:second"])
        XCTAssertEqual(ids([second, first]), ["posting:second", "posting:first"])
    }

    // MARK: - Term behaviour

    func testCommentsAndSavesCountForMoreThanThumbs() {
        let thumbs = posting("thumbs", likes: 6)
        let saves = posting("saves", saves: 6)

        XCTAssertGreaterThan(
            DailyRanker.score(saves, now: now),
            DailyRanker.score(thumbs, now: now)
        )
    }

    func testSocialProofIsARatioNotACount() {
        // 3 of 6 beats 4 of 40: following more people must not dilute your signal.
        let small = posting("small", followedLikers: 3, followedCount: 6)
        let large = posting("large", followedLikers: 4, followedCount: 40)

        XCTAssertGreaterThan(
            DailyRanker.score(small, now: now),
            DailyRanker.score(large, now: now)
        )
    }

    func testAPostFromTheFutureDoesNotOutscoreABrandNewOne() {
        // Clock skew must not be a ranking exploit.
        let future = posting("future", hoursAgo: -5)
        let fresh = posting("fresh", hoursAgo: 0)

        XCTAssertEqual(
            DailyRanker.score(future, now: now),
            DailyRanker.score(fresh, now: now),
            accuracy: 0.0001
        )
    }

    func testEmptyInputRanksToEmpty() {
        XCTAssertTrue(DailyRanker.rank([], now: now).isEmpty)
    }

    // MARK: - Card header

    func testRelativeLabelBuckets() {
        XCTAssertEqual(PostingCard.relativeLabel(for: now, now: now), "now")
        XCTAssertEqual(PostingCard.relativeLabel(for: now.addingTimeInterval(-600), now: now), "10m")
        XCTAssertEqual(PostingCard.relativeLabel(for: now.addingTimeInterval(-4 * 3600), now: now), "4h")
        XCTAssertEqual(PostingCard.relativeLabel(for: now.addingTimeInterval(-3 * 86400), now: now), "3d")
        XCTAssertEqual(PostingCard.relativeLabel(for: now.addingTimeInterval(-21 * 86400), now: now), "3w")
    }
}
