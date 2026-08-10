//
//  FeedMotion.swift
//  Block Party — the Today feed's motion vocabulary, and its Reduce Motion contract.
//
//  Two moments in this app are allowed to feel good: the "+" press, and a Town
//  Notes card opening. This file owns the second one. Everything else in the feed
//  routes through `quietPressScale`, which is deliberately too small to notice.
//
//  Reduce Motion is not a dimmer here — it is a different animation. Every branch
//  below collapses to a CROSS-FADE: no spring, no scale, no offset. `Spec` exists
//  so that contract is assertable in a unit test rather than only in a screenshot
//  (`FeedMotionTests`), and every view in the feed reads its numbers from here.
//
//  Never attach a whole-card LongPressGesture/DragGesture/.gesture(TapGesture) to
//  anything inside the feed's scroll views — it claims the touch on press-down and
//  out-competes the vertical pan. Press feedback is a ButtonStyle's `isPressed`.
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
    /// an error card and an expanding story all hand over at the same speed.
    static let crossFade: Double = 0.20

    // MARK: The signature interaction — a Town Notes card opening

    /// The card's own height change. Slower and flatter than `Motion.bentoExpand`
    /// on purpose: this is the one thing in the feed worth watching, and overshoot
    /// would make a 300pt card read as loose rather than considered.
    static let expandResponse: Double = 0.46
    static let expandDamping: Double = 0.88

    /// The story body arrives a beat AFTER the card edge starts moving, so the two
    /// read as one gesture with a cause and an effect rather than as one lump.
    static let expandBodyDelay: Double = 0.10
    static let expandBodyDuration: Double = 0.26
    static let expandBodyRise: CGFloat = 8
    static let collapseDuration: Double = 0.12

    static func newsExpandSpec(reduceMotion: Bool) -> Spec {
        reduceMotion
            ? Spec(usesSpring: false, usesScale: false, usesOffset: false, duration: crossFade)
            : Spec(usesSpring: true, usesScale: false, usesOffset: true, duration: expandResponse)
    }

    static func newsExpand(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: crossFade)
            : .spring(response: expandResponse, dampingFraction: expandDamping)
    }

    /// Insertion rises and fades; removal only fades, and faster — closing a card
    /// should get out of the way instead of performing.
    static func newsBodyTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: expandBodyRise))
                .animation(.easeOut(duration: expandBodyDuration).delay(expandBodyDelay)),
            removal: .opacity.animation(.easeIn(duration: collapseDuration))
        )
    }

    // MARK: Everything else stays quiet

    /// The only press scale allowed on a feed surface. Small enough to feel like
    /// contact and nothing more; exactly 1 under Reduce Motion.
    static let quietPress: CGFloat = 0.985

    static func quietPressSpec(reduceMotion: Bool) -> Spec {
        reduceMotion
            ? Spec(usesSpring: false, usesScale: false, usesOffset: false, duration: crossFade)
            : Spec(usesSpring: true, usesScale: true, usesOffset: false, duration: pressResponse)
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

    /// The same numbers as `Motion.tilePress`, restated here because `Motion` is
    /// MainActor-isolated and this enum has to stay `nonisolated` so it can be
    /// asserted in a plain unit test.
    static let pressResponse: Double = 0.25
    static let pressDamping: Double = 0.80

    static func pressAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: crossFade / 2)
            : .spring(response: pressResponse, dampingFraction: pressDamping)
    }

    /// Skeleton → content, and content → error. Always a cross-fade, in both
    /// modes: a placeholder swapping for the real thing must not draw the eye.
    static func stateSwap(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? crossFade : 0.28)
    }
}

/// The one press style for a whole feed card. Uses `ButtonStyle.isPressed` rather
/// than a gesture so it composes with the enclosing ScrollView's pan.
struct FeedCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                FeedMotion.pressScale(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(
                FeedMotion.pressOpacity(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .animation(
                FeedMotion.pressAnimation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
