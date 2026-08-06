//
//  TownRainPhysics.swift
//  Block Party — the pure, testable model behind the town-rain drop.
//
//  Pressing "Saint Joseph" (the town pill) or the recenter control flies the camera
//  home; while it flies, a short burst of real local brand marks drops down the
//  screen, bounces once off the top of the map sheet and drifts out to the left.
//
//  The MOTION constants were measured off the reference recording rather than chosen:
//  each sprite was tracked at 60 fps and its flight fitted with least squares
//  (y = y0 + v0·t + ½g·t²) — 10 tracks, 6 of them clean full-length, fit RMS 4–10 px
//  at @3x. `docs/town-rain-reference-measurements.md` records the per-track fits, and
//  `TownRainPhysicsTests` pins each value inside its reference spread, so re-tuning by
//  feel fails the suite unless the measurements are re-derived with it. That covers
//  `gravity`, `restitution`, `spawnInterval`, `ballSize`, `driftRange`, `spawnXRange`,
//  and both spin ranges.
//
//  Three constants are CHOSEN, because the reference could not supply them:
//    • `burstCount` — the clip ends while sprites are still falling, so its burst
//      length was never observable. 14 holds the measured density for the length of
//      this app's 0.8 s camera fly and a beat after.
//    • `floorInset` — this app's contact surface is its own map sheet, not the
//      reference app's bottom bar.
//    • the `spawnXRange` lower bound — widened below the measured entry points to
//      spread the burst across the width (see its own note).
//
//  No SwiftUI here on purpose — the integrator is plain values so it can be stepped
//  in a test at 240 Hz without a view, a display link, or a simulator.
//

import CoreGraphics

// MARK: - One falling brand mark

struct TownRainBall: Equatable, Identifiable {
    let id: Int
    /// Index into the roster of resolved logo images (see `TownRainRoster`).
    let logoIndex: Int
    /// Centre, in the field's point space (y grows downward, screen convention).
    let x: CGFloat
    let y: CGFloat
    /// Velocity in pt/s.
    let vx: CGFloat
    let vy: CGFloat
    /// Clockwise degrees, matching `.rotationEffect` / `GraphicsContext.rotate`.
    let angle: CGFloat
    /// Tumble rate in deg/s.
    let spin: CGFloat
    /// The tumble this ball switches to on its first floor contact, drawn per-ball at
    /// spawn. Carried on the ball rather than picked in `stepped` so the integrator
    /// stays a pure function of its input — and so every ball does not leave the floor
    /// spinning at exactly the same rate, which one shared constant would cause.
    let bounceSpin: CGFloat
    /// Diameter in points.
    let size: CGFloat
    /// Latches on the first floor contact — the reference's tumble speeds up there,
    /// and the renderer uses it for nothing else.
    let hasBounced: Bool
}

// MARK: - The measured constants + the integrator

enum TownRainPhysics {

    // Fitted from the six clean reference tracks: 1044, 1072, 1098, 1101, 1106,
    // 1130 pt/s² (mean 1092). ≈ UIKit Dynamics' own magnitude-1.0 gravity.
    static let gravity: CGFloat = 1090

    // Impact speed ≈ 3900 px/s vs rebound ≈ 1290 px/s across the three tracks that
    // bounced inside the clip: 0.336, 0.328, 0.324.
    static let restitution: CGFloat = 0.33

    /// Reference sprite bounding box was 96–112 px at @3x ⇒ 32–37 pt. 36 pt also
    /// matches the pin logo's own optical size, so the marks read as the same objects.
    static let ballSize: CGFloat = 36

    /// Steady-state spawn spacing in the reference: 0.200, 0.200, 0.217, 0.217 s.
    static let spawnInterval: CGFloat = 0.21

    /// Balls per press. 14 × 0.21 s ≈ 2.9 s of spawning holds the reference's
    /// 5–7-on-screen density for the length of the 0.8 s camera fly and a beat after.
    static let burstCount = 14

    /// Every reference sprite drifted LEFT, none right; fitted vx was 207…297 pt/s.
    static let driftRange: ClosedRange<CGFloat> = -300...(-205)

    /// Where a ball enters, as a fraction of field width — the measured back-extrapolated
    /// entry points of the six clean reference tracks (0.60, 0.92, 1.00, 1.03, 1.05,
    /// 1.10 W), widened slightly at the bottom.
    ///
    /// This range is load-bearing, not cosmetic. With the drift at 205–300 pt/s a ball
    /// needs roughly 235–345 pt of runway to reach the floor at all, so a lower bound
    /// much under ~0.55 W spends balls that exit stage left before they ever bounce.
    /// An earlier 0.25 W (guessed from four short, low-confidence reference tracks that
    /// were probably clipped left-spawners) cost about half the burst its bounce.
    static let spawnXRange: ClosedRange<CGFloat> = 0.55...1.10

    /// In-flight tumble. The reference turned ~90° over ~0.8 s before its first
    /// contact ⇒ order 110°/s, either direction.
    static let flightSpinRange: ClosedRange<CGFloat> = -150...150

    /// Post-contact tumble. The reference's bounding box cycled every ~0.25 s after
    /// the floor hit ⇒ ~720°/s, in the rolling direction.
    static let bounceSpinRange: ClosedRange<CGFloat> = 550...750

    /// The floor sits on the visible surface below the map: the sheet's peek plus the
    /// tab-bar reserve. (The reference bounced on the top of its own bottom bar.)
    static let floorInset: CGFloat = MapSheet.tabBarReserve + MapSheet.peekHeight

    /// One integration step. Returns a NEW ball — never mutates (house rule).
    static func stepped(_ ball: TownRainBall, dt: CGFloat, floorY: CGFloat) -> TownRainBall {
        let vy = ball.vy + gravity * dt
        let x = ball.x + ball.vx * dt
        let y = ball.y + vy * dt
        let angle = ball.angle + ball.spin * dt
        let radius = ball.size / 2

        guard y + radius >= floorY, vy > 0 else {
            return TownRainBall(id: ball.id, logoIndex: ball.logoIndex, x: x, y: y,
                                vx: ball.vx, vy: vy, angle: angle, spin: ball.spin,
                                bounceSpin: ball.bounceSpin,
                                size: ball.size, hasBounced: ball.hasBounced)
        }

        // Floor contact. Solve for the instant the ball's bottom edge actually reaches
        // the plane and reflect the velocity IT had there, rather than the velocity at
        // the end of the step: reflecting the end-of-step value folds up to a whole
        // frame of extra gravity into the rebound, which makes the effective
        // restitution depend on the display's refresh rate (a 60 Hz device would bounce
        // measurably harder than a 120 Hz one). Solving `½g·t² + v₀·t - gap = 0` keeps
        // the bounce identical at any frame rate.
        let gap = floorY - radius - ball.y                  // distance left to fall
        let tContact = gap <= 0
            ? 0
            : (( -ball.vy + (ball.vy * ball.vy + 2 * gravity * gap).squareRoot() ) / gravity)
        let vImpact = ball.vy + gravity * min(max(tContact, 0), dt)

        // Settle exactly ON the plane so the ball can never sink through it, and — on
        // the FIRST contact only — switch to this ball's own post-bounce tumble, in the
        // direction it is rolling.
        let spin = ball.hasBounced
            ? ball.spin
            : (ball.vx < 0 ? -ball.bounceSpin : ball.bounceSpin)

        return TownRainBall(id: ball.id, logoIndex: ball.logoIndex,
                            x: x, y: floorY - radius,
                            vx: ball.vx, vy: -vImpact * restitution,
                            angle: angle, spin: spin,
                            bounceSpin: ball.bounceSpin,
                            size: ball.size, hasBounced: true)
    }

    /// A ball lives until it leaves the field to the left (the drift's destination)
    /// or falls out of the bottom. It is NOT culled above the top edge — that is
    /// where it spawns.
    static func isAlive(_ ball: TownRainBall, in bounds: CGSize) -> Bool {
        let radius = ball.size / 2
        if ball.x + radius < 0 { return false }
        if ball.y - radius > bounds.height { return false }
        return true
    }
}

// MARK: - The emitter

/// Owns one press-worth of rain: the spawn clock, the deterministic draw of which
/// brand marks fall, and the live balls. A value type stepped by `advanced(by:)`, so
/// a test can replay a whole burst with no view attached.
struct TownRainEmitter: Equatable {

    private(set) var balls: [TownRainBall] = []
    private(set) var spawnedCount = 0

    private let bounds: CGSize
    private let floorY: CGFloat
    /// Logo indices in the order they will fall — pre-shuffled so no mark repeats
    /// inside one burst.
    private let deck: [Int]
    private var rng: SplitMix64
    private var timeToNextSpawn: CGFloat = 0
    private var nextID = 0

    init(seed: UInt64, logoCount: Int, bounds: CGSize) {
        self.bounds = bounds
        self.floorY = max(bounds.height * 0.4, bounds.height - TownRainPhysics.floorInset)
        var generator = SplitMix64(seed: seed)
        self.deck = TownRainEmitter.deal(count: TownRainPhysics.burstCount,
                                         from: max(logoCount, 1),
                                         using: &generator)
        self.rng = generator
    }

    /// The burst is over once every ball has been emitted and the last one has left.
    var isFinished: Bool {
        spawnedCount >= TownRainPhysics.burstCount && balls.isEmpty
    }

    /// Advance the whole field by `dt`. Existing balls integrate FIRST, then any new
    /// ball is placed — so a ball's first rendered frame is exactly its spawn state
    /// (at rest, above the top edge), matching the reference's entry.
    func advanced(by dt: CGFloat) -> TownRainEmitter {
        var next = self
        next.balls = balls
            .map { TownRainPhysics.stepped($0, dt: dt, floorY: floorY) }
            .filter { TownRainPhysics.isAlive($0, in: bounds) }

        next.timeToNextSpawn -= dt
        while next.timeToNextSpawn <= 0 && next.spawnedCount < TownRainPhysics.burstCount {
            next.balls.append(next.makeBall())
            next.spawnedCount += 1
            next.timeToNextSpawn += TownRainPhysics.spawnInterval
        }
        return next
    }

    private mutating func makeBall() -> TownRainBall {
        let id = nextID
        nextID += 1
        let size = TownRainPhysics.ballSize
        return TownRainBall(
            id: id,
            logoIndex: deck[min(spawnedCount, deck.count - 1)],
            x: bounds.width * rng.next(in: TownRainPhysics.spawnXRange),
            y: -size / 2,                                   // one half-ball above the edge
            vx: rng.next(in: TownRainPhysics.driftRange),
            vy: 0,                                          // enters under gravity alone
            angle: rng.next(in: 0...360),
            spin: rng.next(in: TownRainPhysics.flightSpinRange),
            bounceSpin: rng.next(in: TownRainPhysics.bounceSpinRange),
            size: size,
            hasBounced: false
        )
    }

    /// `count` distinct logo indices when the pool is big enough, otherwise a cycled
    /// shuffle — so a 3-logo town still rains without three identical marks in a row.
    private static func deal(count: Int, from poolSize: Int,
                             using rng: inout SplitMix64) -> [Int] {
        var dealt: [Int] = []
        while dealt.count < count {
            var pool = Array(0..<poolSize)
            for i in stride(from: pool.count - 1, to: 0, by: -1) {
                pool.swapAt(i, Int(rng.next(upperBound: UInt64(i + 1))))
            }
            dealt += pool
        }
        return Array(dealt.prefix(count))
    }
}

// MARK: - Deterministic RNG

/// SplitMix64 — small, fast, and reproducible, so a seed replays a burst exactly
/// (the verification loop diffs recorded runs frame for frame).
struct SplitMix64: Equatable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        upperBound == 0 ? 0 : next() % upperBound
    }

    /// Uniform in `range`, to 1/10000 of its width.
    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let steps: UInt64 = 10_000
        let t = CGFloat(next(upperBound: steps + 1)) / CGFloat(steps)
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }
}
