//
//  BPOnboardingPalette.swift
//  Block Party — the 20-screen onboarding flow's scoped palette + metrics.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  SCOPE WARNING — read before reusing any token in here.
//
//  The app is monochrome ink-on-paper with ONE meaning-scoped accent (`Hue.accent`,
//  plum). This flow is a deliberate exception: a 1:1 mechanical clone of Duolingo's
//  onboarding, which carries its own colour system. Jesse locked that direction on
//  2026-07-24 after being shown the conflict with `block-party-brand`.
//
//  So: these tokens are for `Features/OnboardingFlow/` ONLY. Do not reference `BP.*`
//  from app chrome, and do not promote them into `Hue` — the colour stops at the tab
//  bar by design. This follows the `InsightsPalette` precedent: a feature-scoped
//  semantic layer that aliases the global tokens wherever they already fit.
//  ─────────────────────────────────────────────────────────────────────────────
//
//  Every number below is MEASURED off the reference frames in
//  `refs/onboarding/duolingo/S01…S20.png` (1180×2556 = iPhone 15/16 Pro @3x), not
//  guessed. The measurement notes live in `refs/onboarding/REFERENCE-SPEC.md`.
//

import SwiftUI

enum BP {

    // MARK: - Colour

    /// Primary buttons, progress fill, splash ground, highlighted stat spans.
    /// Everything Duolingo's green (#5ACD05, sampled) does.
    static let orange = Color(hex: 0xE67633)

    /// The 3D bottom edge + pressed state of a primary button. Duolingo's edge
    /// measured 19% darker than its face (#5ACD05 → #5CA600); this matches that ratio.
    static let orangeEdge = Color(hex: 0xBD612A)

    /// Selection accent — everything Duolingo's blue (#1DB3FB, sampled) does.
    static let teal = Color(hex: 0x72C5B6)

    /// Selected row/card ground. Duolingo's is #E1F4FF — its blue at ~12% over white.
    static let tealTint = Color(hex: 0xEAF6F3)

    /// Selected row/card label. Darkened until it clears 4.5:1 on `tealTint`.
    static let tealText = Color(hex: 0x3F6C64)

    /// Secondary text, small-caps status labels, disabled button labels, the
    /// right-side intensity labels on S12.
    ///
    /// The build spec named #707174; `Hue.inkSecondary` is #6E6E6E — a 2/255
    /// difference, invisible on screen. Aliased rather than duplicated so the flow
    /// tracks the app's grey if it ever moves.
    static let gray = Hue.inkSecondary

    /// Row/card borders and the progress track. Duolingo's measured #E7E5E5 /
    /// #E7E4E7; `Hue.hairline` is #E7E7E4 — same colour to the eye, so alias it.
    static let hairline = Hue.hairline

    /// Disabled button fill and the row icon chip.
    static let chip = Hue.fill

    /// Page ground. The spec calls for the app's existing warm off-white.
    static let paper = Hue.paper

    /// Primary text. The app's near-black.
    static let ink = Hue.ink

    /// The lighter stripe running along the top of the progress fill — Duolingo's
    /// "texture". Sampled #5ACD05 → #7ED733, which is white at ~20% over the fill,
    /// so expressing it as an overlay keeps it correct for any fill colour.
    static let fillHighlight = Color.white.opacity(0.20)

    // MARK: - Metrics (points, measured @3x ÷ 3)

    enum Metric {
        /// The reference's corners are measurably CIRCULAR, not squircles. A
        /// `.continuous` corner spreads its curvature over a longer run and never
        /// "completes" as sharply: at 14pt continuous our row was still 1px inset 36px
        /// down the edge, where the reference had reached full width by 30px. Matching
        /// the measured profile means matching the corner *shape*, not just its size —
        /// so this flow uses `.circular` even though the rest of the app is
        /// `.continuous` by house rule.
        static let cornerStyle: RoundedCornerStyle = .circular

        /// Side margin for buttons, rows and cards. Measured 48px ÷ 3.
        static let pageMargin: CGFloat = 16

        /// Primary/secondary button: 48pt overall = 44pt face + 4pt edge.
        static let buttonHeight: CGFloat = 48
        static let buttonFace: CGFloat = 44
        static let buttonEdge: CGFloat = 4
        /// Circular-arc fit to the measured corner profile (S02): inset 11px at 10px
        /// down, 5px at 20px, 3px at 25px → R ≈ 37px ≈ 12.3pt. 12 also happens to be
        /// the app's own `Radius.button`.
        static let buttonRadius: CGFloat = 12

        /// Answer row: 56pt overall = 52pt face + 4pt edge. Pitch measured 68pt,
        /// so the gap between rows is 12pt. Both verified 1:1 against S06.
        static let rowHeight: CGFloat = 56
        static let rowFace: CGFloat = 52
        static let rowEdge: CGFloat = 4
        static let rowGap: CGFloat = 12
        /// Circular-arc fit to S06's measured corner: R ≈ 33px ≈ 11pt.
        static let rowRadius: CGFloat = 11
        static let rowBorder: CGFloat = 2

        /// The icon chip inside a row — the detail that makes a row read "Duolingo".
        /// Measured off S06's flag chip: 41pt wide, inset 17pt from the row's left
        /// edge (= 2pt border + 15pt padding), with a 16.3pt gap before the label.
        static let chipSide: CGFloat = 41
        static let chipRadius: CGFloat = 11
        static let chipGlyph: CGFloat = 22
        static let rowPadding: CGFloat = 17
        static let rowChipGap: CGFloat = 16

        /// Progress bar: 16pt tall capsule. Highlight stripe sits 4pt down from the
        /// fill's top and is 5pt tall (measured 11px / 14px @3x).
        static let progressHeight: CGFloat = 16
        static let progressStripeTop: CGFloat = 4
        static let progressStripeHeight: CGFloat = 5
        static let progressStripeInset: CGFloat = 6

        /// Big option card (S17–S19). Provisional — re-measure against S17 in Phase 3.
        static let cardRadius: CGFloat = 14
        static let cardBorder: CGFloat = 2
        static let cardEdge: CGFloat = 4

        /// Speech bubble. Provisional — re-measure against S05 in Phase 1.
        static let bubbleRadius: CGFloat = 14
        static let bubbleBorder: CGFloat = 2
        static let bubbleTail: CGFloat = 9
    }

    // MARK: - Motion

    enum Motion {
        /// The button's release spring — snaps back over its edge and settles.
        static let press = Animation.spring(response: 0.22, dampingFraction: 0.62)
        /// Progress fill advance, with the overshoot that gives it the pulse.
        static let progress = Animation.spring(response: 0.42, dampingFraction: 0.62)
        /// Check badge pop on multi-select.
        static let badge = Animation.spring(duration: 0.34, bounce: 0.46)
        /// Row/card selection tint change — no bounce, just a clean settle.
        static let select = Animation.smooth(duration: 0.18)
        /// Bubble content swap when the mascot "reacts".
        static let bubbleSwap = Animation.spring(response: 0.36, dampingFraction: 0.82)
        /// Seconds per character in a typing bubble.
        static let typePerChar: Double = 0.03
    }
}
