//
//  LaunchMotion.swift
//  Block Party — the launch as numbers at a moment (Jesse, 2026-11-18; BP app
//  references/splash-fork, whose mock.html#at-<ms> frames these times match). Two shows start from
//  one still, a black dot in the middle of the yellow:
//
//  The first open of the day (`Kind.first`) copies The Fork's splash, measured off Jesse's
//  recording frame by frame: the dot slides left, creeps back, then shoots right, the letters of
//  BlockParty. coming out behind it one at a time, and stops as the word's full stop. The word
//  holds, and the full stop opens as a circle into the app.
//
//  Every later open (`Kind.later`): the dot hops off the middle as B and p pop out from under it,
//  drops in as the !'s dot, the line grows out of it, and Bp! leaps into the tab bar (the leap of
//  2026-11-02, unchanged) while the yellow opens as a circle from its middle. With no tab bar
//  (Welcome is up) Bp! zooms through and the yellow fades.
//
//  Reduce Motion, every open: the word fades in, holds, and the yellow fades.
//
//  A tap does nothing. Values marked guessed have no Reference behind them; change one only with
//  Jesse.
//

import SwiftUI

nonisolated struct LaunchMotion {
    // MARK: The Reference

    /// The Fork's splash, one row a frame of Jesse's recording (BP app references/splash-fork/
    /// make_mock.py measures it): seconds, the mark's middle x, its height, and the ink's left
    /// edge, in the recording's pixels, 512 across the screen. Three frames are missing from the
    /// recording (0.250, 0.650, 1.017).
    private static let reference: [(t: Double, x: CGFloat, d: CGFloat, ink: CGFloat)] = [
        (0.000, 255.5, 108, 198), (0.083, 255.5, 108, 198), (0.100, 255.0, 108, 197), (0.117, 254.5, 108, 197),
        (0.133, 253.0, 108, 195), (0.150, 251.5, 108, 194), (0.167, 249.0, 108, 191), (0.183, 245.0, 108, 188),
        (0.200, 240.0, 107, 183), (0.217, 233.0, 107, 176), (0.233, 222.0, 106, 165), (0.267, 166.5, 105, 110),
        (0.283, 141.5, 103, 86), (0.300, 130.0, 103, 75), (0.317, 123.5, 101, 69), (0.333, 119.5, 100, 65),
        (0.350, 117.0, 99, 63), (0.367, 116.0, 97, 63), (0.383, 115.5, 97, 63), (0.400, 115.0, 95, 63),
        (0.417, 115.5, 94, 64), (0.433, 115.5, 93, 65), (0.450, 116.5, 91, 66), (0.467, 117.0, 90, 67),
        (0.483, 118.0, 88, 69), (0.500, 119.0, 87, 71), (0.517, 120.5, 85, 73), (0.533, 122.5, 85, 75),
        (0.550, 125.0, 83, 78), (0.567, 127.0, 83, 81), (0.583, 130.5, 81, 85), (0.600, 134.5, 81, 90),
        (0.617, 140.0, 79, 41), (0.633, 146.5, 78, 42), (0.667, 168.0, 78, 44), (0.683, 190.5, 78, 45),
        (0.700, 312.5, 77, 48), (0.717, 339.5, 77, 50), (0.733, 353.0, 77, 53), (0.750, 362.0, 76, 55),
        (0.767, 369.0, 76, 58), (0.783, 374.0, 76, 60), (0.800, 378.5, 76, 63), (0.817, 382.0, 76, 65),
        (0.833, 385.0, 75, 67), (0.850, 387.5, 74, 68), (0.867, 389.5, 74, 70), (0.883, 391.0, 74, 71),
        (0.900, 392.0, 73, 72), (0.917, 393.5, 72, 73), (0.933, 394.0, 72, 74), (0.950, 394.5, 72, 75),
        (0.967, 394.5, 72, 76), (0.983, 395.0, 72, 76), (1.000, 395.0, 72, 76), (1.033, 395.0, 72, 77),
        (1.067, 395.0, 72, 78), (1.200, 395.0, 72, 78),
    ]
    private static let refScreen: CGFloat = 512
    /// Their mark at rest in the middle, as it shoots, and at the end; where their word's left edge rests.
    private static let refMiddle: CGFloat = 255.5
    private static let refDot: CGFloat = 108
    private static let refShoot = (x: CGFloat(134.5), d: CGFloat(81))
    private static let refEnd: CGFloat = 395
    private static let refWord: CGFloat = 78

    /// The Reference at a moment, straight lines between its frames.
    private static func ref(_ t: Double) -> (x: CGFloat, d: CGFloat, ink: CGFloat) {
        guard let next = reference.firstIndex(where: { $0.t >= t }) else {
            let last = reference[reference.count - 1]
            return (last.x, last.d, last.ink)
        }
        guard next > 0 else { return (reference[0].x, reference[0].d, reference[0].ink) }
        let a = reference[next - 1], b = reference[next], v = CGFloat((t - a.t) / (b.t - a.t))
        return (lerp(a.x, b.x, v), lerp(a.d, b.d, v), lerp(a.ink, b.ink, v))
    }

    // MARK: Tuning

    /// The still's dot: their mark's size on an iPhone 16 Pro (Jesse: "Big dot").
    static let dotSize: CGFloat = 85
    /// Until the Reference's mark first moves, the launch screen's own picture shows.
    static let stillUntil = 0.083
    /// The first open's beats, the Reference's: the dot shoots, the first and the last letter
    /// start, the dot is the full stop. Then the word holds and the full stop opens.
    static let shoots = 0.600
    static let firstLetter = 0.617
    static let lastLetter = 0.750
    static let written = 1.000
    static let wordHold = 0.35
    /// The circle opens in 0.36 s, slow then fast (Jesse, 2026-11-18, BP app references/launch-circle).
    static let holeTime = 0.36
    /// BlockParty. ends 70% of the screen wide, as their finished word and mark are.
    static let wordShare: CGFloat = 0.70
    /// Guessed off their frames: a letter starts at 45% size leaning 12°, and is full size in 0.20 s.
    private static let letterFrom: CGFloat = 0.45
    private static let letterLean = 12.0
    static let letterGrow = 0.20
    /// The most the dot stretches along its speed, at 2200 pt/s: the old ball's values.
    private static let stretch: CGFloat = 0.18
    private static let stretchAt: CGFloat = 2200

    /// Later opens, all guessed but the leap: the dot hops 70 pt up off the middle under the old
    /// ball's gravity and squashes 32% for 0.05 s where it lands; B and p pop out on a soft spring;
    /// the !'s line grows in 0.12 s; Bp! rests 0.10 s, then leaps.
    static let toss = 0.10
    private static let tossRise: CGFloat = 70
    private static let gravity: CGFloat = 7600
    private static let squashDot: CGFloat = 0.32
    static let contact = 0.05
    private static let pop = Spring(response: 0.30, dampingRatio: 0.70)
    static let lineGrow = 0.12
    static let rest = 0.10

    /// Bp! leaps into the tab bar (Jesse, 2026-11-02: "faster and not just a straight animation
    /// with no emotion"): it crouches onto its foot, is tossed along a parabola (its middle point
    /// 190 pt above where it starts) down into the slot, leaning 12° and stretching as it flies,
    /// lands with a rubber squash, and the tab bar dips 2.2 pt with it.
    static let leapCrouch = 0.07
    private static let leapDip: CGFloat = 0.10
    /// The crouch lets go over the flight's first fifth: let go in one frame, Bp! snapped 14 pt
    /// taller (Jesse, 2026-11-07: "yes to all", BP app references/launch-glitch).
    private static let leapRelease: CGFloat = 0.2
    static let leapFlight = 0.26
    private static let leapRise: CGFloat = 190
    private static let leapTilt = -12.0
    private static let leapStretch: CGFloat = 0.08
    private static let leapLand = 0.30
    private static let wobble = Spring(response: 0.40, dampingRatio: 0.30)
    private static let bulge = 0.45
    /// The landing's squash plays out until it stays under 1% of Bp!'s height: done at its first
    /// pass through rest, it stopped dead with an 11% rebound still to come (Jesse, 2026-11-07).
    static let leapSettles = settleTime(leapLand, spring: wobble, under: 0.01)
    private static let tabCatch = Spring(response: 0.30, dampingRatio: 0.45)
    private static let tabCatchDip = 2.2
    /// The app behind and Town's rise settle on these once the yellow starts to go.
    private static let glide = Spring(response: 0.38, dampingRatio: 0.88)
    private static let glideFast = Spring(response: 0.26, dampingRatio: 0.95)
    /// With no tab bar, Bp! zooms through to 6x and the yellow fades.
    private static let zoomTo: CGFloat = 6
    static let yellowFade = 0.30
    /// Reduce Motion (guessed): the word fades in over 0.15 s, then holds `wordHold`.
    static let wordSwap = 0.15

    // MARK: The mark: the Daily mark's canvas, viewBox 137 302 751 422

    static let canvas = CGRect(x: 137, y: 302, width: 751, height: 422)
    /// Bp sits in the screen's middle and the ! reaches past it on the right (Jesse, 2026-11-02:
    /// "recenter that the BP is in the middle"): the middle of Bp with its letters at 90%, where
    /// the launch has rested it since, so Bp! moves by `centring` from the canvas's own middle.
    static let bpMiddle = CGPoint(x: 464.875, y: 524.5)
    static let centring = CGSize(width: (canvas.midX - bpMiddle.x) * scale, height: (canvas.midY - bpMiddle.y) * scale)
    /// Bp! is 320 pt wide (Jesse, 2026-11-08), which sets the points per canvas unit.
    static let markWidth: CGFloat = 320
    static let scale = markWidth / canvas.width
    /// The !'s dot, 100.5 canvas units across.
    private static let bangDot = CGPoint(x: 780.75, y: 583.25)
    static let bangSize = scale * 100.5

    // MARK: The wordmark, in its own pixels (BP app references/launch-squeeze/src)

    /// One picture a letter, each the whole wordmark's size, then the full stop.
    static let wordPieces = ["B", "L", "O", "C", "K", "P", "A", "R", "T", "Y"].map { "LaunchWord" + $0 }
    static let wordStop = "LaunchWordDot"
    static let wordSize = CGSize(width: 1051, height: 216)
    private static let wordLefts: [CGFloat] = [0, 139, 196, 304, 387, 511, 634, 746, 839, 900]
    private static let wordBase: CGFloat = 171
    private static let stopCentre = CGPoint(x: 1026.5, y: 149.5)
    private static let stopSize: CGFloat = 48

    // MARK: Inputs

    /// How a later open ends: on the tab bar's Daily Bp! (its frame in this space), or zooming
    /// through (Welcome is up, or a page covers the tab bar).
    enum Ending: Equatable {
        case tab(CGRect)
        case zoom
    }

    /// Which show plays (file header).
    enum Kind: String {
        case first, later
    }

    let screen: CGSize
    var ending: Ending = .zoom
    var kind: Kind = .first
    var reduceMotion = false

    // MARK: Worked out once per screen

    /// The screen's middle, where the still's dot sits.
    let middle: CGPoint
    /// BlockParty. on screen, and its full stop.
    let wordBox: CGRect
    let stop: Dot
    /// When each letter starts.
    let letterStarts: [Double]
    /// Bp!'s canvas's top left on screen, and the !'s dot.
    let origin: CGPoint
    let bang: Dot
    /// The hop's first speed up and its time in the air; when the dot lands, when it has become
    /// the !'s dot, and when Bp! leaps.
    private let tossSpeed: CGFloat, air: Double
    let landAt: Double, lineAt: Double, endAt: Double

    init(screen: CGSize, ending: Ending = .zoom, kind: Kind = .first, reduceMotion: Bool = false) {
        self.screen = screen
        self.ending = ending
        self.kind = kind
        self.reduceMotion = reduceMotion
        middle = CGPoint(x: screen.width / 2, y: screen.height / 2)

        let wide = screen.width * Self.wordShare, unit = wide / Self.wordSize.width
        let box = CGRect(x: (screen.width - wide) / 2, y: screen.height / 2 - Self.wordSize.height * unit / 2,
                         width: wide, height: Self.wordSize.height * unit)
        let stop = Dot(x: box.minX + Self.stopCentre.x * unit, y: box.minY + Self.stopCentre.y * unit, d: Self.stopSize * unit)
        wordBox = box
        self.stop = stop

        let s = Self.scale
        origin = CGPoint(x: (screen.width - Self.canvas.width * s) / 2 + Self.centring.width,
                         y: (screen.height - Self.canvas.height * s) / 2 + Self.centring.height)
        bang = Dot(x: origin.x + (Self.bangDot.x - Self.canvas.minX) * s, y: origin.y + (Self.bangDot.y - Self.canvas.minY) * s,
                   d: Self.bangSize)
        tossSpeed = (2 * Self.tossRise * Self.gravity).squareRoot()
        air = Double(tossSpeed / Self.gravity + (2 * (bang.y - (middle.y - Self.tossRise)) / Self.gravity).squareRoot())
        landAt = Self.toss + air
        lineAt = landAt + Self.contact
        endAt = lineAt + Self.lineGrow + Self.rest

        // Each letter starts on its turn, and never before the dot has passed its left edge.
        let travel = Self.travel(screen: screen, to: stop)
        letterStarts = Self.wordLefts.enumerated().map { i, left in
            var t = Self.firstLetter + (Self.lastLetter - Self.firstLetter) * Double(i) / Double(Self.wordLefts.count - 1)
            while t < Self.written, travel(t).x < box.minX + left * unit { t += 1.0 / 240 }
            return t
        }
    }

    // MARK: The dot

    /// The dot's middle, size, stretch along `heading` (degrees), in screen points.
    struct Dot: Equatable {
        var x: CGFloat, y: CGFloat, d: CGFloat
        var sx: CGFloat = 1, sy: CGFloat = 1, heading: CGFloat = 0
    }

    /// The first open's dot: their mark's path and size until it shoots; then their path stretched
    /// to end on our full stop, the dot shrinking and dropping to the line in step with it (ours:
    /// their mark stays large).
    private static func travel(screen: CGSize, to stop: Dot) -> (Double) -> Dot {
        let k = screen.width / refScreen, mid = CGPoint(x: screen.width / 2, y: screen.height / 2)
        let from = Dot(x: mid.x + (refShoot.x - refMiddle) * k, y: mid.y, d: dotSize * refShoot.d / refDot)
        return { t in
            let r = ref(t)
            if t < shoots { return Dot(x: mid.x + (r.x - refMiddle) * k, y: mid.y, d: dotSize * r.d / refDot) }
            let p = (r.x - refShoot.x) / (refEnd - refShoot.x)
            return Dot(x: lerp(from.x, stop.x, p), y: lerp(from.y, stop.y, p), d: lerp(from.d, stop.d, p))
        }
    }

    /// The first open's dot at a moment, stretched along its speed.
    func dot(at t: Double) -> Dot {
        let travel = Self.travel(screen: screen, to: stop)
        var dot = travel(t)
        let speed = (travel(t + 1.0 / 60).x - travel(t - 1.0 / 60).x) * 30
        let k = Self.stretch * min(1, abs(speed) / Self.stretchAt)
        dot.sx = 1 + k
        dot.sy = 1 / (1 + k)
        return dot
    }

    /// A later open's dot: one parabola from the middle into the !'s dot, shrinking on the way,
    /// stretched along its speed, squashed where it lands.
    func hop(at t: Double) -> Dot {
        let tau = CGFloat(min(t - Self.toss, air))
        guard tau > 0 else { return Dot(x: middle.x, y: middle.y, d: Self.dotSize) }
        let vx = (bang.x - middle.x) / CGFloat(air), vy = -tossSpeed + Self.gravity * tau
        let d = lerp(Self.dotSize, bang.d, smooth(tau / CGFloat(air)))
        let q = Self.squashDot * CGFloat(sin(.pi * clamp01((t - landAt) / Self.contact)))
        var dot = Dot(x: middle.x + vx * tau, y: middle.y - tossSpeed * tau + Self.gravity * tau * tau / 2 + q * d / 2, d: d)
        if t < landAt {
            let k = Self.stretch * min(1, hypot(vx, vy) / Self.stretchAt)
            dot.sx = 1 + k
            dot.sy = 1 / (1 + k)
            dot.heading = atan2(vy, vx) * 180 / .pi
        } else {
            dot.sx = 1 + q / 2
            dot.sy = 1 - q
        }
        return dot
    }

    // MARK: Springs and curves

    /// A spring kicked once from rest, scaled so its first peak is `amp`: Bp!'s rubber landing,
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

    /// The mock's ease-out, cubic-bezier(0.23, 1, 0.32, 1).
    static let easeOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1), endControlPoint: UnitPoint(x: 0.32, y: 1))

    private static func ease(_ x: Double) -> Double { x <= 0 ? 0 : x >= 1 ? 1 : easeOut.value(at: x) }
    private static func cubicOut(_ x: Double) -> Double { 1 - pow(1 - clamp01(x), 3) }

    // MARK: A moment

    /// A round hole in the yellow.
    struct Hole: Equatable {
        var centre: CGPoint
        var radius: CGFloat
    }

    /// One of the word's letters: whether it is out yet, and how it sits, about the top left of
    /// the word's box, in points.
    struct Letter: Equatable {
        var shown = false
        var transform = CGAffineTransform.identity
    }

    /// Everything the screen draws at one moment.
    struct Frame: Equatable {
        /// Nothing has moved yet: the launch screen's own picture of the dot shows.
        var still = false
        var dot: Dot
        var dotShown = true

        /// The first open: the letters in `wordPieces` order, how far left of its place the word
        /// sits, how strongly it shows (Reduce Motion fades it in), and whether the dot has become
        /// the wordmark's own full stop.
        var letters: [Letter] = []
        var wordShift: CGFloat = 0
        var wordOpacity = 1.0
        var stopShown = false

        /// A later open: Bp! is on screen; B and p's size about the screen's middle; the !'s line
        /// about its foot; and whether the dot has become the !'s own.
        var markShown = false
        var pop: CGFloat = 0
        var line = CGSize.zero
        var bangShown = false
        /// Where Bp!'s canvas's top left sits and its points per canvas unit, then a zoom about
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

        /// How much of the yellow is left, for the shade on it and whether a touch is the launch's.
        var yellow = 1.0
        /// How the yellow goes: a hole opening in it, or fading (a zoom, Reduce Motion).
        var yellowOpacity = 1.0
        var hole: Hole?
        /// The app behind: 98.5% growing to full size under Bp!'s leap, or 105% settling for a zoom.
        var backScale: CGFloat = 1
        /// Welcome's logo and headline may rise.
        var headerUp = false
        /// Once the yellow has started to go, the spring the app behind settles on.
        var ending: Spring?
        /// Buzzes so far: one, light, as the dot stops or lands.
        var buzzes = 0
        var done = false

        /// A touch belongs to the launch until its yellow is mostly gone, then goes through to the
        /// app (Jesse, 2026-11-02).
        var takesTaps: Bool { yellow > 0.25 }
    }

    /// The one buzz: light, as the dot stops as the full stop or lands as the !'s dot.
    static let buzz = SensoryFeedback.impact(weight: .light)

    func frame(at t: Double) -> Frame {
        reduceMotion ? fading(at: t) : kind == .first ? writing(at: t) : dropping(at: t)
    }

    /// The first open of the day.
    private func writing(at t: Double) -> Frame {
        var f = Frame(dot: dot(at: t), markOrigin: origin)
        f.still = t < Self.stillUntil
        let unit = wordBox.width / Self.wordSize.width
        if t >= Self.firstLetter { f.wordShift = (Self.ref(t).ink - Self.refWord) * screen.width / Self.refScreen }
        f.letters = letterStarts.enumerated().map { i, start in
            let e = CGFloat(Self.cubicOut((t - start) / Self.letterGrow))
            return Letter(shown: t >= start, transform: Self.grown(lerp(Self.letterFrom, 1, e), lean: Self.letterLean * Double(1 - e),
                                                                   about: CGPoint(x: Self.wordLefts[i] * unit, y: Self.wordBase * unit)))
        }
        f.stopShown = t >= Self.written
        f.dotShown = !f.stopShown
        f.buzzes = f.stopShown ? 1 : 0
        open(&f, from: stop, at: t - Self.written - Self.wordHold)
        f.done = f.yellow <= 0.001
        return f
    }

    /// A letter at `size`, leaning `lean` degrees to the right, about its foot.
    private static func grown(_ size: CGFloat, lean: Double, about foot: CGPoint) -> CGAffineTransform {
        let c = -CGFloat(tan(lean * .pi / 180)) * size
        return CGAffineTransform(a: size, b: 0, c: c, d: size, tx: foot.x - size * foot.x - c * foot.y, ty: foot.y - size * foot.y)
    }

    /// The yellow opens as a circle from `centre`, `since` seconds ago, reaching the far corner in
    /// `holeTime`, slow then fast.
    private func open(_ f: inout Frame, from centre: Dot, at since: Double) {
        guard since >= 0 else { return }
        let v = clamp01(since / Self.holeTime)
        let far = hypot(max(centre.x, screen.width - centre.x), max(centre.y, screen.height - centre.y))
        f.ending = Self.glide
        f.headerUp = true
        f.yellow = 1 - v * v
        f.hole = Hole(centre: CGPoint(x: centre.x, y: centre.y), radius: far * CGFloat(v * v))
        if f.yellow <= 0.001 { f.yellowOpacity = 0 }
    }

    /// Every later open.
    private func dropping(at t: Double) -> Frame {
        var f = Frame(dot: hop(at: t), markOrigin: origin)
        f.still = t < Self.toss
        f.markShown = true
        f.pop = t > Self.toss ? CGFloat(Self.pop.value(target: 1.0, time: t - Self.toss)) : 0
        f.bangShown = t >= lineAt
        f.dotShown = !f.bangShown
        // A plain ease-out: on a sharper one the line was nearly full height in two frames, a pop (2026-11-07).
        let grown = CGFloat(UnitCurve.easeOut.value(at: clamp01((t - lineAt) / Self.lineGrow)))
        f.line = f.bangShown ? CGSize(width: lerp(0.6, 1, grown), height: grown) : .zero
        f.buzzes = t >= landAt ? 1 : 0
        guard t >= endAt else {
            f.backScale = ending == .zoom ? 1.05 : 0.985
            return f
        }

        // The ending: Bp! leaps into the tab bar's Bp!, or zooms through.
        let e = t - endAt
        let settled: Bool
        switch ending {
        case .tab(let target):
            let crouch = Self.leapCrouch, flight = Self.leapFlight
            let s = Self.scale, to = target.width / Self.canvas.width
            let start = CGPoint(x: origin.x + Self.canvas.width * s / 2, y: origin.y + Self.canvas.height * s)
            let end = CGPoint(x: target.midX, y: target.maxY)
            let control = CGPoint(x: start.x + (end.x - start.x) * 0.15, y: start.y - Self.leapRise)
            var foot = start, markScale = s, progress = 0.0
            if e < crouch {
                let q = CGFloat(sin(e / crouch * .pi / 2))
                f.markSquash = CGSize(width: 1 + Self.leapDip / 2 * q, height: 1 - Self.leapDip * q)
                settled = false
            } else if e < crouch + flight {
                let u = CGFloat((e - crouch) / flight), w = 1 - u
                foot = CGPoint(x: w * w * start.x + 2 * w * u * control.x + u * u * end.x,
                               y: w * w * start.y + 2 * w * u * control.y + u * u * end.y)
                markScale = lerp(s, to, smooth(u))
                f.markTilt = Self.leapTilt * sin(.pi * Double(u))
                let stretch = Self.leapStretch * CGFloat(sin(.pi * Double(u)))
                let crouched = Self.leapDip * (1 - smooth(min(1, u / Self.leapRelease)))
                f.markSquash = CGSize(width: (1 + crouched / 2) / (1 + stretch), height: (1 - crouched) * (1 + stretch))
                progress = Double(u)
                settled = false
            } else {
                let tau = e - crouch - flight
                let d = CGFloat(Self.kick(tau, Self.leapLand))
                f.tabDip = CGFloat(Self.kick(tau, Self.tabCatchDip, spring: Self.tabCatch))
                foot = CGPoint(x: end.x, y: end.y + f.tabDip)
                markScale = to
                f.markSquash = CGSize(width: 1 + CGFloat(Self.bulge) * d, height: 1 - d)
                progress = 1
                // Done once the squash has died down; what's left of the tab bar's dip, under half a
                // point, eases out from there (`LaunchStage.finish`).
                settled = tau > max(0.2, Self.leapSettles)
            }
            f.markScale = markScale
            f.markOrigin = CGPoint(x: foot.x - Self.canvas.width * markScale / 2, y: foot.y - Self.canvas.height * markScale)
            f.backScale = 1 - 0.015 * (1 - CGFloat(Self.ease(progress)))
            // The yellow opens from its middle, behind Bp!, gone about as Bp! lands.
            open(&f, from: Dot(x: middle.x, y: middle.y, d: 0), at: e)
            f.headerUp = false
        case .zoom:
            let p = Self.glide.value(target: 1.0, time: e), v = Self.glide.velocity(target: 1.0, time: e)
            f.ending = Self.glide
            f.zoom = 1 + (Self.zoomTo - 1) * CGFloat(max(0, p))
            f.markOpacity = 1 - clamp01((p - 0.1) / 0.5)
            f.backScale = 1 + 0.05 * (1 - CGFloat(clamp01(p)))
            f.headerUp = p >= 0.5
            f.yellow = 1 - Self.ease(e / Self.yellowFade)
            f.yellowOpacity = f.yellow
            settled = abs(p - 1) < 0.003 && abs(v) < 0.01
        }
        f.done = settled && f.yellow <= 0.001
        return f
    }

    /// Reduce Motion: the still's dot gives way to the finished word, which holds; then the yellow
    /// fades, and nothing under it moves.
    private func fading(at t: Double) -> Frame {
        let v = CGFloat(clamp01(t / Self.wordSwap))
        var f = Frame(dot: Dot(x: lerp(middle.x, stop.x, v), y: lerp(middle.y, stop.y, v), d: lerp(Self.dotSize, stop.d, v)),
                      markOrigin: origin)
        f.still = t <= 0
        f.letters = letterStarts.map { _ in Letter(shown: true) }
        f.wordOpacity = Double(v)
        let fadeAt = Self.wordSwap + Self.wordHold
        guard t >= fadeAt else { return f }
        f.ending = Self.glideFast
        f.headerUp = true
        f.yellow = 1 - Self.ease((t - fadeAt) / Self.yellowFade)
        f.yellowOpacity = f.yellow
        f.done = f.yellow <= 0.001
        return f
    }
}

// MARK: - Helpers

nonisolated private func lerp(_ a: CGFloat, _ b: CGFloat, _ v: CGFloat) -> CGFloat { a + (b - a) * v }
nonisolated private func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
nonisolated private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
nonisolated private func smooth(_ v: CGFloat) -> CGFloat { v * v * (3 - 2 * v) }
