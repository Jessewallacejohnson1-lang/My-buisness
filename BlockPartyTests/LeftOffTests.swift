//
//  LeftOffTests.swift
//  BlockPartyTests — back after iOS shut the app down, it opens as you left it; swiped away or
//  long gone, it starts fresh (BP app backlog 21).
//

import XCTest
@testable import BlockParty

@MainActor
final class LeftOffTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func left(at: Date? = nil, feed: [String] = [], top: String? = nil, y: CGFloat = 0,
                      poster: String? = nil) -> LeftOff {
        LeftOff(at: at ?? now, scene: "scene", tab: Tab.search.rawValue, event: "e2", eventY: 340,
                feed: feed, top: top, feedY: y, poster: poster)
    }

    private func entry(_ id: String, leavesIn hours: Double = 24) -> TownFeedEntry {
        let event = UpcomingEvent(id: id, title: "Event \(id)", eventDate: "2026-10-12", startTime: "6 PM",
                                  location: nil, goingCount: 0, createdAt: "2026-10-06T16:08:20+00:00",
                                  clubName: nil, sourceName: "City of St. Joseph")
        return TownFeedEntry(card: FeedCardItem(event), leavesAt: now.addingTimeInterval(hours * 3600))
    }

    private func ids(_ feed: TownFeed) -> [String] { feed.shown.map(\.id) }

    // MARK: When it comes back

    func testBackInsideTheLimitToTheSameSceneComesBack() {
        let spot = left(at: now.addingTimeInterval(-(TownFeed.awayLimit - 1)))
        XCTAssertTrue(spot.usable(now: now, scenes: ["scene"]))
    }

    func testTheLimitAndPastItStartFresh() {
        XCTAssertFalse(left(at: now.addingTimeInterval(-TownFeed.awayLimit)).usable(now: now, scenes: ["scene"]))
        XCTAssertFalse(left(at: now.addingTimeInterval(-3600)).usable(now: now, scenes: ["scene"]))
    }

    /// Swiping the app away ends its scene, so the next launch has another.
    func testSwipedAwayStartsFresh() {
        XCTAssertFalse(left().usable(now: now, scenes: ["another"]))
        XCTAssertFalse(left().usable(now: now, scenes: []))
    }

    /// A phone whose clock moved back mustn't call a spot from "the future" recent.
    func testAClockMovedBackStartsFresh() {
        XCTAssertFalse(left(at: now.addingTimeInterval(60)).usable(now: now, scenes: ["scene"]))
    }

    func testItSurvivesThePhoneAndClears() {
        addTeardownBlock { await MainActor.run { LeftOff.clear() } }
        let spot = left(feed: ["e1", "e2"], top: "e2", y: 812, poster: "e9")
        LeftOff.save(spot)
        XCTAssertEqual(LeftOff.saved(), spot)
        LeftOff.clear()
        XCTAssertNil(LeftOff.saved())
    }

    /// Signing out takes it with the kept feed, so the next account starts fresh.
    func testSigningOutClearsIt() {
        LeftOff.save(left())
        TownFeedCache.clear()
        XCTAssertNil(LeftOff.saved())
    }

    /// A test run never comes back to whatever the simulator's last run left.
    func testATestRunNeverComesBack() {
        XCTAssertNil(LeftOff.current)
        XCTAssertFalse(LeftOff.reopening("e2"))
    }

    // MARK: The feed

    /// The kept copy is the last read's answer, not what was on screen: the list comes back in the
    /// order you left it, without what you hid, which the saved ids leave out.
    func testAResumedFeedIsTheListYouLeftInItsOrder() {
        let feed = TownFeed(read: { [] }, kept: { [self.entry("e1"), self.entry("e2"), self.entry("e3"), self.entry("hid")] })
        feed.resume(left(at: now.addingTimeInterval(-60), feed: ["e3", "e1", "e2"], top: "e1", y: 900), at: now)
        XCTAssertEqual(ids(feed), ["e3", "e1", "e2"])
        XCTAssertEqual(feed.returnY, 900)
        XCTAssertEqual(feed.returnRow, "event:e1")
    }

    /// Back inside the limit, the read behind the list changes no card's place.
    func testAResumedFeedTakesNoFreshOrder() async {
        let feed = TownFeed(read: { [self.entry("e2"), self.entry("e3"), self.entry("e1")] },
                            kept: { [self.entry("e1"), self.entry("e2"), self.entry("e3")] })
        feed.resume(left(at: now.addingTimeInterval(-60), feed: ["e1", "e2", "e3"]), at: now)
        feed.cameBack(at: now)
        await feed.refresh(at: now)
        XCTAssertEqual(ids(feed), ["e1", "e2", "e3"])
    }

    /// A list with nothing left to show waits on the read, as a first launch does.
    func testAResumedFeedWithNothingLeftReads() async {
        let feed = TownFeed(read: { [self.entry("new")] }, kept: { [self.entry("old", leavesIn: -1)] })
        feed.resume(left(at: now.addingTimeInterval(-60), feed: ["old"]), at: now)
        XCTAssertNil(feed.entries)
        feed.cameBack(at: now)
        await feed.refresh(at: now)
        XCTAssertEqual(ids(feed), ["new"])
    }

    /// The card that topped the screen goes with it, so a card gone since lands at the top.
    func testNoRowWhenTheTopCardHasGone() {
        let feed = TownFeed(read: { [] }, kept: { [self.entry("e1")] })
        feed.resume(left(at: now.addingTimeInterval(-60), feed: ["e1", "gone"], top: "gone", y: 900), at: now)
        XCTAssertNil(feed.returnRow)
    }

    /// Only the first screen skips the rise-in; a tab switch later rises as ever.
    func testOnlyTheFirstScreenCountsAsResumed() {
        let feed = TownFeed(read: { [] }, kept: { [self.entry("e1")] })
        XCTAssertFalse(feed.takeResumed())
        feed.resume(left(feed: ["e1"]), at: now)
        XCTAssertTrue(feed.takeResumed())
        XCTAssertFalse(feed.takeResumed())
    }

    /// Leaving keeps the first card on screen in the list's order, whichever reported first.
    func testLeavingKeepsTheTopCard() async {
        let feed = TownFeed(read: { [self.entry("e1"), self.entry("e2"), self.entry("e3")] })
        feed.cameBack(at: now)
        await feed.refresh(at: now)
        feed.cardOnScreen("e3", true, at: now)
        feed.cardOnScreen("e2", true, at: now)
        feed.left(at: now, viewGone: true)
        XCTAssertEqual(feed.spot.top, "e2")
        XCTAssertEqual(feed.spot.feed, ["e1", "e2", "e3"])
    }
}
