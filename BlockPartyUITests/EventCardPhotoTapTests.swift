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

    /// A point on the card's photo, `y` points below the link's top (the host row is 42 pt), and
    /// `x` a fraction of its width. Points from the top, not a fraction of its height: on GitHub's
    /// iPhone 17 (874 pt tall) the first card runs under the tab bar, and its middle sat behind it
    /// (event-card 06, 99d825e: the swipe and the drag up started on the tab bar).
    private func photo(of link: XCUIElement, x: CGFloat = 0.5, y: CGFloat = 120) -> XCUICoordinate {
        link.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0)).withOffset(CGVector(dx: 0, dy: y))
    }

    /// The heart in that card's photo, bottom right (event-card 06).
    private func likeButton(under link: XCUIElement) -> XCUIElement? {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Like,'"))
            .allElementsBoundByIndex
            .first { link.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    /// Pushed = the Event page is up. A push waits out the photo's double-tap window first, and
    /// GitHub's runner can be far slower than a Mac: on 2026-10-17 one look-up of the card took
    /// 31 s there. The wait ends as soon as the page is up, so a long one costs nothing.
    /// Not "the card isn't hittable": with the card's middle under the tab bar, XCTest can't
    /// work out whether it's hittable and fails the test (GitHub, 99d825e).
    private func waitForPush(from link: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        pageOpened(timeout: timeout)
    }

    /// The Event page is up: its own Back button shows. A drag up that scrolls Town's card
    /// under the top bar leaves the card unhittable, which `waitForPush` would read as a push
    /// (GitHub, a6a2298 and b0f753d, 2026-10-20).
    private func pageOpened(timeout: TimeInterval) -> Bool {
        app.buttons["Back"].waitForExistence(timeout: timeout)
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
        XCTAssertTrue(pageOpened(timeout: 15), "the pushed page has no Back button for the swipe test to look for")
    }

    /// A card with two photos swipes between them under the finger and never opens its page;
    /// the dots under it say the second is up; a single tap then still opens the page; a drag
    /// up that starts on the photo scrolls the feed (BP app event-card 02).
    /// `-event-page-two-photos` gives the first card a second photo.
    func testASwipeOnThePhotoPagesAndADragUpScrolls() {
        let link = firstCardLink()
        XCTAssertEqual(link.value as? String, "Photo 1 of 2", "the first card has no second photo to swipe to")

        photo(of: link, x: 0.85).press(forDuration: 0.05, thenDragTo: photo(of: link, x: 0.1))
        XCTAssertFalse(pageOpened(timeout: 2), "a swipe on the photo pushed the event page")
        // Ends as soon as the dots say so; GitHub's runner takes seconds over each look.
        let second = NSPredicate(format: "value == 'Photo 2 of 2'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: second, object: link)], timeout: 15),
                       .completed, "the swipe didn't bring the second photo up")

        let top = link.frame.minY
        photo(of: link, y: 120).press(forDuration: 0.05, thenDragTo: photo(of: link, y: -80))
        XCTAssertFalse(pageOpened(timeout: 2), "a drag up on the photo pushed the event page")
        XCTAssertLessThan(link.frame.minY, top - 50, "a drag up that started on the photo didn't scroll the feed")
    }

    /// A swipe that starts on the title over the photo's bottom pages too: the shade and the words
    /// there used to catch the finger, and the swipe opened nothing or the page (Jesse, 2026-10-23).
    func testASwipeOnTheTitlePagesThePhoto() {
        let link = firstCardLink()
        XCTAssertEqual(link.value as? String, "Photo 1 of 2", "the first card has no second photo to swipe to")
        let title = app.staticTexts["Music in Millstream Park"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "no title on the first card")

        title.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: title.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)))
        XCTAssertFalse(pageOpened(timeout: 2), "a swipe on the title pushed the event page")
        let second = NSPredicate(format: "value == 'Photo 2 of 2'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: second, object: link)], timeout: 15),
                       .completed, "a swipe on the title didn't bring the second photo up")
    }

    /// A card with one photo: a sideways swipe on it rubber-bands and opens nothing (it used to
    /// open the Event page as if it were a tap), and a tap then still opens the page.
    func testASidewaysSwipeOnAOnePhotoCardOpensNothing() {
        app.terminate()
        app.launchArguments = ["-open-tab", "town", "-town-samples", "-ui-tests"]
        app.launch()
        let link = firstCardLink()
        XCTAssertEqual(link.value as? String ?? "", "", "the first sample card has more than one photo")

        photo(of: link, x: 0.85).press(forDuration: 0.05, thenDragTo: photo(of: link, x: 0.1))
        XCTAssertFalse(waitForPush(from: link, timeout: 2), "a sideways swipe on a one-photo card opened its page")

        photo(of: link).tap()
        XCTAssertTrue(waitForPush(from: link), "a tap after the swipe did not open the page")
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
