//
//  LaunchMotionTests.swift
//  Block Party — the launch moves as the approved mock does (BP app references/launch-ball,
//  round 5; references/launch-short since 2026-11-08: Bp! 320 pt, B and p shrinking toward the !,
//  the curtain; references/splash-wordmark since 2026-11-14: the BlockParty. still, the wordmark
//  open and its fade; references/launch-squeeze since 2026-11-17: the ball's hits squeeze
//  BlockParty. into Bp!). Every expected number here was read off the mock's
//  own script (its frozen frames write `data-probe`; the squeeze's come from
//  `mock.html#probe-<ms>,<ms>[-skip<ms>]`), on its 402 x 874 phone, so a drift in the
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
    /// in the screen's middle. The wordmark's B sits lower than Bp's did, so the ball reaches it
    /// 0.02 s later; p's hit and the landing come when they did before the squeeze.
    func testBeatsLandWhenTheMocksDo() {
        XCTAssertEqual(motion.hitB, 0.261240, accuracy: 1e-5)
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

    /// The ball lands on the wordmark's B, then on its P, which B's hit has moved by then; the
    /// wordmark is as wide as Bp!, in the screen's middle.
    func testTheBallLandsOnTheWordmarksBAndP() {
        XCTAssertEqual(LaunchMotion.letterAnchor, CGPoint(x: 781, y: 627))
        XCTAssertEqual(motion.ball(at: motion.hitB).x, 63.835395, accuracy: 1e-4)
        XCTAssertEqual(motion.ball(at: motion.hitP).x, 203.678144, accuracy: 1e-4)
        let word = LaunchMotion.wordBox, s = LaunchMotion.scale
        XCTAssertEqual(word.width * s, 320, accuracy: 1e-9)
        XCTAssertEqual(motion.origin.x + (word.midX - LaunchMotion.canvas.minX) * s, 201, accuracy: 1e-6)
        XCTAssertEqual(motion.origin.y + (word.midY - LaunchMotion.canvas.minY) * s, 437, accuracy: 1e-6)
        XCTAssertEqual(LaunchMotion.wordPieces.count, 11)
    }

    /// The ball flies, squashes and rides the letters where the mock's does: in the air, on B,
    /// over the arc, on p, shrinking into the dot, squashed on it, and at rest.
    func testBallFollowsTheMock() {
        // t, x, y, r, roll, sx, sy, heading
        let mock: [(Double, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            // launch-squeeze's mock: the ball riding the wordmark's B and P as they dip
            (0.05, 60.970943, -2.900131, 24.745663, -97.032646, 1.084280, 0.922271, 89.245733),
            (0.2, 63.004966, 237.099869, 24.745663, -28.130584, 1.177549, 0.849222, 89.641968),
            (0.281, 63.835395, 394.435352, 24.745663, 0, 1.391760, 0.659339, 0),
            (0.45, 130.310249, 314.821928, 24.745663, 171.127553, 1.039258, 0.962225, 3.224559),
            (0.633, 203.678144, 418.865751, 24.745663, 360, 1.394911, 0.656599, 0),
            (0.8, 269.613759, 352.783972, 23.134584, 539.794156, 1.039623, 0.961887, 22.008255),
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

    /// The mock's squeeze at set moments (`mock.html#probe-300,360,450,470,700,800,850` and
    /// `#probe-150,250-skip100`), rounded to 4 places. B and P: whether Bp!'s own letter shows, its
    /// width and height against full size, and where its top left corner's scaling leaves it, in
    /// canvas units from the canvas's top left. Each piece (B, l, o, c, k, P, a, r, t, y, the full
    /// stop): whether it shows, then its matrix about its box's top left.
    private struct Probe: Decodable {
        var t: Double
        var B: [CGFloat]
        var P: [CGFloat]
        var pieces: [[CGFloat]]
    }
    private static let mockShow = """
    [{"t":0.3,"B":[0,0.3397,0.3089,-53.409,163.6505],"P":[0,0.3373,0.3373,217.2624,123.7668],"pieces":[[1,1.0289,0,0,0.9358,-1.5488,7.6239],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0],[1,1,0,0,1,0,0]]},{"t":0.36,"B":[1,0.323,0.2834,-56.3373,169.8657],"P":[0,0.3373,0.3373,218.4354,121.6899],"pieces":[[0,1.0395,0,0,0.9122,-2.1185,10.4295],[1,1,0,-0.0852,1,9.2737,-2.0768],[1,1,0,-0.0595,1,6.8368,-2.0768],[1,1,0,-0.0383,1,4.8117,-2.0768],[1,1,0,-0.0212,1,3.1941,-2.0768],[1,1,0,0,1,1.1737,-2.0768],[1,1,0,0,1,1.1737,-2.0768],[1,1,0,0,1,1.1737,-2.0768],[1,1,0,0,1,1.1737,-2.0768],[1,1,0,0,1,1.1737,-2.0768],[1,1,0,0,1,1.1737,-2.0768]]},{"t":0.45,"B":[1,0.5663,0.5518,-36.3025,109.4861],"P":[0,0.3373,0.3373,203.2574,148.5471],"pieces":[[0,1.008,0,0,0.9822,-0.4287,2.111],[0,0,0,0,0,129.8601,100.8051],[1,0.1372,0,-0.006,0.1372,172.1969,90.3758],[1,1,0,0,1,-18.7679,24.7804],[1,1,0,0,1,-18.7679,24.7804],[1,1,0,0,1,-14.0043,24.7804],[1,1,0,0,1,-14.0043,24.7804],[1,1,0,0,1,-14.0043,24.7804],[1,1,0,0,1,-14.0043,24.7804],[1,1,0,0,1,-14.0043,24.7804],[1,1,0,0,1,-14.0043,24.7804]]},{"t":0.47,"B":[1,0.7369,0.7361,-23.1012,68.2866],"P":[0,0.3373,0.3373,192.6904,167.2457],"pieces":[[0,1.0003,0,0,0.9993,-0.0171,0.0838],[0,0,0,0,0,115.6984,106.2164],[0,0,0,0,0,187.8684,106.2164],[0,0,0,0,0,257.8954,106.2164],[1,0.8252,0,-0.0452,0.8252,34.7422,54.4477],[1,1,0,0,1,-24.5715,43.4789],[1,1,0,0,1,-24.5715,43.4789],[1,1,0,0,1,-24.5715,43.4789],[1,1,0,0,1,-24.5715,43.4789],[1,1,0,0,1,-24.5715,43.4789],[1,1,0,0,1,-24.5715,43.4789]]},{"t":0.7,"B":[1,0.9033,0.8966,-17.0243,33.7225],"P":[1,0.3298,0.2935,179.4349,198.0575],"pieces":[[0,1.0023,0,0,0.9949,-0.1233,0.6061],[0,0,0,0,0,102.3914,111.3109],[0,0,0,0,0,174.5614,111.3109],[0,0,0,0,0,244.5884,111.3109],[0,0.0215,0,-0.0002,0.0215,316.6387,110.2291],[0,1.0353,0,0,0.9214,-49.2338,70.4091],[1,1,0,-0.0833,1,-30.3229,61.0829],[1,1,0,-0.0582,1,-31.5855,61.0829],[1,1,0,-0.0374,1,-32.6348,61.0829],[1,1,0,-0.0208,1,-33.4731,61.0829],[1,1,0,0,1,-34.5201,61.0829]]},{"t":0.8,"B":[1,0.9044,0.8902,28.0988,35.6691],"P":[1,0.66,0.651,113.7043,100.1936],"pieces":[[0,1.0049,0,0,0.9892,-0.261,1.2855],[0,0,0,0,0,102.4678,111.272],[0,0,0,0,0,174.6378,111.272],[0,0,0,0,0,244.6648,111.272],[0,0,0,0,0,324.6948,111.272],[0,1.0042,0,0,0.9906,-36.2088,62.0663],[0,0,0,0,0,472.3404,90.86],[0,0,0,0,0,533.7924,90.86],[1,0.7313,0,-0.0574,0.7313,109.7367,68.9861],[1,1,0,0,1,-67.8656,60.9482],[1,1,0,0,1,-34.444,60.9482]]},{"t":0.85,"B":[1,0.9021,0.8956,66.3926,33.9352],"P":[1,0.9152,0.9429,64.9148,19.8615],"pieces":[[0,1.0022,0,0,0.995,-0.12,0.5897],[0,0,0,0,0,102.4621,111.2748],[0,0,0,0,0,174.6321,111.2748],[0,0,0,0,0,244.6591,111.2748],[0,0,0,0,0,324.6891,111.2748],[0,0.9907,0,0,1.0206,-30.5836,58.5075],[0,0,0,0,0,446.972,74.7314],[0,0,0,0,0,508.424,74.7314],[0,0,0,0,0,561.301,74.7314],[0,0,0,0,0,643.475,74.7314],[1,1,0,0,1,-34.4495,60.9579]]}]
    """
    private static let mockTapped = """
    [{"t":0.15,"B":[1,0.3105,0.3105,-51.1126,161.0418],"P":[1,0.3179,0.3179,223.7557,124.7386],"pieces":[[0,1,0,0,1,0,0],[1,1,0,-0.0861,1,9.3782,-2.0998],[1,1,0,-0.0602,1,6.9136,-2.0998],[1,1,0,-0.0387,1,4.8657,-2.0998],[1,1,0,-0.0215,1,3.2298,-2.0998],[0,1,0,0,1,1.1867,-2.0998],[1,1,0,-0.0861,1,5.3427,-2.0998],[1,1,0,-0.0602,1,4.0923,-2.0998],[1,1,0,-0.0387,1,3.0532,-2.0998],[1,1,0,-0.0215,1,2.2233,-2.0998],[1,1,0,0,1,1.1867,-2.0998]]},{"t":0.25,"B":[1,0.6627,0.6627,20.2562,84.2527],"P":[1,0.6828,0.6828,115.6508,81.4611],"pieces":[[0,1,0,0,1,0,0],[0,0,0,0,0,121.6923,103.9261],[0,0,0,0,0,193.8623,103.9261],[0,0,0,0,0,263.8893,103.9261],[1,0.694,0,-0.0597,0.694,90.6394,56.4851],[0,1,0,0,1,-20.0989,35.5648],[0,0,0,0,0,475.2045,79.5133],[0,0,0,0,0,536.6565,79.5133],[1,0.4968,0,-0.0522,0.4968,266.6448,57.679],[1,1,0,0,1,-65.0015,35.5648],[1,1,0,0,1,-20.0989,35.5648]]}]
    """

    private func assertSqueezes(_ m: LaunchMotion, as json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let canvas = LaunchMotion.canvas, anchor = LaunchMotion.letterAnchor
        for probe in try JSONDecoder().decode([Probe].self, from: Data(json.utf8)) {
            let f = m.frame(at: probe.t), at = "at \(probe.t)"
            XCTAssertEqual(f.word, 0, "the still's picture has handed over \(at)", file: file, line: line)
            for (name, mock, shown, size, shift) in [("B", probe.B, f.bShown, f.b, f.bShift), ("p", probe.P, f.pShown, f.p, f.pShift)] {
                XCTAssertEqual(shown, mock[0] == 1, "\(name) shows \(at)", file: file, line: line)
                XCTAssertEqual(size.width, mock[1], accuracy: 1e-3, "\(name)'s width \(at)", file: file, line: line)
                XCTAssertEqual(size.height, mock[2], accuracy: 1e-3, "\(name)'s height \(at)", file: file, line: line)
                XCTAssertEqual((anchor.x - canvas.minX) * (1 - size.width) + shift.width, mock[3], accuracy: 0.01, "\(name)'s x \(at)", file: file, line: line)
                XCTAssertEqual((anchor.y - canvas.minY) * (1 - size.height) + shift.height, mock[4], accuracy: 0.01, "\(name)'s y \(at)", file: file, line: line)
            }
            XCTAssertEqual(f.pieces.count, 11, at, file: file, line: line)
            for (i, mock) in probe.pieces.enumerated() where f.pieces.indices.contains(i) {
                let piece = f.pieces[i], t = piece.transform, name = "\(LaunchMotion.wordPieces[i]) \(at)"
                XCTAssertEqual(piece.opacity, Double(mock[0]), name, file: file, line: line)
                for (mine, theirs, close) in [(t.a, mock[1], 1e-3), (t.b, mock[2], 1e-3), (t.c, mock[3], 1e-3), (t.d, mock[4], 1e-3),
                                              (t.tx, mock[5], 0.01), (t.ty, mock[6], 0.01)] {
                    XCTAssertEqual(mine, theirs, accuracy: close, name, file: file, line: line)
                }
            }
        }
    }

    /// The ball's hits squeeze BlockParty. into Bp as the mock does (Jesse, 2026-11-17): on B's hit
    /// the wordmark's B dips, then Bp!'s B holds, crouched, in its place and snaps l, o, c, k in,
    /// each shrinking whole and leaning; on P's hit the p does the same with a, r, t, y while
    /// B moves over; the full stop waits for the ball.
    func testTheHitsSqueezeTheWordIntoBp() throws {
        try assertSqueezes(motion, as: Self.mockShow)
        // No letter is ever cut or faded: each shows whole or not at all, and only shrinks.
        for t in stride(from: 0.0, through: 1.2, by: 1.0 / 240) {
            for piece in motion.frame(at: t).pieces {
                XCTAssertTrue(piece.opacity == 0 || piece.opacity == 1, "at \(t)")
                XCTAssertLessThanOrEqual(piece.transform.a, 1.05, "at \(t)")
            }
        }
    }

    /// Until the first hit the still's own picture shows and nothing of Bp does (the pieces wait
    /// under it, clear); from the hit on its pieces draw the word, and once the ball is the dot they
    /// are all gone.
    func testTheStillsPictureShowsUntilTheFirstHit() {
        let m = motion
        for t in [0.0, 0.1, m.hitB - 0.001] {
            let f = m.frame(at: t)
            XCTAssertEqual(f.word, 1, "at \(t)")
            XCTAssertEqual(f.pieces.map(\.opacity), Array(repeating: 0, count: 11), "the pieces wait, clear, at \(t)")
            XCTAssertFalse(f.bShown || f.pShown, "no Bp on the still, at \(t)")
            XCTAssertEqual(f.markOpacity, 1, "the ball shows as it drops in, at \(t)")
        }
        let hit = m.frame(at: m.hitB)
        XCTAssertEqual(hit.word, 0)
        XCTAssertEqual(hit.pieces.map(\.opacity), Array(repeating: 1, count: 11), "the whole word, in pieces")
        XCTAssertFalse(hit.bShown, "the wordmark's own B dips under the ball")
        XCTAssertTrue(m.frame(at: m.hitB + 0.05).bShown, "Bp!'s B swells as the ball leaves")
        XCTAssertFalse(m.frame(at: m.hitP + 0.049).pShown)
        XCTAssertTrue(m.frame(at: m.hitP + 0.05).pShown)
        XCTAssertEqual(m.frame(at: m.landAt + 0.01).pieces.last?.opacity, 1, "the full stop waits for the ball")
        XCTAssertTrue(m.frame(at: m.landAt + 0.02).pieces.isEmpty, "the ball is the dot now")
        // The swell's spring rings past full size and back; a letter it took never shows again.
        for t in stride(from: m.hitB + 0.26, to: m.hitP, by: 0.004) {
            XCTAssertEqual(m.frame(at: t).pieces[1...4].map(\.opacity), [0, 0, 0, 0], "lock is gone, at \(t)")
        }
        XCTAssertEqual(m.frame(at: 2).word, 0)
    }

    /// Squeezed, B and p sit at the still's 90% exactly where they did before the squeeze, so the
    /// jump, the leap and the tab bar's catch are unchanged.
    func testSqueezedBpIsTheOldBp() {
        let f = motion.frame(at: motion.landAt + 0.11)
        XCTAssertEqual(f.b.width, 0.9, accuracy: 0.002, "still 90% as the ball lands")
        XCTAssertEqual(f.p.width, 0.9, accuracy: 0.004)
        for shift in [f.bShift, f.pShift] {   // canvas units: the spring's last ring, under half a point
            XCTAssertEqual(shift.width, 0, accuracy: 1)
            XCTAssertEqual(shift.height, 0, accuracy: 1)
        }
        let late = motion.frame(at: 2)
        XCTAssertEqual(late.bShift.width, 0, accuracy: 1e-6)
        XCTAssertEqual(late.pShift.height, 0, accuracy: 1e-6)
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

    /// Every other open: no ball and no Bp. BlockParty. holds 0.2 s, then shoots out at you as the
    /// 2026-11-08 link open's Bp! did, the yellow and the signature fading in 0.18 s, nothing falling
    /// and the app settling from 105% (Jesse, 2026-11-14: "it just all fades into the app", then "the
    /// blockparty. splash shoots the text like the one we made when you open a event in message").
    /// Full speed, no buzzes, and a tap starts the ending at once.
    func testOtherOpensShowTheWordmarkThenShootIt() {
        let m = LaunchMotion(screen: phone, ending: .tab(tab), kind: .word)
        XCTAssertEqual(m.pace, 1)
        XCTAssertTrue(LaunchMotion.buzzKinds(.word).isEmpty)
        for t in [0.0, 0.1, 0.19] {
            let f = m.frame(at: t)
            XCTAssertEqual(f.word, 1, "at \(t)")
            XCTAssertEqual(f.zoom, 1, "at \(t)")
            XCTAssertEqual(f.markOpacity, 0, "no Bp at \(t)")
            XCTAssertEqual(f.yellow, 1, "at \(t)")
            XCTAssertNil(f.ending, "nothing under it moves yet at \(t)")
            XCTAssertFalse(f.headerUp)
            XCTAssertEqual(f.backScale, 1.05, "the app waits at 105% under the yellow")
        }
        let half = m.frame(at: 0.2 + 0.09)
        XCTAssertEqual(half.yellow, 1 - LaunchMotion.easeOut.value(at: 0.5), accuracy: 1e-9)
        XCTAssertEqual(half.yellowOpacity, half.yellow, "a fade")
        XCTAssertNotNil(half.ending, "Town settles as the yellow clears")
        XCTAssertTrue(half.headerUp)
        // The shot: growing all the way, gone by the time it is 4x.
        var last = m.frame(at: 0.2)
        for t in stride(from: 0.2 + 1.0 / 120, through: 0.45, by: 1.0 / 120) {
            let f = m.frame(at: t)
            XCTAssertGreaterThanOrEqual(f.zoom, last.zoom, "at \(t)")
            XCTAssertLessThanOrEqual(f.word, last.word, "at \(t)")
            last = f
        }
        XCTAssertGreaterThan(m.frame(at: 0.22).word, 0.5, "still there as it starts to grow")
        XCTAssertGreaterThan(m.frame(at: 0.22).zoom, 1.2)
        XCTAssertEqual(m.frame(at: 0.2 + 0.15).word, 0, "gone 0.15 s in")
        XCTAssertGreaterThan(m.frame(at: 0.2 + 0.3).zoom, 5.5)
        for t in stride(from: 0.0, through: 1, by: 0.05) {
            XCTAssertEqual(m.frame(at: t).yellowDrop, 0, "nothing falls at \(t)")
            XCTAssertEqual(m.frame(at: t).buzzes, 0)
        }
        var t = 0.0
        while !m.frame(at: t).done && t < 5 { t += 1.0 / 480 }
        XCTAssertGreaterThan(t, 0.3)
        XCTAssertLessThanOrEqual(t, 0.4 + 1e-3, "gone 0.4 s after the still")
        let tapped = LaunchMotion(screen: phone, skip: 0.05, kind: .word)
        XCTAssertEqual(tapped.frame(at: 0.04).yellow, 1)
        XCTAssertLessThan(tapped.frame(at: 0.2).yellow, 0.5)
        XCTAssertTrue(tapped.frame(at: 0.05 + 0.19).done)
    }

    /// Reduce Motion: the same BlockParty., then no zoom: the wordmark, the yellow and the signature
    /// fade together on the launch's 0.3 s fade, and the app under it holds still.
    func testReduceMotionOnlyFadesTheWordmark() {
        let m = LaunchMotion(screen: phone, ending: .tab(tab), kind: .word, reduceMotion: true)
        for t in stride(from: 0.0, through: 1, by: 0.01) {
            let f = m.frame(at: t)
            XCTAssertEqual(f.zoom, 1, "at \(t)")
            XCTAssertEqual(f.backScale, 1, "at \(t)")
            XCTAssertEqual(f.word, f.yellow, accuracy: 1e-9, "fades with the yellow at \(t)")
        }
        XCTAssertEqual(m.frame(at: 0.2 + 0.15).yellow, 1 - LaunchMotion.easeOut.value(at: 0.5), accuracy: 1e-9)
        XCTAssertFalse(m.frame(at: 0.4).done)
        XCTAssertTrue(m.frame(at: 0.5).done)
    }

    /// A link that arrives while the ball show is on its way turns it into the wordmark open: what
    /// the show had drawn (here the half-squeezed word and the ball in mid-air) fades back into BlockParty. over
    /// 0.15 s, then it holds and fades as any wordmark open does.
    func testALinkFadesTheShowBackIntoTheWordmark() {
        let show = LaunchMotion(screen: phone, ending: .tab(tab))
        let caught = show.frame(at: 0.3)
        XCTAssertEqual(caught.markOpacity, 1)
        XCTAssertEqual(caught.word, 0)
        let m = LaunchMotion(screen: phone, ending: .tab(tab), kind: .word, before: caught)
        let start = m.frame(at: 0)
        XCTAssertEqual(start.ball, caught.ball, "the ball where it was")
        XCTAssertEqual(start.b, caught.b)
        XCTAssertEqual(start.pieces, caught.pieces)
        XCTAssertEqual(start.markOpacity, 1)
        XCTAssertEqual(start.word, 0)
        let mid = m.frame(at: 0.075)
        XCTAssertEqual(mid.markOpacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.word, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.frame(at: 0.15).markOpacity, 0)
        XCTAssertEqual(m.frame(at: 0.15).word, 1)
        XCTAssertEqual(m.frame(at: 0.15 + 0.2 - 0.001).yellow, 1, "then it holds")
        XCTAssertLessThan(m.frame(at: 0.15 + 0.2 + 0.1).yellow, 1)
        // Caught before the first hit: the still's picture never left, and only the ball fades.
        let early = LaunchMotion(screen: phone, kind: .word, before: show.frame(at: 0.05))
        XCTAssertEqual(early.frame(at: 0).word, 1)
        XCTAssertEqual(early.frame(at: 0.075).markOpacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(early.frame(at: 0.15).word, 1)
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

    /// A tap sends the ball into the dot in 0.16 s, squeezes the word at once (the letters the
    /// ball never reached swell without a dip), drops the jump and the buzzes after it, and ends on
    /// the fast spring.
    func testATapSkipsToTheDot() throws {
        let m = LaunchMotion(screen: phone, skip: 0.1)
        XCTAssertEqual(m.frame(at: 0.099).word, 1)
        try assertSqueezes(m, as: Self.mockTapped)
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
}
