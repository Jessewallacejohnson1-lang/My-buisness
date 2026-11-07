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
        // 3.8 s on a phone, and the app shows within 6 s whatever happens. A fixed wait, because
        // XCUITest still lists the finished launch's element (hidden from VoiceOver, untouchable)
        // and never sees it go: the tap below is the proof that it went.
        Thread.sleep(forTimeInterval: 9)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 120)).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 15), "Town's card didn't open after the launch")
    }

    /// Once the yellow is mostly gone, a tap goes through to Town under the glide; before that the
    /// launch takes it (Jesse, 2026-11-02). Held moments (`-launch-at`, the mock's time): 1850 is
    /// in the leap with the yellow gone but the launch not done (LaunchMotionTests checks both),
    /// 1000 is the ! hopping on full yellow.
    func testATapLateInTheGlideReachesTown() {
        continueAfterFailure = false
        for (moment, opens) in [("1850", true), ("1000", false)] {
            let app = XCUIApplication()
            app.launchArguments = ["-open-tab", "town", "-town-samples", "-ui-tests", "-launch-play",
                                   "-launch-at", moment, "-daily-samples", "-daily-hour", "12"]
            app.launch()
            let card = app.buttons["event-card-link"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "no event card on Town")
            Thread.sleep(forTimeInterval: 2)
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 120)).tap()
            XCTAssertEqual(app.buttons["Back"].waitForExistence(timeout: opens ? 15 : 4), opens,
                           opens ? "a tap late in the glide didn't reach Town" : "a tap on the yellow went through to Town")
            app.terminate()
        }
    }
}
