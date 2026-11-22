//
//  EventOpenerTests.swift
//  BlockPartyTests — a Town card's Event page opened over the shell (BP app tab-lag 02, round 5): the page built
//  during the photo's double-tap wait, thrown away on a like, and the photo's way from the card to the page's top.
//

import XCTest
@testable import BlockParty

@MainActor
final class EventOpenerTests: XCTestCase {
    private let source = EventOpener.Source(box: CGRect(x: 16, y: 180, width: 370, height: 247), photo: nil)

    private func card(_ id: String) -> FeedCardItem {
        FeedCardItem(UpcomingEvent(id: id, title: "Music in Millstream Park", eventDate: "2033-05-18",
                                              startTime: "7:00 PM", location: "Millstream Park", goingCount: 41,
                                              createdAt: "2033-05-01T12:00:00Z", imageUrl: nil, rsvpd: false,
                                              clubName: nil, category: .outdoors))
    }

    override func tearDown() {
        AppearanceStore.shared.eventOver = false
        super.tearDown()
    }

    func testPreparedPageIsBuiltHiddenAndALikeThrowsItAway() {
        let opener = EventOpener()
        opener.prepare(card("a"), from: source)
        XCTAssertEqual(opener.item?.id, "a", "the page is built at the first lift")
        XCTAssertFalse(opener.isOpen, "but not shown: it doesn't move, take touches or reach VoiceOver")
        XCTAssertEqual(opener.progress.value, 0)
        opener.discard("a")
        XCTAssertNil(opener.item, "a double tap likes, and the hidden page goes")
    }

    func testOpenAfterPrepareCountsOnceAndMoves() {
        let opener = EventOpener()
        opener.reduceMotion = true
        var counted: [String] = []
        opener.counted = { counted.append($0) }
        opener.prepare(card("a"), from: source)
        XCTAssertEqual(counted, [], "building it hidden is no open")
        opener.open(card("a"), from: source)
        XCTAssertTrue(opener.isOpen)
        XCTAssertEqual(opener.progress.value, 1, "Reduce Motion: there at once")
        XCTAssertEqual(counted, ["a"])
        opener.discard("a")
        XCTAssertEqual(opener.item?.id, "a", "an open page is never thrown away as a like")
        XCTAssertTrue(AppearanceStore.shared.eventOver, "at rest the page's clock is its own")
    }

    func testCloseAndCloseNow() {
        let opener = EventOpener()
        opener.reduceMotion = true
        opener.open(card("a"), from: source)
        opener.close()
        XCTAssertNil(opener.item, "home, and nothing left over the shell")
        XCTAssertFalse(AppearanceStore.shared.eventOver, "Town holds its clock again")
        opener.open(card("b"), from: source)
        opener.closeNow()
        XCTAssertNil(opener.item, "a tab switch takes it away at once")
        XCTAssertEqual(opener.progress.value, 0)
    }

    func testPrepareWaitsForAnOpenPage() {
        let opener = EventOpener()
        opener.reduceMotion = true
        opener.open(card("a"), from: source)
        opener.prepare(card("b"), from: source)
        XCTAssertEqual(opener.item?.id, "a", "a lift on Town under an open page builds nothing")
    }

    func testTheCardStaysWholeUntilItsPhotoFlies() {
        let opener = EventOpener()
        opener.reduceMotion = true
        let photo = EventOpener.Source(box: source.box, photo: URL(string: "https://example.com/walk.jpg"))
        opener.prepare(card("a"), from: photo)
        XCTAssertFalse(opener.hidesCard("a"), "built during the wait, the card keeps its words and its press")
        opener.open(card("a"), from: photo)
        XCTAssertTrue(opener.hidesCard("a"), "its photo is the one flying")
        opener.close()
        XCTAssertFalse(opener.hidesCard("a"))
        opener.open(card("b"), from: source)
        XCTAssertFalse(opener.hidesCard("b"), "a card that grows its box stays under the page")
    }

    func testPhotoFliesFromTheCardToThePageTop() {
        let box = CGRect(x: 16, y: 180, width: 370, height: 247)
        let hero = CGRect(x: 0, y: 0, width: 402, height: 410)
        XCTAssertEqual(EventOpener.flight(from: box, to: hero, scrollY: 0, progress: 0), box)
        XCTAssertEqual(EventOpener.flight(from: box, to: hero, scrollY: 0, progress: 1), hero)
        XCTAssertEqual(EventOpener.flight(from: box, to: hero, scrollY: 100, progress: 1).minY, -100,
                       "scrolled down, it goes home from where the page's picture is")
        XCTAssertEqual(EventOpener.flight(from: box, to: hero, scrollY: 0, progress: 0.5).width, 386)
    }

    func testPageFadesInUnderThePhotoAndThePhotoHandsOver() {
        XCTAssertEqual(EventOpener.pageOpacity(0.2), 0)
        XCTAssertEqual(EventOpener.pageOpacity(0.85), 1, accuracy: 0.0001)
        XCTAssertEqual(EventOpener.pageOpacity(1.03), 1, "past its spot on the overshoot")
        XCTAssertEqual(EventOpener.photoOpacity(0.5), 1)
        XCTAssertEqual(EventOpener.photoOpacity(0.875), 0.5, accuracy: 0.0001)
        XCTAssertEqual(EventOpener.photoOpacity(1), 0, "at rest the page's own picture shows")
    }
}
