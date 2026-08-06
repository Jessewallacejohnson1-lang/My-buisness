//
//  TownRainPhysics.swift
//  Block Party — the pure, testable model behind the town-rain drop.
//
//  Pressing "Saint Joseph" (the town pill) or the recenter control flies the camera
//  home; while it flies, ONE real local brand mark drops into the screen and bounces
//  around it — off the side walls and off the map sheet's live top edge, wherever the
//  user has dragged the sheet to — until it runs out of bounce, settles, and fades.
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
//  The rest is CHOSEN, because the reference could not supply it. Its sprites rained
//  many at once, always drifted left, never touched a wall and left the screen rather
//  than settling — so it has nothing to say about any of the following, and each one
//  carries its own note explaining the call:
//    • `burstCount` — one mark per press, not a rain.
//    • `floorInset` — this app's contact surface is its own map sheet.
//    • `spawnXRange` — entry spread across the middle, not biased to one side.
//    • the DIRECTION of `driftSpeedRange` (the magnitude is measured).
//    • `wallRestitution`, `restSpeed`, `rollingDrag`, `fadeDuration` — the whole
//      closed-field behaviour, which the reference simply does not have.
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
    /// Seconds the ball has spent settled on the floor with no bounce left in it. The
    /// renderer fades it out over this, which is how a ball that can no longer leave
    /// the field (the walls keep it in) ends its life.
    let restTime: CGFloat
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

    /// Balls per press — ONE. The reference rained many at once, but here each press of
    /// the town pill drops a single mark that then has the whole screen to bounce
    /// around in, so the press and the object stay one-to-one. Tapping again replaces
    /// the ball in flight rather than stacking a second one.
    static let burstCount = 1

    /// Speed of the sideways drift. The MAGNITUDE is the reference's (fitted vx was
    /// 207…297 pt/s across all ten tracks) but the DIRECTION is not: every reference
    /// sprite drifted left, because its rain exited stage left and never touched a wall.
    /// Here one ball has to stay in play, and an always-left drift walks it into the
    /// left wall, loses 38% of its speed on each return, and parks it in the corner
    /// within a couple of seconds. Drawing the side per ball uses the whole field.
    static let driftSpeedRange: ClosedRange<CGFloat> = 205...300

    /// Where the ball enters, as a fraction of field width. The reference's entry points
    /// back-extrapolate to 0.60–1.10 W, but that range only made sense paired with an
    /// always-left drift that needed runway before exiting. With walls closing the field
    /// and the drift going either way, entry is spread across the middle instead — fully
    /// on screen, so the mark is legible from the first frame.
    static let spawnXRange: ClosedRange<CGFloat> = 0.15...0.85

    /// In-flight tumble. The reference turned ~90° over ~0.8 s before its first
    /// contact ⇒ order 110°/s, either direction.
    static let flightSpinRange: ClosedRange<CGFloat> = -150...150

    /// Post-contact tumble. The reference's bounding box cycled every ~0.25 s after
    /// the floor hit ⇒ ~720°/s, in the rolling direction.
    static let bounceSpinRange: ClosedRange<CGFloat> = 550...750

    /// Fallback floor, used only before the sheet has published its live top edge: the
    /// sheet at rest on peek. Normally the floor IS the sheet's current top, so a ball
    /// lands on the sheet wherever the user has dragged it to.
    static let floorInset: CGFloat = MapSheet.tabBarReserve + MapSheet.peekHeight

    // --- The following four are CHOSEN, not measured: the reference's sprites left
    // stage left and never touched a wall, so it has nothing to say about any of them.

    /// Side walls. Springier than the floor so a ball actually travels back across the
    /// screen instead of dying against the edge — that return is most of what reads as
    /// "free flowing" rather than "falling past".
    static let wallRestitution: CGFloat = 0.62

    /// Once a floor contact is slower than this the ball has no bounce left; it stops
    /// jittering, settles, and starts its fade. Below ~40 pt/s the hops are sub-pixel
    /// and read as buzzing.
    static let restSpeed: CGFloat = 40

    /// Rolling drag on a settled ball, as a per-second fraction of its speed. It coasts
    /// to a stop instead of sliding forever at constant velocity.
    static let rollingDrag: CGFloat = 1.7

    /// How long a settled ball takes to fade out once it stops.
    static let fadeDuration: CGFloat = 0.8

    /// One integration step. Returns a NEW ball — never mutates (house rule).
    ///
    /// `floorY` is passed per step, not baked in at spawn, because the floor IS the map
    /// sheet's live top edge: drag the sheet mid-flight and the ball lands on it where
    /// it now is. `width` closes the field at the sides — without walls a ball just
    /// leaves, and one ball leaving immediately is not much of an animation.
    static func stepped(_ ball: TownRainBall, dt: CGFloat,
                        floorY: CGFloat, width: CGFloat) -> TownRainBall {
        let radius = ball.size / 2

        var vx = ball.vx
        var vy = ball.vy + gravity * dt
        var x = ball.x + vx * dt
        var y = ball.y + vy * dt
        var spin = ball.spin
        var hasBounced = ball.hasBounced
        var restTime = ball.restTime

        // --- Side walls -----------------------------------------------------------
        // Reflect and settle exactly on the wall, so a ball pinned into a corner by a
        // rising sheet can never creep through it over successive frames.
        if x - radius <= 0, vx < 0 {
            x = radius
            vx = -vx * wallRestitution
            spin = -spin * wallRestitution      // the tumble turns around with it
        } else if x + radius >= width, vx > 0 {
            x = width - radius
            vx = -vx * wallRestitution
            spin = -spin * wallRestitution
        }

        // --- Floor ----------------------------------------------------------------
        if y + radius >= floorY, vy > 0 {
            // Solve for the instant the bottom edge actually reaches the plane and
            // reflect the velocity IT had there, rather than the velocity at the end of
            // the step: reflecting the end-of-step value folds up to a whole frame of
            // extra gravity into the rebound, which would make the bounce depend on the
            // display's refresh rate.
            let gap = floorY - radius - ball.y
            let tContact = gap <= 0
                ? 0
                : (( -ball.vy + (ball.vy * ball.vy + 2 * gravity * gap).squareRoot() ) / gravity)
            let vImpact = ball.vy + gravity * min(max(tContact, 0), dt)

            y = floorY - radius

            if vImpact < restSpeed {
                // Nothing left to bounce with — settle rather than buzz sub-pixel hops.
                vy = 0
                restTime += dt
            } else {
                vy = -vImpact * restitution
                if !hasBounced {
                    spin = ball.vx < 0 ? -ball.bounceSpin : ball.bounceSpin
                    hasBounced = true
                }
            }
        } else if restTime > 0 {
            // Settled last frame, and the floor moved out from under it (the sheet was
            // dragged down) — it is airborne again, so cancel the fade and let it fall.
            restTime = 0
        }

        // --- Rolling ---------------------------------------------------------------
        // A settled ball coasts to a stop instead of sliding at constant speed forever.
        if restTime > 0 {
            let decay = max(0, 1 - rollingDrag * dt)
            vx *= decay
            spin *= decay
        }

        return TownRainBall(id: ball.id, logoIndex: ball.logoIndex, x: x, y: y,
                            vx: vx, vy: vy,
                            angle: ball.angle + spin * dt, spin: spin,
                            bounceSpin: ball.bounceSpin, size: ball.size,
                            hasBounced: hasBounced, restTime: restTime)
    }

    /// 1 while the ball is live, ramping to 0 over `fadeDuration` once it has settled.
    static func opacity(_ ball: TownRainBall) -> CGFloat {
        guard ball.restTime > 0 else { return 1 }
        return max(0, 1 - ball.restTime / fadeDuration)
    }

    /// With walls closing the field, a ball no longer exits sideways — it lives until
    /// it has settled and finished fading. The bottom check is a backstop for a ball
    /// that was somehow left below the field (e.g. the sheet collapsed away beneath a
    /// settled ball and it fell past the screen). It is NOT culled above the top edge —
    /// that is where it spawns.
    static func isAlive(_ ball: TownRainBall, in bounds: CGSize) -> Bool {
        if ball.restTime >= fadeDuration { return false }
        if ball.y - ball.size / 2 > bounds.height { return false }
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
    /// Fallback until the sheet publishes its live top (see `advanced(by:floorY:)`).
    private let restingFloorY: CGFloat
    /// Logo indices in the order they will fall — pre-shuffled so no mark repeats
    /// inside one burst.
    private let deck: [Int]
    private var rng: SplitMix64
    private var timeToNextSpawn: CGFloat = 0
    private var nextID = 0

    init(seed: UInt64, logoCount: Int, bounds: CGSize) {
        self.bounds = bounds
        self.restingFloorY = max(bounds.height * 0.4,
                                 bounds.height - TownRainPhysics.floorInset)
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
    /// `floorY` is the map sheet's current top edge in field coordinates. Pass nil
    /// before it is known and the sheet's resting (peek) top is used.
    func advanced(by dt: CGFloat, floorY: CGFloat? = nil) -> TownRainEmitter {
        var next = self
        // Never let the floor rise above the top of the field, or a ball would spawn
        // already below it and be pinned there.
        let plane = min(max(floorY ?? restingFloorY, TownRainPhysics.ballSize),
                        bounds.height)
        next.balls = balls
            .map { TownRainPhysics.stepped($0, dt: dt, floorY: plane, width: bounds.width) }
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
            vx: rng.next(in: TownRainPhysics.driftSpeedRange)
                * (rng.next(upperBound: 2) == 0 ? -1 : 1),
            vy: 0,                                          // enters under gravity alone
            angle: rng.next(in: 0...360),
            spin: rng.next(in: TownRainPhysics.flightSpinRange),
            bounceSpin: rng.next(in: TownRainPhysics.bounceSpinRange),
            size: size,
            hasBounced: false,
            restTime: 0
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
