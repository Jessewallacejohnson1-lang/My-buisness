//
//  EventCardPhotoTapTests.swift
//  Block Party — one photo, two gestures: a Town event card's photo opens the event
//  page on a single tap and likes on a double tap, never both.
//
//  The photo sits inside the card's link and carries its own double-tap recognizer
//  (`PhotoDoubleTap`), which the link waits on: a single tap pushes once that
//  recognizer's window has closed, a double tap likes instead. With the recognizer
//  removed, the double-tap test fails (the page pushes). The simulator automation used
//  for screenshots cannot send two taps close enough to count as a double tap, so the
//  split is proven here, with XCUITest's own `doubleTap()`.
//
//  Also here: an edge swipe over the event page's photo carousel pops the page.
//
//  Run on the "BlockParty Tests" simulator, never the screenshot one (`sim-guard.sh`).
//

import XCTest

final class EventCardPhotoTapTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Every event page gets a second, bundled photo instead of Google's, so the edge
        // swipe below always has a carousel to start on, network or not.
        app.launchArguments = ["-open-tab", "town", "-town-samples", "-event-page-two-photos", "-ui-tests"]
        app.launch()
    }

    /// The first event card's link: host row and photo.
    private func firstCardLink() -> XCUIElement {
        let link = app.buttons["event-card-link"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "no event card on Town")
        return link
    }

    /// The link's middle is its photo: the host row above is well under a fifth of its
    /// height.
    private func photo(of link: XCUIElement) -> XCUICoordinate {
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// The heart in the action row directly under that card.
    private func likeButton(under link: XCUIElement) -> XCUIElement? {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Like,'"))
            .allElementsBoundByIndex
            .first { $0.frame.minY >= link.frame.maxY }
    }

    /// Pushed = Town's card is no longer on screen to be tapped. A push waits out the
    /// photo's double-tap window first, and GitHub's runner can be far slower than a Mac:
    /// on 2026-10-17 one look-up of the card took 31 s there, and the page wasn't up 2 s
    /// after the tap. The wait ends as soon as the page is up, so a long one costs nothing.
    private func waitForPush(from link: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let gone = NSPredicate(format: "exists == false OR hittable == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: link)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func testDoubleTapOnPhotoLikesAndDoesNotPush() throws {
        let link = firstCardLink()
        let like = try XCTUnwrap(likeButton(under: link), "no heart under the first card")
        XCTAssertEqual(like.value as? String, "Not liked")

        photo(of: link).doubleTap()

        XCTAssertFalse(waitForPush(from: link, timeout: 2), "a double tap on the photo pushed the event page")
        XCTAssertEqual(like.value as? String, "Liked")
    }

    func testSingleTapOnPhotoPushesTheEventPage() {
        let link = firstCardLink()

        photo(of: link).tap()

        XCTAssertTrue(waitForPush(from: link), "a single tap on the photo did not push the event page")
    }

    /// A card with two photos swipes between them under the finger and never opens its page;
    /// the dots under it say the second is up; a single tap then still opens the page; a drag
    /// up that starts on the photo scrolls the feed (BP app event-card 02).
    /// `-event-page-two-photos` gives the first card a second photo.
    func testASwipeOnThePhotoPagesAndADragUpScrolls() {
        let link = firstCardLink()
        let dots = app.otherElements["card-photo-dots"].firstMatch
        XCTAssertTrue(dots.waitForExistence(timeout: 10), "no dots under a two-photo card")
        XCTAssertEqual(dots.label, "Photo 1 of 2")

        link.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
            .press(forDuration: 0.05, thenDragTo: link.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.55)))
        XCTAssertFalse(waitForPush(from: link, timeout: 2), "a swipe on the photo pushed the event page")
        let second = NSPredicate(format: "label == 'Photo 2 of 2'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: second, object: dots)], timeout: 5),
                       .completed, "the swipe didn't bring the second photo up")

        let top = link.frame.minY
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        XCTAssertFalse(waitForPush(from: link, timeout: 2), "a drag up on the photo pushed the event page")
        XCTAssertLessThan(link.frame.minY, top - 50, "a drag up that started on the photo didn't scroll the feed")
    }

    /// The event page hides the navigation bar, and UIKit then turns its edge swipe off.
    /// `SwipeBack` turns it back on and puts it ahead of the photo carousel, so an edge
    /// swipe that starts on the hero pops the page instead of rubber-banding the photos.
    /// At the root the same swipe has nothing to pop and must leave the stack pushable.
    /// Proven here because AXe's simulated touches never start a screen-edge swipe; the
    /// drags XCUITest synthesizes do. With `SwipeBack`'s edge half removed, this fails.
    func testEdgeSwipeOverTheHeroPopsAndTheRootStillPushes() {
        let link = firstCardLink()

        // Across the top bar, clear of the card, whose link would take the touch.
        edgeSwipe(atHeight: 0.12)
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertTrue(waitForPush(from: link), "a swipe at the root froze the stack")

        // The carousel only scrolls with two photos; `-event-page-two-photos` gives it two.
        let twoPhotos = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value BEGINSWITH 'Photo 1 of 2'")).firstMatch
        XCTAssertTrue(twoPhotos.waitForExistence(timeout: 10), "no two-photo carousel to swipe over")

        // The pop itself is quick; checking for it is not. On GitHub's runner each look at the
        // screen can take seconds, and on 2026-10-17 the page popped but the one look a 4 s
        // wait had room for came before the Town card was back.
        edgeSwipe(atHeight: 0.22)
        let back = NSPredicate(format: "exists == true AND hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: link)], timeout: 15),
                       .completed, "an edge swipe on the hero did not pop the page")
    }

    /// A finger from the screen's leading edge, most of the way across. 0.22 of the height
    /// is on the event page's hero (y 200 of 912 pt).
    private func edgeSwipe(atHeight y: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: y))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y)))
    }
}
