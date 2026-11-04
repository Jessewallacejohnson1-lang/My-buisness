//
//  FeedMotion.swift
//  Block Party — the Town feed's motion vocabulary, and its Reduce Motion contract.
//
//  The feed stays quiet: everything routes through `quietPress`, one small press (on a
//  Town event card, the photo alone). Its spring is `Press`'s.
//
//  Reduce Motion is not a dimmer here — it is a different animation. Every branch
//  below collapses to a CROSS-FADE: no spring, no scale, no offset. `Spec` exists
//  so that contract is assertable in a unit test rather than only in a screenshot
//  (`FeedMotionTests`), and every view in the feed reads its numbers from here.
//
//  Never attach a whole-card LongPressGesture/DragGesture/.gesture(TapGesture) to
//  anything inside the feed's scroll views — it claims the touch on press-down and
//  out-competes the vertical pan. Press feedback is a ButtonStyle's `isPressed`.
//  One deliberate exception (DECISIONS.md, 2026-09-25): `FeedEventCard` tracks its
//  touch-down with a UIKit recognizer that only observes (simultaneous with every
//  recognizer, never cancels touches), because its photo's double tap holds the
//  link's `isPressed` back. A SwiftUI LongPressGesture there, even simultaneous,
//  still stopped the feed scrolling. The photo's `.gesture(PhotoDoubleTap …)`, a
//  UIKit double tap, is covered too: a UIKit tap fails as soon as the finger
//  moves, so it never competes with the scroll.
//

import SwiftUI

nonisolated enum FeedMotion {
    /// What a feed animation is actually allowed to do. Reduce Motion drives every
    /// flag false except opacity, which is the cross-fade itself.
    struct Spec: Equatable {
        let usesSpring: Bool
        let usesScale: Bool
        let usesOffset: Bool
        /// Seconds. For a spring this is its `response`, for a cross-fade its duration.
        let duration: Double

        /// A cross-fade is the absence of everything else.
        var isCrossFade: Bool { !usesSpring && !usesScale && !usesOffset }
    }

    /// One duration for every reduced-motion cross-fade in the feed, so a skeleton,
    /// an error card and a press all hand over at the same speed.
    static let crossFade: Double = 0.20

    // MARK: Everything else stays quiet

    /// The only press scale allowed on a feed surface; exactly 1 under Reduce Motion.
    /// 0.97, guessed (2026-10-23). A Town event card sinks only its photo (Jesse, 2026-10-27).
    static let quietPress: CGFloat = 0.97

    static func quietPressSpec(reduceMotion: Bool) -> Spec {
        reduceMotion
            ? Spec(usesSpring: false, usesScale: false, usesOffset: false, duration: crossFade)
            : Spec(usesSpring: true, usesScale: true, usesOffset: false, duration: Press.backResponse)
    }

    static func pressScale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, isPressed else { return 1 }
        return quietPress
    }

    /// Reduce Motion swaps the press scale for a dip in opacity — the same
    /// information, carried by a fade.
    static func pressOpacity(isPressed: Bool, reduceMotion: Bool) -> Double {
        guard reduceMotion, isPressed else { return 1 }
        return 0.78
    }
}
