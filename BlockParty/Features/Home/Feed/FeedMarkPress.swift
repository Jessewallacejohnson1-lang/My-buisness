//
//  FeedMarkPress.swift
//  Block Party — the "+" press, the one feed press allowed to be felt.
//
//  `FeedMotion` owns the feed's motion vocabulary and its Reduce Motion contract;
//  everything there is deliberately quiet (`quietPress` = 0.985). The "+" is the
//  documented exception — one of the two moments in this app permitted to feel
//  good — so its numbers live here rather than diluting `FeedMotion.quietPress`
//  into "sometimes big".
//
//  It is an EXTENSION of that vocabulary, not a second one: the Reduce Motion
//  branch returns `FeedMotion.Spec` and cross-fades on `FeedMotion.crossFade`,
//  exactly like every other feed animation. Under Reduce Motion the "+" and a
//  Town Notes card degrade identically.
//

import SwiftUI

nonisolated enum FeedMarkPress {
    /// Deep enough to read as a real button-press on a 44pt square.
    static let pressedScale: CGFloat = 0.88
    static let response: Double = 0.25
    static let dampingFraction: Double = 0.6

    /// The same shape of contract `FeedMotion.quietPressSpec` returns, so one test
    /// can assert that EVERY feed press — quiet or showcase — cross-fades under
    /// Reduce Motion.
    static func spec(reduceMotion: Bool) -> FeedMotion.Spec {
        reduceMotion
            ? FeedMotion.Spec(
                usesSpring: false,
                usesScale: false,
                usesOffset: false,
                duration: FeedMotion.crossFade
            )
            : FeedMotion.Spec(
                usesSpring: true,
                usesScale: true,
                usesOffset: false,
                duration: response
            )
    }

    static func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, isPressed else { return 1 }
        return pressedScale
    }

    /// Reduce Motion trades the scale for the feed's standard press fade — the
    /// same value dip `FeedMotion.pressOpacity` uses, so the two match exactly.
    static func opacity(isPressed: Bool, reduceMotion: Bool) -> Double {
        FeedMotion.pressOpacity(isPressed: isPressed, reduceMotion: reduceMotion)
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? FeedMotion.pressAnimation(reduceMotion: true)
            : .spring(response: response, dampingFraction: dampingFraction)
    }
}
