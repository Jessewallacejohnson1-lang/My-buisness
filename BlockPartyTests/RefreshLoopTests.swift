//
//  RefreshLoopTests.swift
//  BlockPartyTests — the Town feed's pull-to-refresh loop (`LoopRide`, BP app town-feed 69).
//
//  One chunky line round one loop with gravity: slow and short over the top, fast and long
//  through the bottom. A pull draws it up the left side; at the top the read starts and it falls.
//

import XCTest
@testable import BlockParty

final class RefreshLoopTests: XCTestCase {

    func testGravityIsSlowOverTheTopAndFastThroughTheBottom() {
        XCTAssertEqual(LoopRide.speed(at: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(LoopRide.speed(at: .pi), LoopRide.topSpeedShare, accuracy: 0.0001)
        XCTAssertGreaterThan(LoopRide.speed(at: .pi / 2), LoopRide.speed(at: .pi))
        XCTAssertGreaterThan(LoopRide.arc(at: 0), LoopRide.arc(at: .pi) * 2)
    }

    func testOneLapTakesTheLapTime() {
        // A tab tap starts at the bottom: one lap later it is back at the bottom.
        let back = LoopRide.angle(after: LoopRide.lap, from: .tab)
        XCTAssertEqual(min(back, 2 * .pi - back), 0, accuracy: 0.02)
        // It spends longer over the top half than the bottom half.
        let quarter = LoopRide.angle(after: LoopRide.lap / 4, from: .tab)
        XCTAssertGreaterThan(quarter, .pi / 2)
    }

    func testAPullStartsAtTheTopAndFallsDownTheRight() {
        XCTAssertEqual(LoopRide.angle(after: 0, from: .pull), .pi, accuracy: 0.01)
        let soon = LoopRide.angle(after: 0.1, from: .pull)
        XCTAssertGreaterThan(soon, .pi)
        XCTAssertLessThan(soon, 2 * .pi)
    }

    func testThePullDrawsTheLeftSideUpToTheTop() {
        XCTAssertNil(LoopRide.stroke(pull: 0))
        let half = try! XCTUnwrap(LoopRide.stroke(pull: LoopRide.triggerPoints / 2))
        XCTAssertEqual(half.head, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(half.length, .pi / 2, accuracy: 0.0001)
        let full = try! XCTUnwrap(LoopRide.stroke(pull: LoopRide.triggerPoints * 3))
        XCTAssertEqual(full.head, .pi, accuracy: 0.0001)
    }

    func testTheRideFadesOutAfterItEnds() {
        XCTAssertEqual(LoopRide.stroke(from: .tab, since: 0.5, endsAfter: nil)?.opacity, 1)
        let fading = try! XCTUnwrap(LoopRide.stroke(from: .tab, since: 1.0 + LoopRide.fade / 2, endsAfter: 1.0))
        XCTAssertEqual(fading.opacity, 0.5, accuracy: 0.01)
        XCTAssertNil(LoopRide.stroke(from: .tab, since: 1.0 + LoopRide.fade, endsAfter: 1.0))
    }

    func testTheLoopSitsMidGapThenPinsUnderTheBar() {
        XCTAssertEqual(LoopRide.rise(gap: 40), -20)
        XCTAssertEqual(LoopRide.rise(gap: LoopRide.heldGap), -LoopRide.heldGap / 2)
        // Pulled further, it stays half a held gap under the bar.
        XCTAssertEqual(LoopRide.rise(gap: 160), -(160 - LoopRide.heldGap / 2))
    }

    func testThePullIsMeasuredFromTheRestingInset() {
        let pull = RefreshPull()
        // Laid out before the bar: a smaller inset, then the real one at rest.
        pull.scrolled(.init(top: 40, inset: 40))
        pull.scrolled(.init(top: 120, inset: 120))
        XCTAssertEqual(pull.points, 0)
        pull.scrolled(.init(top: 200, inset: 120))
        XCTAssertEqual(pull.points, 80)
        // A read adds to the inset under the finger; the content hasn't moved, so neither does the pull.
        pull.scrolled(.init(top: 200, inset: 160))
        XCTAssertEqual(pull.points, 80)
        // The read holds its gap: the content rests at the read's inset, 60 pt down.
        pull.reading = .pull
        pull.scrolled(.init(top: 180, inset: 180))
        XCTAssertEqual(pull.points, 60)
        pull.reading = nil
        pull.scrolled(.init(top: -300, inset: 120))
        XCTAssertEqual(pull.points, 0)
    }

    func testAtLeastOneLap() {
        XCTAssertEqual(LoopRide.rest(afterReading: 0.3), LoopRide.lap - 0.3, accuracy: 0.0001)
        XCTAssertEqual(LoopRide.rest(afterReading: 2.6), 0)
    }
}
