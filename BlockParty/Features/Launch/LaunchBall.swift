//
//  LaunchBall.swift
//  Block Party — the launch (Jesse, 2026-11-01; BP app references/launch-ball, taste.md's
//  launch lines). On a fresh start the Town's round logo drops onto Bp, bounces off B and p,
//  lands as the !'s dot, the ! hops as the Daily tab's does, and Bp! lands on the tab bar's own
//  Bp!, or zooms through when Welcome is up. It plays over the app, which loads underneath and
//  never waits on it. A tap skips it.
//
//  `LaunchMotion` holds the numbers; this file draws them, one frame at a time, from a
//  `TimelineView`, so a tap can redirect it at any instant. No `phaseAnimator`: the splash
//  deleted on 2026-09-18 used one and left the app black on every cold start
//  (docs/rules/swift-traps.md).
//

import SwiftUI

/// What the launch shares with the screens under it.
@Observable final class LaunchStage {
    static let shared = LaunchStage()
    /// The app's own coordinate space, inside the launch's scale of it.
    static let space = "launch"

    /// Whether this process start plays the launch: always, except under UI tests that don't ask
    /// for it (`-launch-play`), or every test would wait it out.
    let plays: Bool
    let reduceMotion: Bool
    /// DEBUG: a moment to hold (`-launch-at <ms>`) and a tap (`-launch-skip <ms>`), in the
    /// mock's simulation time, so frames line up with the mock's `#at-<ms>` ones.
    let frozenAt: Double?
    let skipAt: Double?
    /// The launch is over and gone.
    private(set) var finished: Bool
    /// The tab bar's own Daily Bp! shows: the launch's has landed on it, so two never show.
    private(set) var landed: Bool
    /// Welcome's logo and headline may rise: the zoom through is half done.
    private(set) var headerUp: Bool
    /// The tab bar's Daily Bp! in `space`, while it is on screen and the launch heads for it.
    var dailyMark: CGRect?

    private init() {
        frozenAt = LaunchFlags.value(.launchAt).flatMap(Double.init).map { $0 / 1000 }
        skipAt = LaunchFlags.value(.launchSkip).flatMap(Double.init).map { $0 / 1000 }
        plays = !LaunchFlags.has(.uiTests) || LaunchFlags.has(.launchPlay) || frozenAt != nil
        reduceMotion = UIAccessibility.isReduceMotionEnabled || LaunchFlags.has(.launchReduce)
        finished = !plays
        // Reduce Motion crossfades into the app, so the tab bar's Bp! shows under it throughout.
        landed = !plays || reduceMotion
        headerUp = !plays || reduceMotion
    }

    func raiseHeader() { headerUp = true }

    func finish() {
        withTransaction(Transaction(animation: nil)) {
            landed = true
            headerUp = true
            finished = true
            dailyMark = nil
        }
    }
}

/// The app with the launch over it. Keeps the app at one place in the tree whether the launch
/// plays or not, so nothing in it restarts when the launch ends.
struct LaunchHost<Content: View>: View {
    @ViewBuilder var content: Content

    private let stage = LaunchStage.shared
    @State private var clock = LaunchClock()
    @State private var skip: Double?
    /// The launch's own frame on screen (full screen), and the top left of the app's space
    /// (`LaunchStage.space`): together they put the tab bar's Bp! in the launch's space. Both are
    /// the screen's top left while the launch plays, but without this reading of the app's
    /// space the tab bar's Bp! reached the launch only once, unlaid, and Bp! zoomed off instead
    /// of landing (measured, 2026-11-01).
    @State private var screen = Self.windowBounds
    @State private var appOrigin = CGPoint.zero
    /// The window's safe area, for the app while the launch plays.
    @State private var insets = Self.windowInsets
    /// The app behind: 98.5% or 105% under the yellow, settling to full size on the ending's
    /// own spring.
    @State private var backScale: CGFloat = 1

    var body: some View {
        // The app stays outside the launch's timeline, and whether the launch shows is decided
        // here, never inside the timeline.
        ZStack {
            content
                // A scaled view is a wall the app's full-bleed parts can't reach past: scaled as
                // laid out in the safe area, even at 0.9998, the whole app stopped at the safe
                // area and its tab bar sat 34 pt high till the launch ended, then dropped
                // (measured, 2026-11-01). So while the launch plays, the scaled layer fills the
                // screen and the app inside it gets the window's safe area back as padding.
                .safeAreaPadding(stage.finished ? EdgeInsets() : insets)
                .coordinateSpace(.named(LaunchStage.space))
                .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { appOrigin = $0 }
                .scaleEffect(backScale)
                .ignoresSafeArea(.container, edges: stage.finished ? [] : .all)
            // Paused only once done: a paused timeline doesn't draw again when what it reads
            // changes, so a held DEBUG frame (`-launch-at`) keeps ticking on its one moment, to
            // pick up the tab bar's Bp! once the bar has measured it.
            TimelineView(.animation(paused: stage.finished)) { context in
                let moment = self.moment(at: context.date)
                LaunchMark(frame: moment.frame, origin: moment.origin)
                    .contentShape(Rectangle())
                    // On touch-down, as every touch in BP answers.
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in tap() })
                    .allowsHitTesting(moment.frame.takesTaps)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { screen = $0 }
                    .sensoryFeedback(trigger: moment.frame.buzzes) { _, count in
                        LaunchMotion.buzzKinds.indices.contains(count - 1) ? LaunchMotion.buzzKinds[count - 1] : nil
                    }
                    .onChange(of: backTarget(moment.frame), initial: true) { _, target in
                        settleBack(to: target, moment.frame)
                    }
                    .onChange(of: moment.frame.headerUp, initial: true) { _, up in if up { stage.raiseHeader() } }
                    .onChange(of: moment.frame.done, initial: true) { _, done in if done { stage.finish() } }
            }
            // Done, it goes, from here. It stays in the tree: taken out when done, SwiftUI kept it
            // on screen and ticking, an invisible layer over the app taking every tap (traced,
            // and caught by `LaunchBallTests`, 2026-11-01).
            .opacity(stage.finished ? 0 : 1)
            .allowsHitTesting(!stage.finished)
            // VoiceOver hears "Block Party" once, and its focus stays in the app.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("launch")
            .accessibilityHidden(stage.finished || !LaunchFlags.has(.launchPlay))
            .ignoresSafeArea()
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
        .onChange(of: stage.finished) { _, done in if done { backScale = 1 } }
        .onAppear {
            guard stage.plays, UIAccessibility.isVoiceOverRunning else { return }
            AccessibilityNotification.Announcement("Block Party").post()
        }
        // Whatever stalls it, the app shows within 6 s: the splash deleted on 2026-09-18 left
        // the app black on every cold start (swift-traps). It plays in 2.5.
        .task {
            guard stage.plays, stage.frozenAt == nil else { return }
            try? await Task.sleep(for: .seconds(6))
            stage.finish()
        }
    }

    /// The app behind's scale to head for: its resting scale under the yellow, then full size
    /// once the ending starts. A held DEBUG frame takes the mock's exact value at that moment.
    /// Full size once finished: a launch that never plays (UI tests) still draws its first frame,
    /// and its 105% stuck on the app (2026-11-02, OnboardingNextBarTests red on main).
    private func backTarget(_ f: LaunchMotion.Frame) -> CGFloat {
        if stage.finished { return 1 }
        return stage.frozenAt != nil || f.ending == nil ? f.backScale : 1
    }

    private func settleBack(to target: CGFloat, _ f: LaunchMotion.Frame) {
        guard let spring = f.ending, stage.frozenAt == nil else { backScale = target; return }
        withAnimation(.spring(spring)) { backScale = target }
    }

    private func moment(at date: Date) -> (frame: LaunchMotion.Frame, origin: CGPoint) {
        let t = stage.frozenAt ?? clock.time(at: date)
        var ending = LaunchMotion.Ending.zoom
        if let mark = stage.dailyMark {
            ending = .tab(mark.offsetBy(dx: appOrigin.x - screen.minX, dy: appOrigin.y - screen.minY))
        }
        let motion = LaunchMotion(screen: screen.size, skip: skip ?? stage.skipAt,
                                  reduceMotion: stage.reduceMotion, ending: ending)
        return (motion.frame(at: t), motion.origin)
    }

    private func tap() {
        guard skip == nil else { return }
        skip = stage.frozenAt ?? clock.t
    }

    private static var windowInsets: EdgeInsets {
        let window = (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.windows.first
        let i = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }

    /// The screen, for the first frame, before the launch has measured itself: it has to land
    /// exactly on the launch screen's still.
    private static var windowBounds: CGRect {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen.bounds ?? .zero
    }
}

/// The launch's clock, in the mock's simulation time. A stalled frame slows it rather than
/// skipping ahead (the mock's 50 ms cap), so a slow first second on a cold start can't jump
/// the ball past a bounce.
final class LaunchClock {
    private(set) var t = 0.0
    private var last: Date?

    func time(at date: Date) -> Double {
        if let last, date > last {
            t += min(0.05, date.timeIntervalSince(last)) * LaunchMotion.pace
        }
        if last.map({ date > $0 }) ?? true { last = date }
        return t
    }
}

/// One frame of the launch: the yellow, then Bp! with the ball, all on the Daily mark's canvas.
/// The yellow is the app icon's glass, its edge at 2.5x, and Bp! casts the icon's soft shade on
/// it (Jesse, 2026-11-02; BP app references/launch-ball, mock round 6). Both fade with the yellow.
private struct LaunchMark: View {
    let frame: LaunchMotion.Frame
    /// Where the canvas's top left sits at rest; the ball is placed from it.
    let origin: CGPoint

    private static let box = CGSize(width: LaunchMotion.canvas.width * LaunchMotion.scale,
                                    height: LaunchMotion.canvas.height * LaunchMotion.scale)
    /// The tab bar's hop is in its own points, for a Bp! 39.15 pt wide: these are its points here.
    private static let hopPoints = box.width / TabBarMetric.dailyMarkWidth
    /// The glass picture's corners, which keep their shape on any screen; its middle stretches.
    /// The same 90 pt as the 270 px cap insets in LaunchGlass.imageset (drawn at 62 pt corners by
    /// BP app references/launch-ball/make_still.py): change one, change both.
    private static let glassCaps = EdgeInsets(top: 90, leading: 90, bottom: 90, trailing: 90)
    /// The shade: the mock's drop-shadow(0 9 12) in canvas units, in the ink at 21%. SwiftUI's
    /// radius is CSS's blur length (half of it fell off twice as fast, measured 2026-11-02).
    private static let shade = 0.21
    private static let shadeDrop = 9 * LaunchMotion.scale
    private static let shadeBlur = 12 * LaunchMotion.scale

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The launch screen's own picture, so its still and this first frame are one.
            Image("LaunchGlass")
                .resizable(capInsets: Self.glassCaps, resizingMode: .stretch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(frame.yellow)
            ZStack(alignment: .topLeading) {
                piece("LaunchMarkB")
                    .scaleEffect(x: frame.b.width, y: frame.b.height, anchor: Self.unit(LaunchMotion.footB))
                    .opacity(frame.letters)
                piece("LaunchMarkP")
                    .scaleEffect(x: frame.p.width, y: frame.p.height, anchor: Self.unit(LaunchMotion.footP))
                    .opacity(frame.letters)
                // Reduce Motion's full-size B and p, fading in over the 90% ones.
                piece("LaunchMarkB").opacity(frame.fullLetters)
                piece("LaunchMarkP").opacity(frame.fullLetters)
                bang
                ball
            }
            .frame(width: Self.box.width, height: Self.box.height, alignment: .topLeading)
            .foregroundStyle(Hue.onBrandDisc)
            .compositingGroup()
            .shadow(color: Hue.onBrandDisc.opacity(Self.shade * frame.yellow), radius: Self.shadeBlur, y: Self.shadeDrop)
            .scaleEffect(frame.zoom)
            .scaleEffect(frame.markScale / LaunchMotion.scale, anchor: .topLeading)
            .offset(x: frame.markOrigin.x, y: frame.markOrigin.y)
            .opacity(frame.markOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The ! : at rest, or the Daily tab's own hop, its line growing out of the dot during the
    /// crouch since it isn't there before.
    @ViewBuilder private var bang: some View {
        let (line, dot) = hop
        piece("DailyMarkBangLine")
            .scaleEffect(x: line.width, y: line.height, anchor: DailyMarkGlyph.lineFoot)
            .offset(y: line.y * Self.hopPoints)
            .opacity(frame.lineOpacity)
        piece("DailyMarkBangDot")
            .scaleEffect(x: dot.width, y: dot.height, anchor: DailyMarkGlyph.dotBase)
            .offset(y: dot.y * Self.hopPoints)
            .opacity(frame.dotShown ? 1 : 0)
    }

    private var hop: (DailyMarkGlyph.Hop, DailyMarkGlyph.Hop) {
        guard let h = frame.hop else { return (DailyMarkGlyph.Hop(), DailyMarkGlyph.Hop()) }
        var line = DailyMarkGlyph.lineHop.value(time: h)
        let crouch = DailyMarkGlyph.crouch
        if h < crouch {
            line.height = DailyMarkGlyph.lineHop.value(time: crouch).height * LaunchMotion.easeOut.value(at: h / crouch)
        }
        return (line, DailyMarkGlyph.dotHop.value(time: h))
    }

    /// The Town's round logo: rolling, stretched along its speed, squashed on a hit, and going
    /// black as it lands.
    private var ball: some View {
        let b = frame.ball
        return Image(Town.logo)
            .resizable()
            .scaledToFill()
            .frame(width: 2 * b.r, height: 2 * b.r)
            .overlay { Circle().fill(Hue.onBrandDisc).opacity(frame.ballBlack) }
            .clipShape(Circle())
            .rotationEffect(.degrees(b.roll - b.heading))
            .scaleEffect(x: b.sx, y: b.sy)
            .rotationEffect(.degrees(b.heading))
            .position(x: b.x - origin.x, y: b.y - origin.y)
            .opacity(frame.ballOpacity)
    }

    private func piece(_ name: String) -> some View {
        Image(name).resizable().frame(width: Self.box.width, height: Self.box.height)
    }

    /// A canvas point as a point of the canvas's box.
    private static func unit(_ p: CGPoint) -> UnitPoint {
        UnitPoint(x: (p.x - LaunchMotion.canvas.minX) / LaunchMotion.canvas.width,
                  y: (p.y - LaunchMotion.canvas.minY) / LaunchMotion.canvas.height)
    }
}

extension View {
    /// The tab bar's Daily Bp!: hidden until the launch's lands on it, and telling the launch
    /// where it sits.
    func launchLanding() -> some View { modifier(LaunchLanding()) }
}

private struct LaunchLanding: ViewModifier {
    private let stage = LaunchStage.shared

    func body(content: Content) -> some View {
        content
            // Its own opacity, not a dimmed glass: the bar is Liquid Glass (swift-traps).
            .opacity(stage.landed ? 1 : 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LaunchStage.space)) } action: { frame in
                if !stage.landed { stage.dailyMark = frame }
            }
            .onDisappear { if !stage.landed { stage.dailyMark = nil } }
    }
}
