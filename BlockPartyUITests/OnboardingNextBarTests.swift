//
//  OnboardingNextBarTests.swift
//  Block Party — onboarding's locked rule (ONBOARDING.md): the Next bar never moves, except
//  to ride with the keyboard. Walks every question step and reads the bar's frame on each,
//  then steps back once. The Name and Photo steps copy Clubhouse's (onboarding 55): no dashes, and
//  Clubhouse's narrow pill, which rides the keyboard on Name and sits 55 pt up on Photo, where Skip goes on
//  without a photo; from Birthday the pill is every step's in every step's spot. Birthday starts on a saved
//  one, so Next is allowed (ticket 19); Interests takes 3 picks (20);
//  Follow 3 takes 3 follows once its places are read (22); Find your friends' Next asks iPhone for
//  contacts, which the test allows, from a fresh answer each run (23).
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
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step \(step) of 5")).firstMatch
    }

    /// The bar's frame once it has held still for 0.3 s (the keyboard leaving carries it down).
    private func resting(_ next: XCUIElement) -> CGRect {
        let deadline = Date().addingTimeInterval(3)
        var last = next.frame
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if next.frame == last { break }
            last = next.frame
        }
        return last
    }

    /// The bar's frame once it has come to rest (the keyboard leaving carries it down).
    private func settled(_ next: XCUIElement, at home: CGRect) -> CGRect {
        let deadline = Date().addingTimeInterval(3)
        while next.frame != home, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        return next.frame
    }

    /// Taps iPhone's contacts prompt through to allowed until the bar reads step 5: SpringBoard's
    /// Continue, then the Contacts sheet's "Share All 7 Contacts" (iOS 26), whichever comes up.
    private func allowContacts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let sheet = XCUIApplication(bundleIdentifier: "com.apple.ContactsUI.LimitedAccessPromptView")
        let allow = NSPredicate(format: "label == 'Continue' OR label BEGINSWITH 'Share All' OR label == 'Allow Full Access'")
        let deadline = Date().addingTimeInterval(20)
        while !bar(app, 5).exists, Date() < deadline {
            // One tap a round: the sheet's button tapped while SpringBoard's alert still leaves goes stale.
            for owner in [springboard, sheet] {
                let button = owner.buttons.matching(allow).firstMatch
                if button.exists, button.isHittable { button.tap(); break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    func testNextBarHoldsStillOnEveryStep() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A refusal kept from an earlier run would end the flow on Find your friends.
        app.resetAuthorizationStatus(for: .contacts)
        // Follow 3's picks and Interests' stay saved between runs too: `<5b5d>` is "[]", so it starts on
        // none, and `()` empties the interests a run before left under their own key. Starts on Profile:
        // Create account before it would make a live account (onboarding 27).
        app.launchArguments = ["-ui-tests", "-onboarding",
                               "-onboarding.step", "profile", "-onboarding.finished", "NO",
                               "-onboarding.name", "", "-onboarding.bio", "", "-onboarding.birthday", "2001-10-24",
                               "-bp.interests", "()", "-onboarding.interests", "()", "-onboarding.follows", "<5b5d>"]
        app.launch()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "no Next bar")
        // Name (onboarding 55): no dashes; Clubhouse's narrow pill, grey until a name is in, riding the
        // keyboard that comes up with the step.
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5), "not on the name step")
        XCTAssertFalse(bar(app, 1).exists, "dashes on the name step")
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Avery")
        let riding = resting(next)
        XCTAssertEqual(riding.width, 199, accuracy: 0.5, "not Clubhouse's pill")
        XCTAssertEqual(riding.height, 49, accuracy: 0.5)
        XCTAssertEqual(riding.midX, app.frame.midX, accuracy: 0.5, "Clubhouse's pill isn't centred")
        next.tap()
        // Photo: the same pill 55 pt up, grey until a photo is in; Skip goes on without one.
        XCTAssertTrue(app.buttons["Add a photo"].waitForExistence(timeout: 3), "never reached the photo step")
        let photo = resting(next)
        XCTAssertEqual(photo.width, 199, accuracy: 0.5)
        XCTAssertEqual(app.frame.maxY - photo.maxY, 55, accuracy: 0.5, "not Clubhouse's spot")
        XCTAssertGreaterThan(photo.maxY, riding.maxY, "the pill didn't ride the keyboard on the name step")
        app.buttons["Skip"].tap()
        XCTAssertTrue(bar(app, 1).waitForExistence(timeout: 3), "Skip never reached Birthday")
        // Birthday opens its wheel (ticket 19): the bar rides above it.
        let wheel = resting(next)
        next.tap()
        XCTAssertTrue(bar(app, 2).waitForExistence(timeout: 3), "never reached step 2")
        let home = resting(next)
        XCTAssertEqual(home.height, 48, accuracy: 0.5)   // Luma's flat pill (onboarding 34)
        XCTAssertEqual(home.width, app.frame.width - 40, accuracy: 0.5, "not every step's pill, 20 pt in from each side")
        XCTAssertLessThan(wheel.maxY, home.maxY, "Next bar dropped on the Birthday")
        XCTAssertEqual(wheel.width, home.width, accuracy: 0.5, "Birthday's pill isn't every step's")

        // Interests (step 2) to Contacts (step 5): three moves, the frame read after each.
        for step in 3...5 {
            switch step {
            case 3:
                // Interests asks for 3 before it lets you on (ticket 20).
                // The title rolls its number (onboarding 26): read it once the roll has landed.
                XCTAssertTrue(next.wait(for: \.label, toEqual: "Pick 3 more", timeout: 3), "Next bar says \(next.label)")
                for picked in 1...3 {
                    // The first row not yet picked (onboarding 28).
                    let chip = app.buttons.matching(NSPredicate(format: "identifier == 'interest-chip' AND isSelected == NO"))
                        .element(boundBy: 0)
                    XCTAssertTrue(chip.waitForExistence(timeout: 3), "no chip to pick \(picked)")
                    Thread.sleep(forTimeInterval: 0.6)
                    chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                XCTAssertTrue(next.wait(for: \.label, toEqual: "Next", timeout: 3), "Next bar says \(next.label)")
                next.tap()
            case 4:
                // Follow 3 asks for 3 once its places are read (ticket 22, a grid since 26); a failed read
                // lets Next on.
                if app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Follow, '")).element(boundBy: 0)
                    .waitForExistence(timeout: 10) {
                    XCTAssertTrue(next.wait(for: \.label, toEqual: "Follow 3 more", timeout: 3), "Next bar says \(next.label)")
                    for followed in 1...3 {
                        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Follow, '")).element(boundBy: 0)
                        XCTAssertTrue(pill.waitForExistence(timeout: 3), "no place to follow \(followed)")
                        // Once the step has slid in and the last pill has popped, as the chips above.
                        Thread.sleep(forTimeInterval: 0.6)
                        pill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                }
                XCTAssertTrue(next.wait(for: \.label, toEqual: "Next", timeout: 3), "Next bar says \(next.label)")
                next.tap()
            case 5:
                next.tap()
                allowContacts(app)
            default:
                next.tap()
            }
            XCTAssertTrue(bar(app, step).waitForExistence(timeout: 3), "never reached step \(step)")
            XCTAssertEqual(settled(next, at: home), home, "Next bar moved on step \(step)")
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(bar(app, 4).waitForExistence(timeout: 3))
        XCTAssertEqual(next.frame, home, "Next bar moved going back")
    }
}
