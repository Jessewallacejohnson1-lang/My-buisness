//
//  AfterFramesTests.swift
//  Block Party — a tab's first visit waits for its page to be drawn before it slides in (tab-lag 04).
//

import XCTest
@testable import BlockParty

@MainActor
final class AfterFramesTests: XCTestCase {
    func testRunsOnceAndNotBeforeTheFrames() {
        let ran = expectation(description: "ran")
        ran.assertForOverFulfill = true
        var calls = 0
        AfterFrames.run(2) {
            calls += 1
            ran.fulfill()
        }
        XCTAssertEqual(calls, 0, "the work never runs in the same turn")
        wait(for: [ran], timeout: 2)
        XCTAssertEqual(calls, 1)
        // A few more frames: the link has stopped.
        let later = expectation(description: "later")
        AfterFrames.run(3) { later.fulfill() }
        wait(for: [later], timeout: 2)
        XCTAssertEqual(calls, 1)
    }
}
