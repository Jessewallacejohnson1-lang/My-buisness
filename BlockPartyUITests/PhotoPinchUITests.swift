//
//  PhotoPinchUITests.swift
//  Block Party — two fingers lift a photo where it sits and it lands back (BP app photo-zoom). A pinch
//  opens nothing, the feed still scrolls and a tap still opens the Event after one, and on the Event
//  page the buttons over the picture come back once it has landed. AXe can't pinch, so XCUITest's own
//  `pinch(withScale:velocity:)` proves it.
//
//  Run on the "BlockParty Tests" simulator, never the screenshot one (`sim-guard.sh`).
//

import XCTest

final class PhotoPinchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The samples, as EventCardPhotoTapTests: the poster and cards sit where they always do.
        app.launchArguments = ["-open-tab", "town", "-town-samples", "-ui-tests",
                               "-daily-samples", "-daily-hour", "12"]
        app.launch()
    }

    private func pageOpened(timeout: TimeInterval) -> Bool {
        app.buttons["Back"].waitForExistence(timeout: timeout)
    }

    /// A pinch on the poster opens nothing; after it the feed scrolls and a tap opens the Event.
    func testAPinchOpensNothingAndLeavesTheFeedWorking() {
        let poster = app.buttons["event-of-the-day-poster"]
        XCTAssertTrue(poster.waitForExistence(timeout: 10), "no poster on Town")

        poster.pinch(withScale: 2.5, velocity: 2)
        XCTAssertFalse(pageOpened(timeout: 2), "a pinch on the poster opened the Event page")

        let top = poster.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        XCTAssertLessThan(poster.frame.minY, top - 50, "after a pinch the feed didn't scroll")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        poster.tap()
        XCTAssertTrue(pageOpened(timeout: 15), "after a pinch a tap on the poster didn't open the Event page")
    }

    /// A Town card pinches as the poster does, and opens nothing.
    func testATownCardPinchesAndOpensNothing() {
        let link = app.buttons["event-card-link"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "no event card on Town")
        // Out from under the tab bar first.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        link.pinch(withScale: 2.5, velocity: 2)
        XCTAssertFalse(pageOpened(timeout: 2), "a pinch on a Town card opened the Event page")
    }

    /// On the Event page the picture pinches, and its Back comes back once it has landed.
    func testThePagePicturePinchesAndItsButtonsComeBack() {
        let poster = app.buttons["event-of-the-day-poster"]
        XCTAssertTrue(poster.waitForExistence(timeout: 10), "no poster on Town")
        poster.tap()
        XCTAssertTrue(pageOpened(timeout: 15), "the Event page didn't open")

        let picture = app.descendants(matching: .any)["event-page-picture"]
        XCTAssertTrue(picture.waitForExistence(timeout: 10), "no picture on the Event page")
        picture.pinch(withScale: 2.5, velocity: 2)
        XCTAssertTrue(pageOpened(timeout: 3), "Back didn't come back after the picture landed")
    }
}
