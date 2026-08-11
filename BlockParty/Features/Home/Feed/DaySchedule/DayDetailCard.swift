//
//  DayDetailCard.swift
//  Block Party — one thing in the neighbour's day, at full size.
//
//  The card carries the SAME category gradient as its rail card, as a 6pt bar down
//  the leading edge. That bar is the continuity between the two views: the terse
//  rail card and this one are visibly the same object, so opening the sheet reads
//  as growing a card rather than arriving somewhere new.
//
//  Everything below the title is conditional. See `DayScheduleLogic.stats` for why
//  a one-column stat row is the normal case rather than a degraded one.
//

import SwiftUI
import UIKit

struct DayDetailCard: View {
    let item: DayItem
    let isComplete: Bool
    let stats: [DayStat]
    /// The rail's namespace. The accent bar and title carry the agreed ids so the
    /// tapped card morphs into this row.
    let namespace: Namespace.ID
    let morphs: Bool
    /// Whether this row is receding because it is over. The card dims; the
    /// completion box does NOT — see `body`.
    var dims = false

    let onToggleComplete: () -> Void
    let onDetails: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isPressed = false

    private var radius: CGFloat { DayScheduleMetrics.cardRadius }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            accentBar
            content
        }
        // The whole card answers a touch. It used to be dead: only the checkbox and
        // the two ghost buttons were hit targets, so the obvious gesture — tap the
        // thing — did nothing. A BUTTON behind the content, never a card-level
        // `.gesture`, which claims the touch on press-down and out-competes the
        // timeline's scroll (the CLAUDE.md rule that already shipped once as "the
        // feed only scrolls at the top"). It sits between the ground and the
        // content so the checkbox and the ghost buttons still win their own taps.
        .background { openTapTarget }
        // The ground is clipped, the CARD is not. A card-level `.clipShape` looks
        // identical at rest and costs the whole morph: the accent bar's matched
        // frame starts at the rail card, far outside these bounds, so the clip ate
        // every frame of the flight and the bar simply appeared at its destination.
        // The bar now carries its own rounded leading corners instead (below), and
        // nothing else here draws outside the card.
        .background(
            DaySchedulePalette.card,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DaySchedulePalette.rule, lineWidth: 1)
        }
        .modifier(CardShadow())
        .opacity(dims ? YourDayRailMetrics.completedOpacity : 1)
        // APPLIED OVER THE DIM, exactly as the rail applies its checkmark: the tick
        // is the reason the row receded, so it is the one mark that must not recede
        // with it. Dimmed to #797978 the box read as DISABLED rather than as done.
        .overlay(alignment: .topTrailing) {
            DayCompletionBox(isComplete: isComplete, action: onToggleComplete)
                .padding(DayScheduleMetrics.cardPadding)
        }
        // Press feedback is a dip in VALUE, not the rail's 0.97 scale. The accent
        // bar inside this card holds a live `matchedGeometryEffect`; a transform on
        // one of its ancestors is the one kind of press effect that could feed the
        // namespace a frame it did not expect, and the morph is not worth 0.03 of
        // scale. Applied last so the whole card — checkbox included — answers.
        .opacity(isPressed ? YourDayRailMetrics.pressOpacity : 1)
        .animation(.easeOut(duration: YourDayRailMetrics.pressDuration), value: isPressed)
    }

    /// The card-body tap. Labelled `Color.clear` rather than a shape so it inherits
    /// the card's exact frame, and hidden from VoiceOver because the row already
    /// republishes "Details" as a custom action.
    private var openTapTarget: some View {
        Button(action: onDetails) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(DayCardPressStyle(isPressed: $isPressed))
        .accessibilityHidden(true)
    }

    // MARK: - The category spine

    private var accentBar: some View {
        CategoryGradient.of(item.event.category).linear
            .frame(width: DayScheduleMetrics.accentBarWidth)
            .frame(maxHeight: .infinity)
            // Its own leading corners, so it can be drawn outside the card's ground
            // while it is in flight and still sit flush in the card at rest. Same
            // shape the rail card's bar carries, which is what it flies from.
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: radius,
                    bottomLeadingRadius: radius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .modifier(
                DayMatchedElement(
                    id: DayScheduleSheet.accentID(item.id),
                    namespace: namespace,
                    active: morphs
                )
            )
    }

    // MARK: - Everything else

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.eyebrow)
                        .font(.sansSemibold(DayType.body))
                        .foregroundStyle(DaySchedulePalette.muted)
                        .monospacedDigit()

                    Text(item.title)
                        .font(.dayDisplay(DayType.pageTitle))
                        .foregroundStyle(DaySchedulePalette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(
                            DayMatchedElement(
                                id: DayScheduleSheet.titleID(item.id),
                                namespace: namespace,
                                active: morphs
                            )
                        )

                    if let subtitle = DayScheduleLogic.subtitle(for: item) {
                        Text(subtitle)
                            .font(.sans(DayType.body))
                            .foregroundStyle(DaySchedulePalette.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The completion box is drawn by `body`, OVER the completed dim.
                // This is the hole it sits in, so the title still wraps clear of it.
                Color.clear
                    .frame(
                        width: DayScheduleMetrics.checkboxSize,
                        height: DayScheduleMetrics.checkboxSize
                    )
            }
            // Text does not eat the card-body tap. Without this the eyebrow, the
            // title and the subtitle would each swallow a touch and do nothing —
            // the same dead card in three smaller pieces.
            .allowsHitTesting(false)

            if !stats.isEmpty {
                Rectangle()
                    .fill(DaySchedulePalette.rule)
                    .frame(height: 1)
                    .padding(.top, DayScheduleMetrics.cardPadding)
                    .allowsHitTesting(false)

                DayStatRow(stats: stats)
                    .padding(.top, DayScheduleMetrics.cardPadding)
                    .allowsHitTesting(false)
            }

            DayCardActions(
                directionsURL: DayScheduleLogic.directionsURL(for: item),
                onDirections: { url in openURL(url) },
                onDetails: onDetails
            )
            .padding(.top, DayScheduleMetrics.cardPadding)
        }
        .padding(DayScheduleMetrics.cardPadding)
    }
}

// MARK: - Stat row

/// Whatever columns survived, spread across the card. One survivor takes the whole
/// width; there is no empty seat where a suppressed column would have been.
private struct DayStatRow: View {
    let stats: [DayStat]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.label)
                        .font(.sansSemibold(DayType.statLabel))
                        .tracking(0.6)
                        .foregroundStyle(DaySchedulePalette.muted)

                    Text(stat.value)
                        .font(.sansBold(DayType.cardTitle))
                        .foregroundStyle(DaySchedulePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Completion

/// A rounded square, never a circle — the house shape for anything tappable.
private struct DayCompletionBox: View {
    let isComplete: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            DayScheduleHaptics.medium()
            withAnimation(reduceMotion ? DayScheduleMotion.reduced : DayScheduleMotion.check) {
                action()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isComplete ? DaySchedulePalette.ink : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isComplete ? .clear : DaySchedulePalette.checkbox,
                                lineWidth: 1.5
                            )
                    }

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DaySchedulePalette.card)
                    .opacity(isComplete ? 1 : 0)
                    .scaleEffect(isComplete ? 1 : 0.6)
            }
            .frame(
                width: DayScheduleMetrics.checkboxSize,
                height: DayScheduleMetrics.checkboxSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isComplete ? "Done" : "Mark done")
        .accessibilityAddTraits(isComplete ? [.isSelected] : [])
    }
}

// MARK: - Actions

/// Two buttons. Directions disappears rather than greying out when the row never
/// named a place.
///
/// NO LONGER GHOSTS. An outline-only control has to carry 3:1 on its boundary to
/// satisfy WCAG 1.4.11, and #E5E3DB on a white card measured 1.29:1 — so the button
/// was, non-textually, invisible. Darkening the outline to compliance would have
/// put two heavy rules at the foot of every card; a `Hue.fill` ground identifies
/// the control by AREA instead, which is the quieter half of the house's
/// fill-vs-outline pair and does not add a line to the page.
private struct DayCardActions: View {
    let directionsURL: URL?
    let onDirections: (URL) -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let url = directionsURL {
                button("Directions") { onDirections(url) }
            }
            button("Details", action: onDetails)
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(.sansMedium(DayType.body))
                .foregroundStyle(DaySchedulePalette.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(
                    DaySchedulePalette.ghostFill,
                    in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .strokeBorder(DaySchedulePalette.rule, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardPressStyle())
    }
}

// MARK: - Press

/// Reports a press up to the card without drawing anything itself.
///
/// A `ButtonStyle`'s `isPressed` is the only sanctioned way to get press feedback
/// on a scrollable cell here — a card-level `.gesture` claims the touch on
/// press-down and kills the enclosing scroll. The style is a reporter rather than a
/// renderer because the thing that should react is the whole card, and the button
/// is only the transparent layer behind it.
struct DayCardPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
                if pressed { Haptics.light() }
            }
    }
}

// MARK: - Matched geometry

/// Applies the rail's agreed matched-geometry id, and applies NOTHING under Reduce
/// Motion — the spec's cross-fade must not carry a geometry morph with it.
struct DayMatchedElement: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Haptics

/// The medium impact the completion control asks for. `Haptics` holds light,
/// selection, success and error; adding a fifth generator there would touch a file
/// this change does not own, so the one extra generator lives beside its one
/// caller — held once and prepared, exactly like the shared ones.
@MainActor
enum DayScheduleHaptics {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)

    static func medium() {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        impact.impactOccurred()
        impact.prepare()
    }
}
