//
//  SpringReveal.swift
//  Block Party — the "everything springs out" entrance.
//
//  A staggered spring reveal: sections fade in, rise from just below, and settle
//  with a subtle overshoot — cascading top-to-bottom so the whole screen reads as
//  one gesture, not a slideshow. Ported in spirit from the Wolt home reveal that
//  plays on open / refresh.
//
//  Craft notes (Emil Kowalski's animation framework):
//   • Never from scale(0) — start at ~0.97 + opacity so nothing pops from nothing.
//   • Entrances feel best with an ease-out character; a spring with a small bounce
//     gives that "spring out" settle without looking springy/toylike.
//   • Stagger stays short (≈55ms) so the cascade is felt, not waited on.
//   • Reduce Motion collapses movement to a gentle fade (comprehension, no motion).
//   • Only transform + opacity animate — GPU-friendly, no layout thrash on scroll.
//

import SwiftUI

/// Tunable tokens for the reveal — kept in one place so the screenshot loop can
/// dial feel without hunting through call sites.
enum RevealTiming {
    static let stagger: Double = 0.05    // delay between successive sections
    static let bounce: Double  = 0.28    // spring overshoot (0.1–0.3 stays tasteful)
    static let duration: Double = 0.48   // spring settle time
    static let rise: CGFloat   = 22       // how far below its resting place it starts
    static let startScale: CGFloat = 0.94 // never 0 — scale carries the "out toward you" pop
    static let reducedFade: Double = 0.25 // Reduce-Motion fade duration
}

struct SpringReveal: ViewModifier {
    /// Position in the cascade (0 = first/top). Drives the stagger delay.
    let index: Int
    /// Flip false → true to play the reveal.
    let isRevealed: Bool
    /// When false, `isRevealed` changes apply instantly (no animation). Used to
    /// collapse the screen on refresh without a reverse-spring before it plays in.
    let animated: Bool
    /// Per-step delay between successive sections. Defaults to the app-wide
    /// `RevealTiming.stagger`; a caller with fewer, larger rows (the calendar day
    /// detail) dials it up to match a slower reference cascade.
    var stagger: Double = RevealTiming.stagger
    /// Spring settle time / overshoot. Defaulted to the app-wide feel; the day
    /// detail slows the settle and softens the bounce to match its reference.
    var duration: Double = RevealTiming.duration
    var bounce: Double = RevealTiming.bounce

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var delay: Double { Double(index) * stagger }

    private var animation: Animation {
        reduceMotion
            ? .easeOut(duration: RevealTiming.reducedFade).delay(delay)
            : .spring(duration: duration, bounce: bounce).delay(delay)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            // Reduce Motion keeps the fade but drops the movement.
            .scaleEffect(isRevealed || reduceMotion ? 1 : RevealTiming.startScale, anchor: .top)
            .offset(y: isRevealed || reduceMotion ? 0 : RevealTiming.rise)
            // nil animation makes the collapse instant — `.animation(_:value:)`
            // would otherwise re-animate the change even inside a disabled transaction.
            .animation(animated ? animation : nil, value: isRevealed)
    }
}

extension View {
    /// Give a section its place in the staggered spring entrance.
    /// `revealed` starts false and flips true on appear / refresh. Pass
    /// `animated: false` to collapse instantly (the pull-to-refresh reset).
    func springReveal(_ index: Int, revealed: Bool, animated: Bool = true,
                      stagger: Double = RevealTiming.stagger,
                      duration: Double = RevealTiming.duration,
                      bounce: Double = RevealTiming.bounce) -> some View {
        modifier(SpringReveal(index: index, isRevealed: revealed, animated: animated,
                              stagger: stagger, duration: duration, bounce: bounce))
    }
}
