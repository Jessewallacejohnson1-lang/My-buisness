//
//  YourDayCard.swift
//  Block Party — the compact Your Day card and its three siblings.
//
//  236 × 116, down from 218 × 208. The card carries four facts and stops: when,
//  what, where, and whose day it belongs to. The height is a fixed frame rather
//  than an intrinsic one, so Dynamic Type cannot grow the rail — the title gives
//  up its second line first.
//
//  WHOLE-TOWN MARKING. A town-calendar item and a personal commitment must never
//  read alike. Three signals, all reinforcing, none of them a new type size or a
//  new colour:
//    1. VALUE — the category gradient runs at 45% on a town item and full strength
//       on a commitment. The leading edge is the first thing the eye meets in a
//       rail, so a pastel bar vs a saturated one separates the two lanes before a
//       single word is read.
//    2. ELEVATION — a commitment floats (the 4% shadow); a town item sits flat
//       behind a hairline. Fill-vs-outline is the house device for state pairs.
//    3. A WORD — `Town` in ink after the eyebrow, at the eyebrow's own 13pt.
//       Emphasis is bold ink, never a colour change, and a literal reader (and
//       VoiceOver) gets an unambiguous answer rather than a visual hint.
//  The dashed border is deliberately NOT used here — it is spoken for by
//  SUGGESTED, which means something else.
//

import SwiftUI

private typealias M = YourDayRailMetrics

// MARK: - The card

struct YourDayCard: View {
    let item: DayItem
    let namespace: Namespace.ID
    /// Whether this card holds the accent-bar/title half of the matched pair. See
    /// `YourDayRail.morphs` — it is withdrawn while the day sheet has them.
    var morphs = false
    let onOpenDay: (DayItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isWholeTown: Bool { item.source == .wholeTown }

    var body: some View {
        // A Button, never a card-level `.gesture`: a whole-card gesture claims the
        // touch on press-down and out-competes the enclosing ScrollView's pan,
        // which once shipped as "the feed only scrolls at the top".
        Button { onOpenDay(item) } label: { card }
            .buttonStyle(YourDayPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(YourDayRailAccessibility.label(for: item))
            .accessibilityHint("Opens your day")
    }

    private var card: some View {
        HStack(spacing: 0) {
            accentBar
            content
        }
        .frame(width: M.cardWidth, height: M.cardHeight)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: M.cardRadius, style: .continuous))
        .overlay { if isWholeTown { hairline } }
        .shadow(
            color: .black.opacity(isWholeTown ? 0 : M.shadowOpacity),
            radius: M.shadowRadius,
            x: 0,
            y: M.shadowY
        )
        .opacity(item.isComplete ? M.completedOpacity : 1)
        // Applied over the dim, not inside it: the check is the reason the card
        // receded, so it is the one mark that must not recede with it.
        .overlay(alignment: .topTrailing) { if item.isComplete { completedCheck } }
    }

    /// Rounded on the card's leading corners only, so the bar reads as part of the
    /// card's edge rather than as a chip sitting on it.
    private var accentBar: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: M.cardRadius,
            bottomLeadingRadius: M.cardRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(CategoryGradient.of(item.event.category).linear)
        .opacity(isWholeTown ? 0.45 : 1)
        .frame(width: M.accentBarWidth)
        // The id comes from the sheet so there is ONE spelling of the contract.
        .modifier(
            DayMatchedElement(
                id: DayScheduleSheet.accentID(item.id),
                namespace: namespace,
                active: morphs
            )
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            Spacer(minLength: M.eyebrowToTitle)
            title
            Spacer(minLength: M.titleToMeta)
            meta
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, M.contentLeading)
        .padding(.trailing, M.contentTrailing)
        .padding(.vertical, M.contentVertical)
    }

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Text(item.eyebrow)
                .foregroundStyle(Hue.inkSecondary)

            if isWholeTown {
                Text("·").foregroundStyle(Hue.inkSecondary)
                Text("Town").foregroundStyle(Hue.ink)
            }
        }
        .font(.sansSemibold(M.bodySize))
        .lineLimit(1)
    }

    private var title: some View {
        Text(item.title)
            .font(.sansBold(M.titleSize))
            .tracking(M.titleTracking)
            .foregroundStyle(Hue.ink)
            .lineLimit(M.titleLineLimit(for: dynamicTypeSize))
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(
                DayMatchedElement(
                    id: DayScheduleSheet.titleID(item.id),
                    namespace: namespace,
                    active: morphs
                )
            )
    }

    /// Absent, not blank: an empty `Text` still claims its line box, so a card with
    /// no place and no category would hold a 13pt gap where a fact should be.
    @ViewBuilder
    private var meta: some View {
        if !metaText.isEmpty {
            Text(metaText)
                .font(.sans(M.bodySize))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The place if we have one, else the category. Never "Location TBD" — a blank
    /// location is a fact we do not have.
    ///
    /// `.other` is not a category, it is the absence of one, so it never prints:
    /// every live row is currently uncategorised, and the fallback was rendering
    /// the literal word "Other" as the meta line on every card. `DayScheduleLogic`
    /// already refused to print it for the same reason; the two surfaces now agree.
    private var metaText: String {
        let location = item.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let location, !location.isEmpty { return location }
        return item.event.category == .other ? "" : item.event.category.label
    }

    private var completedCheck: some View {
        Image(systemName: "checkmark")
            .font(.system(size: M.checkPointSize, weight: .semibold))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.top, M.contentVertical)
            .padding(.trailing, M.contentTrailing)
    }

    private var hairline: some View {
        RoundedRectangle(cornerRadius: M.cardRadius, style: .continuous)
            .strokeBorder(Hue.hairline, lineWidth: M.hairlineWidth)
    }
}

// MARK: - The suggested card

/// Shown only beside a lone commitment. Dashed, unfilled and gradient-less: it is
/// on today's calendar but it is not yet anybody's plan, and it must not be able
/// to pass for one.
struct YourDaySuggestedCard: View {
    let item: DayItem
    let onOpenDay: (DayItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button { onOpenDay(item) } label: { card }
            .buttonStyle(YourDayPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Suggested, \(YourDayRailAccessibility.label(for: item))")
            .accessibilityHint("Opens this suggestion")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(YourDayRailCopy.suggested)
                .font(.sansSemibold(M.tagSize))
                .kerning(0.6)
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)

            Spacer(minLength: M.eyebrowToTitle)

            Text(item.title)
                .font(.sansBold(M.titleSize))
                .tracking(M.titleTracking)
                .foregroundStyle(Hue.ink)
                .lineLimit(M.titleLineLimit(for: dynamicTypeSize))
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: M.titleToMeta)

            Text(item.eyebrow)
                .font(.sans(M.bodySize))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Text lines up with the real cards': their leading padding is measured
        // from the accent bar, and this card has none.
        .padding(.leading, M.contentLeading + M.accentBarWidth)
        .padding(.trailing, M.contentTrailing)
        .padding(.vertical, M.contentVertical)
        .frame(width: M.cardWidth, height: M.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: M.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: M.cardRadius, style: .continuous)
                .strokeBorder(
                    YourDayRailPalette.suggestedBorder,
                    style: StrokeStyle(lineWidth: M.hairlineWidth, dash: M.suggestedDash)
                )
        }
    }
}

// MARK: - The add tile

/// Always last in the rail, never first — the invitation follows the day, it does
/// not introduce it.
struct YourDayAddTile: View {
    let onAdd: () -> Void

    var body: some View {
        // No haptic here — `YourDayPressStyle` already fires one on press-down, and
        // firing again on tap-up reads as a stutter.
        Button(action: onAdd) {
            VStack(spacing: M.addGlyphToLabel) {
                RoundedRectangle(cornerRadius: M.addGlyphRadius, style: .continuous)
                    .fill(Hue.ink)
                    .frame(width: M.addGlyphSide, height: M.addGlyphSide)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: M.addGlyphPointSize, weight: .semibold))
                            .foregroundStyle(Hue.surface)
                    }

                Text(YourDayRailCopy.addTile)
                    .font(.sansMedium(M.bodySize))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .frame(width: M.addTileWidth, height: M.cardHeight)
            .background(
                YourDayRailPalette.addTileFill,
                in: RoundedRectangle(cornerRadius: M.cardRadius, style: .continuous)
            )
        }
        .buttonStyle(YourDayPressStyle())
        .accessibilityLabel(YourDayRailCopy.addTile)
    }
}

// MARK: - The empty card

/// The zero state, and — with the town calendar carrying nothing dated today —
/// the state a real neighbour actually sees. Full width, still 116pt, still a
/// card: an empty day is not a broken one.
struct YourDayEmptyCard: View {
    let townCount: Int?
    let onExplore: () -> Void

    var body: some View {
        Button(action: onExplore) {
            HStack(spacing: 0) {
                UnevenRoundedRectangle(
                    topLeadingRadius: M.cardRadius,
                    bottomLeadingRadius: M.cardRadius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(CategoryGradient.civicTown.linear)
                .frame(width: M.accentBarWidth)

                VStack(alignment: .leading, spacing: M.titleToMeta) {
                    Text(YourDayRailCopy.emptyTitle)
                        .font(.sansBold(M.titleSize))
                        .tracking(M.titleTracking)
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)

                    Text(YourDayRailCopy.emptyMeta(townCount: townCount))
                        .font(.sans(M.bodySize))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, M.contentLeading)
                .padding(.trailing, M.contentTrailing)
                .padding(.vertical, M.contentVertical)
            }
            .frame(maxWidth: .infinity)
            .frame(height: M.cardHeight)
            .background(Hue.surface)
            .clipShape(RoundedRectangle(cornerRadius: M.cardRadius, style: .continuous))
            .shadow(
                color: .black.opacity(M.shadowOpacity),
                radius: M.shadowRadius,
                x: 0,
                y: M.shadowY
            )
        }
        .buttonStyle(YourDayPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(YourDayRailCopy.emptyTitle) \(YourDayRailCopy.emptyMeta(townCount: townCount))"
        )
        .accessibilityHint("Opens today in Activities")
    }
}

// MARK: - Press

/// Scale 0.97 over 0.12s, and a light tap on press-DOWN. Driven by a ButtonStyle's
/// `isPressed` so it composes with the ScrollView's pan instead of fighting it.
struct YourDayPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(configuration.isPressed))
            .opacity(opacity(configuration.isPressed))
            .animation(.easeOut(duration: M.pressDuration), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.light() }
            }
    }

    private func scale(_ isPressed: Bool) -> CGFloat {
        guard !reduceMotion, isPressed else { return 1 }
        return M.pressScale
    }

    /// Reduce Motion trades the scale for a dip in value — the same information,
    /// carried by a fade.
    private func opacity(_ isPressed: Bool) -> Double {
        guard reduceMotion, isPressed else { return 1 }
        return M.pressOpacity
    }
}
