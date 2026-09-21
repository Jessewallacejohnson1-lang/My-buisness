//
//  FeedCardLikeBurst.swift
//  Block Party — the heart that pops where you double-tapped, then leaves.
//
//  Instagram's double-tap heart lands under your finger, not in the middle of the
//  picture: the gesture and the feedback are the same event, and a heart that
//  appears somewhere else reads as the app answering a different tap. It is also
//  the one red thing on a card that is otherwise ink on paper — the same red the
//  action row's heart takes when it is yours.
//
//  It does not fade out. It flies up through the top of the photograph and is gone
//  (Jesse, 2026-09-20). Which is why the modifier is applied INSIDE each card's
//  `clipShape`: the picture's own edge is what takes the heart away, and a fade
//  would say "this is finished" where a departure says "sent".
//
//  Lives here rather than in either card because both cards had their own copy of
//  the same choreography, which is how two hearts start animating differently.
//

import SwiftUI

/// A double-tap, addressed: where it landed and which one it was.
///
/// `generation` is what replays the animation — a second double-tap in the same
/// spot is a new burst, and comparing points alone would swallow it.
nonisolated struct FeedLikeBurst: Equatable {
    /// In the photo's own coordinate space. nil centres it, which is what the
    /// DEBUG gallery's scripted like has to do — it has no finger.
    var point: CGPoint?
    var generation: Int = 0

    mutating func fire(at point: CGPoint?) {
        self.point = point
        generation += 1
    }

    /// How far up the heart travels to clear the photo's top edge.
    ///
    /// Measured from where it was born, not from the middle: a tap near the bottom
    /// of a tall 4:5 posting has most of the picture to cross, and a fixed distance
    /// would leave it parked in mid-air.
    ///
    /// The clearance is not half of `Size.glyph`. 84 is a FONT size, and SF Symbols
    /// draws `heart.fill` at roughly 0.72 of it, so ~30pt of glyph above the centre
    /// plus the drop shadow's reach. Over-clearing costs nothing — the clip has
    /// already taken the heart by then.
    static func exitTravel(from point: CGPoint?, photoHeight: CGFloat) -> CGFloat {
        let originY = point?.y ?? photoHeight / 2
        return originY + clearance
    }

    /// One nominal speed for every exit, floored and capped.
    ///
    /// A fixed duration would send a top-edge tap out at a crawl and a bottom-edge
    /// tap out in a blur — the same gesture reading as two different features. A
    /// travel of 0 means "distance unknown" (the fingerless gallery like) and takes
    /// the floor, which is what a centred heart on either card's photo works out to
    /// anyway.
    static func exitDuration(travel: CGFloat) -> Double {
        min(maxExit, max(minExit, Double(travel) / speed))
    }

    static let clearance: CGFloat = 60
    private static let speed: Double = 1400
    private static let minExit: Double = 0.28
    private static let maxExit: Double = 0.42
}

extension View {
    /// Overlays the double-tap heart on a card's photograph.
    ///
    /// Apply this INSIDE the photo's `clipShape` — the heart's exit is the picture's
    /// edge cutting it off. Applied outside, it flies over the card above instead.
    func feedCardLikeBurst(_ burst: FeedLikeBurst, reduceMotion: Bool) -> some View {
        modifier(FeedCardLikeBurstModifier(burst: burst, reduceMotion: reduceMotion))
    }
}

private struct FeedCardLikeBurstModifier: ViewModifier {
    let burst: FeedLikeBurst
    let reduceMotion: Bool

    /// Timings. The hold is what makes it read as a stamp rather than a flicker;
    /// the flight is timed per-tap, in `FeedLikeBurst.exitDuration`.
    private enum Beat {
        static let settle = 150
        static let hold = 300
        /// Reduce Motion's exit only. The full-motion heart leaves through the clip.
        static let fade = 250
    }

    private enum Size {
        static let glyph: CGFloat = 84
        static let overshoot: CGFloat = 1.15
        /// Slightly translucent the whole time it is on screen — it is a stamp on
        /// the photograph, not a sticker over it.
        static let peak: Double = 0.85
        /// A hand-drawn tilt, not a stamp. Small enough to read as accident.
        static let tilt: ClosedRange<Double> = -10...10
    }

    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var tilt: Double = 0
    @State private var point: CGPoint?
    /// 0 = where it was born, 1 = fully departed. The distance it multiplies is
    /// resolved in the view, where the photo's height is known.
    @State private var lift: CGFloat = 0
    /// The last burst actually played. `task(id:)` also fires on REAPPEARANCE, so
    /// without this a liked card relaunches its heart every time you scroll back to
    /// it — invisible when the heart faded in place, very visible now.
    @State private var playedGeneration = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let travel = FeedLikeBurst.exitTravel(
                        from: point,
                        photoHeight: proxy.size.height
                    )

                    Image(systemName: "heart.fill")
                        .font(.glyph(Size.glyph, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Hue.heart)
                        // Red on a photograph needs its own edge — a sunset will
                        // happily swallow this heart otherwise.
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
                        .scaleEffect(reduceMotion ? 1 : scale)
                        .rotationEffect(.degrees(tilt))
                        // Flatten glyph and shadow BEFORE taking alpha. Without this
                        // the shadow's black blur shows through the translucent red
                        // and the heart goes muddy.
                        .compositingGroup()
                        .opacity(opacity)
                        .position(point ?? center(of: proxy.size))
                        // After `position`, not before: this shifts the placed layer,
                        // where an offset inside `position` would be reasoning about
                        // the parent-filling frame instead.
                        .offset(y: -lift * travel)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // `task(id:)` cancels the run in flight, so a rapid second double-tap
            // restarts the burst instead of racing the first one's departure.
            .task(id: burst.generation) { await play() }
    }

    private func center(of size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func play() async {
        guard burst.generation > 0, burst.generation != playedGeneration else { return }
        playedGeneration = burst.generation

        point = burst.point
        tilt = reduceMotion ? 0 : Double.random(in: Size.tilt)
        lift = 0

        if reduceMotion {
            scale = 1
            withAnimation(.easeInOut(duration: 0.15)) { opacity = Size.peak }
        } else {
            scale = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                scale = Size.overshoot
                opacity = Size.peak
            }
        }

        try? await Task.sleep(for: .milliseconds(Beat.settle))
        guard !Task.isCancelled else { return }

        // Settles harder than it popped. At the pop's damping it is still visibly
        // resolving at 400ms, which used to hide inside a long hold and would now
        // launch mid-wobble.
        if !reduceMotion {
            withAnimation(Motion.card) { scale = 1 }
        }

        try? await Task.sleep(for: .milliseconds(Beat.hold))
        guard !Task.isCancelled else { return }

        if reduceMotion {
            // No travel at all: a ~500pt translate is the exact thing this setting
            // exists to suppress, so here the heart does fade where it stands.
            withAnimation(.easeIn(duration: 0.15)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(Beat.fade))
        } else {
            // Up and out. No fade, no shrink, no drift — a constant-size object
            // sliding behind the picture's edge, which is what the eye already
            // knows how to read. `easeIn` departs from the rest the hold set.
            let seconds = FeedLikeBurst.exitDuration(
                travel: burst.point.map { $0.y + FeedLikeBurst.clearance } ?? 0
            )
            withAnimation(.easeIn(duration: seconds)) { lift = 1 }
            try? await Task.sleep(for: .seconds(seconds))
        }

        guard !Task.isCancelled else { return }
        // Offstage now, so this resets with no animation to watch.
        opacity = 0
        scale = 0
        lift = 0
    }
}
