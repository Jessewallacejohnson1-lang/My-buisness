//
//  OnboardingNextBarTests.swift
//  Block Party — onboarding's locked rule (ONBOARDING.md): the Next bar never moves. Walks
//  every question step and reads the bar's frame on each, then steps back once.
//
//  `-onboarding` shows the flow as a first launch would; the two `-onboarding.*` pairs set
//  its saved place, and `-bp.interests` its picks, through the launch arguments' defaults domain, so every run starts on the
//  Welcome even though the test runner keeps the app's data between runs.
//
//  Run on the "BlockParty Tests" simulator, never the screenshot one (`sim-guard.sh`).
//

import XCTest

final class OnboardingNextBarTests: XCTestCase {

    /// The progress bar, by what VoiceOver reads on it.
    private func bar(_ app: XCUIApplication, _ step: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step \(step) of 9")).firstMatch
    }

    func testNextBarHoldsStillOnEveryStep() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-tests", "-onboarding",
                               "-onboarding.step", "0", "-onboarding.finished", "NO",
                               "-bp.interests", "()"]
        app.launch()

        let phone = app.buttons["Continue with phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15), "no Welcome")
        phone.tap()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "no Next bar")
        let home = next.frame
        XCTAssertEqual(home.height, 52, accuracy: 0.5)

        // Phone (step 1) to Contacts (step 9): eight taps, the frame read after each.
        for step in 2...9 {
            if step == 7 {
                // Interests asks for 3 before it lets you on (ticket 20).
                XCTAssertEqual(next.label, "Pick 3 more")
                for name in ["Live music", "Coffee shops", "Campus"] { app.buttons[name].firstMatch.tap() }
                XCTAssertEqual(next.label, "Next")
            }
            next.tap()
            XCTAssertTrue(bar(app, step).waitForExistence(timeout: 3), "never reached step \(step)")
            XCTAssertEqual(next.frame, home, "Next bar moved on step \(step)")
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(bar(app, 8).waitForExistence(timeout: 3))
        XCTAssertEqual(next.frame, home, "Next bar moved going back")
    }
}
