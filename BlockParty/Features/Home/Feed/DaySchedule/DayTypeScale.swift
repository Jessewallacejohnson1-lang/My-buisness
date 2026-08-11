//
//  DayTypeScale.swift
//  Block Party — the ONE type scale the Your Day rail and the day sheet share.
//
//  The two surfaces are the same feature seen at two sizes, and they were carrying
//  SEVEN sizes between them: 11 / 13 / 15 / 17 / 22 / 24 / 28. Three of those pairs
//  were the same role at two values — eyebrow 13 (rail) vs 15 (sheet), title 17 vs
//  22, section header 24 vs 28 — which is not a scale, it is two scales that were
//  never reconciled. Five sizes, named by ROLE, stated once:
//
//      sectionHeader 24   the "Your day" heading, and the sheet's big date
//      pageTitle     18   the title of a full-width card in the sheet
//      cardTitle     17   the title of a rail card; a stat value; a primary button
//      body          13   eyebrows, subtitles, meta lines, the gutter clock
//      statLabel     11   the tracked all-caps stat labels, the now line
//
//  Anything that wants a sixth size is asking the wrong question.
//

import SwiftUI

nonisolated enum DayType {
    static let sectionHeader: CGFloat = 24
    static let pageTitle: CGFloat = 18
    static let cardTitle: CGFloat = 17
    static let body: CGFloat = 13
    static let statLabel: CGFloat = 11
}

// MARK: - Containment: Jost may not outrun SF

extension Font {
    /// Jost Bold, FROZEN — and this is CONTAINMENT, not an accessibility fix.
    ///
    /// `Font.system(size:)` is a fixed point size and does not scale with Dynamic
    /// Type; `Font.custom(_:size:)` DOES. Every SF helper in `BlockPartyFont` is the
    /// former and every Jost helper is the latter, so at AX5 the display face grows
    /// ~2.4× while the body face beside it does not move at all. Measured on this
    /// surface: the sheet's 22pt Jost title ballooned to ~55pt inside a 208pt column
    /// and truncated MID-WORD, and the rail's 24pt header hit ~53pt, which dragged
    /// the `.firstTextBaseline`-aligned count 40pt down into the descender.
    ///
    /// Freezing Jost puts the two faces back in step. It does NOT make Your Day
    /// legible at AX5 — nothing here grows — and it is deliberately scoped to this
    /// feature: converting `BlockPartyFont`'s SF helpers to scaling metrics is the
    /// real fix, it touches every screen in the app, and it is filed separately.
    static func dayDisplay(_ size: CGFloat) -> Font { .custom(Face.displayBold, fixedSize: size) }

    /// Jost SemiBold, frozen. See `dayDisplay(_:)`.
    static func dayDisplaySemi(_ size: CGFloat) -> Font {
        .custom(Face.displaySemi, fixedSize: size)
    }
}
