//
//  Motion.swift
//  Block Party — the ONE motion vocabulary for the app's SwiftUI animations.
//
//  Named springs live here, so timing stays consistent and a feel tweak happens in
//  one place.
//
//  Match the token to the MASS of what's moving (emil-design-eng: physics-credible):
//  a small chip is `snappy`, a small card is `card`, a pick or bump is `select`, a
//  colour/opacity fade is `smooth`, and a big surface is `sheet` (heavier — it
//  shouldn't feel as loose as a small card). `bentoExpand` grows something in place.
//
//  `Press` below is how anything pressable answers the finger.
//
//  NOT here on purpose: Mapbox camera moves (ViewportAnimation) live in the map.
//

import SwiftUI

enum Motion {
    /// Default UI state changes, toggles, chips. ≈ .spring(duration:0.25, bounce:0.15).
    static let snappy: Animation = .spring(duration: 0.25, bounce: 0.15)

    /// A small card settling back (the hello pill after a drag, a like burst).
    static let card: Animation = .spring(response: 0.28, dampingFraction: 0.78)

    /// A pick or a bump: Daily's topic, You's day, a team's star.
    static let select: Animation = .spring(response: 0.32, dampingFraction: 0.72)

    /// Opacity / colour fades, non-bouncy moves (critically damped, no overshoot).
    static let smooth: Animation = .smooth(duration: 0.35)

    /// A big surface moving (the hello drop, the feed's hide and undo). Heavier than
    /// `card` on purpose — a full-width surface should read as more mass than a small card.
    static let sheet: Animation = .spring(response: 0.42, dampingFraction: 0.86)

    /// Something expanding/collapsing in place (the hello drop). Slower and calmer
    /// than `card`: it GROWS where it stands rather than arriving from somewhere, so
    /// it should settle rather than pop.
    static let bentoExpand: Animation = .spring(response: 0.44, dampingFraction: 0.82)
}

/// How a button answers the finger. Everything pressable is one of these three, unless it
/// draws something extra when pressed (Attend, •••, Next, the interest chips, Welcome's pills),
/// and those take these numbers too.
nonisolated enum Press {
    /// Sinks while the finger is down, and springs back the way it went.
    case squish
    /// Fades while pressed: words alone, like Cancel.
    case dim
    /// A list row darkens a touch under the finger.
    case row

    /// A squish takes the same 5 pt off anything's width, so a big card and a small icon
    /// read alike, between these two: a Town card's and Attend's 97%, a 44 pt icon's 88%.
    static let widthLost: CGFloat = 5
    static let shallowest: CGFloat = 0.97
    static let deepest: CGFloat = 0.88
    static func depth(width: CGFloat) -> CGFloat {
        min(shallowest, max(deepest, 1 - widthLost / width))
    }

    /// In fast enough for a quick tap to show it, and back on the spring of Jesse's Search mockup.
    static let inSeconds: Double = 0.08
    static let backResponse: Double = 0.28
    static let backDamping: Double = 0.68

    static func animation(down: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: FeedMotion.crossFade / 2) }
        return down ? .easeOut(duration: inSeconds)
                    : .spring(response: backResponse, dampingFraction: backDamping)
    }

    /// Next and the interest chips push down like a key and come straight back.
    static func push(down: Bool) -> Animation {
        down ? .easeOut(duration: inSeconds) : .spring(response: 0.12, dampingFraction: 0.62)
    }

    static let dimmed: Double = 0.45
    static let rowShade: Double = 0.05
}

extension View {
    /// `down` from whatever knows the finger is down: a `ButtonStyle`, or a card's own touch tracker.
    func press(_ press: Press, down: Bool) -> some View {
        modifier(PressEffect(press: press, down: down))
    }
}

private struct PressEffect: ViewModifier {
    let press: Press
    let down: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        switch press {
        case .squish:
            let sinks = down && !reduceMotion
            content
                .visualEffect { view, proxy in
                    view.scaleEffect(sinks ? Press.depth(width: proxy.size.width) : 1)
                }
                .opacity(FeedMotion.pressOpacity(isPressed: down, reduceMotion: reduceMotion))
                .animation(Press.animation(down: down, reduceMotion: reduceMotion), value: down)
        case .dim:
            content.opacity(down ? Press.dimmed : 1)
        case .row:
            content.background(Hue.ink.opacity(down ? Press.rowShade : 0))
        }
    }
}

/// `.buttonStyle(.press(.squish))`. `haptic` ticks on touch-down, for the few that commit something.
struct PressStyle: ButtonStyle {
    let press: Press
    var haptic = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .press(press, down: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if haptic && down { Haptics.light() } }
    }
}

extension ButtonStyle where Self == PressStyle {
    static func press(_ press: Press, haptic: Bool = false) -> PressStyle {
        PressStyle(press: press, haptic: haptic)
    }
}
