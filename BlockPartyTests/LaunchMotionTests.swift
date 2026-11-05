//
//  LaunchMotionTests.swift
//  Block Party — the launch moves as the approved mock does (BP app references/launch-ball,
//  round 5). Every expected number here was read off the mock's own script with node, on its
//  402 x 874 phone, so a drift in the port fails here before anyone has to see it.
//

import XCTest
import SwiftUI
@testable import BlockParty

final class LaunchMotionTests: XCTestCase {

    private let phone = CGSize(width: 402, height: 874)
    /// The mock's numbers were read before Bp moved to the screen's middle (2026-11-02): every
    /// position on screen is theirs plus this.
    private let moved = LaunchMotion.centring
    private var motion: LaunchMotion { LaunchMotion(screen: phone) }

    /// The drop, the two arcs and the landing take the mock's times.
    func testBeatsLandWhenTheMocksDo() {
        XCTAssertEqual(motion.hitB, 0.249537, accuracy: 1e-5)
        XCTAssertEqual(motion.hitP, 0.606587, accuracy: 1e-5)
        XCTAssertEqual(motion.landAt, 0.934977, accuracy: 1e-5)
        XCTAssertEqual(motion.ballEnd, 0.984977, accuracy: 1e-5)
        XCTAssertEqual(motion.origin.x, 76.200045 + moved.width, accuracy: 1e-4)
        XCTAssertEqual(motion.origin.y, 366.872728 + moved.height, accuracy: 1e-4)
        XCTAssertEqual(moved.width, 27.5, accuracy: 0.01, "Bp sits 27.5 pt right of where Bp! was centred")
        XCTAssertEqual(LaunchMotion.ball, 38.603235, accuracy: 1e-5)
        XCTAssertEqual(LaunchMotion.dot, 33.56803, accuracy: 1e-5)
    }

    /// The ball flies, squashes and rides the letters where the mock's does: in the air, on B,
    /// over the arc, on p, shrinking into the dot, squashed on it, and at rest.
    func testBallFollowsTheMock() {
        // t, x, y, r, roll, sx, sy, heading
        let mock: [(Double, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            // round 11's mock: Bp in the screen's middle, the ball riding B and p at their 90%
            (0.05, 84.072526, -1.822102, 19.301618, -95.955516, 1.088527, 0.918672, 72.16454),
            (0.2, 133.782546, 238.177898, 19.301618, -23.822063, 1.179604, 0.847742, 81.316939),
            (0.269537, 150.199273, 365.260097, 19.301618, 0, 1.393734, 0.657623, 0),
            (0.45, 199.587752, 277.195863, 19.301618, 176.409861, 1.027226, 0.973495, 9.454704),
            (0.636587, 250.986453, 388.968893, 19.301618, 360, 1.393735, 0.657622, 0),
            (0.8, 285.374883, 345.259403, 17.985611, 545.454992, 1.032079, 0.968919, 52.295667),
            (0.959977, 317.740304, 461.730665, 16.784015, 720, 1.368, 0.68, 0),
            (1.084977, 317.740304, 456.35978, 16.784015, 720, 1, 1, 0),
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
        // t, B's dip, p's dip (the mock's)
        for (t, dB, dP) in [(0.299537, 0.075598, 0.0), (0.449537, 0.007894, 0.0), (0.706587, 0.008735, 0.07775)] {
            let f = m.frame(at: t)
            XCTAssertEqual(f.b.height, 0.9 * (1 - dB), accuracy: 1e-5, "B at \(t)")
            XCTAssertEqual(f.b.width, 0.9 * (1 + 0.45 * dB), accuracy: 1e-5, "B at \(t)")
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
        // 30 ms into the crouch the line is 0.808 of its height, growing out of the dot.
        XCTAssertEqual(m.frame(at: pop + 0.03).line.height, 0.808292, accuracy: 1e-4)
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
    /// 2.96 s after the still. A tap belongs to the launch until its yellow is mostly gone.
    func testLeapsIntoTheTabBarsBp() {
        let target = CGRect(x: 113.6, y: 813, width: 39.15, height: 22)
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
        XCTAssertEqual(t / LaunchMotion.pace, 2.96, accuracy: 0.03)
        let last = m.frame(at: t)
        XCTAssertEqual(last.tabDip, 0, accuracy: 0.5, "the rest eases out once it's done")
        XCTAssertEqual(last.yellow, 0, accuracy: 0.001)
        XCTAssertEqual(last.backScale, 1, accuracy: 0.001)
        XCTAssertEqual(last.buzzes, 5)
        XCTAssertTrue(m.frame(at: endAt).takesTaps)
        XCTAssertFalse(m.frame(at: endAt + 0.2).takesTaps, "the yellow is mostly gone 0.2 s in")
        // LaunchBallTests holds 1.85 to tap through: the yellow gone, the launch still on screen.
        XCTAssertFalse(m.frame(at: 1.85).takesTaps)
        XCTAssertFalse(m.frame(at: 1.85).done)
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
