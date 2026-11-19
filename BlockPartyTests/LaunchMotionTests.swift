//
//  LaunchMotionTests.swift
//  Block Party — the launch moves as the approved mock does (BP app references/splash-fork,
//  round 2, Jesse's yes on 2026-11-18). Every expected number here is the mock's on its
//  402 x 874 phone, worked from the Reference's frames and the mock's own constants, so a drift
//  in the port fails here before anyone has to see it.
//

import XCTest
import SwiftUI
@testable import BlockParty

final class LaunchMotionTests: XCTestCase {

    private let phone = CGSize(width: 402, height: 874)
    private let tab = CGRect(x: 113.6, y: 813, width: 39.15, height: 22)
    private var first: LaunchMotion { LaunchMotion(screen: phone, ending: .tab(tab), kind: .first) }
    private var later: LaunchMotion { LaunchMotion(screen: phone, ending: .tab(tab), kind: .later) }

    /// Every open starts from the one still: the dot, their mark's size, alone in the screen's
    /// middle, drawn by the launch screen's own picture until it first moves.
    func testEveryOpenStartsFromTheDotInTheMiddle() {
        for m in [first, later, LaunchMotion(screen: phone, reduceMotion: true)] {
            let f = m.frame(at: 0)
            XCTAssertTrue(f.still)
            XCTAssertEqual(f.dot, LaunchMotion.Dot(x: 201, y: 437, d: 85))
            XCTAssertFalse(f.letters.contains { $0.shown } && f.wordOpacity > 0)
            XCTAssertEqual(f.pop, 0)
            XCTAssertNil(f.hole)
            XCTAssertEqual(f.yellow, 1)
            XCTAssertEqual(f.buzzes, 0)
        }
        XCTAssertFalse(first.frame(at: 0.09).still, "the Reference's mark moves from 0.083 s")
        XCTAssertFalse(later.frame(at: 0.11).still)
    }

    /// The word ends 70% of the screen wide in its middle, and Bp! sits where it has since
    /// 2026-11-08: 320 pt wide, Bp in the screen's middle.
    func testWhereTheWordAndBpSit() {
        let m = first
        XCTAssertEqual(m.wordBox.width, 281.4, accuracy: 1e-9)
        XCTAssertEqual(m.wordBox.midX, 201, accuracy: 1e-9)
        XCTAssertEqual(m.wordBox.midY, 437, accuracy: 1e-9)
        XCTAssertEqual(m.stop.x, 335.140, accuracy: 1e-3)
        XCTAssertEqual(m.stop.y, 448.111, accuracy: 1e-3)
        XCTAssertEqual(m.stop.d, 12.852, accuracy: 1e-3)
        XCTAssertEqual(LaunchMotion.wordPieces.count, 10)
        XCTAssertEqual(m.origin.x, 61.292993, accuracy: 1e-4)
        XCTAssertEqual(m.origin.y, 342.193110, accuracy: 1e-4)
        XCTAssertEqual(LaunchMotion.canvas.width * LaunchMotion.scale, 320, accuracy: 1e-9)
        XCTAssertEqual(m.bang.x, 335.700, accuracy: 1e-3)
        XCTAssertEqual(m.bang.y, 461.820, accuracy: 1e-3)
        XCTAssertEqual(m.bang.d, 43.035936, accuracy: 1e-4)
        XCTAssertEqual(LaunchMotion.ball, 49.491327, accuracy: 1e-4)
        XCTAssertEqual(LaunchMotion.letterAnchor, CGPoint(x: 781, y: 627))
    }

    /// The first open's dot is on the Reference's path, 402/512 of its pixels: left by 0.40 s,
    /// creeping back and smaller by 0.60 s, then shooting right to end on the full stop, shrinking
    /// in step with its travel and stretched along its speed.
    func testTheDotFollowsTheReference() {
        let m = first
        let left = m.dot(at: 0.40)
        XCTAssertEqual(left.x, 90.686, accuracy: 1e-3)
        XCTAssertEqual(left.y, 437)
        XCTAssertEqual(left.d, 74.769, accuracy: 1e-3)
        let shoots = m.dot(at: 0.60)
        XCTAssertEqual(shoots.x, 105.996, accuracy: 1e-3)
        XCTAssertEqual(shoots.d, 63.75, accuracy: 1e-3)
        let flying = m.dot(at: 0.70)
        XCTAssertEqual(flying.x, 262.570, accuracy: 1e-2)
        XCTAssertEqual(flying.d, 28.972, accuracy: 1e-2)
        XCTAssertEqual(flying.sx, 1.18, accuracy: 1e-9, "stretched all the way at their fastest")
        XCTAssertEqual(flying.sx * flying.sy, 1, accuracy: 1e-9)
        let end = m.dot(at: 1.0)
        XCTAssertEqual(end.x, m.stop.x, accuracy: 1e-9)
        XCTAssertEqual(end.y, m.stop.y, accuracy: 1e-9)
        XCTAssertEqual(end.d, m.stop.d, accuracy: 1e-9)
        XCTAssertEqual(m.dot(at: 1.2).sx, 1, accuracy: 1e-9, "at rest it is round")
        var last = m.dot(at: 0.60).x
        for t in stride(from: 0.61, through: 1.0, by: 0.01) {
            XCTAssertGreaterThanOrEqual(m.dot(at: t).x, last, "it never comes back, at \(t)")
            last = m.dot(at: t).x
        }
    }

    /// The letters come out one at a time, B first, each behind the dot: small and leaning about
    /// its foot, full size 0.20 s later, while the word slides the Reference's 29 pt into place.
    func testTheLettersComeOutBehindTheDot() {
        let m = first
        let unit = m.wordBox.width / 1051
        let lefts: [CGFloat] = [0, 139, 196, 304, 387, 511, 634, 746, 839, 900]
        XCTAssertEqual(m.letterStarts.count, 10)
        XCTAssertEqual(m.letterStarts[0], 0.617, accuracy: 1e-9)
        XCTAssertEqual(m.letterStarts, m.letterStarts.sorted())
        for (i, start) in m.letterStarts.enumerated() {
            XCTAssertLessThan(start, 0.80, "letter \(i) starts with the Reference's last, or as the dot passes")
            XCTAssertGreaterThanOrEqual(m.dot(at: start).x, m.wordBox.minX + lefts[i] * unit - 1e-6, "letter \(i) is behind the dot")
            XCTAssertFalse(m.frame(at: start - 0.001).letters[i].shown)
            let small = m.frame(at: start).letters[i]
            XCTAssertTrue(small.shown)
            XCTAssertEqual(small.transform.a, 0.45, accuracy: 1e-9)
            XCTAssertEqual(small.transform.d, 0.45, accuracy: 1e-9)
            XCTAssertEqual(small.transform.c, -0.45 * tan(12 * .pi / 180), accuracy: 1e-9, "leaning right")
            let foot = CGPoint(x: lefts[i] * unit, y: 171 * unit)
            XCTAssertEqual(foot.applying(small.transform).x, foot.x, accuracy: 1e-9, "its foot stays put")
            XCTAssertEqual(foot.applying(small.transform).y, foot.y, accuracy: 1e-9)
            XCTAssertEqual(m.frame(at: start + 0.21).letters[i].transform, .identity)
        }
        XCTAssertEqual(m.frame(at: 0.60).wordShift, 0)
        XCTAssertEqual(m.frame(at: 0.617).wordShift, -29.051, accuracy: 1e-3)
        XCTAssertEqual(m.frame(at: 1.067).wordShift, 0, accuracy: 1e-9)
        let done = m.frame(at: 1.2)
        XCTAssertTrue(done.letters.allSatisfy { $0.shown && $0.transform == .identity })
        XCTAssertTrue(done.stopShown, "the dot is the wordmark's own full stop")
        XCTAssertFalse(done.dotShown)
        XCTAssertFalse(done.markShown, "no Bp! on the first open")
    }

    /// One light buzz as the dot stops; the word holds 0.35 s; then the full stop opens as a
    /// circle that reaches the far corner in 0.36 s, slow then fast, and the launch is done at 1.71 s.
    func testTheFullStopOpensAsACircle() {
        let m = first
        XCTAssertEqual(m.frame(at: 0.99).buzzes, 0)
        XCTAssertEqual(m.frame(at: 1.0).buzzes, 1)
        let holds = m.frame(at: 1.349)
        XCTAssertNil(holds.hole)
        XCTAssertNil(holds.ending)
        XCTAssertEqual(holds.yellow, 1)
        XCTAssertTrue(holds.takesTaps)
        let far = hypot(m.stop.x, m.stop.y)
        let half = m.frame(at: 1.35 + 0.18)
        XCTAssertEqual(half.hole?.centre.x ?? 0, m.stop.x, accuracy: 1e-9)
        XCTAssertEqual(half.hole?.centre.y ?? 0, m.stop.y, accuracy: 1e-9)
        XCTAssertEqual(half.hole?.radius ?? 0, far * 0.25, accuracy: 1e-6, "a quarter of the way at half time: it gathers speed")
        XCTAssertEqual(half.yellow, 0.75, accuracy: 1e-9)
        XCTAssertEqual(half.yellowOpacity, 1, "solid as it opens")
        XCTAssertNotNil(half.ending)
        XCTAssertTrue(half.headerUp)
        XCTAssertFalse(half.done)
        XCTAssertFalse(m.frame(at: 1.35 + 0.32).takesTaps, "the yellow is mostly gone")
        let gone = m.frame(at: 1.71)
        XCTAssertEqual(gone.hole?.radius ?? 0, far, accuracy: 1e-6)
        XCTAssertGreaterThan(far, hypot(402 - m.stop.x, 874 - m.stop.y), "the far corner is the top left")
        XCTAssertEqual(gone.yellow, 0, accuracy: 1e-9)
        XCTAssertEqual(gone.yellowOpacity, 0)
        XCTAssertTrue(gone.done)
        XCTAssertEqual(gone.backScale, 1, "the app behind holds still")
        XCTAssertEqual(gone.buzzes, 1)
    }

    /// A later open is the short cut of 2026-11-08 behind the still's 0.10 s: the still's dot goes as
    /// Bp pops out from under it, and the Town's ball falls straight into the !'s dot, spinning,
    /// shrinking and stretched along its speed, squashes there, and goes black in 0.12 s.
    func testLaterOpensDropTheTownsBall() {
        let m = later
        XCTAssertEqual(m.landAt, 0.389523, accuracy: 1e-4)
        XCTAssertEqual(m.popAt, m.landAt + 0.12, accuracy: 1e-9)
        XCTAssertEqual(m.endAt, m.popAt + 0.49, accuracy: 1e-9)
        let goes = m.frame(at: 0.10 + 0.075)
        XCTAssertTrue(goes.markShown)
        XCTAssertTrue(goes.dotShown)
        XCTAssertEqual(goes.dot.d, 85 * 0.125, accuracy: 1e-6, "the still's dot, an eighth left half way")
        XCTAssertEqual(goes.dot.x, 201)
        XCTAssertFalse(m.frame(at: 0.26).dotShown)
        XCTAssertGreaterThan(m.frame(at: 0.25).pop, 0.9, "Bp is out before the ball lands")
        XCTAssertLessThan(m.frame(at: 0.25).pop, 1.06, "a soft pop, not a big one")
        XCTAssertEqual(m.frame(at: 0.3).letter.width, 0.9, accuracy: 1e-9, "B and p at the still's 90%")
        XCTAssertEqual(m.frame(at: 0.3).letter.height, 0.9, accuracy: 1e-9)

        let start = m.ball(at: 0.10)
        XCTAssertEqual(start.x, m.bang.x)
        XCTAssertEqual(start.y, -44.900, accuracy: 1e-3, "above the screen")
        XCTAssertEqual(start.r, LaunchMotion.ball / 2, accuracy: 1e-9)
        XCTAssertEqual(start.roll, -120, accuracy: 1e-9)
        let falling = m.ball(at: 0.30)
        XCTAssertEqual(falling.x, m.bang.x, "straight down")
        XCTAssertEqual(falling.heading, 90)
        XCTAssertEqual(falling.sx, 1 + 0.18 * 2170 / 2200, accuracy: 1e-6)
        XCTAssertEqual(falling.sx * falling.sy, 1, accuracy: 1e-9)
        let lands = m.ball(at: m.landAt)
        XCTAssertEqual(lands.y, m.bang.y, accuracy: 1e-6)
        XCTAssertEqual(lands.r, m.bang.d / 2, accuracy: 1e-6)
        XCTAssertEqual(lands.roll, 360, accuracy: 1e-6)
        let squashed = m.ball(at: m.landAt + 0.025)
        XCTAssertEqual(squashed.sy, 0.68, accuracy: 1e-6)
        XCTAssertEqual(squashed.sx, 1.368, accuracy: 1e-6)
        XCTAssertEqual(squashed.y + squashed.r * squashed.sy, m.bang.y + m.bang.d / 2, accuracy: 1e-6, "its foot stays on the line")

        let air = m.frame(at: 0.2)
        XCTAssertTrue(air.ballShown)
        XCTAssertEqual(air.ballBlack, 0)
        XCTAssertGreaterThan(air.shadeDrop, 20, "high up, its shadow is far off and faint")
        XCTAssertFalse(m.frame(at: 0.05).ballShown, "not during the still")
        XCTAssertEqual(m.frame(at: m.landAt - 0.001).buzzes, 0)
        XCTAssertEqual(m.frame(at: m.landAt).buzzes, 1)
        XCTAssertLessThan(m.frame(at: m.landAt + 0.01).shadeDrop, 6)
        let black = m.frame(at: m.popAt)
        XCTAssertFalse(black.ballShown)
        XCTAssertTrue(black.bangShown, "the ball is the !'s own dot")
        XCTAssertEqual(black.ballBlack, 1, accuracy: 1e-6)
        XCTAssertEqual(m.frame(at: m.endAt - 0.01).backScale, 0.985, accuracy: 1e-9)
        XCTAssertTrue(m.frame(at: m.endAt - 0.01).letters.isEmpty, "no word on a later open")
        XCTAssertEqual(LaunchMotion.buzzKinds(.later).count, 3)
        XCTAssertEqual(LaunchMotion.buzzKinds(.first).count, 1)
    }

    /// Once the ball is the dot, B, p and the ! jump as one, without the hang at the top: a crouch
    /// while the !'s line grows out of the dot, up the Daily tab's 4 pt with B and p growing to
    /// full size, and down on one beat 0.35 s in, with one firm buzz.
    func testBpJumpsWithoutTheHang() {
        let m = later, pop = m.popAt
        XCTAssertEqual(m.frame(at: pop - 0.001).lineOpacity, 0)
        XCTAssertEqual(m.frame(at: pop + 0.02).lineOpacity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(m.frame(at: pop + 0.035).line.height, 0.86 * CGFloat(UnitCurve.easeOut.value(at: 0.5)), accuracy: 1e-6)
        let crouched = m.frame(at: pop + 0.07)
        XCTAssertEqual(crouched.bang.height, 0.86, accuracy: 1e-6)
        XCTAssertEqual(crouched.bang.width, 1.10, accuracy: 1e-6)
        XCTAssertEqual(crouched.letter.height, 0.9 * 0.86, accuracy: 1e-6, "B and p still at 90%")
        XCTAssertEqual(crouched.lift, 0, accuracy: 1e-6)
        let top = m.frame(at: pop + 0.07 + 0.16)
        XCTAssertEqual(top.lift, -4, accuracy: 1e-6)
        XCTAssertEqual(top.letter.width, 0.95, accuracy: 1e-6, "full size at the top")
        XCTAssertEqual(top.line.height, 0.94, accuracy: 1e-6, "the line alone, 6% short")
        XCTAssertEqual(m.frame(at: pop + 0.35 - 0.001).buzzes, 1)
        XCTAssertEqual(m.frame(at: pop + 0.35).buzzes, 2, "one firm buzz as it lands")
        XCTAssertEqual(m.frame(at: pop + 0.35).lift, 0, accuracy: 1e-6)
        // The landing's last rebound plays out under the leap's crouch, as it shipped.
        XCTAssertEqual(m.frame(at: m.endAt).letter.width, 0.97, accuracy: 1e-6)
        let rest = m.frame(at: m.endAt + 0.1)
        XCTAssertEqual(rest.letter.width, 1, accuracy: 1e-6)
        XCTAssertEqual(rest.letter.height, 1, accuracy: 1e-6)
        XCTAssertEqual(rest.bang, CGSize(width: 1, height: 1))
        XCTAssertEqual(rest.line.height, 1, accuracy: 1e-6)
        XCTAssertEqual(rest.pop, 1, accuracy: 0.01)
    }

    /// Bp! leaps into the tab bar's Bp!: it crouches onto its foot, is tossed up and down into the
    /// slot leaning 12°, lands with a squash as the tab bar dips with it, and the launch is done
    /// 2.15 s after the still, once the squash has played out. Meanwhile the yellow opens as a
    /// circle from its middle, gone in 0.36 s. A touch belongs to the launch until then.
    func testLeapsIntoTheTabBarsBp() {
        let m = later, endAt = m.endAt
        let canvas = LaunchMotion.canvas
        func foot(_ f: LaunchMotion.Frame) -> CGPoint {
            CGPoint(x: f.markOrigin.x + canvas.width * f.markScale / 2, y: f.markOrigin.y + canvas.height * f.markScale)
        }
        let rest = foot(m.frame(at: endAt - 0.01))
        XCTAssertEqual(m.frame(at: endAt - 0.01).markOrigin, m.origin)
        XCTAssertNil(m.frame(at: endAt - 0.01).hole)
        XCTAssertEqual(m.frame(at: endAt + 0.07 - 1e-9).markSquash.height, 0.9, accuracy: 1e-6, "crouched")
        XCTAssertLessThan(foot(m.frame(at: endAt + 0.07 + 0.26 / 4)).y, rest.y - 40, "tossed up first")
        XCTAssertEqual(m.frame(at: endAt + 0.07 + 0.13).markTilt, -12, accuracy: 1e-6)
        let half = m.frame(at: endAt + 0.18)
        XCTAssertEqual(half.hole?.centre, CGPoint(x: 201, y: 437))
        XCTAssertEqual(half.hole?.radius ?? 0, hypot(201, 437) * 0.25, accuracy: 1e-6)
        XCTAssertEqual(half.yellow, 0.75, accuracy: 1e-9)
        XCTAssertEqual(half.yellowOpacity, 1)
        let landed = m.frame(at: endAt + 0.07 + 0.26 + 0.05)
        XCTAssertEqual(canvas.width * landed.markScale, tab.width, accuracy: 1e-6)
        XCTAssertGreaterThan(landed.tabDip, 1, "the tab bar catches it")
        XCTAssertEqual(foot(landed).x, tab.midX, accuracy: 1e-6)
        XCTAssertEqual(foot(landed).y, tab.maxY + landed.tabDip, accuracy: 1e-6)
        XCTAssertEqual(landed.yellowOpacity, 0)
        var t = 0.0
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertEqual(t, 2.146, accuracy: 0.01)
        let last = m.frame(at: t)
        XCTAssertEqual(last.tabDip, 0, accuracy: 0.5, "the rest eases out once it's done")
        XCTAssertEqual(last.yellow, 0, accuracy: 0.001)
        XCTAssertEqual(last.backScale, 1, accuracy: 0.001)
        XCTAssertEqual(last.buzzes, 3, "the third, light, as it lands in the tab bar")
        XCTAssertEqual(m.frame(at: endAt + 0.07 + 0.26 - 0.001).buzzes, 2)
        XCTAssertFalse(last.headerUp)
        XCTAssertTrue(m.frame(at: endAt).takesTaps)
        XCTAssertFalse(m.frame(at: endAt + 0.32).takesTaps, "the yellow is mostly gone 0.32 s into the circle")
        // LaunchBallTests holds 0.3 to tap the yellow, and 1.5 to tap through: the yellow gone,
        // the launch still on screen.
        XCTAssertTrue(m.frame(at: 0.3).takesTaps)
        XCTAssertFalse(m.frame(at: 1.5).takesTaps)
        XCTAssertFalse(m.frame(at: 1.5).done)
    }

    /// Nothing on Bp! snaps in one frame of a 120 Hz screen: the crouch lets go and the !'s line
    /// grows over several frames, and the launch ends only once the landing's squash has died
    /// down, not as it swings through rest (2026-11-07, BP app references/launch-glitch).
    func testNothingJumpsInOneFrame() throws {
        let m = later
        let step = 1.0 / 120
        var last = m.frame(at: m.popAt), t = m.popAt + step, done: Double?
        while t < 5 && done == nil {
            let f = m.frame(at: t)
            // 6%: the landing's first frame, now that the leap plays at full speed (under 5% at ¾).
            XCTAssertLessThan(abs(f.markSquash.height - last.markSquash.height), 0.06, "Bp!'s squash at \(t)")
            // 20%: the line's first frame at full speed, as the short cut shipped (under 15% at ¾).
            XCTAssertLessThan(abs(f.line.height - last.line.height), 0.20, "the !'s line at \(t)")
            if f.done { done = t }
            last = f
            t += step
        }
        let end = try XCTUnwrap(done)
        for after in stride(from: end, to: end + 1, by: 0.005) {
            XCTAssertEqual(m.frame(at: after).markSquash.height, 1, accuracy: 0.01, "still squashing after it's done, at \(after)")
        }
    }

    /// With no tab bar (Welcome is up), a later open's Bp! zooms through as the yellow fades, and
    /// Welcome's logo and headline may rise half way.
    func testWithNoTabBarBpZoomsThrough() {
        let m = LaunchMotion(screen: phone, ending: .zoom, kind: .later)
        XCTAssertEqual(m.frame(at: m.endAt - 0.01).backScale, 1.05, accuracy: 1e-9)
        XCTAssertFalse(m.frame(at: m.endAt + 0.05).headerUp)
        let half = m.frame(at: m.endAt + 0.1)   // the glide is at 0.54
        XCTAssertTrue(half.headerUp)
        XCTAssertGreaterThan(half.zoom, 3)
        for t in stride(from: 0.0, through: 3, by: 0.1) {
            let f = m.frame(at: t)
            XCTAssertNil(f.hole, "nothing opens, at \(t)")
            XCTAssertEqual(f.yellowOpacity, f.yellow, accuracy: 1e-9, "it fades, at \(t)")
        }
        XCTAssertTrue(m.frame(at: 3).done)
        // The first open's full stop opens over Welcome as over Town.
        let word = LaunchMotion(screen: phone, ending: .zoom, kind: .first)
        XCTAssertEqual(word.frame(at: 1.6), first.frame(at: 1.6))
    }

    /// Reduce Motion, every open: the dot gives way to the finished word over 0.15 s, the word
    /// holds 0.35 s, and the yellow fades in 0.30 s. Nothing opens, zooms, buzzes or moves under it.
    func testReduceMotionFadesTheWordIn() {
        for kind in [LaunchMotion.Kind.first, .later] {
            let m = LaunchMotion(screen: phone, ending: .tab(tab), kind: kind, reduceMotion: true)
            XCTAssertEqual(m.frame(at: 0).wordOpacity, 0)
            let half = m.frame(at: 0.075)
            XCTAssertEqual(half.wordOpacity, 0.5, accuracy: 1e-9)
            XCTAssertEqual(half.dot.x, (201 + m.stop.x) / 2, accuracy: 1e-9)
            let word = m.frame(at: 0.15)
            XCTAssertEqual(word.wordOpacity, 1)
            XCTAssertEqual(word.dot.x, m.stop.x, accuracy: 1e-9)
            XCTAssertEqual(word.dot.y, m.stop.y, accuracy: 1e-9)
            XCTAssertEqual(word.dot.d, m.stop.d, accuracy: 1e-9)
            XCTAssertTrue(word.letters.allSatisfy { $0.shown && $0.transform == .identity })
            XCTAssertEqual(m.frame(at: 0.49).yellow, 1)
            XCTAssertNil(m.frame(at: 0.49).ending)
            XCTAssertEqual(m.frame(at: 0.5 + 0.15).yellow, 1 - LaunchMotion.easeOut.value(at: 0.5), accuracy: 1e-9)
            for t in stride(from: 0.0, through: 1, by: 0.05) {
                let f = m.frame(at: t)
                XCTAssertNil(f.hole)
                XCTAssertFalse(f.markShown)
                XCTAssertEqual(f.yellowOpacity, f.yellow, accuracy: 1e-9)
                XCTAssertEqual(f.backScale, 1)
                XCTAssertEqual(f.buzzes, 0)
                XCTAssertEqual(f.dot.sx, 1)
            }
            XCTAssertTrue(m.frame(at: 0.81).done)
        }
    }

    /// On a wider phone the word is still 70% of the screen in its middle, the dot still starts
    /// 85 pt in the middle and ends on the full stop, and the Reference's path widens with it.
    func testOnAWiderPhone() {
        let m = LaunchMotion(screen: CGSize(width: 440, height: 956), kind: .first)
        XCTAssertEqual(m.wordBox.width, 308, accuracy: 1e-9)
        XCTAssertEqual(m.wordBox.midX, 220, accuracy: 1e-9)
        XCTAssertEqual(m.dot(at: 0), LaunchMotion.Dot(x: 220, y: 478, d: 85))
        XCTAssertEqual(m.dot(at: 0.40).x, 220 + (115 - 255.5) * 440 / 512, accuracy: 1e-6)
        XCTAssertEqual(m.dot(at: 1.0).x, m.stop.x, accuracy: 1e-9)
        XCTAssertTrue(m.frame(at: 1.71).done)
        let drops = LaunchMotion(screen: CGSize(width: 440, height: 956), ending: .tab(tab), kind: .later)
        XCTAssertEqual(drops.ball(at: drops.landAt).y, drops.bang.y, accuracy: 1e-6)
    }
}
