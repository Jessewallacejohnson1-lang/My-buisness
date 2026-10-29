//
//  OnboardingNextBarTests.swift
//  Block Party — onboarding's locked rule (ONBOARDING.md): the Next bar never moves, except
//  to ride with the keyboard. Walks every question step and reads the bar's frame on each,
//  then steps back once. Name needs a first name to go on and Photo is skipped (ticket 18);
//  Birthday starts on a saved one, so Next is allowed (ticket 19); Interests takes 3 picks (20);
//  Follow 3 takes 3 follows once its places are read (22).
//
//  `-onboarding` shows the flow as a first launch would; the `-onboarding.*` pairs set its
//  saved place and name, and `-bp.interests` its picks, through the launch arguments' defaults domain, so every run starts
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
                               "-onboarding.firstName", "", "-onboarding.birthday", "2001-10-24",
                               "-bp.interests", "()"]
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
            case 7:
                // Interests asks for 3 before it lets you on (ticket 20).
                XCTAssertEqual(next.label, "Pick 3 more")
                // Popular in St. Joseph slides in when its counts land; let it, so no chip moves mid-tap.
                _ = app.staticTexts["Popular in St. Joseph"].waitForExistence(timeout: 10)
                for picked in 1...3 {
                    // The first chip not yet picked, once the last one has glided into Added.
                    let chip = app.buttons.matching(NSPredicate(format: "identifier == 'interest-chip' AND isSelected == NO"))
                        .element(boundBy: 0)
                    XCTAssertTrue(chip.waitForExistence(timeout: 3), "no chip to pick \(picked)")
                    Thread.sleep(forTimeInterval: 0.6)
                    chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                XCTAssertEqual(next.label, "Next")
                next.tap()
            case 8:
                // Follow 3 asks for 3 once its places are read (ticket 22); a failed read lets Next on.
                if app.staticTexts["Suggested for you"].waitForExistence(timeout: 10) {
                    XCTAssertEqual(next.label, "Follow 3 more")
                    for followed in 1...3 {
                        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Follow, '")).element(boundBy: 0)
                        XCTAssertTrue(pill.waitForExistence(timeout: 3), "no place to follow \(followed)")
                        // Once the step has slid in and the last pill has popped, as the chips above.
                        Thread.sleep(forTimeInterval: 0.6)
                        pill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                }
                XCTAssertEqual(next.label, "Next")
                next.tap()
            default:
                next.tap()
            }
            XCTAssertTrue(bar(app, step).waitForExistence(timeout: 3), "never reached step \(step)")
            if step == 3 || step == 5 {
                // Name opens the keyboard and Birthday its wheel (ticket 19): the bar rides above
                // it, or stays put on a simulator with a hardware keyboard.
                XCTAssertEqual(next.frame.width, home.width, "Next bar changed width on step \(step)")
                XCTAssertLessThanOrEqual(next.frame.minY, home.minY, "Next bar dropped on step \(step)")
            } else {
                XCTAssertEqual(settled(next, at: home), home, "Next bar moved on step \(step)")
            }
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(bar(app, 8).waitForExistence(timeout: 3))
        XCTAssertEqual(next.frame, home, "Next bar moved going back")
    }
}
