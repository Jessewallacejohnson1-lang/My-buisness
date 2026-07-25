//
//  BPIcon.swift
//  Block Party — the row icon chip.
//
//  "The chip is what makes rows read Duolingo — keep it." A lucide line glyph, dark
//  stroke, centred in a light-grey rounded square.
//
//  ICON SOURCE — why these are bundled vectors, not SF Symbols and not a package.
//  The build spec calls for lucide specifically. The repo is SF-Symbols-only and has
//  exactly one SPM dependency (Mapbox), so adding an icon package would be the first
//  non-Mapbox dependency in the project. Instead the 14 glyphs this flow needs are
//  vendored as SVGs under `Assets.xcassets/Lucide/` with `preserves-vector-representation`
//  and template rendering — lucide is ISC-licensed, so vendoring is permitted. No
//  dependency, no rasterisation, and they tint like any SF Symbol.
//
//  To add a glyph: drop `<name>.svg` into a new `Lucide/<name>.imageset` with a
//  Contents.json matching its siblings, then add a case here.
//

import SwiftUI

/// The lucide glyphs vendored for this flow. Raw values are the asset names.
enum BPGlyph: String {
    case house
    case truck
    case graduationCap = "graduation-cap"
    case mapPin = "map-pin"
    case car
    case partyPopper = "party-popper"
    case users
    case newspaper
    case baby
    case megaphone
    case ellipsis
    case calendarCheck = "calendar-check"
    case map
    case calendar
}

/// A lucide glyph, template-rendered so it takes the current foreground style.
struct BPLucide: View {
    let glyph: BPGlyph
    var size: CGFloat = BP.Metric.chipGlyph

    var body: some View {
        Image("Lucide/\(glyph.rawValue)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// The light-grey rounded square that a row's glyph sits in.
struct BPIconChip: View {
    let glyph: BPGlyph
    var tint: Color = BP.ink

    var body: some View {
        RoundedRectangle(cornerRadius: BP.Metric.chipRadius, style: BP.Metric.cornerStyle)
            .fill(BP.chip)
            .frame(width: BP.Metric.chipSide, height: BP.Metric.chipSide)
            .overlay {
                BPLucide(glyph: glyph)
                    .foregroundStyle(tint)
            }
    }
}

/// The ascending-bars glyph for S08's five town-knowledge levels — 1 to 5 bars rising
/// left to right. Drawn rather than vendored: it is a *scale*, so the filled-bar count
/// carries the meaning and no icon set ships five variants of it.
struct BPLevelBars: View {
    /// 1…5 — how many bars are filled.
    let level: Int
    var tint: Color = BP.teal
    var size: CGFloat = BP.Metric.chipGlyph

    private let total = 5

    var body: some View {
        // Chunkier than an even bar/gap split: at size/(2n-1) the bars came out ~2.4pt
        // wide and read as hairlines next to the reference's solid ramp.
        let barW = size * 0.148
        let gap = (size - barW * CGFloat(total)) / CGFloat(total - 1)
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(0 ..< total, id: \.self) { i in
                let frac = CGFloat(i + 1) / CGFloat(total)
                Capsule(style: BP.Metric.cornerStyle)
                    .fill(i < level ? tint : tint.opacity(0.30))
                    .frame(width: barW, height: size * frac)
            }
        }
        .frame(width: size, height: size, alignment: .bottom)
    }
}

/// A row chip holding the level bars instead of a lucide glyph.
struct BPLevelChip: View {
    let level: Int

    var body: some View {
        RoundedRectangle(cornerRadius: BP.Metric.chipRadius, style: BP.Metric.cornerStyle)
            .fill(BP.chip)
            .frame(width: BP.Metric.chipSide, height: BP.Metric.chipSide)
            .overlay { BPLevelBars(level: level) }
    }
}
