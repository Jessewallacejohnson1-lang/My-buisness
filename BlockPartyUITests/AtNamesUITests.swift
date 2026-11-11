//
//  AtNamesUITests.swift
//  Block Party — typing `@` in New post (BP app docs/plans/town-feed, ticket 60): the row of names comes up as you
//  type, from the `@` to the cursor, and a pick writes "@Name " in the words with the cursor after it. Typed for
//  real, since AXe can't type on BP Build. The sample friends (`-town-samples`) are the names; Dale Brunner is one.
//
//  Run on the "BlockParty Tests" simulator, never the screenshot one (`sim-guard.sh`).
//

import XCTest

final class AtNamesUITests: XCTestCase {
    func testTypingAtShowsTheRowAndAPickWritesTheName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-town-samples", "-ui-tests", "-new-post"]
        app.launch()

        let words = app.descendants(matching: .any)["new-post-words"]
        XCTAssertTrue(words.waitForExistence(timeout: 10), "no New post")
        words.tap()
        words.typeText("Pint night with @dal")
        let dale = app.buttons["Dale Brunner"]
        XCTAssertTrue(dale.waitForExistence(timeout: 5), "typing @dal showed no row")
        dale.tap()
        XCTAssertEqual(words.value as? String, "Pint night with @Dale Brunner ")
        XCTAssertFalse(app.buttons["Dale Brunner"].waitForExistence(timeout: 1), "the row stays after a pick")

        // The cursor sits after the name: what's typed next follows it.
        words.typeText("and @")
        XCTAssertTrue(app.buttons["Dale Brunner"].waitForExistence(timeout: 5), "an @ alone offers everyone")
        words.typeText("zzz")
        XCTAssertFalse(app.buttons["Dale Brunner"].waitForExistence(timeout: 1), "no match: the row goes")
        XCTAssertEqual(words.value as? String, "Pint night with @Dale Brunner and @zzz")
    }
}
