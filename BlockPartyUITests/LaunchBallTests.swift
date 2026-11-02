//
//  LaunchBallTests.swift
//  Block Party — after the launch the Town feed is there and answers a tap. The splash deleted on
//  2026-09-18 left the app black on every cold start while every test passed, because the tests
//  never saw it (docs/rules/swift-traps.md); this one plays the launch and waits it out.
//
//  Run on the "BlockParty Tests" simulator, never the screenshot one (`sim-guard.sh`).
//

import XCTest

final class LaunchBallTests: XCTestCase {

    /// The launch plays, and once it has gone a tap on Town's first card opens its Event page.
    /// A layer left over the app takes the tap and the page never opens (2026-11-01: an invisible
    /// launch layer did exactly that while every frame looked right).
    func testTownIsThereAndTappableAfterTheLaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // `-launch-play` plays the launch under `-ui-tests`, which otherwise skips it, and shows it
        // to XCUITest as the element `launch`.
        app.launchArguments = ["-open-tab", "town", "-town-samples", "-ui-tests", "-launch-play",
                               "-daily-samples", "-daily-hour", "12"]
        app.launch()
        XCTAssertTrue(app.otherElements["launch"].waitForExistence(timeout: 10), "the launch didn't play")

        let card = app.buttons["event-card-link"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no event card on Town")
        // 2.5 s on a phone, and the app shows within 6 s whatever happens; a slow runner gets 9.
        Thread.sleep(forTimeInterval: 9)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 120)).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 15), "Town's card didn't open after the launch")
    }
}
