//
//  DaySchedulePalette.swift
//  Block Party — the day sheet's own ink, rules, and measurements.
//
//  The sheet runs a slightly warmer, paler neutral ramp than the app chrome: its
//  greys sit against six saturated category gradients rather than against bare
//  paper, and `Hue.hairline` / `Hue.inkSecondary` read a shade cold beside them.
//  These are the spec's values, named here ONCE so no view carries a raw hex —
//  the same rule `BlockPartyColor` enforces for the app tokens.
//
//  Anything the app ramp already gets right (`Hue.paper`, `Hue.surface`,
//  `Hue.ink`) is referenced, not re-stated, so a token change still reaches here.
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

    /// Eyebrows, gutter times, subtitles, stat labels. Warmer and one step
    /// lighter than `Hue.inkSecondary`, which goes muddy next to the gradients.
    static let muted = Color(hex: 0x707174)
    /// The spine and the in-card divider.
    static let rule = Color(hex: 0xE5E3DB)
    /// The now line, its dot, and its label. Deliberately the SAME orange as
    /// `CategoryGradient.eventsFestivals`'s top stop: "right now" and "the town's
    /// default event colour" are one hue, so the page never carries two oranges.
    static let now = Color(hex: 0xE67633)
    /// An unchecked completion box.
    static let checkbox = Color(hex: 0xD8D6CE)
}

/// Every measurement the timeline agrees on. The gutter, the 12pt offset, and the
/// spine have to be stated once or the rows drift apart as the card grows.
nonisolated enum DayScheduleMetrics {
    /// Page margin, matching the Today feed's own 18pt column.
    static let pageMargin: CGFloat = 18
    /// The clock scale on the left.
    static let gutterWidth: CGFloat = 56
    /// Gap between the gutter's right edge and the spine.
    static let spineInset: CGFloat = 12
    static let spineWidth: CGFloat = 1
    /// Gap between the spine and a detail card.
    static let cardInset: CGFloat = 14

    /// Distance from the content's leading edge to the spine's centre.
    static let spineOffset: CGFloat = gutterWidth + spineInset

    static let accentBarWidth: CGFloat = 6
    static let checkboxSize: CGFloat = 28
    static let nowDotSize: CGFloat = 6
    static let nowLineHeight: CGFloat = 1.5

    static let ctaHeight: CGFloat = 56
    static let ctaRadius: CGFloat = 28
    static let ctaMargin: CGFloat = 20
    static let sheetCornerRadius: CGFloat = 20

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
