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
//  Every later open (`Kind.later`) is the short cut of 2026-11-08 (Jesse, 2026-11-18: "our
//  already made joetown falls down ball"; BP app references/launch-short): the still's dot pops
//  into Bp, the Town's ball falls straight into the !'s dot, squashes and goes black, B, p and the
//  ! jump as one without the hang, and Bp! leaps into the tab bar while the yellow opens as a
//  circle from its middle. With no tab bar (Welcome is up) Bp! zooms through and the yellow fades.
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

    /// Later opens. Guessed: the still's dot goes in 0.15 s as Bp pops out from under it on a soft
    /// spring. The rest is the short cut's, at full speed: the ball falls at the old ball's gravity
    /// and starting speed from above the screen, touches the dot 0.05 s squashing 32%, and its
    /// colours go black in 0.12 s; then Bp! jumps.
    static let stillGoes = 0.10
    private static let burst = 0.15
    private static let pop = Spring(response: 0.30, dampingRatio: 0.70)
    private static let gravity: CGFloat = 7600
    private static let dropSpeed: CGFloat = 650
    private static let dropFrom: CGFloat = -40
    static let contact = 0.05
    private static let squashDot: CGFloat = 0.32
    private static let blacken = 0.12
    /// B and p are 10% small, shrunk toward the !'s dot on the line, until they grow to full size
    /// on the jump's way up (Jesse, 2026-11-01 and 2026-11-08).
    static let startSize: CGFloat = 0.9
    static let letterAnchor = CGPoint(x: 781, y: 627)
    /// The jump without the hang at the top (Jesse, 2026-11-08): B, p and the ! crouch while the
    /// !'s line grows out of the dot, jump the Daily tab's 4 pt (scaled up), and land on one beat,
    /// 0.35 s in, with one firm buzz. The leap starts 0.49 s in, once the landing has rebounded.
    static let jumpLands = 0.35
    static let jumpEnds = 0.49
    private typealias Key = (to: CGFloat, seconds: Double, curve: UnitCurve)
    private static let lift = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.3, y: 1))
    private static let fall = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.5, y: 0), endControlPoint: UnitPoint(x: 0.8, y: 0.4))
    private static let jumpY: [Key] = [(0, 0.07, .linear), (-4, 0.16, lift), (0, 0.12, fall), (0, 0.22, .linear)]
    private static let jumpWidth: [Key] = [(1.10, 0.07, .linear), (0.95, 0.16, lift), (0.97, 0.12, fall),
                                           (1.14, 0.06, .linear), (0.97, 0.08, lift), (1, 0.08, .linear)]
    private static let jumpHeight: [Key] = [(0.86, 0.07, .linear), (1.08, 0.16, lift), (1.05, 0.12, fall),
                                            (0.84, 0.06, .linear), (1.04, 0.08, lift), (1, 0.08, .linear)]
    /// The !'s line alone on the way up: 6% short and a little wide where everything else stretches
    /// (Jesse, 2026-11-05: "when the ! bounces up very slightly compress the top line", then "6 percent").
    private static let jumpLineWidth: [Key] = [(1.10, 0.07, .linear), (1.027, 0.16, lift)] + jumpWidth.dropFirst(2)
    private static let jumpLineHeight: [Key] = [(0.86, 0.07, .linear), (0.94, 0.16, lift)] + jumpHeight.dropFirst(2)

    /// Keyframes as SwiftUI's `LinearKeyframe` plays them: each eases from the last.
    private static func track(_ keys: [Key], from start: CGFloat, at time: Double) -> CGFloat {
        var from = start, t = time
        for key in keys {
            if t < key.seconds { return lerp(from, key.to, CGFloat(key.curve.value(at: t / key.seconds))) }
            t -= key.seconds
            from = key.to
        }
        return from
    }

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
    /// The !'s dot, 101 canvas units across, and the Town's ball, 15% larger than it.
    private static let bangDot = CGPoint(x: 781, y: 582.75)
    static let bangSize = scale * 101
    static let ball = bangSize * 1.15

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
    /// Where the ball starts, above the screen, and how long it falls; when it lands, when it has
    /// gone black and become the !'s dot (the jump starts), and when Bp! leaps.
    private let dropStart: CGPoint, dropTime: Double
    let landAt: Double, popAt: Double, endAt: Double

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
        let from = CGPoint(x: bang.x, y: Self.dropFrom + Self.centring.height), g = Self.gravity, v0 = Self.dropSpeed
        dropStart = from
        dropTime = Double((-v0 + (v0 * v0 + 2 * g * (bang.y - from.y)).squareRoot()) / g)
        landAt = Self.stillGoes + dropTime
        popAt = landAt + Self.blacken
        endAt = popAt + Self.jumpEnds

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

    // MARK: The ball

    struct Ball: Equatable {
        /// Centre, radius, roll in degrees, stretch along the velocity's angle `heading`.
        var x: CGFloat, y: CGFloat, r: CGFloat, roll: CGFloat
        var sx: CGFloat = 1, sy: CGFloat = 1, heading: CGFloat = 0
    }

    /// A later open's ball: straight down into the !'s dot from above it, spinning, shrinking to
    /// the dot's size and stretched along its speed on the way, squashed where it lands.
    func ball(at t: Double) -> Ball {
        let r0 = Self.ball / 2, rf = bang.d / 2, tt = t - Self.stillGoes
        if tt >= dropTime + Self.contact { return Ball(x: bang.x, y: bang.y, r: rf, roll: 360) }
        if tt < dropTime {
            let s = CGFloat(max(0, tt)), v = s / CGFloat(dropTime)
            let vy = Self.dropSpeed + Self.gravity * s
            let k = Self.stretch * min(1, vy / Self.stretchAt)
            return Ball(x: dropStart.x, y: dropStart.y + Self.dropSpeed * s + Self.gravity * s * s / 2, r: lerp(r0, rf, smooth(v)),
                        roll: lerp(-120, 360, v), sx: 1 + k, sy: 1 / (1 + k), heading: 90)
        }
        let q = sin(.pi * clamp01(CGFloat((tt - dropTime) / Self.contact)))
        let sy = 1 - Self.squashDot * q
        return Ball(x: bang.x, y: bang.y + rf * (1 - sy), r: rf, roll: 360, sx: 1 + Self.squashDot * 1.15 * q, sy: sy)
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

        /// A later open: Bp! is on screen, popped out about the screen's middle (`pop`); the ball,
        /// how far its colours have gone black, and whether it still shows (it goes once it has
        /// become the !'s own dot).
        var markShown = false
        var pop: CGFloat = 0
        var ball = Ball(x: 0, y: 0, r: 0, roll: 0)
        var ballBlack = 0.0
        var ballShown = false
        /// The ball's shadow on the glass: how far below the ball, how soft, how dark.
        var shadeDrop: CGFloat = 0
        var shadeBlur: CGFloat = 0
        var shadeOpacity = 0.0
        /// B and p's size about `letterAnchor`; the jump: how far up everything is, in the tab
        /// bar's points, and the !'s line and dot's squash and stretch about their feet.
        var letter = CGSize(width: LaunchMotion.startSize, height: LaunchMotion.startSize)
        var lift: CGFloat = 0
        var line = CGSize(width: 1, height: 1)
        var lineOpacity = 0.0
        var bang = CGSize(width: 1, height: 1)
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
        /// Buzzes so far, in `buzzKinds` order.
        var buzzes = 0
        var done = false

        /// A touch belongs to the launch until its yellow is mostly gone, then goes through to the
        /// app (Jesse, 2026-11-02).
        var takesTaps: Bool { yellow > 0.25 }
    }

    /// The buzzes in order. The first open: one, light, as the dot stops as the full stop. A later
    /// open, the short cut's three: firm as the ball lands, firm as Bp! lands from its jump, light
    /// as it lands in the tab bar. Reduce Motion has none.
    static func buzzKinds(_ kind: Kind) -> [SensoryFeedback] {
        switch kind {
        case .first: [.impact(weight: .light)]
        case .later: [.impact(weight: .medium), .impact(weight: .medium), .impact(weight: .light)]
        }
    }

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
        // The still gives way: its dot shrinks to nothing as Bp pops out from under it.
        let since = t - Self.stillGoes
        var f = Frame(dot: Dot(x: middle.x, y: middle.y, d: Self.dotSize * CGFloat(1 - Self.cubicOut(since / Self.burst))),
                      markOrigin: origin)
        f.still = since < 0
        f.dotShown = since < Self.burst
        f.markShown = true
        f.pop = since > 0 ? CGFloat(Self.pop.value(target: 1.0, time: since)) : 0

        // The ball falls into the !'s dot and goes black.
        let swapped = t >= popAt
        f.ball = ball(at: t)
        f.ballBlack = clamp01(Self.ease((t - landAt) / Self.blacken))
        f.ballShown = since >= 0 && !swapped
        f.bangShown = swapped
        // Its shadow on the glass: farther off, softer and fainter while the ball is high above the
        // dot, closing in under it as it lands.
        if f.ballShown {
            let height = max(0, bang.y - f.ball.y)
            f.shadeDrop = 3 + 0.10 * height
            f.shadeBlur = 1.5 + 0.05 * height
            f.shadeOpacity = max(0.06, 0.30 - 0.0012 * Double(height)) * (1 - f.ballBlack)
        }

        // The jump: B and p grow to full size on the way up, and the !'s line grows out of the dot
        // during the crouch, fading in over its first 40 ms, on a plain ease-out (on a sharper one
        // it was nearly full height in two frames, a pop; 2026-11-07).
        let h = t - popAt
        func jump(_ keys: [Key], _ rest: CGFloat) -> CGFloat { h < 0 ? rest : Self.track(keys, from: rest, at: h) }
        let wide = jump(Self.jumpWidth, 1), tall = jump(Self.jumpHeight, 1)
        let up = h < 0.07 ? 0 : CGFloat(Self.lift.value(at: min(1, (h - 0.07) / 0.16)))
        let k = 1 - (1 - Self.startSize) * (1 - up)
        f.letter = CGSize(width: k * wide, height: k * tall)
        f.lift = jump(Self.jumpY, 0)
        f.bang = CGSize(width: wide, height: tall)
        let grown = h < DailyMarkGlyph.crouch ? 0.86 * CGFloat(UnitCurve.easeOut.value(at: max(0, h) / DailyMarkGlyph.crouch))
            : jump(Self.jumpLineHeight, 1)
        f.line = CGSize(width: jump(Self.jumpLineWidth, 1), height: grown)
        f.lineOpacity = clamp01(h / 0.04)
        f.buzzes = [landAt, popAt + Self.jumpLands].filter { $0 <= t }.count
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
                f.buzzes = 3
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
