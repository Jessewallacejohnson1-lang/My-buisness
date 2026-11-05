//
//  LaunchMotion.swift
//  Block Party — the launch as numbers at a moment: where the Town's ball is, how B and p dip
//  and grow, when the ! hops and where Bp! goes at the end. The approved mock's math, ported
//  line for line (Jesse approved round 5 on 2026-11-01; BP app references/launch-ball/
//  mock.template.html holds the original). Every tuning value was GUESSED in the mock and
//  approved as played; change one only with Jesse.
//
//  Times here are the mock's simulation time. The screen plays them at `pace`, so each
//  motion takes 1.33x its value (Jesse: "can you do .75 speed"; slower still was tried and
//  dropped on 2026-11-02: "nvm do 1 speed").
//

import SwiftUI

nonisolated struct LaunchMotion {
    // MARK: Tuning (the mock's `T`)

    static let pace = 0.75
    /// Gravity and the drop's starting speed, in points per second (per second).
    private static let gravity: CGFloat = 7600
    private static let dropSpeed: CGFloat = 650
    /// Where the ball starts: above the screen, on the left.
    private static let start = CGPoint(x: 40, y: -40)
    /// How high the two arcs rise above where they leave, each lower than the last.
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
    /// B and p start 10% small (Jesse, round 4). The ball's hits only dip them; they grow to full
    /// size in the jump (Jesse, 2026-11-02: "what if the letters sync into place when the ! does").
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
    /// Bp! leaps into the tab bar (Jesse, 2026-11-02: "faster and not just a straight animation
    /// with no emotion"): it crouches onto its foot, is tossed along a parabola (its middle point
    /// 190 pt above where it starts) down into the slot, leaning 12° and stretching as it flies,
    /// lands with B and p's rubber squash, and the tab bar dips 2.2 pt with it. After a tap it
    /// flies faster and just lands.
    private static let leapCrouch = 0.07
    private static let leapDip: CGFloat = 0.10
    private static let leapFlight = 0.26
    private static let leapFlightFast = 0.16
    private static let leapRise: CGFloat = 190
    private static let leapTilt = -12.0
    private static let leapStretch: CGFloat = 0.08
    private static let leapLand = 0.30
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
    /// Reduce Motion's beats: the crest fades in, turns black, the ! line fades in, then the
    /// whole launch fades into the app.
    private static let reduceOut = 0.80

    // MARK: The mark: the Daily mark's canvas, viewBox 137 302 751 422

    static let canvas = CGRect(x: 137, y: 302, width: 751, height: 422)
    /// The middle of the still's Bp (B and p at 90%) on the canvas, measured off `LaunchStill`.
    /// It sits in the screen's middle and the ! reaches past it on the right (Jesse, 2026-11-02:
    /// "recenter that the BP is in the middle"), so the whole launch, the ball's start included,
    /// moves by `centring` from the canvas's own middle.
    static let bpMiddle = CGPoint(x: 429.75, y: 524.5)
    static let centring = CGSize(width: (canvas.midX - bpMiddle.x) * scale, height: (canvas.midY - bpMiddle.y) * scale)
    /// Round 1's 17.2 pt ball, 125% larger (Jesse: "joetown logo needs to be 125% larger"),
    /// and the dot 15% smaller than it. The dot is 101 canvas units across, which sets the
    /// points per unit and so Bp!'s 249.6 pt width.
    static let ball: CGFloat = 49 * 320 / 1051 * 1.15 * 2.25
    static let dot = ball / 1.15
    static let scale = dot / 101
    /// Where B and p grow from: the middle of their feet on the baseline.
    static let footB = CGPoint(x: 294, y: 627)
    static let footP = CGPoint(x: 581.5, y: 627)
    /// The tops of B and p, and where along each the ball lands.
    private static let topB: CGFloat = 303.5
    private static let topP: CGFloat = 383.5
    private static let landB: CGFloat = 275
    private static let landP: CGFloat = 580
    /// The !'s dot.
    private static let dotCentre = CGPoint(x: 781, y: 582.75)

    // MARK: Inputs

    /// How the launch ends: on the tab bar's Daily Bp! (its frame in this space), or zooming
    /// through (a first open, which has no tab bar).
    enum Ending: Equatable {
        case tab(CGRect)
        case zoom
    }

    let screen: CGSize
    /// When a tap skipped, in simulation time; ignored at moments before it.
    var skip: Double?
    var reduceMotion = false
    var ending: Ending = .zoom

    // MARK: The path, worked out once per screen

    /// The canvas's top left on screen: Bp! sits in the middle.
    let origin: CGPoint
    private let base: CGFloat, capB: CGFloat, capP: CGFloat
    private let onB: CGPoint, onP: CGPoint, onDot: CGPoint
    private let drop: Flight, toP: Flight, toDot: Flight
    let hitB: Double, hitP: Double, landAt: Double, ballEnd: Double

    init(screen: CGSize, skip: Double? = nil, reduceMotion: Bool = false, ending: Ending = .zoom) {
        self.screen = screen
        self.skip = skip
        self.reduceMotion = reduceMotion
        self.ending = ending
        let s = Self.scale
        origin = CGPoint(x: (screen.width - Self.canvas.width * s) / 2 + Self.centring.width,
                         y: (screen.height - Self.canvas.height * s) / 2 + Self.centring.height)
        let u = { [origin] (x: CGFloat, y: CGFloat) in
            CGPoint(x: origin.x + (x - Self.canvas.minX) * s, y: origin.y + (y - Self.canvas.minY) * s)
        }
        base = u(0, Self.footB.y).y
        capB = (Self.footB.y - Self.topB) * s
        capP = (Self.footP.y - Self.topP) * s
        let r0 = Self.ball / 2
        // The ball lands on each letter's top at its starting size.
        let k = Self.startSize
        onB = CGPoint(x: u(Self.footB.x + k * (Self.landB - Self.footB.x), 0).x, y: base - k * capB - r0)
        onP = CGPoint(x: u(Self.footP.x + k * (Self.landP - Self.footP.x), 0).x, y: base - k * capP - r0)
        onDot = u(Self.dotCentre.x, Self.dotCentre.y)

        let g = Self.gravity, v0 = Self.dropSpeed
        let start = CGPoint(x: Self.start.x + Self.centring.width, y: Self.start.y + Self.centring.height)
        let dropTime = (-v0 + (v0 * v0 + 2 * g * (onB.y - start.y)).squareRoot()) / g
        drop = Flight(from: start, time: Double(dropTime), vy: v0,
                      vx: (onB.x - start.x) / dropTime, spin: (-120, 0), shrinks: false)
        toP = Flight.arc(from: onB, to: onP, height: Self.arcB, spin: (0, 360))
        toDot = Flight.arc(from: onP, to: onDot, height: Self.arcP, spin: (360, 720), shrinks: true)
        hitB = drop.time
        hitP = hitB + Self.contact + toP.time
        landAt = hitP + Self.contact + toDot.time
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
        if t >= ballEnd { return Ball(x: onDot.x, y: onDot.y, r: rf, roll: 720) }
        if t < hitB { return fly(drop, t, r0) }
        if t < hitB + Self.contact { return hit(t - hitB, at: onB, r: r0, roll: 0, squash: Self.squash, letter: (hitB, capB, Self.dipB)) }
        if t < hitP { return fly(toP, t - hitB - Self.contact, r0) }
        if t < hitP + Self.contact { return hit(t - hitP, at: onP, r: r0, roll: 360, squash: Self.squash, letter: (hitP, capP, Self.dipP)) }
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

    /// Squashed on a letter or the dot; on a letter it rides the letter's top as it dips and grows.
    private func hit(_ tt: Double, at p: CGPoint, r: CGFloat, roll: CGFloat, squash: CGFloat,
                     letter: (at: Double, cap: CGFloat, dip: Double)?) -> Ball {
        let q = sin(.pi * clamp01(CGFloat(tt / Self.contact)))
        let sy = 1 - squash * q, sx = 1 + squash * 1.15 * q
        var y = p.y + r * (1 - sy)
        if let letter {
            let t = letter.at + tt
            y = base - Self.startSize * (1 - CGFloat(Self.kick(t - letter.at, letter.dip))) * letter.cap - r * sy
        }
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
        /// How far the ball's colours have gone black, and how strongly it shows: Reduce Motion
        /// fades it in, and it goes once it has become the real dot.
        var ballBlack: Double = 0
        var ballOpacity = 1.0
        /// B and p's scale about their feet, and how strongly they show.
        var b = CGSize(width: Self.small, height: Self.small)
        var p = CGSize(width: Self.small, height: Self.small)
        var letters = 1.0
        /// Reduce Motion only: B and p at full size, fading in over the 90% ones as the ! appears.
        var fullLetters = 0.0
        var dotShown = false
        var lineOpacity = 0.0
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
        var yellow = 1.0
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
    }

    static let buzzKinds: [SensoryFeedback] = [.impact(weight: .light), .impact(weight: .light),
                                               .impact(weight: .medium), .impact(weight: .medium),
                                               .impact(weight: .light)]

    func frame(at t: Double) -> Frame {
        reduceMotion ? reduced(at: t) : moving(at: t)
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

        // B and p dip and bulge on their hit and stay at 90%, then grow to full size on the jump's
        // way up. A tap grows them as the ! appears, and a letter the ball never reached doesn't dip.
        var k = Self.startSize
        if early != nil {
            k = size(t, hit: swapAt)
        } else if h >= 0 {
            let up = h < 0.07 ? 0 : CGFloat(Self.lift.value(at: min(1, (h - 0.07) / 0.16)))
            k = 1 - (1 - Self.startSize) * (1 - up) * CGFloat(settle)
        }
        func letter(hit: Double, dip: Double) -> CGSize {
            let reached = early.map { hit <= $0 } ?? true
            let d = reached ? CGFloat(Self.kick(t - hit, dip)) : 0
            return CGSize(width: k * jumpWidth * (1 + CGFloat(Self.bulge) * d), height: k * jumpHeight * (1 - d))
        }
        f.b = letter(hit: hitB, dip: Self.dipB)
        f.p = letter(hit: hitP, dip: Self.dipP)

        // The ! : after a tap it simply appears; otherwise it jumps with B and p, its line growing
        // out of the dot during the crouch and fading in over its first 40 ms.
        f.lift = jump(Self.jumpY, 0)
        f.dot = CGSize(width: jumpWidth, height: jumpHeight)
        if let popAt {
            let height = h < DailyMarkGlyph.crouch ? 0.86 * CGFloat(Self.easeOut.value(at: h / DailyMarkGlyph.crouch)) : jump(Self.jumpLineHeight, 1)
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
        f.ending = Self.paced(skip == nil ? Self.glide : Self.glideFast)
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
                f.markSquash = CGSize(width: 1 / (1 + stretch), height: 1 + stretch)
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
                settled = tau > 0.2 && abs(d) < 0.01
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
        f.yellow = 1 - Self.ease((t - endAt) / (skip == nil ? Self.yellowFade : Self.yellowFadeFast))
        f.done = settled && f.yellow <= 0.001
        return f
    }

    /// The buzzes this far, none after a tap.
    private func buzzes(at t: Double, skip: Double?, beats: [Double]) -> Int {
        beats.prefix { beat in beat <= t && (skip.map { beat <= $0 } ?? true) }.count
    }

    /// A spring in the screen's time, which plays every motion at `pace`.
    private static func paced(_ s: Spring) -> Spring {
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

    /// Reduce Motion: nothing moves. B and p start at the still's 90%, so nothing jumps from it,
    /// and fade over to full size as the ! line fades in, so it ends on the true Bp! (Jesse,
    /// 2026-11-02): the full ones fade in on top, then the 90% ones go, so where they overlap
    /// never thins. The crest fades in at the dot and goes black, and the whole launch fades into
    /// the app. A tap jumps to the fade.
    private func reduced(at real: Double) -> Frame {
        var t = real
        if let skip, skip <= real, skip < Self.reduceOut { t = Self.reduceOut + (real - skip) }
        let out = clamp01((t - Self.reduceOut) / 0.25)
        var f = Frame(ball: Ball(x: onDot.x, y: onDot.y, r: Self.dot / 2, roll: 0), markOrigin: origin)
        f.b = CGSize(width: Self.startSize, height: Self.startSize)
        f.p = f.b
        f.ballOpacity = t < 0.5 ? clamp01(t / 0.15) : 0
        f.ballBlack = clamp01((t - 0.30) / 0.20)
        f.dotShown = t >= 0.5
        f.lineOpacity = clamp01((t - 0.50) / 0.15)
        f.fullLetters = f.lineOpacity
        f.letters = 1 - clamp01((t - 0.65) / 0.15)
        f.yellow = 1 - out
        f.markOpacity = 1 - out
        f.headerUp = true
        f.done = out >= 1
        return f
    }
}

// MARK: - Helpers

nonisolated private func lerp(_ a: CGFloat, _ b: CGFloat, _ v: CGFloat) -> CGFloat { a + (b - a) * v }
nonisolated private func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
nonisolated private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
nonisolated private func smooth(_ v: CGFloat) -> CGFloat { v * v * (3 - 2 * v) }
