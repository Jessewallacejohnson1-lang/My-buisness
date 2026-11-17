//
//  LaunchMotion.swift
//  Block Party — the launch as numbers at a moment: where the Town's ball is, how B and p dip
//  and grow, when the ! hops and where Bp! goes at the end. The approved mock's math, ported
//  line for line (Jesse approved round 5 on 2026-11-01; BP app references/launch-ball/
//  mock.template.html holds the original). Every tuning value was GUESSED in the mock and
//  approved as played; change one only with Jesse.
//
//  Times here are the mock's simulation time. The screen plays the full show at `fullPace`, so
//  each motion takes 1.33x its value (Jesse: "can you do .75 speed"; slower still was tried and
//  dropped on 2026-11-02: "nvm do 1 speed"); the wordmark open plays at full speed.
//
//  Two kinds (Jesse, 2026-11-14; BP app references/splash-wordmark): the full show on the day's
//  first cold start, starting from the still's BlockParty. wordmark, which the ball's hits squeeze
//  into Bp! (Jesse, 2026-11-17; BP app references/launch-squeeze, mock round 3, whose
//  mock.html#probe-<ms> writes the numbers LaunchMotionTests holds); every other open (later ones,
//  a link, Reduce Motion) shows the wordmark, which shoots out at you as the link's Bp! did while
//  the yellow fades into the app (Reduce Motion: only the fade). The short cut and the link's own
//  pop (2026-11-08) went with it.
//

import SwiftUI

nonisolated struct LaunchMotion {
    // MARK: Tuning (the mock's `T`)

    static let fullPace = 0.75
    /// The wordmark open plays at full speed.
    static func pace(for kind: Kind) -> Double { kind == .full ? fullPace : 1 }
    var pace: Double { Self.pace(for: kind) }
    /// Gravity and the drop's starting speed, in points per second (per second).
    private static let gravity: CGFloat = 7600
    private static let dropSpeed: CGFloat = 650
    /// Where the ball starts: above the screen, on the left.
    private static let start = CGPoint(x: 40, y: -40)
    /// How high the two arcs rose off B and p at their 90%, each lower than the last. The squeeze's
    /// arcs leave the wordmark's smaller letters and take the same time (`init`).
    private static let arcB: CGFloat = 78
    private static let arcP: CGFloat = 40
    /// How long the ball touches a letter or the dot, and how far it squashes there.
    private static let contact = 0.05
    private static let squash: CGFloat = 0.36
    private static let squashDot: CGFloat = 0.32
    /// The most the ball stretches along its speed (at 2200 pt/s).
    private static let stretch: CGFloat = 0.18
    /// B and p's rubber dip: the top drops 9% and 8% and the letter bulges 0.45 of that.
    private static let wobble = Spring(response: 0.40, dampingRatio: 0.30)
    private static let dipB = 0.09
    private static let dipP = 0.08
    private static let bulge = 0.45
    /// B and p are 10% small once squeezed (Jesse, round 4). They grow to full size in the jump
    /// (Jesse, 2026-11-02: "what if the letters sync into place when the ! does").
    static let startSize: CGFloat = 0.9
    private static let grow = Spring(response: 0.40, dampingRatio: 0.45)
    /// The landed ball's colours go black, then Bp! jumps.
    private static let blacken = 0.12
    /// As the ball becomes the dot, Bp! jumps as one (Jesse, 2026-11-02: "what if the letters stay
    /// up then everything syncs in at once to make it satisfying"): it crouches while the !'s line
    /// grows out of the dot, jumps the Daily tab's 4 pt (scaled up), hangs, and all of it lands on
    /// one beat with one firm buzz. The ending starts 0.63 in, once the landing has rebounded.
    static let jumpLands = 0.49
    private static let jumpEnds = 0.63
    /// A link that catches the full show fades what it had drawn back into BlockParty. in 0.15 s.
    static let wordSwap = 0.15
    /// The squeeze (Jesse, 2026-11-17: "i like yours", then "a micro animation for attention to
    /// detail", no letters that "fade out at a visible line point"). The ball hits the wordmark's own
    /// B and P. Each hit swells its letter into Bp!'s in four gulps, `gulp` s apart, one for each
    /// letter it takes in; the letter being taken fills what is left of its own room, so it shrinks
    /// whole toward the big letter's widest point (`bellyB`, `bellyP`: canvas units above the line),
    /// leaning `gulpLean` degrees, with no cut and no fade. The big B waits `squeezeGap` canvas units
    /// from the small "Party." until the P swells.
    private static let gulp = 0.045
    private static let gulpSpring = Spring(response: 0.20, dampingRatio: 0.50)
    private static let gulpLean = 6.0
    private static let bellyB: CGFloat = 76
    private static let bellyP: CGFloat = 115
    private static let squeezeGap: CGFloat = 6
    /// Every other open: BlockParty. holds 0.2 s (guessed), then shoots out at you as the yellow fades
    /// (Jesse, 2026-11-14: "instead of the sheet going down, it just all fades", then "the blockparty.
    /// splash shoots the text like the one we made when you open a event in message").
    static let wordHold = 0.20
    /// Into the tab bar, the yellow falls off the bottom of the screen like a curtain, gathering
    /// speed, gone as Bp! lands (Jesse, 2026-11-08: "curtain"); quicker after a tap. A zoom fades.
    static let curtainTime = 0.36
    static let curtainTimeFast = 0.22
    /// Bp! leaps into the tab bar (Jesse, 2026-11-02: "faster and not just a straight animation
    /// with no emotion"): it crouches onto its foot, is tossed along a parabola (its middle point
    /// 190 pt above where it starts) down into the slot, leaning 12° and stretching as it flies,
    /// lands with B and p's rubber squash, and the tab bar dips 2.2 pt with it. After a tap it
    /// flies faster and just lands.
    private static let leapCrouch = 0.07
    private static let leapDip: CGFloat = 0.10
    /// The crouch lets go over the flight's first fifth: let go in one frame, Bp! snapped 14 pt
    /// taller (Jesse, 2026-11-07: "yes to all", BP app references/launch-glitch).
    private static let leapRelease: CGFloat = 0.2
    private static let leapFlight = 0.26
    private static let leapFlightFast = 0.16
    private static let leapRise: CGFloat = 190
    private static let leapTilt = -12.0
    private static let leapStretch: CGFloat = 0.08
    private static let leapLand = 0.30
    /// The landing's squash plays out until it stays under 1% of Bp!'s height: done at its first
    /// pass through rest, it stopped dead with an 11% rebound still to come (Jesse, 2026-11-07).
    static let leapSettles = settleTime(leapLand, spring: wobble, under: 0.01)
    private static let tabCatch = Spring(response: 0.30, dampingRatio: 0.45)
    private static let tabCatchDip = 2.2
    private static let glide = Spring(response: 0.38, dampingRatio: 0.88)
    private static let glideFast = Spring(response: 0.26, dampingRatio: 0.95)
    private static let yellowFade = 0.30
    private static let yellowFadeFast = 0.18
    /// A tap: the ball goes into the dot in 0.16 s, and the ending starts 0.10 after.
    private static let skipMove = 0.16
    private static let skipToEnd = 0.10
    /// A first open zooms Bp! through, to 6x.
    private static let zoomTo: CGFloat = 6

    // MARK: The mark: the Daily mark's canvas, viewBox 137 302 751 422

    static let canvas = CGRect(x: 137, y: 302, width: 751, height: 422)
    /// The middle of the still's Bp (B and p at 90%, shrunk toward the !) on the canvas: the full
    /// Bp's middle (429.75, 513) taken 90% of the way from `letterAnchor`. It sits in the screen's
    /// middle and the ! reaches past it on the right (Jesse, 2026-11-02: "recenter that the BP is
    /// in the middle"), so the whole launch, the ball's start included, moves by `centring` from
    /// the canvas's own middle.
    static let bpMiddle = CGPoint(x: 464.875, y: 524.5)
    static let centring = CGSize(width: (canvas.midX - bpMiddle.x) * scale, height: (canvas.midY - bpMiddle.y) * scale)
    /// Bp! is 320 pt wide (Jesse, 2026-11-08: "320", from 249.6: "the current one is
    /// underwhelming"), which sets the points per canvas unit. The dot is 101 canvas units across
    /// and the ball 15% larger than it (round 1's 17.2 pt ball 125% larger, then grown with Bp!).
    static let markWidth: CGFloat = 320
    static let scale = markWidth / canvas.width
    static let dot = scale * 101
    static let ball = dot * 1.15
    /// What B and p shrink toward at their 90%: the !'s dot on the baseline, so the word never
    /// splits (Jesse, 2026-11-08: "i dont like how the letters are separated", "together with the
    /// !"; each about its own foot, the gaps had grown 9 and 7 pt).
    static let letterAnchor = CGPoint(x: 781, y: 627)
    /// The tops of B and p, and where along each the ball landed before the squeeze: only the
    /// show's times still come from them.
    private static let topB: CGFloat = 303.5
    private static let topP: CGFloat = 383.5
    private static let landB: CGFloat = 275
    private static let landP: CGFloat = 580
    /// The !'s dot.
    private static let dotCentre = CGPoint(x: 781, y: 582.75)

    // MARK: The wordmark: the still's BlockParty., as wide as Bp!, in the screen's middle

    /// The wordmark's pieces, each a picture the wordmark's size holding one letter (BP app
    /// references/launch-squeeze/src), in the order `Frame.pieces` holds them.
    static let wordPieces = ["B", "L", "O", "C", "K", "P", "A", "R", "T", "Y", "Dot"].map { "LaunchWord" + $0 }
    private static let pieceB = 0, pieceL = 1, pieceP = 5, pieceA = 6, pieceDot = 10
    /// The wordmark in its own pixels: its B and P, and each small letter's left and right edge.
    private static let wordSize = CGSize(width: 1051, height: 216)
    private static let wordB = CGRect(x: 0, y: 16, width: 150, height: 155)
    private static let wordP = CGRect(x: 511, y: 9, width: 143, height: 160)
    private static let wordLock: [(CGFloat, CGFloat)] = [(139, 208), (196, 309), (304, 407), (387, 519)]
    private static let wordArty: [(CGFloat, CGFloat)] = [(634, 756), (746, 842), (839, 916), (900, 1031)]
    /// Canvas units per wordmark pixel, and the wordmark's box on the canvas: the same on every
    /// screen, since both sit in the screen's middle.
    private static let wordUnit = canvas.width / wordSize.width
    static let wordBox = CGRect(x: canvas.minX - centring.width / scale,
                                y: canvas.midY - wordSize.height * wordUnit / 2 - centring.height / scale,
                                width: wordSize.width * wordUnit, height: wordSize.height * wordUnit)
    private static func wx(_ pixel: CGFloat) -> CGFloat { wordBox.minX + wordUnit * pixel }
    private static func wy(_ pixel: CGFloat) -> CGFloat { wordBox.minY + wordUnit * pixel }
    /// Bp!'s B and p on the canvas (measured off their pictures). The wordmark's B and P are the same
    /// shapes at a third of the size, so each hands over to Bp!'s own as its hit lets go.
    private static let glyphB = CGRect(x: 137, y: 302, width: 322.5, height: 335.5)
    private static let glyphP = CGRect(x: 444, y: 385, width: 283.5, height: 339)
    /// Bp!'s B and p at the wordmark's size: how small, and where the middle of each foot sits.
    private static let smallB = wordUnit * wordB.height / glyphB.height
    private static let smallP = wordUnit * wordP.height / glyphP.height
    private static let smallFootB = CGPoint(x: wx(wordB.midX), y: wy(wordB.maxY) - smallB * (glyphB.maxY - letterAnchor.y))
    private static let smallFootP = CGPoint(x: wx(wordP.midX), y: wy(wordP.maxY) - smallP * (glyphP.maxY - letterAnchor.y))
    /// After B's hit the big B and the small "Party." sit side by side in the screen's middle, on
    /// Bp!'s line: where B's foot is then, and how far "Party." moved to get there.
    private static let besideB: CGFloat = {
        let wide = startSize * glyphB.width, rest = wx(wordSize.width) - wx(wordP.minX)
        let middle = canvas.minX + (markWidth / 2 - centring.width) / scale
        return middle - (wide + squeezeGap + rest) / 2 + wide / 2
    }()
    private static let partyShift = CGSize(width: besideB + startSize * glyphB.width / 2 + squeezeGap - wx(wordP.minX),
                                           height: letterAnchor.y - smallFootB.y)
    /// B and p's feet at the still's 90%, shrunk toward the !.
    private static let endB = letterAnchor.x + startSize * (glyphB.midX - letterAnchor.x)
    private static let endP = letterAnchor.x + startSize * (glyphP.midX - letterAnchor.x)

    // MARK: Inputs

    /// How the launch ends: on the tab bar's Daily Bp! (its frame in this space), or zooming
    /// through (a first open, which has no tab bar).
    enum Ending: Equatable {
        case tab(CGRect)
        case zoom
    }

    /// Which launch plays (file header): the full show, or the wordmark shooting out.
    enum Kind: String {
        case full, word
    }

    let screen: CGSize
    /// When a tap skipped, in simulation time; ignored at moments before it.
    var skip: Double?
    var ending: Ending = .zoom
    var kind: Kind = .full
    /// A link that caught the full show on its way (`LaunchStage.openedLink`): the show's last
    /// frame, which fades out as BlockParty. comes back, rather than vanishing.
    var before: Frame?
    /// Reduce Motion: the wordmark fades with the yellow instead of shooting out.
    var reduceMotion = false

    // MARK: The path, worked out once per screen

    /// The canvas's top left on screen: Bp! sits in the middle.
    let origin: CGPoint
    /// The wordmark's B and P's heights on screen, and where the ball sits on each and on the dot.
    private let tallB: CGFloat, tallP: CGFloat
    private let onB: CGPoint, onP: CGPoint, onDot: CGPoint
    private let drop: Flight, toP: Flight, toDot: Flight
    let hitB: Double, hitP: Double, landAt: Double, ballEnd: Double

    init(screen: CGSize, skip: Double? = nil, ending: Ending = .zoom, kind: Kind = .full, before: Frame? = nil,
         reduceMotion: Bool = false) {
        self.screen = screen
        self.skip = skip
        self.ending = ending
        self.kind = kind
        self.before = before
        self.reduceMotion = reduceMotion
        let s = Self.scale
        origin = CGPoint(x: (screen.width - Self.canvas.width * s) / 2 + Self.centring.width,
                         y: (screen.height - Self.canvas.height * s) / 2 + Self.centring.height)
        let u = { [origin] (x: CGFloat, y: CGFloat) in
            CGPoint(x: origin.x + (x - Self.canvas.minX) * s, y: origin.y + (y - Self.canvas.minY) * s)
        }
        tallB = Self.wordB.height * Self.wordUnit * s
        tallP = Self.wordP.height * Self.wordUnit * s
        let r0 = Self.ball / 2
        // The ball lands on the wordmark's B, then on its P, which B's hit has moved by then.
        onB = CGPoint(x: u(Self.smallFootB.x, 0).x, y: u(0, Self.wy(Self.wordB.minY)).y - r0)
        onP = CGPoint(x: u(Self.smallFootP.x + Self.partyShift.width, 0).x,
                      y: u(0, Self.wy(Self.wordP.minY) + Self.partyShift.height).y - r0)
        onDot = u(Self.dotCentre.x, Self.dotCentre.y)

        let g = Self.gravity, v0 = Self.dropSpeed
        let start = CGPoint(x: Self.start.x + Self.centring.width, y: Self.start.y + Self.centring.height)
        func fall(_ from: CGPoint, to: CGPoint) -> CGFloat { (-v0 + (v0 * v0 + 2 * g * (to.y - from.y)).squareRoot()) / g }
        switch kind {
        case .full:
            let dropTime = fall(start, to: onB)
            drop = Flight(from: start, time: Double(dropTime), vy: v0,
                          vx: (onB.x - start.x) / dropTime, spin: (-120, 0), shrinks: false)
            // The small letters sit lower than B and p at their 90% did, so the drop is longer and
            // the hops lower: each is as high as lands the ball on p and on the dot when it did
            // before the squeeze (the show is no longer).
            let k = Self.startSize, a = Self.letterAnchor.x, base = u(0, Self.letterAnchor.y).y
            let wasB = CGPoint(x: u(a + k * (Self.landB - a), 0).x, y: base - k * (Self.letterAnchor.y - Self.topB) * s - r0)
            let wasP = CGPoint(x: u(a + k * (Self.landP - a), 0).x, y: base - k * (Self.letterAnchor.y - Self.topP) * s - r0)
            let late = Double(dropTime - fall(start, to: wasB))
            toP = Flight.arc(from: onB, to: onP, spin: (0, 360),
                             taking: Flight.arc(from: wasB, to: wasP, height: Self.arcB, spin: (0, 0)).time - late)
            toDot = Flight.arc(from: onP, to: onDot, spin: (360, 720), shrinks: true,
                               taking: Flight.arc(from: wasP, to: onDot, height: Self.arcP, spin: (0, 0)).time)
            hitB = drop.time
            hitP = hitB + Self.contact + toP.time
            landAt = hitP + Self.contact + toDot.time
        case .word:
            // No ball: the wordmark.
            drop = Flight(from: onDot, time: 0, vy: 0, vx: 0, spin: (0, 0), shrinks: false)
            toP = drop
            toDot = drop
            hitB = .infinity
            hitP = .infinity
            landAt = 0
        }
        ballEnd = landAt + Self.contact
    }

    /// One parabola: leaves `from` at (vx, vy) under gravity.
    private struct Flight {
        var from: CGPoint
        var time: Double
        var vy: CGFloat
        var vx: CGFloat
        var spin: (CGFloat, CGFloat)
        var shrinks: Bool

        /// Up `height` above `from`, then down onto `to`.
        static func arc(from: CGPoint, to: CGPoint, height: CGFloat, spin: (CGFloat, CGFloat), shrinks: Bool = false) -> Flight {
            let g = LaunchMotion.gravity
            let up = (2 * height / g).squareRoot(), down = (2 * (to.y - (from.y - height)) / g).squareRoot()
            return Flight(from: from, time: Double(up + down), vy: -g * up, vx: (to.x - from.x) / (up + down),
                          spin: spin, shrinks: shrinks)
        }

        /// The arc from `from` onto `to` that takes `time`: a higher arc takes longer, so halve the
        /// range of heights till it fits.
        static func arc(from: CGPoint, to: CGPoint, spin: (CGFloat, CGFloat), shrinks: Bool = false, taking time: Double) -> Flight {
            var low = max(0, from.y - to.y) + 0.01, high: CGFloat = 600
            for _ in 0..<40 {
                let height = (low + high) / 2
                if arc(from: from, to: to, height: height, spin: spin).time < time { low = height } else { high = height }
            }
            return arc(from: from, to: to, height: (low + high) / 2, spin: spin, shrinks: shrinks)
        }
    }

    // MARK: The ball

    struct Ball: Equatable {
        /// Centre, radius, roll in degrees, stretch along the velocity's angle `heading`.
        var x: CGFloat, y: CGFloat, r: CGFloat, roll: CGFloat
        var sx: CGFloat = 1, sy: CGFloat = 1, heading: CGFloat = 0
    }

    /// The ball as it flies and bounces, with no tap.
    func ball(at t: Double) -> Ball {
        let r0 = Self.ball / 2, rf = Self.dot / 2
        if kind == .word || t >= ballEnd { return Ball(x: onDot.x, y: onDot.y, r: rf, roll: 720) }
        if t < hitB { return fly(drop, t, r0) }
        if t < hitB + Self.contact { return hit(t - hitB, at: onB, r: r0, roll: 0, squash: Self.squash, letter: (tallB, Self.dipB)) }
        if t < hitP { return fly(toP, t - hitB - Self.contact, r0) }
        if t < hitP + Self.contact { return hit(t - hitP, at: onP, r: r0, roll: 360, squash: Self.squash, letter: (tallP, Self.dipP)) }
        if t < landAt { return fly(toDot, t - hitP - Self.contact, r0) }
        return hit(t - landAt, at: onDot, r: rf, roll: 720, squash: Self.squashDot, letter: nil)
    }

    private func fly(_ f: Flight, _ tt: Double, _ r0: CGFloat) -> Ball {
        let g = Self.gravity, s = CGFloat(tt), v = CGFloat(tt / f.time)
        let vy = f.vy + g * s
        let k = Self.stretch * min(1, hypot(f.vx, vy) / 2200)
        let r = f.shrinks ? lerp(r0, Self.dot / 2, smooth(clamp01(v))) : r0
        return Ball(x: f.from.x + f.vx * s, y: f.from.y + f.vy * s + g * s * s / 2, r: r,
                    roll: lerp(f.spin.0, f.spin.1, v), sx: 1 + k, sy: 1 / (1 + k),
                    heading: atan2(vy, f.vx) * 180 / .pi)
    }

    /// Squashed on a letter or the dot; on a letter (its height and dip) it rides the top as it dips.
    private func hit(_ tt: Double, at p: CGPoint, r: CGFloat, roll: CGFloat, squash: CGFloat,
                     letter: (tall: CGFloat, dip: Double)?) -> Ball {
        let q = sin(.pi * clamp01(CGFloat(tt / Self.contact)))
        let sy = 1 - squash * q, sx = 1 + squash * 1.15 * q
        var y = p.y + r * (1 - sy)
        if let letter { y += CGFloat(Self.kick(tt, letter.dip)) * letter.tall }
        return Ball(x: p.x, y: y, r: r, roll: roll, sx: sx, sy: sy)
    }

    // MARK: Springs and curves

    /// A spring kicked once from rest, scaled so its first peak is `amp`: a letter's rubber dip,
    /// or the tab bar's catch.
    static func kick(_ tau: Double, _ amp: Double, spring: Spring = wobble) -> Double {
        guard tau > 0, amp != 0 else { return 0 }
        let w = 2 * .pi / spring.response, z = spring.dampingRatio, wd = w * (1 - z * z).squareRoot()
        let peak = atan(wd / (z * w)) / wd
        return amp * spring.value(target: 0.0, initialVelocity: 1.0, time: tau)
            / spring.value(target: 0.0, initialVelocity: 1.0, time: peak)
    }

    /// When a `kick` stays under `under` for good: its envelope, not its value, which passes
    /// through zero on every swing.
    static func settleTime(_ amp: Double, spring: Spring, under: Double) -> Double {
        let w = 2 * .pi / spring.response, z = spring.dampingRatio, wd = w * (1 - z * z).squareRoot()
        let peak = atan(wd / (z * w)) / wd
        let atPeak = exp(-z * w * peak) * sin(wd * peak)
        return max(0, log(amp / (atPeak * under)) / (z * w))
    }

    /// The jump's keyframes, the mock's `JUMP`: [to, seconds, curve], each easing from the last as
    /// SwiftUI's `LinearKeyframe` does. y is in the tab bar's points, like the Daily tab's hop.
    private typealias Key = (to: CGFloat, seconds: Double, curve: UnitCurve)
    private static let lift = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.3, y: 1))
    private static let fall = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.5, y: 0), endControlPoint: UnitPoint(x: 0.8, y: 0.4))
    private static let hang = UnitCurve.bezier(startControlPoint: UnitPoint(x: 1.0 / 3, y: 0), endControlPoint: UnitPoint(x: 2.0 / 3, y: 1))
    private static let jumpY: [Key] = [(0, 0.07, .linear), (-4, 0.16, lift), (-4.4, 0.14, hang), (0, 0.12, fall), (0, 0.22, .linear)]
    private static let jumpWidth: [Key] = [(1.10, 0.07, .linear), (0.95, 0.16, lift), (1, 0.14, .linear), (0.97, 0.12, fall),
                                           (1.14, 0.06, .linear), (0.97, 0.08, lift), (1, 0.08, .linear)]
    private static let jumpHeight: [Key] = [(0.86, 0.07, .linear), (1.08, 0.16, lift), (1, 0.14, .linear), (1.05, 0.12, fall),
                                            (0.84, 0.06, .linear), (1.04, 0.08, lift), (1, 0.08, .linear)]
    /// The !'s line alone on the way up: 6% short and a little wide where everything else stretches,
    /// full height by the end of the hang, then back with the rest (Jesse, 2026-11-05: "when the !
    /// bounces up very slightly compress the top line", then "6 percent").
    private static let jumpLineWidth: [Key] = [(1.10, 0.07, .linear), (1.027, 0.16, lift)] + jumpWidth.dropFirst(2)
    private static let jumpLineHeight: [Key] = [(0.86, 0.07, .linear), (0.94, 0.16, lift)] + jumpHeight.dropFirst(2)

    private static func track(_ keys: [Key], from start: CGFloat, at time: Double) -> CGFloat {
        var from = start, t = time
        for key in keys {
            if t < key.seconds { return lerp(from, key.to, CGFloat(key.curve.value(at: t / key.seconds))) }
            t -= key.seconds
            from = key.to
        }
        return from
    }

    /// A letter's size: 90% until its hit, then springing to full size.
    private func size(_ t: Double, hit: Double) -> CGFloat {
        let tau = t - hit
        return Self.startSize + (1 - Self.startSize) * (tau > 0 ? CGFloat(Self.grow.value(target: 1.0, time: tau)) : 0)
    }

    /// The mock's ease-out, cubic-bezier(0.23, 1, 0.32, 1).
    static let easeOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1), endControlPoint: UnitPoint(x: 0.32, y: 1))

    private static func ease(_ x: Double) -> Double { x <= 0 ? 0 : x >= 1 ? 1 : easeOut.value(at: x) }

    // MARK: A moment

    /// Everything the screen draws at one moment.
    struct Frame: Equatable {
        var ball: Ball
        /// How far the ball's colours have gone black, and how strongly it shows: it goes once it
        /// has become the real dot.
        var ballBlack: Double = 0
        var ballOpacity = 1.0
        /// B and p's scale about `letterAnchor`, and how strongly they show.
        var b = CGSize(width: Self.small, height: Self.small)
        var p = CGSize(width: Self.small, height: Self.small)
        var letters = 1.0
        /// The squeeze: how far B and p sit from their place in Bp!, in canvas units, and whether
        /// they show yet (the wordmark's own B and P do until their hit lets go).
        var bShift = CGSize.zero
        var pShift = CGSize.zero
        var bShown = true
        var pShown = true
        /// The wordmark's pieces in `wordPieces` order, each moved about its box's top left in
        /// canvas units; none while the still's picture shows, or once Bp has taken them all in.
        var pieces: [Piece] = []
        var dotShown = false
        var lineOpacity = 0.0
        /// The still's BlockParty. picture, on the yellow: there until the full show's first hit,
        /// when its pieces take over, and staying till the fade on every other open.
        var word = 0.0
        /// The jump: how far up everything is, in the tab bar's points, and the !'s line and dot's
        /// squash and stretch about their feet.
        var lift: CGFloat = 0
        var line = CGSize(width: 1, height: 1)
        var dot = CGSize(width: 1, height: 1)
        /// The ball's shadow on the glass: how far below the ball, how soft, how dark.
        var shadeDrop: CGFloat = 0
        var shadeBlur: CGFloat = 0
        var shadeOpacity = 0.0
        /// Where the canvas's top left sits and its points per canvas unit, then a zoom about
        /// Bp!'s middle and its opacity.
        var markOrigin: CGPoint
        var markScale: CGFloat = LaunchMotion.scale
        /// The leap's lean and squash, both about Bp!'s foot (the middle of its canvas's bottom).
        var markTilt = 0.0
        var markSquash = CGSize(width: 1, height: 1)
        /// How far the tab bar has dipped catching Bp!, in points.
        var tabDip: CGFloat = 0
        var zoom: CGFloat = 1
        var markOpacity = 1.0
        /// How much of the yellow is left, for the shade on it and whether a tap is the launch's.
        var yellow = 1.0
        /// How the yellow goes: fading (a zoom), or falling off the screen's bottom (the curtain,
        /// into the tab bar), its pictures' opacity and how far they have dropped, in points.
        var yellowOpacity = 1.0
        var yellowDrop: CGFloat = 0
        /// The app behind: 98.5% growing to full size under Bp!'s glide, or 105% settling for a zoom.
        var backScale: CGFloat = 1
        /// Welcome's logo and headline may rise: the zoom is half done.
        var headerUp = false
        /// Once the ending has started, its spring in real time (paced), for the app behind,
        /// which SwiftUI animates on it.
        var ending: Spring?
        /// Buzzes so far: light on B, light on p, firm on the dot, firm as Bp! lands from its jump,
        /// light as it lands in the tab bar.
        var buzzes = 0
        var done = false

        /// A tap belongs to the launch until its yellow is mostly gone, then goes through to the
        /// app under the glide (Jesse, 2026-11-02).
        var takesTaps: Bool { yellow > 0.25 }

        private static let small = LaunchMotion.startSize

        struct Piece: Equatable {
            var opacity = 0.0
            var transform = CGAffineTransform.identity
        }
    }

    /// The buzzes in order: the full show's five. The wordmark open has none.
    static func buzzKinds(_ kind: Kind) -> [SensoryFeedback] {
        switch kind {
        case .full: [.impact(weight: .light), .impact(weight: .light), .impact(weight: .medium), .impact(weight: .medium), .impact(weight: .light)]
        case .word: []
        }
    }

    func frame(at t: Double) -> Frame {
        kind == .word ? worded(at: t) : moving(at: t)
    }

    private func moving(at t: Double) -> Frame {
        let rf = Self.dot / 2
        let skip = self.skip.flatMap { $0 <= t ? $0 : nil }
        let swapNormally = landAt + Self.blacken
        let endNormally = swapNormally + Self.jumpEnds
        // A tap before the ball has turned into the dot sends it there and drops the jump.
        let early = skip.flatMap { $0 < swapNormally ? $0 : nil }
        let swapAt = early.map { $0 + Self.skipMove } ?? swapNormally
        let popAt: Double? = early == nil ? swapNormally : nil
        var endAt = early.map { $0 + Self.skipMove + Self.skipToEnd } ?? endNormally
        // A tap during the jump settles it in 0.10 s, and the ending starts then.
        var settle = 1.0
        if let skip, early == nil, skip < endNormally {
            endAt = min(endAt, skip + Self.skipToEnd)
            settle = 1 - Self.ease((t - skip) / Self.skipToEnd)
        }

        var f = Frame(ball: ball(at: t), markOrigin: origin)
        f.ballBlack = clamp01(Self.ease((t - landAt) / Self.blacken))
        if let early {
            let from = ball(at: min(early, ballEnd))
            let fromBlack = clamp01(Self.ease((early - landAt) / Self.blacken))
            let v = CGFloat(Self.ease((t - early) / Self.skipMove))
            f.ball = Ball(x: lerp(from.x, onDot.x, v), y: lerp(from.y, onDot.y, v), r: lerp(from.r, rf, v),
                          roll: lerp(from.roll, ceil(from.roll / 360 - 1e-6) * 360, v),
                          sx: lerp(from.sx, 1, v), sy: lerp(from.sy, 1, v), heading: from.heading)
            f.ballBlack = Double(lerp(CGFloat(fromBlack), 1, v))
        }
        let swapped = t >= swapAt
        f.ballOpacity = swapped ? 0 : 1
        f.dotShown = swapped

        // The ball's shadow on the glass: farther off, softer and fainter while the ball is high
        // above where it comes down next, closing in under it as it lands.
        if !swapped {
            let next = t < hitB ? onB : t < hitP ? onP : onDot
            let height = max(0, next.y - f.ball.y)
            f.shadeDrop = 3 + 0.10 * height
            f.shadeBlur = 1.5 + 0.05 * height
            f.shadeOpacity = max(0.06, 0.30 - 0.0012 * Double(height)) * (1 - f.ballBlack)
        }

        // The jump, at any moment, eased back to rest by a tap during it.
        let h = popAt.map { t - $0 } ?? -1
        func jump(_ keys: [Key], _ rest: CGFloat) -> CGFloat {
            h < 0 ? rest : rest + (Self.track(keys, from: rest, at: h) - rest) * CGFloat(settle)
        }
        let jumpWidth = jump(Self.jumpWidth, 1), jumpHeight = jump(Self.jumpHeight, 1)

        // B and p dip and bulge on their hit, swell to 90% as it lets go, then grow to full size on
        // the jump's way up. A tap grows them as the ! appears, and a letter the ball never reached
        // doesn't dip.
        var k = Self.startSize
        if early != nil {
            k = size(t, hit: swapAt)
        } else if h >= 0 {
            let up = h < 0.07 ? 0 : CGFloat(Self.lift.value(at: min(1, (h - 0.07) / 0.16)))
            k = 1 - (1 - Self.startSize) * (1 - up) * CGFloat(settle)
        }
        func dip(hit: Double, _ amp: Double) -> CGFloat {
            (early.map { hit <= $0 } ?? true) ? CGFloat(Self.kick(t - hit, amp)) : 0
        }
        squeeze(&f, at: t, skip: skip, size: k, jump: CGSize(width: jumpWidth, height: jumpHeight),
                dipB: dip(hit: hitB, Self.dipB), dipP: dip(hit: hitP, Self.dipP), swapped: swapped)

        // The ! : after a tap it simply appears; otherwise it jumps with B and p, its line growing
        // out of the dot during the crouch and fading in over its first 40 ms. It grows on a plain
        // ease-out: on the mock's sharp one it was nearly full height in two frames, a pop (2026-11-07).
        f.lift = jump(Self.jumpY, 0)
        f.dot = CGSize(width: jumpWidth, height: jumpHeight)
        if let popAt {
            let height = h < DailyMarkGlyph.crouch ? 0.86 * CGFloat(UnitCurve.easeOut.value(at: h / DailyMarkGlyph.crouch)) : jump(Self.jumpLineHeight, 1)
            f.line = CGSize(width: jump(Self.jumpLineWidth, 1), height: h < 0 ? 0 : height)
            f.lineOpacity = clamp01((t - popAt) / 0.04)
        } else {
            f.lineOpacity = swapped ? 1 : 0
        }

        // The ending: Bp! leaps into the tab bar's Bp!, or zooms through.
        guard t >= endAt else {
            f.backScale = ending == .zoom ? 1.05 : 0.985
            f.buzzes = buzzes(at: t, skip: skip, beats: [hitB, hitP, landAt, popAt.map { $0 + Self.jumpLands } ?? .infinity])
            return f
        }
        f.ending = paced(skip == nil ? Self.glide : Self.glideFast)
        var settled: Bool
        var landed = Double.infinity
        switch ending {
        case .tab(let target):
            let e = t - endAt
            let crouch = skip == nil ? Self.leapCrouch : 0
            let flight = skip == nil ? Self.leapFlight : Self.leapFlightFast
            let s = Self.scale, to = target.width / Self.canvas.width
            let start = CGPoint(x: origin.x + Self.canvas.width * s / 2, y: origin.y + Self.canvas.height * s)
            let end = CGPoint(x: target.midX, y: target.maxY)
            let control = CGPoint(x: start.x + (end.x - start.x) * 0.15, y: start.y - Self.leapRise)
            var foot = start, markScale = s, progress = 0.0
            settled = false
            if e < crouch {
                let q = CGFloat(sin(e / crouch * .pi / 2))
                f.markSquash = CGSize(width: 1 + Self.leapDip / 2 * q, height: 1 - Self.leapDip * q)
            } else if e < crouch + flight {
                let u = CGFloat((e - crouch) / flight), w = 1 - u
                foot = CGPoint(x: w * w * start.x + 2 * w * u * control.x + u * u * end.x,
                               y: w * w * start.y + 2 * w * u * control.y + u * u * end.y)
                markScale = lerp(s, to, smooth(u))
                f.markTilt = Self.leapTilt * sin(.pi * Double(u))
                let stretch = Self.leapStretch * CGFloat(sin(.pi * Double(u)))
                let crouched = crouch > 0 ? Self.leapDip * (1 - smooth(min(1, u / Self.leapRelease))) : 0
                f.markSquash = CGSize(width: (1 + crouched / 2) / (1 + stretch), height: (1 - crouched) * (1 + stretch))
                progress = Double(u)
            } else {
                let tau = e - crouch - flight
                let d = CGFloat(Self.kick(tau, skip == nil ? Self.leapLand : 0))
                f.tabDip = CGFloat(Self.kick(tau, skip == nil ? Self.tabCatchDip : 0, spring: Self.tabCatch))
                foot = CGPoint(x: end.x, y: end.y + f.tabDip)
                markScale = to
                f.markSquash = CGSize(width: 1 + CGFloat(Self.bulge) * d, height: 1 - d)
                progress = 1
                landed = endAt + crouch + flight
                // Done once the squash has died down; what's left of the tab bar's dip, under half a
                // point, eases out from there (`LaunchStage.finish`).
                settled = tau > max(0.2, skip == nil ? Self.leapSettles : 0)
            }
            f.markScale = markScale
            f.markOrigin = CGPoint(x: foot.x - Self.canvas.width * markScale / 2, y: foot.y - Self.canvas.height * markScale)
            f.backScale = 1 - 0.015 * (1 - CGFloat(Self.ease(progress)))
        case .zoom:
            let (p, v) = endSpring(at: t, endAt: endAt, skip: skip)
            f.zoom = 1 + (Self.zoomTo - 1) * CGFloat(max(0, p))
            f.markOpacity = 1 - clamp01((p - 0.1) / 0.5)
            f.backScale = 1 + 0.05 * (1 - CGFloat(clamp01(p)))
            f.headerUp = p >= 0.5
            settled = abs(p - 1) < 0.003 && abs(v) < 0.01
        }
        f.buzzes = buzzes(at: t, skip: skip, beats: [hitB, hitP, landAt, popAt.map { $0 + Self.jumpLands } ?? .infinity, landed])
        if case .tab = ending {
            // The curtain: the yellow, glass and signature with it, falls off the bottom of the
            // screen gathering speed (Jesse, 2026-11-08), gone about as Bp! lands in the tab bar.
            let v = clamp01((t - endAt) / (skip == nil ? Self.curtainTime : Self.curtainTimeFast))
            f.yellow = 1 - v * v
            f.yellowDrop = screen.height * v * v
        } else {
            f.yellow = 1 - Self.ease((t - endAt) / (skip == nil ? Self.yellowFade : Self.yellowFadeFast))
            f.yellowOpacity = f.yellow
        }
        f.done = settled && f.yellow <= 0.001
        return f
    }

    /// The squeeze at one moment (the mock's `squeeze`, its round 3 fold). Each hit lets go as the
    /// ball leaves its letter, and a tap lets go of whatever the ball never reached. B swells from
    /// the wordmark's B to the still's 90% B beside the small "Party.", taking in l, o, c, k; then p
    /// swells from the wordmark's P, its foot sinking below the line, taking in a, r, t, y, while B
    /// moves over to its place in Bp!. The full stop waits where the ball lands. Once both have let
    /// go and settled, B and p sit exactly as they did before the squeeze, so the jump is unchanged.
    private func squeeze(_ f: inout Frame, at t: Double, skip: Double?, size k: CGFloat, jump: CGSize,
                         dipB: CGFloat, dipP: CGFloat, swapped: Bool) {
        typealias M = LaunchMotion
        let letGoB = min(hitB + M.contact, skip ?? .infinity), letGoP = min(hitP + M.contact, skip ?? .infinity)
        let s1 = M.gulps(t - letGoB), s2 = M.gulps(t - letGoP), c1 = clamp01(s1), c2 = clamp01(s2)
        let a = M.letterAnchor, big = M.startSize, bulge = CGFloat(M.bulge)
        let party = CGSize(width: M.partyShift.width * s1, height: M.partyShift.height * s1)

        let kb = lerp(M.smallB, big, s1)
        let footB = CGPoint(x: lerp(M.smallFootB.x, M.besideB, s1) + (M.endB - M.besideB) * s2, y: lerp(M.smallFootB.y, a.y, s1))
        f.bShown = t >= letGoB
        f.bShift = CGSize(width: footB.x - a.x - kb * (M.glyphB.midX - a.x), height: footB.y - a.y)
        f.b = CGSize(width: kb * k / big * jump.width * (1 + bulge * dipB), height: kb * k / big * jump.height * (1 - dipB))

        let kp = lerp(M.smallP, big, s2)
        let footP = CGPoint(x: lerp(M.smallFootP.x + party.width, M.endP, s2), y: lerp(M.smallFootP.y + party.height, a.y, s2))
        f.pShown = t >= letGoP
        f.pShift = CGSize(width: footP.x - a.x - kp * (M.glyphP.midX - a.x), height: footP.y - a.y)
        f.p = CGSize(width: kp * k / big * jump.width * (1 + bulge * dipP), height: kp * k / big * jump.height * (1 - dipP))

        // The still's own picture shows until the first hit, or a tap: nothing in the word has moved.
        // The pieces wait under it, drawn clear, so their pictures are ready on the frame of the hit.
        f.word = t < min(hitB, skip ?? .infinity) ? 1 : 0
        var pieces = [Frame.Piece](repeating: Frame.Piece(), count: M.wordPieces.count)
        // The wordmark's own B and P until their hit lets go: they dip under the ball, like rubber.
        let line = M.smallFootB.y - M.wordBox.minY
        pieces[M.pieceB] = Frame.Piece(opacity: f.bShown ? 0 : 1, transform: M.about(
            CGPoint(x: M.wordB.midX * M.wordUnit, y: line), CGAffineTransform(scaleX: 1 + bulge * dipB, y: 1 - dipB)))
        pieces[M.pieceP] = Frame.Piece(opacity: f.pShown ? 0 : 1, transform: M.about(
            CGPoint(x: M.wordP.midX * M.wordUnit, y: line), CGAffineTransform(scaleX: 1 + bulge * dipP, y: 1 - dipP), shift: party))
        pieces[M.pieceDot] = Frame.Piece(opacity: swapped || (skip == nil && t >= landAt + 0.02) ? 0 : 1,
                                         transform: CGAffineTransform(translationX: party.width, y: party.height))
        // "lock" has the room between B's right edge and P's left edge, "arty" the room p's right
        // edge leaves as it swells.
        let rightB = footB.x + kb * M.glyphB.width / 2, rightB0 = M.smallFootB.x + M.smallB * M.glyphB.width / 2
        let lock0 = M.wx(M.wordLock[0].0), lock1 = M.wx(M.wordLock[3].1), leftP0 = M.wx(M.wordP.minX)
        M.take(M.wordLock, into: &pieces, from: M.pieceL,
               left: rightB - (rightB0 - lock0) * (1 - c1),
               right: leftP0 + party.width + (lock1 - leftP0) * (1 - c1) - M.squeezeGap * c1,
               belly: footB.y - M.bellyB * kb, drop: party.height, gone: t - letGoB >= M.gulpsFull)
        let rightP = footP.x + kp * M.glyphP.width / 2, rightP0 = M.smallFootP.x + M.smallP * M.glyphP.width / 2
        M.take(M.wordArty, into: &pieces, from: M.pieceA,
               left: rightP - (rightP0 - M.wx(M.wordArty[0].0)) * (1 - c2),
               right: lerp(M.wx(M.wordArty[3].1) + party.width, M.endP + big * M.glyphP.width / 2, c2),
               belly: footP.y - M.bellyP * kp, drop: party.height, gone: t - letGoP >= M.gulpsFull)
        if f.word == 1 {
            f.pieces = pieces.map { Frame.Piece(opacity: 0, transform: $0.transform) }
        } else {
            f.pieces = pieces.contains { $0.opacity > 0 } ? pieces : []
        }
    }

    /// How far a big letter has swelled `tau` s after its hit let go: the mean of four gulps.
    private static func gulps(_ tau: Double) -> CGFloat {
        CGFloat((0..<4).reduce(0.0) { sum, i in
            let since = tau - Double(i) * gulp
            return sum + (since > 0 ? gulpSpring.value(target: 1.0, time: since) : 0)
        } / 4)
    }

    /// When the swell first reaches full size. Its row is gone for good from then on: the spring
    /// still rings, and without this the row's last letter came back as a speck each time it did.
    private static let gulpsFull: Double = {
        var tau = 0.0
        while gulps(tau) < 1 { tau += 0.0005 }
        return tau
    }()

    /// A row of letters between the big letter's edge (`left`) and what follows them (`right`): as
    /// the room closes they are taken one at a time from the left. The one being taken fills what is
    /// left of its own room, so it shrinks whole, never stretched, toward `belly`, the big letter's
    /// widest point; the rest ride with what follows them.
    private static func take(_ row: [(CGFloat, CGFloat)], into pieces: inout [Frame.Piece], from first: Int,
                             left: CGFloat, right: CGFloat, belly: CGFloat, drop: CGFloat, gone: Bool) {
        let start = wx(row[0].0), whole = wx(row[row.count - 1].1) - start, taken = whole - max(0, right - left)
        for (i, letter) in row.enumerated() {
            let before = wx(letter.0) - start, wide = wx(letter.1) - wx(letter.0), u = clamp01((taken - before) / wide)
            let lean = CGAffineTransform(a: 1, b: 0, c: tan(-gulpLean * sin(.pi * Double(u)) * .pi / 180), d: 1, tx: 0, ty: 0)
            pieces[first + i] = Frame.Piece(opacity: gone || u > 0.995 ? 0 : 1, transform: about(
                CGPoint(x: letter.1 * wordUnit, y: belly - drop - wordBox.minY),
                lean.concatenating(CGAffineTransform(scaleX: 1 - u, y: 1 - u)),
                shift: CGSize(width: right - (whole - before - wide) - wx(letter.1), height: drop)))
        }
    }

    /// `transform` about the point `origin`, then moved by `shift`.
    private static func about(_ origin: CGPoint, _ transform: CGAffineTransform, shift: CGSize = .zero) -> CGAffineTransform {
        CGAffineTransform(translationX: -origin.x, y: -origin.y).concatenating(transform)
            .concatenating(CGAffineTransform(translationX: origin.x + shift.width, y: origin.y + shift.height))
    }

    /// Every open but the day's first (Jesse, 2026-11-14 and 2026-11-17; BP app references/splash-wordmark): no
    /// ball and no Bp. The still's BlockParty. holds, then shoots out at you as the 2026-11-08 link
    /// open's Bp! did (the zoom to 6x on the fast spring, gone by 60% of the way), the yellow and the
    /// signature fading in 0.18 s and the app settling from 105%. Reduce Motion: no zoom, everything
    /// fades together on the launch's 0.3 s fade, the app holding still. A link that caught the full
    /// show on its way fades what the show had drawn back into the wordmark first. A tap starts the
    /// ending at once.
    private func worded(at real: Double) -> Frame {
        let swap = before == nil ? 0 : Self.wordSwap
        let fadeAt = swap + Self.wordHold
        var t = real
        if let skip, skip <= real, skip < fadeAt { t = fadeAt + (real - skip) }
        let v = swap > 0 ? clamp01(t / swap) : 1
        var f = before ?? Frame(ball: ball(at: 0), markOrigin: origin)
        f.word = before.map { $0.word + (1 - $0.word) * v } ?? 1
        f.markOpacity = (before?.markOpacity ?? 0) * (1 - v)
        f.backScale = reduceMotion ? 1 : 1.05
        f.buzzes = 0
        guard t >= fadeAt else { return f }
        let spring = paced(Self.glideFast)
        f.ending = spring
        f.headerUp = true
        f.yellow = 1 - Self.ease((t - fadeAt) / (reduceMotion ? Self.yellowFade : Self.yellowFadeFast))
        f.yellowOpacity = f.yellow
        if reduceMotion {
            f.word = f.yellow
        } else {
            let p = max(0, spring.value(target: 1.0, time: t - fadeAt))
            f.zoom = 1 + (Self.zoomTo - 1) * CGFloat(p)
            f.word = 1 - clamp01((p - 0.1) / 0.5)
            f.backScale = 1 + 0.05 * (1 - CGFloat(clamp01(p)))
        }
        f.done = f.yellow <= 0.001
        return f
    }

    /// The buzzes this far, none after a tap. A beat that never comes (a letter a tap kept the
    /// ball from) doesn't hold the ones after it.
    private func buzzes(at t: Double, skip: Double?, beats: [Double]) -> Int {
        beats.filter(\.isFinite).prefix { beat in beat <= t && (skip.map { beat <= $0 } ?? true) }.count
    }

    /// A spring in the screen's time, which plays every motion at `pace`.
    private func paced(_ s: Spring) -> Spring {
        Spring(response: s.response / pace, dampingRatio: s.dampingRatio)
    }

    /// The zoom's progress and speed. A tap mid-way hands it to the fast spring, speed and all.
    private func endSpring(at t: Double, endAt: Double, skip: Double?) -> (Double, Double) {
        if let skip, skip > endAt {
            let p1 = Self.glide.value(target: 1.0, time: skip - endAt)
            let v1 = Self.glide.velocity(target: 1.0, time: skip - endAt)
            let gap = 1 - p1, tau = t - skip
            return (p1 + Self.glideFast.value(target: gap, initialVelocity: v1, time: tau),
                    Self.glideFast.velocity(target: gap, initialVelocity: v1, time: tau))
        }
        let spring = skip == nil ? Self.glide : Self.glideFast
        return (spring.value(target: 1.0, time: t - endAt), spring.velocity(target: 1.0, time: t - endAt))
    }
}

// MARK: - Helpers

nonisolated private func lerp(_ a: CGFloat, _ b: CGFloat, _ v: CGFloat) -> CGFloat { a + (b - a) * v }
nonisolated private func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
nonisolated private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
nonisolated private func smooth(_ v: CGFloat) -> CGFloat { v * v * (3 - 2 * v) }
