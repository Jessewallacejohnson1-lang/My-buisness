//
//  LaunchMotion.swift
//  Block Party — the launch as numbers at a moment: where the Town's ball is, how B and p dip
//  and grow, when the ! hops and where Bp! goes at the end. The approved mock's math, ported
//  line for line (Jesse approved round 5 on 2026-11-01; BP app references/launch-ball/
//  mock.template.html holds the original). Every tuning value was GUESSED in the mock and
//  approved as played; change one only with Jesse.
//
//  Times here are the mock's simulation time. The screen plays them at `pace`, so each
//  motion takes 1.33x its value (Jesse: "can you do .75 speed").
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
    /// B and p start 10% small and spring to full size on their hit (Jesse, round 4).
    static let startSize: CGFloat = 0.9
    private static let grow = Spring(response: 0.40, dampingRatio: 0.45)
    /// The landed ball's colours go black, then the ! hops; the ending starts 0.40 in, when
    /// the hop's line is back on the dot.
    private static let blacken = 0.12
    private static let endDelay = 0.40
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
        origin = CGPoint(x: (screen.width - Self.canvas.width * s) / 2, y: (screen.height - Self.canvas.height * s) / 2)
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
        let dropTime = (-v0 + (v0 * v0 + 2 * g * (onB.y - Self.start.y)).squareRoot()) / g
        drop = Flight(from: Self.start, time: Double(dropTime), vy: v0,
                      vx: (onB.x - Self.start.x) / dropTime, spin: (-120, 0), shrinks: false)
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
            y = base - size(t, hit: letter.at) * (1 - CGFloat(Self.kick(t - letter.at, letter.dip))) * letter.cap - r * sy
        }
        return Ball(x: p.x, y: y, r: r, roll: roll, sx: sx, sy: sy)
    }

    // MARK: Springs and curves

    /// A spring kicked once from rest, scaled so its first peak is `amp`: a letter's rubber dip.
    static func kick(_ tau: Double, _ amp: Double) -> Double {
        guard tau > 0 else { return 0 }
        let w = 2 * .pi / wobble.response, z = wobble.dampingRatio, wd = w * (1 - z * z).squareRoot()
        let peak = atan(wd / (z * w)) / wd
        return amp * wobble.value(target: 0.0, initialVelocity: 1.0, time: tau)
            / wobble.value(target: 0.0, initialVelocity: 1.0, time: peak)
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
        /// B and p's scale about their feet.
        var b = CGSize(width: Self.small, height: Self.small)
        var p = CGSize(width: Self.small, height: Self.small)
        var dotShown = false
        var lineOpacity = 0.0
        /// Time into the Daily tab's ! hop (`DailyMarkGlyph`); nil holds the ! at rest.
        var hop: Double?
        /// Where the canvas's top left sits and its points per canvas unit, then a zoom about
        /// Bp!'s middle and its opacity.
        var markOrigin: CGPoint
        var markScale: CGFloat = LaunchMotion.scale
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
        /// Buzzes so far: light on B, light on p, firm on the dot, light as the ! hops.
        var buzzes = 0
        var done = false

        private static let small = LaunchMotion.startSize
    }

    static let buzzKinds: [SensoryFeedback] = [.impact(weight: .light), .impact(weight: .light),
                                               .impact(weight: .medium), .impact(weight: .light)]

    func frame(at t: Double) -> Frame {
        reduceMotion ? reduced(at: t) : moving(at: t)
    }

    private func moving(at t: Double) -> Frame {
        let rf = Self.dot / 2
        let skip = self.skip.flatMap { $0 <= t ? $0 : nil }
        let swapNormally = landAt + Self.blacken
        let endNormally = swapNormally + Self.endDelay
        // A tap before the ball has turned into the dot sends it there and drops the hop.
        let early = skip.flatMap { $0 < swapNormally ? $0 : nil }
        let swapAt = early.map { $0 + Self.skipMove } ?? swapNormally
        let popAt: Double? = early == nil ? swapNormally : nil
        var endAt = early.map { $0 + Self.skipMove + Self.skipToEnd } ?? endNormally
        if let skip, early == nil, skip < endNormally { endAt = min(endAt, skip + 0.05) }

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

        // B and p dip and bulge on their hit and grow from 90%. A tap grows a letter the ball
        // never reached, without the dip (the mock dipped it at its old hit time: a letter
        // bouncing with no ball on it).
        func letter(hit: Double, dip: Double) -> CGSize {
            let reached = early.map { hit <= $0 } ?? true
            let d = reached ? CGFloat(Self.kick(t - hit, dip)) : 0
            let k = size(t, hit: early.map { min(hit, $0) } ?? hit)
            return CGSize(width: k * (1 + CGFloat(Self.bulge) * d), height: k * (1 - d))
        }
        f.b = letter(hit: hitB, dip: Self.dipB)
        f.p = letter(hit: hitP, dip: Self.dipP)

        // The ! : after a tap it simply appears; otherwise the Daily tab's hop, its line
        // fading in over 40 ms as it grows out of the dot.
        if let popAt {
            if t >= popAt { f.hop = t - popAt }
            f.lineOpacity = clamp01((t - popAt) / 0.04)
        } else {
            f.lineOpacity = swapped ? 1 : 0
        }

        // The buzzes this far, none after a tap.
        let beats = [hitB, hitP, landAt, popAt ?? .infinity]
        f.buzzes = beats.prefix { beat in beat <= t && (skip.map { beat <= $0 } ?? true) }.count

        // The ending: a spring from Bp! to the tab bar's Bp!, or a zoom through.
        guard t >= endAt else {
            f.backScale = ending == .zoom ? 1.05 : 0.985
            return f
        }
        let (p, v) = endSpring(at: t, endAt: endAt, skip: skip)
        f.ending = Self.paced(skip == nil ? Self.glide : Self.glideFast)
        switch ending {
        case .tab(let target):
            let to = target.width / Self.canvas.width
            f.markOrigin = CGPoint(x: lerp(origin.x, target.minX, CGFloat(p)), y: lerp(origin.y, target.minY, CGFloat(p)))
            f.markScale = lerp(Self.scale, to, CGFloat(p))
            f.backScale = 1 - 0.015 * (1 - CGFloat(clamp01(p)))
        case .zoom:
            f.zoom = 1 + (Self.zoomTo - 1) * CGFloat(max(0, p))
            f.markOpacity = 1 - clamp01((p - 0.1) / 0.5)
            f.backScale = 1 + 0.05 * (1 - CGFloat(clamp01(p)))
            f.headerUp = p >= 0.5
        }
        f.yellow = 1 - Self.ease((t - endAt) / (skip == nil ? Self.yellowFade : Self.yellowFadeFast))
        f.done = abs(p - 1) < 0.003 && abs(v) < 0.01 && f.yellow <= 0.001
        return f
    }

    /// A spring in the screen's time, which plays every motion at `pace`.
    private static func paced(_ s: Spring) -> Spring {
        Spring(response: s.response / pace, dampingRatio: s.dampingRatio)
    }

    /// The ending's progress and speed. A tap mid-way hands it to the fast spring, speed and all.
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

    /// Reduce Motion: nothing moves. B and p are full size, the crest fades in at the dot and
    /// goes black, the ! line fades in, and the whole launch fades into the app. A tap jumps to
    /// the fade.
    private func reduced(at real: Double) -> Frame {
        var t = real
        if let skip, skip <= real, skip < Self.reduceOut { t = Self.reduceOut + (real - skip) }
        let out = clamp01((t - Self.reduceOut) / 0.25)
        var f = Frame(ball: Ball(x: onDot.x, y: onDot.y, r: Self.dot / 2, roll: 0), markOrigin: origin)
        f.b = CGSize(width: 1, height: 1)
        f.p = f.b
        f.ballOpacity = t < 0.5 ? clamp01(t / 0.15) : 0
        f.ballBlack = clamp01((t - 0.30) / 0.20)
        f.dotShown = t >= 0.5
        f.lineOpacity = clamp01((t - 0.50) / 0.15)
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
