//
//  LaunchMotionTests.swift
//  Block Party — the launch moves as the approved mock does (BP app references/launch-ball,
//  round 5; references/launch-short since 2026-11-08: Bp! 320 pt, B and p shrinking toward the !,
//  the short cut, the link open, the curtain). Every expected number here was read off the mock's
//  own script (its frozen frames write `data-probe`), on its 402 x 874 phone, so a drift in the
//  port fails here before anyone has to see it.
//

import XCTest
import SwiftUI
@testable import BlockParty

final class LaunchMotionTests: XCTestCase {

    private let phone = CGSize(width: 402, height: 874)
    private let tab = CGRect(x: 113.6, y: 813, width: 39.15, height: 22)
    private var motion: LaunchMotion { LaunchMotion(screen: phone) }

    /// The drop, the two arcs and the landing take the mock's times, and Bp! its 320 pt with Bp
    /// in the screen's middle.
    func testBeatsLandWhenTheMocksDo() {
        XCTAssertEqual(motion.hitB, 0.240763, accuracy: 1e-5)
        XCTAssertEqual(motion.hitP, 0.603148, accuracy: 1e-5)
        XCTAssertEqual(motion.landAt, 0.947188, accuracy: 1e-5)
        XCTAssertEqual(motion.ballEnd, 0.997188, accuracy: 1e-5)
        XCTAssertEqual(motion.origin.x, 61.292993, accuracy: 1e-4)
        XCTAssertEqual(motion.origin.y, 342.193110, accuracy: 1e-4)
        XCTAssertEqual(LaunchMotion.centring.width, 20.293, accuracy: 0.001, "Bp, shrunk toward the !, sits in the screen's middle")
        XCTAssertEqual(LaunchMotion.centring.height, -4.9, accuracy: 0.001)
        XCTAssertEqual(LaunchMotion.canvas.width * LaunchMotion.scale, 320, accuracy: 1e-9)
        XCTAssertEqual(LaunchMotion.ball, 49.491327, accuracy: 1e-4)   // the mock scales round 1's ball; this scales the canvas
        XCTAssertEqual(LaunchMotion.dot, 43.035936, accuracy: 1e-4)
    }

    /// B and p shrink toward the !'s dot, so the ball lands on their tops where the mock's does.
    func testLettersShrinkTowardTheBang() {
        XCTAssertEqual(LaunchMotion.letterAnchor, CGPoint(x: 781, y: 627))
        XCTAssertEqual(motion.ball(at: motion.hitB).x, 141.655148, accuracy: 1e-4)
        XCTAssertEqual(motion.ball(at: motion.hitP).x, 258.619154, accuracy: 1e-4)
    }

    /// The ball flies, squashes and rides the letters where the mock's does: in the air, on B,
    /// over the arc, on p, shrinking into the dot, squashed on it, and at rest.
    func testBallFollowsTheMock() {
        // t, x, y, r, roll, sx, sy, heading
        let mock: [(Double, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            // launch-short's mock: Bp! 320 pt, the ball riding B and p at their 90%, shrunk toward the !
            (0.05, 77.189647, -2.900131, 24.745663, -95.079275, 1.088693, 0.918533, 71.835777),
            (0.2, 127.879781, 237.099869, 24.745663, -20.317099, 1.179685, 0.847684, 81.148424),
            (0.261, 141.655148, 345.114331, 24.745663, 0, 1.395595, 0.656004, 0),
            (0.45, 201.276964, 254.839603, 24.745663, 183.508197, 1.032203, 0.968801, 17.956767),
            (0.633, 258.619154, 375.42974, 24.745663, 360, 1.394911, 0.656599, 0),
            (0.8, 297.115678, 329.991942, 23.134584, 539.794156, 1.034889, 0.966287, 52.066146),
            (0.972, 335.700351, 468.7055, 21.517968, 720, 1.367974, 0.680022, 0),
            (1.097, 335.700351, 461.820231, 21.517968, 720, 1, 1, 0),
        ]
        for (t, x, y, r, roll, sx, sy, heading) in mock {
            let b = motion.ball(at: t)
            XCTAssertEqual(b.x, x, accuracy: 1e-3, "x at \(t)")
            XCTAssertEqual(b.y, y, accuracy: 1e-3, "y at \(t)")
            XCTAssertEqual(b.r, r, accuracy: 1e-3, "r at \(t)")
            XCTAssertEqual(b.roll, roll, accuracy: 1e-3, "roll at \(t)")
            XCTAssertEqual(b.sx, sx, accuracy: 1e-4, "sx at \(t)")
            XCTAssertEqual(b.sy, sy, accuracy: 1e-4, "sy at \(t)")
            XCTAssertEqual(b.heading, heading, accuracy: 1e-3, "heading at \(t)")
        }
    }

    /// B and p start at 90% and dip and bulge on their hit as the mock's springs do (here Apple's
    /// `Spring`), staying at 90% till the jump.
    func testLettersDipOnTheirHitsAndStaySmall() {
        let m = motion
        XCTAssertEqual(m.frame(at: 0.1).b.width, 0.9, accuracy: 1e-9)
        // after the hit, B's dip and p's dip (the mock's springs, which don't move with the geometry)
        for (t, dB, dP) in [(m.hitB + 0.05, 0.075598, 0.0), (m.hitB + 0.2, 0.007894, 0.0), (m.hitP + 0.1, nil, 0.07775)] {
            let f = m.frame(at: t)
            if let dB {
                XCTAssertEqual(f.b.height, 0.9 * (1 - dB), accuracy: 1e-5, "B at \(t)")
                XCTAssertEqual(f.b.width, 0.9 * (1 + 0.45 * dB), accuracy: 1e-5, "B at \(t)")
            }
            XCTAssertEqual(f.p.height, 0.9 * (1 - dP), accuracy: 1e-5, "p at \(t)")
        }
        XCTAssertEqual(m.frame(at: m.landAt + 0.11).b.width, 0.9, accuracy: 0.002, "still 90% as the ball lands")
    }

    /// As the ball becomes the dot, Bp! jumps as one on the mock's keyframes: it crouches while
    /// the !'s line grows out of the dot, rises the tab bar's 4 pt with B and p growing to full
    /// size, hangs 0.4 pt higher, lands all together with a squash, and settles.
    func testBpJumpsAsOne() {
        let m = motion
        let pop = m.landAt + 0.12
        // h, lift, width, height, and B and p's size
        let keys: [(Double, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.07, 0, 1.10, 0.86, 0.9),
            (0.23, -4, 0.95, 1.08, 1),
            (0.37, -4.4, 1, 1, 1),
            (0.49, 0, 0.97, 1.05, 1),
            (0.55, 0, 1.14, 0.84, 1),
            (0.71, 0, 1, 1, 1),
        ]
        for (h, lift, w, ht, k) in keys {
            let f = m.frame(at: pop + h)
            XCTAssertEqual(f.lift, lift, accuracy: 1e-6, "lift at \(h)")
            XCTAssertEqual(f.dot.width, w, accuracy: 1e-6, "dot width at \(h)")
            XCTAssertEqual(f.dot.height, ht, accuracy: 1e-6, "dot height at \(h)")
            // The line alone compresses on the way up, where the rest stretches.
            let compressed = h == 0.23
            XCTAssertEqual(f.line.height, compressed ? 0.94 : ht, accuracy: 1e-6, "line height at \(h)")
            XCTAssertEqual(f.line.width, compressed ? 1.027 : w, accuracy: 1e-6, "line width at \(h)")
            XCTAssertEqual(f.b.height, k * ht, accuracy: 0.002, "B at \(h)")
            XCTAssertEqual(f.p.width, k * w, accuracy: 0.01, "p at \(h)")   // p's dip from its hit is still dying down
        }
        // 30 ms into the crouch the line is 0.52 of its height, growing out of the dot on a plain
        // ease-out (the mock's sharp one had it at 0.81 already: a pop, 2026-11-07).
        XCTAssertEqual(m.frame(at: pop + 0.03).line.height, 0.519999, accuracy: 1e-4)
        XCTAssertEqual(m.frame(at: pop - 0.01).line.height, 0)
        XCTAssertEqual(m.frame(at: pop + LaunchMotion.jumpLands - 0.001).buzzes, 3)
        XCTAssertEqual(m.frame(at: pop + LaunchMotion.jumpLands).buzzes, 4, "one firm buzz as it lands")
    }

    /// The ball's shadow on the glass closes in under it as it comes down, and goes with it.
    func testTheBallsShadowClosesInAsItComesDown() {
        let m = motion
        let high = m.frame(at: 0.05), near = m.frame(at: m.hitB - 0.005)
        XCTAssertGreaterThan(high.shadeDrop, near.shadeDrop)
        XCTAssertGreaterThan(high.shadeBlur, near.shadeBlur)
        XCTAssertLessThan(high.shadeOpacity, near.shadeOpacity)
        XCTAssertLessThan(near.shadeDrop, 6)
        XCTAssertEqual(m.frame(at: m.landAt + 0.2).shadeOpacity, 0, "gone once the ball is the dot")
    }

    /// Bp! leaps into the tab bar's Bp!: it crouches onto its foot, is tossed up and down into the
    /// slot leaning 12°, lands with a squash as the tab bar dips with it, and the launch is done
    /// 3.80 s after the still, once the squash has played out (2.96 s before 2026-11-07). A tap
    /// belongs to the launch until its yellow is mostly gone.
    func testLeapsIntoTheTabBarsBp() {
        let target = tab
        let m = LaunchMotion(screen: phone, ending: .tab(target))
        let endAt = m.landAt + 0.12 + 0.63
        let canvas = LaunchMotion.canvas
        func foot(_ f: LaunchMotion.Frame) -> CGPoint {
            CGPoint(x: f.markOrigin.x + canvas.width * f.markScale / 2, y: f.markOrigin.y + canvas.height * f.markScale)
        }
        let rest = foot(m.frame(at: endAt - 0.01))
        XCTAssertEqual(m.frame(at: endAt - 0.01).markOrigin, m.origin)
        XCTAssertEqual(m.frame(at: endAt + 0.07 - 1e-9).markSquash.height, 0.9, accuracy: 1e-6, "crouched")
        XCTAssertLessThan(foot(m.frame(at: endAt + 0.07 + 0.26 / 4)).y, rest.y - 40, "tossed up first")
        XCTAssertEqual(m.frame(at: endAt + 0.07 + 0.13).markTilt, -12, accuracy: 1e-6)
        let landed = m.frame(at: endAt + 0.07 + 0.26 + 0.05)
        XCTAssertEqual(canvas.width * landed.markScale, target.width, accuracy: 1e-6)
        XCTAssertGreaterThan(landed.tabDip, 1, "the tab bar catches it")
        XCTAssertEqual(foot(landed).x, target.midX, accuracy: 1e-6)
        XCTAssertEqual(foot(landed).y, target.maxY + landed.tabDip, accuracy: 1e-6)
        var t = 0.0
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertEqual(t / m.pace, 3.80, accuracy: 0.03)
        let last = m.frame(at: t)
        XCTAssertEqual(last.tabDip, 0, accuracy: 0.5, "the rest eases out once it's done")
        XCTAssertEqual(last.yellow, 0, accuracy: 0.001)
        XCTAssertEqual(last.backScale, 1, accuracy: 0.001)
        XCTAssertEqual(last.buzzes, 5)
        XCTAssertTrue(m.frame(at: endAt).takesTaps)
        XCTAssertFalse(m.frame(at: endAt + 0.32).takesTaps, "the yellow is mostly gone 0.32 s into the curtain")
        // LaunchBallTests holds 2.2 to tap through: the yellow gone, the launch still on screen.
        XCTAssertFalse(m.frame(at: 2.2).takesTaps)
        XCTAssertFalse(m.frame(at: 2.2).done)
    }

    /// Into the tab bar the yellow is a curtain: its pictures stay solid and fall off the bottom of
    /// the screen in 0.36 s, gathering speed; a zoom still fades it (Jesse, 2026-11-08).
    func testTheYellowFallsAsACurtainIntoTheTabBar() {
        let m = LaunchMotion(screen: phone, ending: .tab(tab))
        let endAt = m.landAt + 0.12 + 0.63
        let before = m.frame(at: endAt - 0.01)
        XCTAssertEqual(before.yellowDrop, 0)
        XCTAssertEqual(before.yellowOpacity, 1)
        let half = m.frame(at: endAt + 0.18)
        XCTAssertEqual(half.yellowDrop, 874 * 0.25, accuracy: 1e-6, "a quarter of the way at half time: it gathers speed")
        XCTAssertEqual(half.yellow, 0.75, accuracy: 1e-6)
        XCTAssertEqual(half.yellowOpacity, 1, "solid as it falls")
        let gone = m.frame(at: endAt + 0.36)
        XCTAssertEqual(gone.yellowDrop, 874, accuracy: 1e-6)
        XCTAssertEqual(gone.yellow, 0, accuracy: 1e-9)
        XCTAssertEqual(m.frame(at: endAt + 0.5).yellowOpacity, 1)
        // After a tap the curtain falls in 0.22 s.
        let tapped = LaunchMotion(screen: phone, skip: 0.1, ending: .tab(tab))
        XCTAssertEqual(tapped.frame(at: 0.1 + 0.16 + 0.10 + 0.22).yellowDrop, 874, accuracy: 1e-6)
        // A zoom fades: nothing drops.
        let zoom = LaunchMotion(screen: phone, ending: .zoom)
        for t in stride(from: 0.0, through: 3, by: 0.1) {
            let f = zoom.frame(at: t)
            XCTAssertEqual(f.yellowDrop, 0, "zoom at \(t)")
            XCTAssertEqual(f.yellowOpacity, f.yellow, accuracy: 1e-9, "zoom at \(t)")
        }
    }

    /// The short cut (after the day's two full shows): the ball drops straight into the dot from
    /// above it, shrinking on the way, B and p never dip, the jump has no hang, and it all plays at
    /// full speed, done within 1.6 s of the still.
    func testTheShortCutDropsStraightIntoTheDot() {
        let m = LaunchMotion(screen: phone, ending: .tab(tab), kind: .short)
        XCTAssertEqual(m.pace, 1)
        XCTAssertEqual(m.hitB, .infinity)
        XCTAssertEqual(m.hitP, .infinity)
        XCTAssertEqual(m.landAt, 0.289523, accuracy: 1e-5)
        XCTAssertEqual(m.ballEnd, 0.339523, accuracy: 1e-5)
        let rest = m.ball(at: 5)
        for t in [0.0, 0.1, 0.25] {
            XCTAssertEqual(m.ball(at: t).x, rest.x, accuracy: 1e-9, "straight down at \(t)")
        }
        XCTAssertEqual(m.ball(at: 0).r, 24.745663, accuracy: 1e-5)
        XCTAssertEqual(m.ball(at: 0).y, -44.900131, accuracy: 1e-5)
        XCTAssertEqual(m.ball(at: m.landAt - 1e-9).r, 21.517968, accuracy: 1e-3, "the dot's size as it arrives")
        XCTAssertGreaterThan(m.ball(at: 0.15).r, 22, "still shrinking on the way down")
        let squashed = m.ball(at: 0.3)   // the mock at 300 ms
        XCTAssertEqual(squashed.y, 466.032586, accuracy: 1e-4)
        XCTAssertEqual(squashed.sx, 1.225124, accuracy: 1e-5)
        XCTAssertEqual(squashed.sy, 0.80424, accuracy: 1e-5)
        XCTAssertEqual(m.ball(at: 0.4).y, 461.820231, accuracy: 1e-4)
        let early = m.frame(at: 0.2)
        XCTAssertEqual(early.b, CGSize(width: 0.9, height: 0.9), "no dip: nothing hits B")
        XCTAssertEqual(early.p, CGSize(width: 0.9, height: 0.9))
        XCTAssertEqual(early.shadeOpacity, max(0.06, 0.30 - 0.0012 * Double(rest.y - m.ball(at: 0.2).y)), accuracy: 1e-6,
                       "the shadow waits under the dot")
        let pop = m.landAt + 0.12
        XCTAssertEqual(m.frame(at: pop + 0.23).lift, -4, accuracy: 1e-6, "up")
        XCTAssertEqual(m.frame(at: pop + 0.35).lift, 0, accuracy: 1e-6, "down with no hang")
        XCTAssertEqual(m.frame(at: pop + 0.35 - 0.001).buzzes, 1)
        XCTAssertEqual(m.frame(at: pop + 0.35).buzzes, 2, "the dot, then the landing")
        XCTAssertEqual(m.frame(at: pop + 0.49 - 0.01).markOrigin, m.origin, "the leap starts at 0.49")
        XCTAssertNotEqual(m.frame(at: pop + 0.49 + 0.2).markOrigin, m.origin)
        // Bp! is in the slot and the curtain down about 1.3 s after the still; what's left of its
        // squash, under 1%, plays out unseen after (the launch is done at 2.05 s).
        let slot = pop + 0.49 + 0.07 + 0.26
        XCTAssertLessThan(slot / m.pace, 1.3)
        XCTAssertEqual(LaunchMotion.canvas.width * m.frame(at: slot + 0.01).markScale, tab.width, accuracy: 1e-6)
        var t = 0.0
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertLessThan(t / m.pace, 2.1)
        XCTAssertEqual(m.frame(at: t).buzzes, 3)
        XCTAssertEqual(LaunchMotion.buzzKinds(.short).count, 3)
        XCTAssertEqual(LaunchMotion.buzzKinds(.full).count, 5)
        XCTAssertLessThan(m.frame(at: pop + 0.49 + 0.36).yellow, 0.001, "the curtain is down by about 1.3 s")
    }

    /// A link open: no ball; the ! appears in 0.12 s as B and p grow, then Bp! pops out (the zoom
    /// on the fast spring) over the page the link opened, done well inside a second. A tap jumps
    /// to the pop. No buzzes.
    func testALinkOpenPopsOutOverThePage() {
        let m = LaunchMotion(screen: phone, ending: .zoom, kind: .link)
        XCTAssertEqual(m.pace, 1)
        XCTAssertEqual(m.landAt, 0)
        for t in [0.0, 0.1, 0.3, 0.6] {
            let f = m.frame(at: t)
            XCTAssertEqual(f.ballOpacity, 0, "no ball at \(t)")
            XCTAssertEqual(f.shadeOpacity, 0, "no shadow at \(t)")
            XCTAssertEqual(f.buzzes, 0)
            XCTAssertEqual(f.lift, 0, "no jump")
        }
        let start = m.frame(at: 0)
        XCTAssertTrue(start.dotShown)
        XCTAssertEqual(start.dotOpacity, 0)
        XCTAssertEqual(start.lineOpacity, 0)
        XCTAssertEqual(start.dot.width, 0.6, accuracy: 1e-9)
        XCTAssertEqual(start.line.height, 0.5, accuracy: 1e-9)
        XCTAssertEqual(start.b.width, 0.9, accuracy: 1e-9)
        XCTAssertEqual(start.backScale, 1.05, accuracy: 1e-9)
        let shown = m.frame(at: 0.12)
        XCTAssertEqual(shown.dotOpacity, 1, accuracy: 1e-9)
        XCTAssertEqual(shown.dot, CGSize(width: 1, height: 1))
        XCTAssertEqual(shown.line, CGSize(width: 1, height: 1))
        XCTAssertEqual(m.frame(at: 0.19).zoom, 1)
        XCTAssertGreaterThan(m.frame(at: 0.3).zoom, 1.5)
        XCTAssertTrue(m.frame(at: 0.4).headerUp)
        XCTAssertEqual(m.frame(at: 0.6).b.width, 1, accuracy: 0.01)
        var t = 0.0
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertLessThan(t, 0.7, "the pop is over well inside a second")
        XCTAssertEqual(m.frame(at: t).yellow, 0, accuracy: 0.001)
        XCTAssertEqual(m.frame(at: t).yellowOpacity, 0, accuracy: 0.001, "a fade, not the curtain")
        let tapped = LaunchMotion(screen: phone, skip: 0.05, ending: .zoom, kind: .link)
        XCTAssertGreaterThan(tapped.frame(at: 0.15).zoom, 1, "a tap jumps to the pop")
        // The link caught the ball mid-air: it fades out where it was as the ! appears.
        let full = LaunchMotion(screen: phone)
        let caught = LaunchMotion(screen: phone, ending: .zoom, kind: .link, ballBefore: full.ball(at: 0.2))
        XCTAssertEqual(caught.frame(at: 0).ball, full.ball(at: 0.2))
        XCTAssertEqual(caught.frame(at: 0).ballOpacity, 1)
        XCTAssertEqual(caught.frame(at: 0.06).ballOpacity, 1 - caught.frame(at: 0.06).dotOpacity, accuracy: 1e-9)
        XCTAssertEqual(caught.frame(at: 0.12).ballOpacity, 0, accuracy: 1e-9)
    }

    /// Nothing on Bp! jumps in one frame of a 120 Hz screen: the crouch lets go and the !'s line
    /// grows over several frames, and the launch ends only once the landing's squash has died
    /// down, not as it swings through rest (2026-11-07, BP app references/launch-glitch).
    func testNothingJumpsInOneFrame() throws {
        let m = LaunchMotion(screen: phone, ending: .tab(tab))
        let step = m.pace / 120
        var last = m.frame(at: 0), t = step, done: Double?
        while t < 5 && done == nil {
            let f = m.frame(at: t)
            XCTAssertLessThan(abs(f.markSquash.height - last.markSquash.height), 0.05, "Bp!'s squash at \(t)")
            XCTAssertLessThan(abs(f.line.height - last.line.height), 0.15, "the !'s line at \(t)")
            if f.done { done = t }
            last = f
            t += step
        }
        let end = try XCTUnwrap(done)
        for after in stride(from: end, to: end + 1, by: 0.005) {
            XCTAssertEqual(m.frame(at: after).markSquash.height, 1, accuracy: 0.01, "still squashing after it's done, at \(after)")
        }
    }

    /// A first open zooms Bp! through, and Welcome's logo and headline may rise half way.
    func testFirstOpenZoomsThrough() {
        let m = LaunchMotion(screen: phone, ending: .zoom)
        let endAt = m.landAt + 0.12 + 0.63
        XCTAssertEqual(m.frame(at: endAt - 0.01).backScale, 1.05, accuracy: 1e-9)
        XCTAssertFalse(m.frame(at: endAt + 0.05).headerUp)
        let half = m.frame(at: endAt + 0.1)   // the glide is at 0.54
        XCTAssertTrue(half.headerUp)
        XCTAssertGreaterThan(half.zoom, 3)
    }

    /// A tap sends the ball into the dot in 0.16 s, grows the letters the ball never reached
    /// without a dip, drops the jump and the buzzes after it, and ends on the fast spring.
    func testATapSkipsToTheDot() {
        let m = LaunchMotion(screen: phone, skip: 0.1)
        let midway = m.frame(at: 0.18)
        XCTAssertEqual(midway.ballOpacity, 1)
        XCTAssertGreaterThan(midway.ball.x, m.ball(at: 0.1).x)
        let landed = m.frame(at: 0.27)
        XCTAssertEqual(landed.ballOpacity, 0)
        XCTAssertTrue(landed.dotShown)
        XCTAssertEqual(landed.lineOpacity, 1)
        XCTAssertEqual(landed.lift, 0, "no jump after a tap")
        XCTAssertEqual(landed.line, CGSize(width: 1, height: 1))
        let late = m.frame(at: 0.33)          // when the ball would have hit B, it isn't there
        XCTAssertEqual(late.b.width, late.b.height, accuracy: 1e-9, "B dipped with no ball on it")
        XCTAssertEqual(m.frame(at: 2).buzzes, 0)
        XCTAssertLessThan(m.frame(at: 0.45).yellow, 0.1, "the yellow goes in 0.18 s from 0.36")
        var t = 0.1
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertLessThan(t, 1, "a skip ends well inside a second")
        XCTAssertEqual(m.frame(at: t).b.width, 1, accuracy: 0.01)
        XCTAssertEqual(m.frame(at: t).p.width, 1, accuracy: 0.01)
    }

    /// With Reduce Motion nothing moves: B and p at the still's 90%, fading over to full size as
    /// the ! line fades in, the crest fading in at the dot and going black, then a fade into the app.
    func testReduceMotionFades() {
        let m = LaunchMotion(screen: phone, reduceMotion: true)
        for t in [0.0, 0.3, 0.6, 0.9] {
            let f = m.frame(at: t)
            XCTAssertEqual(f.b, CGSize(width: 0.9, height: 0.9))
            XCTAssertEqual(f.ball.x, m.ball(at: 5).x)
            XCTAssertEqual(f.ball.y, m.ball(at: 5).y)
        }
        XCTAssertEqual(m.frame(at: 0.075).ballOpacity, 0.5, accuracy: 1e-9)
        XCTAssertTrue(m.frame(at: 0.6).dotShown)
        XCTAssertEqual(m.frame(at: 0.4).fullLetters, 0)
        XCTAssertEqual(m.frame(at: 0.65).fullLetters, 1, accuracy: 1e-9)
        XCTAssertEqual(m.frame(at: 0.65).letters, 1, accuracy: 1e-9, "the full B and p are in before the 90% ones go")
        XCTAssertEqual(m.frame(at: 0.8).letters, 0, accuracy: 1e-9)
        XCTAssertEqual(LaunchMotion(screen: phone).frame(at: 2).fullLetters, 0, "only Reduce Motion fades letters")
        XCTAssertFalse(m.frame(at: 1.0).done)
        XCTAssertTrue(m.frame(at: 0.9).takesTaps)
        XCTAssertFalse(m.frame(at: 1.0).takesTaps)
        XCTAssertTrue(m.frame(at: 1.05).done)
        XCTAssertTrue(LaunchMotion(screen: phone, skip: 0.2, reduceMotion: true).frame(at: 0.45).done)
    }
}
