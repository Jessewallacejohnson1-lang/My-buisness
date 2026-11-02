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
    private var motion: LaunchMotion { LaunchMotion(screen: phone) }

    /// The drop, the two arcs and the landing take the mock's times.
    func testBeatsLandWhenTheMocksDo() {
        XCTAssertEqual(motion.hitB, 0.249537, accuracy: 1e-5)
        XCTAssertEqual(motion.hitP, 0.606587, accuracy: 1e-5)
        XCTAssertEqual(motion.landAt, 0.934977, accuracy: 1e-5)
        XCTAssertEqual(motion.ballEnd, 0.984977, accuracy: 1e-5)
        XCTAssertEqual(motion.origin.x, 76.200045, accuracy: 1e-4)
        XCTAssertEqual(motion.origin.y, 366.872728, accuracy: 1e-4)
        XCTAssertEqual(LaunchMotion.ball, 38.603235, accuracy: 1e-5)
        XCTAssertEqual(LaunchMotion.dot, 33.56803, accuracy: 1e-5)
    }

    /// The ball flies, squashes and rides the letters where the mock's does: in the air, on B,
    /// over the arc, on p, shrinking into the dot, squashed on it, and at rest.
    func testBallFollowsTheMock() {
        // t, x, y, r, roll, sx, sy, heading
        let mock: [(Double, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.05, 56.570006, 2, 19.301618, -95.955516, 1.088527, 0.918672, 72.16454),
            (0.2, 106.280026, 242, 19.301618, -23.822063, 1.179604, 0.847742, 81.316939),
            (0.269537, 122.696753, 368.620435, 19.301618, 0, 1.393737, 0.65762, 0),
            (0.45, 172.085232, 281.017965, 19.301618, 176.409861, 1.027226, 0.973495, 9.454704),
            (0.636587, 223.483933, 392.057318, 19.301618, 360, 1.393737, 0.65762, 0),
            (0.8, 257.872363, 349.081505, 17.985611, 545.454992, 1.032079, 0.968919, 52.295667),
            (0.959977, 290.237784, 465.552767, 16.784015, 720, 1.368, 0.68, 0),
            (1.084977, 290.237784, 460.181882, 16.784015, 720, 1, 1, 0),
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

    /// B and p start at 90%, dip and bulge on their hit and grow past full size and back, as the
    /// mock's springs do (here Apple's `Spring`).
    func testLettersDipAndGrowAsTheMocksDo() {
        let m = motion
        XCTAssertEqual(m.frame(at: 0.1).b.width, 0.9, accuracy: 1e-9)
        // t, B's size, B's dip, p's size, p's dip
        let mock: [(Double, Double, Double, Double, Double)] = [
            (0.299537, 0.923515, 0.075598, 0.9, 0),
            (0.449537, 1.018921, 0.007894, 0.9, 0),
            (0.706587, 0.995825, 0.008735, 0.96725, 0.07775),
        ]
        for (t, kB, dB, kP, dP) in mock {
            let f = m.frame(at: t)
            XCTAssertEqual(f.b.height, kB * (1 - dB), accuracy: 1e-5, "B at \(t)")
            XCTAssertEqual(f.b.width, kB * (1 + 0.45 * dB), accuracy: 1e-5, "B at \(t)")
            XCTAssertEqual(f.p.height, kP * (1 - dP), accuracy: 1e-5, "p at \(t)")
        }
    }

    /// The ! does the Daily tab's own hop (its keyframes, not a copy), its line growing out of
    /// the dot during the crouch, as in the mock.
    @MainActor
    func testTheBangHopsWithTheDailyTabsKeyframes() {
        let mock: [(Double, CGFloat, CGFloat, CGFloat, CGFloat)] = [   // h, line y, line height, dot y, dot height
            (0.1, -2.415791, 0.992868, -1.112729, 1.033382),
            (0.2, -3.97593, 1.078676, -2, 1.06),
            (0.3, -3.188602, 1.043487, -0.804812, 0.934505),
            (0.4, 0, 1.024122, 0, 1),
        ]
        for (h, lineY, lineH, dotY, dotH) in mock {
            let line = DailyMarkGlyph.lineHop.value(time: h), dot = DailyMarkGlyph.dotHop.value(time: h)
            XCTAssertEqual(line.y, lineY, accuracy: 1e-4, "line y at \(h)")
            XCTAssertEqual(line.height, lineH, accuracy: 1e-4, "line height at \(h)")
            XCTAssertEqual(dot.y, dotY, accuracy: 1e-4, "dot y at \(h)")
            XCTAssertEqual(dot.height, dotH, accuracy: 1e-4, "dot height at \(h)")
        }
        // 30 ms into the crouch the mock's line is 0.808 of its height.
        let grown = DailyMarkGlyph.lineHop.value(time: DailyMarkGlyph.crouch).height
            * LaunchMotion.easeOut.value(at: 0.03 / DailyMarkGlyph.crouch)
        XCTAssertEqual(grown, 0.808292, accuracy: 1e-4)
    }

    /// The landed ball goes black, the ! hops, and Bp! glides onto the tab bar's Bp! on the
    /// mock's spring, the whole launch done 2.48 s after the still.
    func testEndsOnTheTabBarsBpAfter248Seconds() {
        let target = CGRect(x: 113.6, y: 813, width: 39.15, height: 22)
        let m = LaunchMotion(screen: phone, ending: .tab(target))
        let endAt = m.landAt + 0.12 + 0.40
        XCTAssertEqual(m.frame(at: m.landAt + 0.12).dotShown, true)
        XCTAssertEqual(m.frame(at: m.landAt + 0.12).hop, 0)
        // The ending's spring, against the mock's. The mock steps its spring at 480 Hz, which runs
        // it about 0.01 ahead of the exact one (Apple's `Spring`): 0.539 against 0.529 at 0.1 s.
        for (tau, p) in [(0.1, 0.539485), (0.2, 0.899941), (0.3, 0.990345), (0.5, 1.001075)] {
            let f = m.frame(at: endAt + tau)
            let progress = (Double(f.markOrigin.y) - Double(m.origin.y)) / (813 - Double(m.origin.y))
            XCTAssertEqual(progress, p, accuracy: 0.012, "glide at \(tau)")
        }
        var t = 0.0
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertEqual(t / LaunchMotion.pace, 2.478, accuracy: 0.03)
        // Done at the spring's last overshoot, under 0.3% past the tab bar's Bp!, as in the mock:
        // a point or less.
        let last = m.frame(at: t)
        XCTAssertEqual(last.markOrigin.x, target.minX, accuracy: 1)
        XCTAssertEqual(last.markOrigin.y, target.minY, accuracy: 1.5)
        XCTAssertEqual(LaunchMotion.canvas.width * last.markScale, target.width, accuracy: 0.7)
        XCTAssertEqual(last.yellow, 0, accuracy: 0.001)
        XCTAssertEqual(last.backScale, 1, accuracy: 0.001)
        XCTAssertEqual(m.frame(at: t).buzzes, 4)
    }

    /// A first open zooms Bp! through, and Welcome's logo and headline may rise half way.
    func testFirstOpenZoomsThrough() {
        let m = LaunchMotion(screen: phone, ending: .zoom)
        let endAt = m.landAt + 0.52
        XCTAssertEqual(m.frame(at: endAt - 0.01).backScale, 1.05, accuracy: 1e-9)
        XCTAssertFalse(m.frame(at: endAt + 0.05).headerUp)
        let half = m.frame(at: endAt + 0.1)   // the glide is at 0.54
        XCTAssertTrue(half.headerUp)
        XCTAssertGreaterThan(half.zoom, 3)
    }

    /// A tap sends the ball into the dot in 0.16 s, grows the letters the ball never reached
    /// without a dip, drops the hop and the buzzes after it, and ends on the fast spring.
    func testATapSkipsToTheDot() {
        let m = LaunchMotion(screen: phone, skip: 0.1)
        let midway = m.frame(at: 0.18)
        XCTAssertEqual(midway.ballOpacity, 1)
        XCTAssertGreaterThan(midway.ball.x, m.ball(at: 0.1).x)
        let landed = m.frame(at: 0.27)
        XCTAssertEqual(landed.ballOpacity, 0)
        XCTAssertTrue(landed.dotShown)
        XCTAssertEqual(landed.lineOpacity, 1)
        XCTAssertNil(landed.hop)
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

    /// With Reduce Motion nothing moves: full-size letters, the crest fading in at the dot and
    /// going black, the ! line fading in, then a fade into the app.
    func testReduceMotionFades() {
        let m = LaunchMotion(screen: phone, reduceMotion: true)
        for t in [0.0, 0.3, 0.6, 0.9] {
            let f = m.frame(at: t)
            XCTAssertEqual(f.b, CGSize(width: 1, height: 1))
            XCTAssertEqual(f.ball.x, m.ball(at: 5).x)
            XCTAssertEqual(f.ball.y, m.ball(at: 5).y)
        }
        XCTAssertEqual(m.frame(at: 0.075).ballOpacity, 0.5, accuracy: 1e-9)
        XCTAssertTrue(m.frame(at: 0.6).dotShown)
        XCTAssertFalse(m.frame(at: 1.0).done)
        XCTAssertTrue(m.frame(at: 1.05).done)
        XCTAssertTrue(LaunchMotion(screen: phone, skip: 0.2, reduceMotion: true).frame(at: 0.45).done)
    }
}
