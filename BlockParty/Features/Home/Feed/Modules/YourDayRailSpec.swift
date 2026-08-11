//
//  YourDayRailSpec.swift
//  Block Party — the Your Day rail's measurements, palette, copy and spoken text.
//
//  Everything here is pure and `nonisolated` so the rail's numbers and strings can
//  be asserted in a plain unit test, and so no view file carries a magic number.
//  The rail replaces a 218 × 208 card with a 236 × 116 one: reclaiming that
//  vertical space is the whole point, so `cardHeight` is a hard ceiling rather
//  than a suggestion — content is cut before the card is allowed to grow.
//

import SwiftUI

// MARK: - Measurements

nonisolated enum YourDayRailMetrics {
    /// The card. 116pt is a CEILING, enforced by a fixed frame: a taller card
    /// would undo the phase.
    static let cardWidth: CGFloat = 236
    static let cardHeight: CGFloat = 116
    static let cardRadius: CGFloat = 16

    /// The category gradient down the leading edge.
    static let accentBarWidth: CGFloat = 6

    /// Card padding. Leading is measured from the accent bar, not the card edge.
    /// On the 4pt grid — 14 was not, and it was the same 14 the day sheet's card
    /// padding used, so both moved to 12 together.
    static let contentLeading: CGFloat = 12
    static let contentTrailing: CGFloat = 16
    static let contentVertical: CGFloat = 12

    /// Minimum gaps inside the card. The leftovers become slack, so a one-line
    /// title still pins its eyebrow to the top and its meta to the bottom.
    /// 8 and 4, not 6 and 4: the pair still steps, and both sit on the grid. The
    /// 4pt reclaimed above pays for the extra 2 here inside the 116pt ceiling.
    static let eyebrowToTitle: CGFloat = 8
    static let titleToMeta: CGFloat = 4

    /// The add tile — narrower than a card because it holds no content, only an
    /// invitation.
    static let addTileWidth: CGFloat = 100
    static let addGlyphSide: CGFloat = 40
    static let addGlyphRadius: CGFloat = 12
    static let addGlyphPointSize: CGFloat = 18
    static let addGlyphToLabel: CGFloat = 8

    /// The rail itself.
    static let pageMargin: CGFloat = 20
    static let cardSpacing: CGFloat = 12
    static let headerToRail: CGFloat = 16
    /// The gap above the section in the feed. Was three separate `22`s — one per
    /// phase branch — which is both off the 4pt grid and three chances to move one
    /// and not the others.
    static let sectionTop: CGFloat = 20

    /// The completed check, top-trailing.
    static let checkPointSize: CGFloat = 16
    static let completedOpacity: Double = 0.55

    /// Borders.
    static let hairlineWidth: CGFloat = 1
    static let suggestedDash: [CGFloat] = [4, 3]

    /// The barely-there lift. A card floats; a whole-town card does not.
    static let shadowOpacity: Double = 0.04
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 2

    /// Press feedback. Driven by a ButtonStyle's `isPressed` — never a card-level
    /// `.gesture`, which claims the touch on press-down and kills the enclosing
    /// ScrollView's pan.
    static let pressScale: CGFloat = 0.97
    static let pressDuration: Double = 0.12
    /// Reduce Motion trades the scale for a dip in value, same as the feed's
    /// shared press style.
    static let pressOpacity: Double = 0.78

    /// Type. The rail's four roles, resolved from the ONE scale both Your Day
    /// surfaces share — see `DayType`. The rail was already right; it is the sheet
    /// that carried a second set of values for the same roles.
    static let headerSize: CGFloat = DayType.sectionHeader
    static let titleSize: CGFloat = DayType.cardTitle
    static let bodySize: CGFloat = DayType.body
    static let tagSize: CGFloat = DayType.statLabel

    static let titleTracking: CGFloat = -0.2
    // The spec's 20pt title line height is not a token because it is not a choice:
    // SF Pro at 17pt already lays out at ~20.3pt naturally. A `lineSpacing` on top
    // of that would push a two-line title past the 116pt ceiling, so the value is
    // met by leaving it alone. (It previously sat here as an unreferenced constant.)

    /// Dynamic Type may not grow the card, so the title gives up its second line
    /// before the layout gives up its ceiling.
    static func titleLineLimit(for size: DynamicTypeSize) -> Int {
        size >= .xxLarge ? 1 : 2
    }
}

// MARK: - Palette

/// ONE warm value the neutral ramp does not already carry. Everything else on the
/// rail resolves to an existing `Hue` token — `ink`, `inkSecondary`, `surface`,
/// `edge` — so the rail cannot drift from the rest of the app.
nonisolated enum YourDayRailPalette {
    /// The add tile's ground. Warmer and a step darker than `Hue.fill`, so an
    /// empty invitation reads as paper rather than as a disabled control.
    static let addTileFill = Color(light: 0xEFEEE8, dark: 0x26261F)

    /// The suggested card's dashed edge. Darker than `Hue.hairline` because a dash
    /// at hairline value disappears — which is exactly what `Hue.edge` is for. It
    /// used to be #D8D6CE written out here AND in the day sheet's palette; one
    /// token, one place.
    static let suggestedBorder = Hue.edge
}

// MARK: - Copy

nonisolated enum YourDayRailCopy {
    static let header = "Your day"
    static let addTile = "Add to today"
    static let suggested = "SUGGESTED"

    static let emptyTitle = "Nothing planned today."
    static let emptyMetaFallback = "See what’s happening in St. Joe →"

    /// `3 things` / `1 thing`, and nothing at all at zero — a count of nought is
    /// not news, and the empty card already says so in words.
    static func countLabel(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "thing" : "things")"
    }

    /// Real data only: a count we do not have is a sentence we do not write.
    static func emptyMeta(townCount: Int?) -> String {
        guard let townCount, townCount > 0 else { return emptyMetaFallback }
        let noun = townCount == 1 ? "thing" : "things"
        return "\(townCount) \(noun) happening in St. Joe →"
    }
}

// MARK: - Spoken text

/// A card is ONE accessibility element. Reading its parts out separately turns a
/// glanceable rail into five swipes per event.
nonisolated enum YourDayRailAccessibility {
    /// e.g. `11 AM, Farmers Market, Music & arts, Resurrection lot, not completed`
    /// — with `on the town calendar` inserted before the completion state when the
    /// item is the town's rather than this neighbour's.
    static func label(for item: DayItem) -> String {
        label(for: item, isComplete: item.isComplete)
    }

    /// The same sentence, with the completion the STORE resolved rather than the
    /// one the clock guessed.
    static func label(for item: DayItem, isComplete: Bool) -> String {
        // `.other` is the absence of a category, not one of them. Unconditionally
        // appending the label made VoiceOver read "11 AM, Farmers Market, Other,
        // Resurrection lot" on every card, since no live row is categorised yet.
        var parts: [String] = [item.eyebrow, item.title]

        if item.event.category != .other {
            parts.append(item.event.category.label)
        }

        if let location = item.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            parts.append(location)
        }

        if item.source == .wholeTown {
            parts.append("on the town calendar")
        }

        parts.append(isComplete ? "completed" : "not completed")
        return parts.joined(separator: ", ")
    }

    /// The rail announces how much is in it before a neighbour starts swiping.
    static func railLabel(count: Int) -> String {
        guard let countLabel = YourDayRailCopy.countLabel(count) else {
            return "\(YourDayRailCopy.header), nothing planned"
        }
        return "\(YourDayRailCopy.header), \(countLabel)"
    }
}
