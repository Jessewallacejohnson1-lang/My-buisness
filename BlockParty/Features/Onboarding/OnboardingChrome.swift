//
//  OnboardingChrome.swift
//  Block Party — the pieces every onboarding question screen shares (BP app
//  docs/plans/onboarding, mock v7): the faint yellow backdrop, the back chevron, Duolingo's
//  chunky yellow progress bar and the one Next bar. `OnboardingFlow` owns where they sit;
//  the steps draw none of them. `OnboardingBackButton` and `ContinueButton` are Edit
//  Profile's interest picker's, kept from the deleted wizard.
//

import SwiftUI

/// Instagram's backdrop, measured corner by corner, rebuilt as the one yellow at low strength
/// over paper (mock v3 to v7): strongest top right and bottom centre, a hint top left and
/// bottom left, and 3.5% everywhere. No new yellow exists; it is `Hue.brandDisc` faded.
struct OnboardingBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Hue.paper
                Hue.brandDisc.opacity(0.035)
                glow(0.17, at: .topTrailing, radii: (0.75, 0.45), fade: 0.70, size)
                glow(0.09, at: .topLeading, radii: (0.60, 0.40), fade: 0.70, size)
                glow(0.22, at: .bottom, radii: (0.70, 0.30), fade: 0.72, size)
                glow(0.08, at: .bottomLeading, radii: (0.60, 0.35), fade: 0.70, size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// One of the mock's CSS radial gradients: an ellipse `radii` of the screen's width and
    /// height around `center`, fading to nothing `fade` of the way out.
    private func glow(_ strength: Double, at center: UnitPoint, radii: (CGFloat, CGFloat),
                      fade: CGFloat, _ size: CGSize) -> some View {
        let rx = radii.0 * size.width, ry = radii.1 * size.height
        return EllipticalGradient(colors: [Hue.brandDisc.opacity(strength), Hue.brandDisc.opacity(0)],
                                  center: center, startRadiusFraction: 0, endRadiusFraction: fade)
            .frame(width: rx * 2, height: ry * 2)
            .position(x: center.x * size.width, y: center.y * size.height)
    }
}

/// The back chevron at the top left of every question step: control grey, 44 pt to tap,
/// sinking to 88% under the finger.
struct OnboardingBackChevron: View {
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: "chevron.left")
                .font(.glyph(22, weight: .bold))
                .foregroundStyle(Hue.control)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPress(scale: 0.88))
        .accessibilityLabel("Back")
    }
}

/// Duolingo's bar in BP's yellow: a 16 pt capsule on an 8% ink track, the fill carrying a
/// white highlight stripe 4 pt down and 5 pt tall. Each step it rises past its mark by 7.5% of
/// a step, peaks at 0.23 s and settles by 0.4 s (iOS refs/onboarding/REFERENCE-SPEC.md §8),
/// and a glint runs along it going forward.
struct OnboardingProgressBar: View {
    /// 1 to `total`.
    let index: Int
    let total: Int

    /// The spring that overshoots 7.5% and peaks at 0.23 s: damping ratio 0.636 gives
    /// exp(-ζπ/√(1-ζ²)) = 0.075, and response 0.355 puts the first peak at π/ω_d = 0.23 s.
    static let advance: Animation = .spring(response: 0.355, dampingFraction: 0.636)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts steps forward only, so Back runs no glint.
    @State private var forwardMoves = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(16, geo.size.width * CGFloat(index) / CGFloat(max(total, 1)))
            Capsule()
                .fill(Hue.ink.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Hue.brandDisc)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(0.5))
                                .frame(height: 5)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                        }
                        .overlay(Capsule().strokeBorder(Hue.ink.opacity(0.05), lineWidth: 1))
                        .overlay(alignment: .leading) { if !reduceMotion { glint(width: w) } }
                        .clipShape(Capsule())
                        .frame(width: w)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.advance, value: index)
                }
        }
        .frame(height: 16)
        .onChange(of: index) { old, new in if new > old { forwardMoves += 1 } }
        .accessibilityElement()
        .accessibilityLabel("Step \(index) of \(total)")
    }

    /// A 30 pt band of light that sweeps the fill once per step forward: in from nothing over
    /// a quarter of its run, out over the rest, 0.52 s after a 0.14 s wait (mock v4).
    private func glint(width: CGFloat) -> some View {
        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: 30)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: forwardMoves) { band, t in
                band
                    .offset(x: t * (width - 30))
                    .opacity(t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75)
            } keyframes: { _ in
                LinearKeyframe(0, duration: 0)
                LinearKeyframe(0, duration: 0.14)
                CubicKeyframe(1, duration: 0.52)
            }
            .allowsHitTesting(false)
    }
}

/// The one primary button, Duolingo's build lit as BP's charcoal pill: a 48 pt face on a 4 pt
/// edge (`Hue.nextEdge`). Pressed, the face sinks onto the edge in 80 ms and springs back in
/// 70 ms with a hair of overshoot (REFERENCE-SPEC §8: 4 pt travel, damping 0.62), with a light
/// haptic on the press-down. Not allowed, it greys and shakes instead of acting, so it stays
/// tappable: a disabled button could not shake.
struct OnboardingNextBar: View {
    let title: String
    var allowed = true
    let action: () -> Void

    @State private var shakes = 0

    var body: some View {
        Button {
            if allowed { action() } else { shakes += 1; Haptics.error() }
        } label: {
            Text(title)
                .font(.sansSemibold(17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(NextBarStyle(allowed: allowed))
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { bar, x in
            bar.offset(x: x)
        } keyframes: { _ in
            LinearKeyframe(-6, duration: 0.06)
            LinearKeyframe(5, duration: 0.06)
            LinearKeyframe(-3, duration: 0.06)
            LinearKeyframe(1, duration: 0.06)
            LinearKeyframe(0, duration: 0.06)
        }
        .accessibilityIdentifier("onboarding-next")
        .accessibilityHint(allowed ? "" : "Not yet: answer the question first")
    }
}

private struct NextBarStyle: ButtonStyle {
    let allowed: Bool

    private var face: some ShapeStyle {
        LinearGradient(stops: [.init(color: Hue.pillTop, location: 0),
                               .init(color: Hue.pillDeep, location: 0.25),
                               .init(color: Hue.pillBottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .white.opacity(0.16), radius: 0, x: 0, y: 1))
    }

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        return ZStack(alignment: .top) {
            Capsule().fill(allowed ? Hue.nextEdge : Hue.nextOffEdge)
            configuration.label
                .foregroundStyle(allowed ? Color.white : Hue.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    if allowed { Capsule().fill(face) } else { Capsule().fill(Hue.nextOffFace) }
                }
                .offset(y: down ? 4 : 0)
                .animation(down ? .easeOut(duration: 0.08) : .spring(response: 0.12, dampingFraction: 0.62),
                           value: down)
        }
        .frame(height: 52)
        .shadow(color: Hue.ink.opacity(allowed ? (down ? 0.2 : 0.3) : 0), radius: down ? 3 : 8, y: down ? 2 : 6)
        .contentShape(Capsule())
        .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
    }
}

/// The Skip / Not now / I already have an account link under the Next bar: ink words that
/// sink to 95% and dim under the finger.
struct OnboardingLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPress(scale: 0.95, dim: 0.6))
    }
}

/// A press that sinks on touch-down (80 ms) and springs back (70 ms): the chevron, the links
/// and the Welcome's white pills, which also grey to `pill` under the finger.
struct OnboardingPress: ButtonStyle {
    let scale: CGFloat
    var dim: Double = 1
    var pill: Color?
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .background { if let pill { Capsule().fill(down ? pill : .white) } }
            .scaleEffect(down ? scale : 1)
            .opacity(down ? dim : 1)
            .animation(down ? .easeOut(duration: 0.08) : .spring(response: 0.12, dampingFraction: 0.62), value: down)
    }
}

/// Edit Profile's interest picker's back button.
struct OnboardingBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: "chevron.left")
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .frame(width: 44, height: 44)
                .background(Hue.surface, in: Circle())
                .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

/// The full-width ink CTA. It was the wizard's shared pill; the interest picker
/// outlived the wizard (Edit Profile presents it), so the button moved here with
/// the rest of that screen's chrome when the onboarding flow was deleted on
/// 2026-09-18.
struct ContinueButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sansSemibold(17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? Hue.ink : Hue.ink.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
    }
}
