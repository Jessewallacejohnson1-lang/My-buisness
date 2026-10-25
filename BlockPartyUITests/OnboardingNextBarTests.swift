//
//  OnboardingNextBarTests.swift
//  Block Party — onboarding's locked rule (ONBOARDING.md): the Next bar never moves, except
//  to ride with the keyboard. Walks every question step and reads the bar's frame on each,
//  then steps back once. Name needs a first name to go on and Photo is skipped (ticket 18).
//
//  `-onboarding` shows the flow as a first launch would; the `-onboarding.*` pairs set its
//  saved place and name through the launch arguments' defaults domain, so every run starts
//  on the Welcome with no name even though the test runner keeps the app's data between runs.
//
//  Run on the "BlockParty Tests" simulator, never the screenshot one (`sim-guard.sh`).
//

import XCTest

final class OnboardingNextBarTests: XCTestCase {

    /// The progress bar, by what VoiceOver reads on it.
    private func bar(_ app: XCUIApplication, _ step: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step \(step) of 9")).firstMatch
    }

    /// The bar's frame once it has come to rest (the keyboard leaving carries it down).
    private func settled(_ next: XCUIElement, at home: CGRect) -> CGRect {
        let deadline = Date().addingTimeInterval(3)
        while next.frame != home, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        return next.frame
    }

    func testNextBarHoldsStillOnEveryStep() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-tests", "-onboarding",
                               "-onboarding.step", "0", "-onboarding.finished", "NO",
                               "-onboarding.firstName", ""]
        app.launch()

        let phone = app.buttons["Continue with phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15), "no Welcome")
        phone.tap()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "no Next bar")
        let home = next.frame
        XCTAssertEqual(home.height, 52, accuracy: 0.5)

        // Phone (step 1) to Contacts (step 9): eight moves, the frame read after each.
        for step in 2...9 {
            switch step {
            case 4:
                let first = app.textFields["First name"]
                first.tap()
                first.typeText("Avery")
                next.tap()
            case 5:
                app.buttons["Skip"].tap()
            default:
                next.tap()
            }
            XCTAssertTrue(bar(app, step).waitForExistence(timeout: 3), "never reached step \(step)")
            if step == 3 {
                // Name opens the keyboard: the bar rides above it, or stays put on a
                // simulator with a hardware keyboard.
                XCTAssertEqual(next.frame.width, home.width, "Next bar changed width on step 3")
                XCTAssertLessThanOrEqual(next.frame.minY, home.minY, "Next bar dropped on step 3")
            } else {
                XCTAssertEqual(settled(next, at: home), home, "Next bar moved on step \(step)")
            }
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(bar(app, 8).waitForExistence(timeout: 3))
        XCTAssertEqual(next.frame, home, "Next bar moved going back")
    }
}
