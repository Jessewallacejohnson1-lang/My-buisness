//
//  TownRainPhysicsTests.swift
//  BlockPartyTests — the measured contract for the town-rain drop.
//
//  The motion constants asserted here were MEASURED off the reference recording
//  (`ScreenRecording_08-03-2026 10-55-12_1.MP4`) by tracking each sprite at 60 fps
//  and least-squares fitting y(t) = y0 + v0·t + ½g·t² per flight segment
//  (10 tracks; 6 clean full-length ones, fit RMS 4–10 px at @3x). See
//  `docs/town-rain-reference-measurements.md` for the raw fits.
//
//  These are tolerance tests, not snapshots: the tolerances are the spread of the
//  reference tracks themselves, so a change that drifts the feel fails here.
//
//  `burstCount` and `floorInset` are the exceptions — the reference clip ends while
//  sprites are still falling and its floor was its own app's bottom bar, so neither is
//  measurable from it. Where they are asserted, the assertion is a design decision
//  being pinned, not a measurement; the comments say which is which.
//

import XCTest
import CoreGraphics
@testable import BlockParty

final class TownRainPhysicsTests: XCTestCase {

    // Integrating at 240 Hz keeps the discretisation error well under the tolerances
    // below, so a failure means the model changed — not the step size.
    private let fineStep: CGFloat = 1.0 / 240.0

    private func ball(
        x: CGFloat = 200, y: CGFloat = 0,
        vx: CGFloat = -250, vy: CGFloat = 0,
        spin: CGFloat = 0, bounceSpin: CGFloat = 650,
        size: CGFloat = TownRainPhysics.ballSize
    ) -> TownRainBall {
        TownRainBall(id: 1, logoIndex: 0, x: x, y: y, vx: vx, vy: vy,
                     angle: 0, spin: spin, bounceSpin: bounceSpin,
                     size: size, hasBounced: false)
    }

    /// Steps an EXACT whole number of `fineStep`s, so the elapsed time is exactly
    /// `seconds` and the expected values below are plain closed-form arithmetic.
    /// (Accumulating `elapsed += fineStep` in a `while elapsed < seconds` loop runs
    /// one extra step at 0.5 s — a harness artifact that would read as a physics bug.)
    private func advance(_ start: TownRainBall, seconds: CGFloat, floorY: CGFloat) -> TownRainBall {
        var b = start
        for _ in 0..<Int((seconds / fineStep).rounded()) {
            b = TownRainPhysics.stepped(b, dt: fineStep, floorY: floorY)
        }
        return b
    }

    // MARK: The constants themselves

    /// Every OTHER test asserts that the integrator applies the constants correctly —
    /// which it would still do if someone retuned them by feel. This one pins the
    /// values to the reference spreads, so re-tuning fails unless the recording is
    /// re-measured with it. (A mutation run proved the need: flipping `restitution`
    /// from 0.33 to 0.55 broke nothing until this existed.)
    func testEveryMeasuredConstantStaysInsideItsReferenceSpread() {
        // Fitted g per clean track: 1044, 1072, 1098, 1101, 1106, 1130 pt/s².
        XCTAssertEqual(TownRainPhysics.gravity, 1090, accuracy: 45, "gravity")

        // Rebound / impact speed on the three tracks that bounced in frame:
        // 0.336, 0.328, 0.324.
        XCTAssertEqual(TownRainPhysics.restitution, 0.33, accuracy: 0.02, "restitution")

        // Steady-state spacing: 0.200, 0.200, 0.217, 0.217 s.
        XCTAssertEqual(TownRainPhysics.spawnInterval, 0.21, accuracy: 0.015, "spawnInterval")

        // Sprite bounding box 96–112 px at @3x ⇒ 32–37 pt.
        XCTAssertGreaterThanOrEqual(TownRainPhysics.ballSize, 32, "ballSize")
        XCTAssertLessThanOrEqual(TownRainPhysics.ballSize, 37, "ballSize")

        // In flight the reference turned ~90° in ~0.8 s (~110°/s); after the floor hit
        // its bounding box cycled every ~0.25 s (~720°/s).
        XCTAssertEqual(TownRainPhysics.flightSpinRange.upperBound, 150, accuracy: 60)
        XCTAssertEqual(-TownRainPhysics.flightSpinRange.lowerBound,
                       TownRainPhysics.flightSpinRange.upperBound, accuracy: 0.001,
                       "in-flight tumble must be symmetric — the reference span both ways")
        XCTAssertTrue(TownRainPhysics.bounceSpinRange.contains(720),
                      "post-bounce tumble must be able to reach the measured ~720°/s")

        // 5–7 airborne at once in the reference: burstCount × interval must cover the
        // 0.8 s camera fly and a beat after, without running long.
        XCTAssertEqual(TownRainPhysics.burstCount, 14)
    }

    // MARK: Free fall — the measured gravity

    func testGravityMatchesTheMeasuredReferenceRate() {
        // Arrange — reference fit: g = 1044…1130 pt/s² across the six clean tracks.
        let start = ball(vy: 0)

        // Act — one second of free fall, floor far below so nothing interferes.
        let after = advance(start, seconds: 1.0, floorY: 100_000)

        // Assert
        XCTAssertEqual(after.vy, TownRainPhysics.gravity, accuracy: 6,
                       "one second of fall must add exactly one g of downward speed")
        XCTAssertEqual(TownRainPhysics.gravity, 1090, accuracy: 45,
                       "gravity must stay inside the reference spread (1044…1130 pt/s²)")
    }

    func testHorizontalDriftIsConstantDuringFreeFall() {
        // Arrange — reference: vx is constant per sprite, leftward, 207…297 pt/s.
        let start = ball(x: 300, vx: -250)

        // Act
        let after = advance(start, seconds: 0.5, floorY: 100_000)

        // Assert
        XCTAssertEqual(after.vx, -250, accuracy: 0.001, "gravity must not touch vx")
        XCTAssertEqual(after.x, 300 - 250 * 0.5, accuracy: 1.0)
    }

    func testDriftRangeMatchesTheReferenceSpread() {
        XCTAssertLessThanOrEqual(TownRainPhysics.driftRange.upperBound, -200,
                                 "every reference sprite drifted left; none drifted right")
        XCTAssertGreaterThanOrEqual(TownRainPhysics.driftRange.lowerBound, -305,
                                    "fastest measured drift was 297 pt/s")
    }

    // MARK: The bounce

    func testBounceReversesVelocityWithTheMeasuredRestitution() {
        // Arrange — reference: impact ~1300 pt/s, rebound ~427 pt/s ⇒ e ≈ 0.33.
        let floorY: CGFloat = 700
        let r = TownRainPhysics.ballSize / 2
        let incoming = ball(y: floorY - r - 0.5, vy: 1300)

        // Act — one step carries it through the floor plane.
        let after = TownRainPhysics.stepped(incoming, dt: 1.0 / 60.0, floorY: floorY)

        // Assert
        XCTAssertLessThan(after.vy, 0, "the ball must come back up")
        // Tolerance is the reference's own spread (0.324-0.336), not a round number:
        // the exact-crossing solve in `stepped` leaves almost no discretisation slack
        // to allow for (see testReboundBarelyMovesWithTheFrameRate for what remains).
        XCTAssertEqual(-after.vy / 1300, TownRainPhysics.restitution, accuracy: 0.006,
                       "rebound ratio must match the measured e = 0.33")
    }

    func testBallNeverSinksBelowTheFloor() {
        // Arrange
        let floorY: CGFloat = 700
        let start = ball(y: 0, vy: 0)

        // Act — three seconds, long enough for several bounces.
        var b = start
        var worstOvershoot: CGFloat = 0
        var elapsed: CGFloat = 0
        while elapsed < 3.0 {
            b = TownRainPhysics.stepped(b, dt: fineStep, floorY: floorY)
            worstOvershoot = max(worstOvershoot, b.y + b.size / 2 - floorY)
            elapsed += fineStep
        }

        // Assert
        XCTAssertLessThanOrEqual(worstOvershoot, 0.5,
                                 "the ball's bottom edge must never pass the floor plane")
    }

    func testReboundBarelyMovesWithTheFrameRate() {
        // Arrange — the same approach integrated at 60 / 120 / 240 Hz. Reflecting the
        // END-of-step velocity folds a whole frame of gravity into the rebound, which
        // is ~6 pt/s of 60-vs-240 Hz spread; solving for the contact instant cuts that
        // to ~2.2 (measured: -399.4 / -400.9 / -401.6 pt/s). It does NOT reach zero,
        // and this test says so: the position the solve starts from still carries the
        // step's own Euler error, so `gap` — and with it the impact speed — differs
        // slightly by frame rate. 2.2 pt/s on a ~400 pt/s rebound is 0.55%, well inside
        // the reference's own 0.324–0.336 restitution spread (±1.8%).
        let floorY: CGFloat = 700
        let start = ball(y: 0, vy: 0)

        // Act — drop each to its first contact and record the rebound.
        let rebounds: [CGFloat] = [60.0, 120.0, 240.0].map { hz in
            var b = start
            let dt = CGFloat(1.0 / hz)
            while !b.hasBounced { b = TownRainPhysics.stepped(b, dt: dt, floorY: floorY) }
            return b.vy
        }

        // Assert
        XCTAssertEqual(rebounds[0], rebounds[2], accuracy: 2.5, "60 Hz vs 240 Hz rebound")
        XCTAssertEqual(rebounds[1], rebounds[2], accuracy: 1.0, "120 Hz vs 240 Hz rebound")
    }

    func testEachBallCarriesItsOwnPostBounceTumble() {
        // Arrange — the reference's sprites did not all leave the floor at one rate.
        var emitter = TownRainEmitter(seed: 5, logoCount: 50,
                                      bounds: CGSize(width: 402, height: 874))

        // Act — collect the whole burst.
        var seen: [CGFloat] = []
        for _ in 0..<900 {
            let before = emitter.balls.map(\.id)
            emitter = emitter.advanced(by: fineStep)
            seen += emitter.balls.filter { !before.contains($0.id) }.map(\.bounceSpin)
        }

        // Assert
        XCTAssertGreaterThan(seen.count, 5)
        XCTAssertGreaterThan(Set(seen).count, 1, "every ball got the same post-bounce spin")
        for s in seen {
            XCTAssertTrue(TownRainPhysics.bounceSpinRange.contains(s), "\(s) outside the measured band")
        }
    }

    func testBounceImpartsSpinTheWayTheReferenceDoes() {
        // Arrange — reference: ~110°/s tumble in flight, ~720°/s after the floor hit.
        let floorY: CGFloat = 700
        let r = TownRainPhysics.ballSize / 2
        let incoming = ball(y: floorY - r - 0.5, vy: 1300, spin: 90)

        // Act
        let after = TownRainPhysics.stepped(incoming, dt: 1.0 / 60.0, floorY: floorY)

        // Assert
        XCTAssertTrue(after.hasBounced)
        XCTAssertGreaterThan(abs(after.spin), 400,
                             "the floor hit must kick the tumble up to the measured post-bounce rate")
    }

    func testSpinIntegratesIntoAngle() {
        // Arrange
        let start = ball(spin: 180)

        // Act
        let after = advance(start, seconds: 1.0, floorY: 100_000)

        // Assert
        XCTAssertEqual(after.angle, 180, accuracy: 1.0)
    }

    // MARK: End-to-end timing — the number a viewer actually feels

    func testFallFromSpawnToFloorMatchesTheReferenceDuration() {
        // Arrange — reference geometry: spawn centre one half-ball above the top edge,
        // floor 766 pt down the 874 pt screen ⇒ measured first contact at ~1.19 s.
        let floorY: CGFloat = 766
        let start = ball(y: -TownRainPhysics.ballSize / 2, vy: 0)

        // Act — advance until the first bounce is recorded.
        var b = start
        var t: CGFloat = 0
        while !b.hasBounced && t < 5 {
            b = TownRainPhysics.stepped(b, dt: fineStep, floorY: floorY)
            t += fineStep
        }

        // Assert
        XCTAssertTrue(b.hasBounced, "the ball must reach the floor")
        XCTAssertEqual(t, 1.19, accuracy: 0.06,
                       "spawn→floor must match the reference's measured 1.19 s")
    }

    // MARK: Lifetime

    func testBallDiesAfterExitingTheLeftEdge() {
        // Arrange
        let bounds = CGSize(width: 402, height: 874)
        let offLeft = ball(x: -TownRainPhysics.ballSize)

        // Assert
        XCTAssertFalse(TownRainPhysics.isAlive(offLeft, in: bounds))
        XCTAssertTrue(TownRainPhysics.isAlive(ball(x: 10), in: bounds))
    }

    func testBallDiesAfterFallingPastTheBottom() {
        // Arrange
        let bounds = CGSize(width: 402, height: 874)

        // Assert
        XCTAssertFalse(TownRainPhysics.isAlive(ball(x: 200, y: 874 + TownRainPhysics.ballSize),
                                               in: bounds))
    }

    func testBallSpawnedAboveTheTopEdgeIsStillAlive() {
        // Arrange — sprites spawn off-screen above and must not be culled on frame one.
        let bounds = CGSize(width: 402, height: 874)

        // Assert
        XCTAssertTrue(TownRainPhysics.isAlive(ball(x: 200, y: -TownRainPhysics.ballSize / 2),
                                              in: bounds))
    }

    // MARK: Immutability (house rule)

    func testSteppingReturnsANewBallAndLeavesTheInputUntouched() {
        // Arrange
        let start = ball(y: 100, vy: 200)

        // Act
        _ = TownRainPhysics.stepped(start, dt: 0.1, floorY: 700)

        // Assert
        XCTAssertEqual(start.y, 100, "stepped() must not mutate its input")
        XCTAssertEqual(start.vy, 200)
    }

    // MARK: The emitter — cadence and determinism

    func testEmitterMatchesTheReferenceCadenceAndCount() {
        // Arrange — reference steady state: one sprite every 0.21 s.
        var emitter = TownRainEmitter(seed: 7, logoCount: 50,
                                      bounds: CGSize(width: 402, height: 874))

        // Act — drain the whole burst, recording the time of each spawn.
        var spawnTimes: [CGFloat] = []
        var t: CGFloat = 0
        while t < 10 {
            let before = emitter.spawnedCount
            emitter = emitter.advanced(by: fineStep)
            if emitter.spawnedCount > before { spawnTimes.append(t) }
            t += fineStep
        }

        // Assert
        XCTAssertEqual(spawnTimes.count, TownRainPhysics.burstCount)
        XCTAssertEqual(TownRainPhysics.burstCount, 14)
        for (a, b) in zip(spawnTimes, spawnTimes.dropFirst()) {
            XCTAssertEqual(b - a, TownRainPhysics.spawnInterval, accuracy: 0.02,
                           "spacing must hold the reference's 0.21 s cadence")
        }
    }

    func testEmitterIsDeterministicForAGivenSeed() {
        // Arrange
        let bounds = CGSize(width: 402, height: 874)
        var a = TownRainEmitter(seed: 42, logoCount: 50, bounds: bounds)
        var b = TownRainEmitter(seed: 42, logoCount: 50, bounds: bounds)

        // Act
        for _ in 0..<600 {
            a = a.advanced(by: fineStep)
            b = b.advanced(by: fineStep)
        }

        // Assert
        XCTAssertEqual(a.balls, b.balls, "same seed must replay identically")
    }

    func testEveryEmittedBallStartsAboveTheTopEdgeAtRest() {
        // Arrange — reference: sprites enter under gravity alone, not launched.
        var emitter = TownRainEmitter(seed: 3, logoCount: 50,
                                      bounds: CGSize(width: 402, height: 874))
        var seen: [TownRainBall] = []

        // Act
        for _ in 0..<240 {
            let before = emitter.balls.map(\.id)
            emitter = emitter.advanced(by: fineStep)
            seen += emitter.balls.filter { !before.contains($0.id) }
        }

        // Assert
        XCTAssertFalse(seen.isEmpty)
        for b in seen {
            XCTAssertLessThanOrEqual(b.y, 0, "\(b.id) must spawn above the top edge")
            XCTAssertEqual(b.vy, 0, accuracy: 0.001, "\(b.id) must start at rest")
            XCTAssertTrue(TownRainPhysics.driftRange.contains(b.vx),
                          "\(b.id) drift \(b.vx) outside the measured range")
        }
    }

    func testBurstFinishesWithinTheDesignedWindow() {
        // Arrange — 14 balls at 0.21 s + ~1.2 s fall + bounce-out must clear well
        // inside 8 s, or the map control feels like it hangs.
        var emitter = TownRainEmitter(seed: 11, logoCount: 50,
                                      bounds: CGSize(width: 402, height: 874))

        // Act
        var t: CGFloat = 0
        while !emitter.isFinished && t < 20 {
            emitter = emitter.advanced(by: fineStep)
            t += fineStep
        }

        // Assert
        XCTAssertTrue(emitter.isFinished, "the burst must end on its own")
        XCTAssertLessThan(t, 8.0, "burst ran \(t)s — too long for a map control")
    }
}
