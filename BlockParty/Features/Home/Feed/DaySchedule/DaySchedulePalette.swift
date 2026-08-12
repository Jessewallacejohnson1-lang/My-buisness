//
//  DaySchedulePalette.swift
//  Block Party — the day sheet's own ink, rules, and measurements.
//
//  THE SHEET NO LONGER HAS ITS OWN RAMP. It used to: a warmer `muted` (#707174)
//  and a warmer `rule` (#E5E3DB), on the theory that the app greys read cold beside
//  six saturated gradients. Measured, the theory did not pay: #707174 is 4.67:1 on
//  paper where `Hue.inkSecondary` is 5.10:1, the two rules differ by 0.6 ΔE — a
//  difference no eye resolves and every screenshot diff does — and #D8D6CE was
//  written out twice, here and in the rail. So every value below now resolves to a
//  `Hue` token, which is what makes the two Your Day surfaces provably the same
//  palette and gets the whole feature dark mode for free.
//

import SwiftUI

/// MainActor-isolated, unlike the metrics below, because it reads `Hue` — which is
/// itself isolated. Only views read these, and views are already on main.
enum DaySchedulePalette {
    /// The page ground behind the timeline — the app's warm white.
    static let page = Hue.paper
    /// A detail card.
    static let card = Hue.surface
    /// Titles, stat values, the filled checkbox, the CTA.
    static let ink = Hue.ink

    /// Eyebrows, gutter times, subtitles, stat labels.
    static let muted = Hue.inkSecondary
    /// The spine and the in-card divider.
    static let rule = Hue.hairline
    /// The now line, its dot, and its label. A DEEPER orange than
    /// `CategoryGradient.eventsFestivals`'s `#E67633` top stop, for two reasons
    /// that turned out to be the same reason. Every uncategorised row maps to
    /// `eventsFestivals`, and today that is every row — so sharing the hue meant
    /// the one live element on the page wore the same colour as every accent bar
    /// and stopped meaning "now". And `#E67633` on paper measures 2.87:1, under
    /// WCAG 1.4.11's 3:1 for a non-text indicator. `#C25A1C` is 3.4:1 and reads as
    /// the same orange family, so the page still carries one orange story.
    static let now = Color(hex: 0xC25A1C)
    /// An unchecked completion box. `Hue.control`, not `Hue.edge`: an empty control
    /// has to clear WCAG 1.4.11's 3:1, and the border it used to wear measured
    /// 1.46:1 on a white card.
    static let checkbox = Hue.control
    /// The ghost buttons' ground. Their outline alone measured 1.29:1, so the
    /// control is identified by a filled ground rather than by a darker hairline.
    static let ghostFill = Hue.fill
}

/// Every measurement the timeline agrees on. The gutter, the 12pt offset, and the
/// spine have to be stated once or the rows drift apart as the card grows.
nonisolated enum DayScheduleMetrics {
    /// ONE page margin for the whole feature. The rail already used 20 and the CTA
    /// already used 20; only the timeline column was on 18, so the sheet's content
    /// and its own button did not line up with each other, let alone with the rail
    /// the sheet grew out of.
    static let pageMargin: CGFloat = YourDayRailMetrics.pageMargin
    /// The clock scale on the left.
    static let gutterWidth: CGFloat = 56
    /// Gap between the gutter's right edge and the spine.
    static let spineInset: CGFloat = 12
    static let spineWidth: CGFloat = 1
    /// Gap between the spine and a detail card.
    static let cardInset: CGFloat = 12

    /// Distance from the content's leading edge to the spine's centre.
    static let spineOffset: CGFloat = gutterWidth + spineInset

    /// SPEC — do not move. The 6pt bar is the continuity between a rail card and a
    /// timeline row, and it is the thing that flies between them.
    static let accentBarWidth: CGFloat = 6

    /// The detail card's own radius, which MUST equal the rail card's.
    ///
    /// It was 20 here and 16 there, so the matched pair interpolated a SHAPE change
    /// on top of a position change: the accent bar's rounded leading corners grew
    /// through the flight and shrank back on the way home. One value, taken from
    /// the rail because the rail's card geometry is spec'd.
    static let cardRadius: CGFloat = YourDayRailMetrics.cardRadius
    /// Padding inside a detail card, and the inset of the completion box from the
    /// card's top-trailing corner. On the 4pt grid, unlike the 14 it replaces.
    static let cardPadding: CGFloat = 12
    /// The gap between rows on the timeline.
    static let rowSpacing: CGFloat = 16

    static let checkboxSize: CGFloat = 28
    static let nowDotSize: CGFloat = 6
    static let nowLineHeight: CGFloat = 1.5

    static let ctaHeight: CGFloat = 56
    static let ctaRadius: CGFloat = 28
    static let ctaMargin: CGFloat = pageMargin
    static let sheetCornerRadius: CGFloat = 20

    /// The band ABOVE the CTA over which the page fades in.
    ///
    /// The gradient used to run across the CTA's own inset and reach full page
    /// colour at its midpoint, ~43pt BEHIND the pill — so content was cut off by a
    /// hard edge level with the button's waist rather than faded out. The ramp now
    /// lives entirely above the button.
    static let ctaScrimFade: CGFloat = 40

    /// Where a tapped item comes to rest: one third down the viewport.
    static let openAnchor = UnitPoint(x: 0, y: 1.0 / 3.0)

    // MARK: - The hand-built `.large` detent
    //
    // A system `.large` sheet rests with its top edge on the presenting view's top
    // SAFE AREA — measured at 62pt on an iPhone 17, which is exactly that device's
    // top inset (screenshot of the old `.sheet` presentation, `refs/your-day/`).
    // The host therefore top-aligns the card inside the safe area and adds nothing;
    // this constant exists so the resting position is a named decision rather than
    // an absent modifier, and so a device whose sheet sits lower can be corrected
    // in one place.

    /// Extra drop below the top safe area at the resting detent.
    static let restingTopInset: CGFloat = 0
    /// The floor for devices with no top inset to rest against.
    static let minimumTopInset: CGFloat = 20

    /// The scrim over the Today tab. Unreachable while this was a `.sheet` — the
    /// system dim is not configurable — and a large part of why the in-hierarchy
    /// route was chosen.
    static let backdropDim: Double = 0.35

    /// The lift under the card's top edge, so it reads as a surface over the town
    /// rather than a panel welded to it.
    static let sheetShadowOpacity: Double = 0.18
    static let sheetShadowRadius: CGFloat = 24
    static let sheetShadowY: CGFloat = -4

    /// The grab strip along the card's top edge. The close button owns the leading
    /// `dragHandleLeading` points of it, so the two never compete for a touch.
    static let dragHandleHeight: CGFloat = 48
    static let dragHandleLeading: CGFloat = 56
}

/// The sheet's motion, in one place so Reduce Motion has a single switch.
nonisolated enum DayScheduleMotion {
    /// The open morph — the rail card's accent bar and title into the timeline row.
    static let open: Animation = .spring(response: 0.42, dampingFraction: 0.86)
    /// The completion checkbox.
    static let check: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    /// What Reduce Motion gets instead of any of the above.
    static let reduced: Animation = .easeInOut(duration: 0.2)
}
