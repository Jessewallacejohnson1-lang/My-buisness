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

// MARK: - Jost and SF now scale together

//  This file used to freeze Jost here, because `Font.custom(_:size:)` scaled and
//  `Font.system(size:)` did not, so the display face outran the body face beside
//  it — measured on this surface: a 22pt Jost title reached ~55pt inside a 208pt
//  column and truncated mid-word, and the 24pt rail header hit ~53pt, dragging a
//  `.firstTextBaseline`-aligned count 40pt into the descender.
//
//  That containment is gone because the cause is gone. `BlockPartyFont` now scales
//  BOTH faces against a shared text style, so `Font.display(_:)` is what this
//  surface wants and the local `dayDisplay` freeze would only re-break it — it
//  would hold Your Day still while the rest of the app grew.
