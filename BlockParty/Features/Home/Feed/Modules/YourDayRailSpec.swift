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
    static let contentLeading: CGFloat = 14
    static let contentTrailing: CGFloat = 16
    static let contentVertical: CGFloat = 14

    /// Minimum gaps inside the card. The leftovers become slack, so a one-line
    /// title still pins its eyebrow to the top and its meta to the bottom.
    static let eyebrowToTitle: CGFloat = 6
    static let titleToMeta: CGFloat = 4

    /// The add tile — narrower than a card because it holds no content, only an
    /// invitation.
    static let addTileWidth: CGFloat = 100
    static let addGlyphSide: CGFloat = 40
    static let addGlyphRadius: CGFloat = 12
    static let addGlyphPointSize: CGFloat = 18
    static let addGlyphToLabel: CGFloat = 10

    /// The rail itself.
    static let pageMargin: CGFloat = 20
    static let cardSpacing: CGFloat = 12
    static let headerToRail: CGFloat = 16

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

    /// Type. Four sizes, and deliberately no fifth.
    static let headerSize: CGFloat = 24
    static let titleSize: CGFloat = 17
    static let bodySize: CGFloat = 13
    static let tagSize: CGFloat = 11

    static let titleTracking: CGFloat = -0.2
    static let titleLineHeight: CGFloat = 20

    /// Dynamic Type may not grow the card, so the title gives up its second line
    /// before the layout gives up its ceiling.
    static func titleLineLimit(for size: DynamicTypeSize) -> Int {
        size >= .xxLarge ? 1 : 2
    }
}

// MARK: - Palette

/// Two warm values the neutral ramp does not already carry. Everything else on
/// the rail resolves to an existing `Hue` token — `ink`, `inkSecondary`,
/// `surface` — so the rail cannot drift from the rest of the app.
nonisolated enum YourDayRailPalette {
    /// The add tile's ground. Warmer and a step darker than `Hue.fill`, so an
    /// empty invitation reads as paper rather than as a disabled control.
    static let addTileFill = Color(hex: 0xEFEEE8)

    /// The suggested card's dashed edge. Darker than `Hue.hairline` because a
    /// dash at hairline value disappears.
    static let suggestedBorder = Color(hex: 0xD8D6CE)
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
        var parts: [String] = [item.eyebrow, item.title, item.event.category.label]

        if let location = item.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            parts.append(location)
        }

        if item.source == .wholeTown {
            parts.append("on the town calendar")
        }

        parts.append(item.isComplete ? "completed" : "not completed")
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
