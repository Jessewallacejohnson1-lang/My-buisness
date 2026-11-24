//
//  StartGroupSwipeTests.swift
//  Block Party — inside Start a group's sheet, a Group's page goes back to New group with the edge swipe (BP app
//  start-a-group 09): its hidden bar turns the swipe off, and the sheet's own `SwipeBack` turns it back on. A UI test
//  because AXe's touches never start a screen-edge swipe.
//

import XCTest

final class StartGroupSwipeTests: XCTestCase {

    func testTheEdgeSwipeGoesBackToNewGroup() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-tests", "-skip-onboarding", "-open-friends", "-start-group", "Sewing", "-group-admin", "member"]
        app.launch()
        let page = app.staticTexts["Joetown Sewing Circle"]
        XCTAssertTrue(page.waitForExistence(timeout: 20), "the Group's page isn't in the sheet")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 1, dy: 0))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.buttons["Create"].waitForExistence(timeout: 10), "the swipe didn't go back to New group")
        XCTAssertFalse(page.exists)
    }
}
