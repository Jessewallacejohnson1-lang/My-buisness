//
//  FeedLikeBurstTests.swift
//  Block Party — the double-tap heart is addressed, and repeatable.
//

import XCTest
@testable import BlockParty

final class FeedLikeBurstTests: XCTestCase {

    func testFiringRecordsWhereTheFingerLanded() {
        var burst = FeedLikeBurst()

        burst.fire(at: CGPoint(x: 40, y: 220))

        XCTAssertEqual(burst.point, CGPoint(x: 40, y: 220))
    }

    /// A second double-tap in the same spot must still replay the animation. The
    /// view restarts on `generation`, so an equal point alone would swallow it.
    func testASecondTapInTheSameSpotIsANewBurst() {
        var burst = FeedLikeBurst()
        burst.fire(at: CGPoint(x: 40, y: 220))
        let first = burst

        burst.fire(at: CGPoint(x: 40, y: 220))

        XCTAssertNotEqual(burst, first)
        XCTAssertEqual(burst.generation, first.generation + 1)
    }

    /// The DEBUG gallery likes a card with no finger involved; nil centres the heart.
    func testAFingerlessLikeStillFires() {
        var burst = FeedLikeBurst()

        burst.fire(at: nil)

        XCTAssertNil(burst.point)
        XCTAssertEqual(burst.generation, 1)
    }

    /// Generation 0 is "never tapped" — the view uses it to skip the animation on
    /// first appearance, so a fresh burst must not look like a fired one.
    func testAFreshBurstHasNotFired() {
        XCTAssertEqual(FeedLikeBurst().generation, 0)
    }

    // MARK: - The exit

    /// The heart leaves through the TOP of the photo, so a tap near the bottom of a
    /// tall posting has to travel the whole picture. A fixed distance would park it
    /// in mid-air.
    func testATapLowOnThePhotoTravelsPastItsTopEdge() {
        let travel = FeedLikeBurst.exitTravel(
            from: CGPoint(x: 40, y: 460),
            photoHeight: 495
        )

        XCTAssertGreaterThan(travel, 460)
    }

    /// The fingerless like (the DEBUG gallery) is centred, so it climbs half the
    /// picture plus the clearance.
    func testAFingerlessBurstClimbsFromTheCentre() {
        let travel = FeedLikeBurst.exitTravel(from: nil, photoHeight: 240)

        XCTAssertEqual(travel, 120 + FeedLikeBurst.clearance)
    }

    /// One nominal speed, so the same gesture does not read as two features on the
    /// tall posting and the short event card.
    func testAFartherExitTakesLonger() {
        let near = FeedLikeBurst.exitDuration(travel: 400)
        let far = FeedLikeBurst.exitDuration(travel: 560)

        XCTAssertGreaterThan(far, near)
    }

    /// Floored and capped: a heart born at the very top must not flick out in two
    /// frames, and one born at the very bottom must not drift.
    func testTheExitIsFlooredAndCapped() {
        XCTAssertEqual(FeedLikeBurst.exitDuration(travel: 0), 0.28, accuracy: 0.001)
        XCTAssertEqual(FeedLikeBurst.exitDuration(travel: 5_000), 0.42, accuracy: 0.001)
    }
}
