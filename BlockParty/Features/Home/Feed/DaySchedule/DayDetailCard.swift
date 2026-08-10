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

    let onToggleComplete: () -> Void
    let onDetails: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            accentBar
            content
        }
        // The ground is clipped, the CARD is not. A card-level `.clipShape` looks
        // identical at rest and costs the whole morph: the accent bar's matched
        // frame starts at the rail card, far outside these bounds, so the clip ate
        // every frame of the flight and the bar simply appeared at its destination.
        // The bar now carries its own rounded leading corners instead (below), and
        // nothing else here draws outside the card.
        .background(
            DaySchedulePalette.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(DaySchedulePalette.rule, lineWidth: 1)
        }
        .modifier(CardShadow())
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
                    topLeadingRadius: Radius.card,
                    bottomLeadingRadius: Radius.card,
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
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.eyebrow)
                        .font(.sansSemibold(15))
                        .foregroundStyle(DaySchedulePalette.muted)
                        .monospacedDigit()

                    Text(item.title)
                        .font(.display(22))
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
                            .font(.sans(15))
                            .foregroundStyle(DaySchedulePalette.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DayCompletionBox(isComplete: isComplete, action: onToggleComplete)
            }

            if !stats.isEmpty {
                Rectangle()
                    .fill(DaySchedulePalette.rule)
                    .frame(height: 1)
                    .padding(.top, 14)

                DayStatRow(stats: stats)
                    .padding(.top, 12)
            }

            DayCardActions(
                directionsURL: directionsURL,
                onDirections: { url in openURL(url) },
                onDetails: onDetails
            )
            .padding(.top, 14)
        }
        .padding(14)
    }

    /// Only when the row actually names a place. There is no coordinate on an
    /// event, so this is a text search against the town — good enough to open the
    /// right pin, and honest about being a search.
    private var directionsURL: URL? {
        guard let location = item.location, !location.isEmpty else { return nil }
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(location), \(Town.display)")]
        return components?.url
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.label)
                        .font(.sansSemibold(11))
                        .tracking(0.6)
                        .foregroundStyle(DaySchedulePalette.muted)

                    Text(stat.value)
                        .font(.sansBold(17))
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

/// Two ghost buttons. Directions disappears rather than greying out when the row
/// never named a place.
private struct DayCardActions: View {
    let directionsURL: URL?
    let onDirections: (URL) -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let url = directionsURL {
                ghost("Directions") { onDirections(url) }
            }
            ghost("Details", action: onDetails)
        }
    }

    private func ghost(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(.sansMedium(15))
                .foregroundStyle(DaySchedulePalette.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .strokeBorder(DaySchedulePalette.rule, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardPressStyle())
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
