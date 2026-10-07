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

    /// The first event card's link: host row, photo and going line.
    private func firstCardLink() -> XCUIElement {
        let link = app.buttons["event-card-link"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "no event card on Town")
        return link
    }

    /// The link's middle is its photo: the host row above and the going line below
    /// are each well under a fifth of its height.
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

    /// Pushed = Town's card is no longer on screen to be tapped.
    private func waitForPush(from link: XCUIElement, timeout: TimeInterval) -> Bool {
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

        XCTAssertTrue(waitForPush(from: link, timeout: 3), "a single tap on the photo did not push the event page")
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
        XCTAssertTrue(waitForPush(from: link, timeout: 3), "a swipe at the root froze the stack")

        // The carousel only scrolls with two photos; `-event-page-two-photos` gives it two.
        let twoPhotos = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value BEGINSWITH 'Photo 1 of 2'")).firstMatch
        XCTAssertTrue(twoPhotos.waitForExistence(timeout: 10), "no two-photo carousel to swipe over")

        edgeSwipe(atHeight: 0.22)
        let back = NSPredicate(format: "exists == true AND hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: link)], timeout: 4),
                       .completed, "an edge swipe on the hero did not pop the page")
    }

    /// A finger from the screen's leading edge, most of the way across. 0.22 of the height
    /// is on the event page's hero (y 200 of 912 pt).
    private func edgeSwipe(atHeight y: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: y))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y)))
    }
}
