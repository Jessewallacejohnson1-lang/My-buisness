//
//  DayTimelineRow.swift
//  Block Party — one row of the day: the clock scale and the card.
//
//  The vertical hairline is NOT drawn here. It runs behind the whole column (see
//  `DayScheduleSheet.spine`) so it stays unbroken through the gaps between rows;
//  a per-row segment would leave a dashed ladder. The row only reserves its width.
//
//  The row is ONE VoiceOver element. A dense card with an eyebrow, a title, a
//  subtitle, two or three stat columns, a checkbox and two buttons is nine stops
//  under a screen reader and one glance under an eye; the fix is to speak the row
//  as a sentence and hand the controls over as custom actions, reachable from the
//  rotor without ever leaving the row.
//

import SwiftUI

struct DayTimelineRow: View {
    let item: DayItem
    let state: DayRowState
    let isComplete: Bool
    let stats: [DayStat]
    let namespace: Namespace.ID
    let morphs: Bool

    let onToggleComplete: () -> Void
    let onDetails: () -> Void

    @Environment(\.openURL) private var openURL

    /// A past row recedes rather than disappears — the day still happened. The
    /// 55% stays (owner's call against the audit's 2.12:1 finding); the one thing
    /// exempted from it is the completion box, which `DayDetailCard` draws over
    /// its own dim.
    private var dims: Bool { state == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Dimmed here rather than on the whole row, so the card can hold back
            // its checkbox. Same value, same trigger — the two halves recede
            // together and the tick does not.
            gutter.opacity(dims ? YourDayRailMetrics.completedOpacity : 1)

            DayDetailCard(
                item: item,
                isComplete: isComplete,
                stats: stats,
                namespace: namespace,
                morphs: morphs,
                dims: dims,
                onToggleComplete: onToggleComplete,
                onDetails: onDetails
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // ALL THREE ACTIONS IN ONE BLOCK. `children: .ignore` publishes nothing the
        // row does not republish, and the row republished only two — so the card's
        // Directions button was unreachable to a screen reader entirely. Declaring
        // them together rather than mixing `.accessibilityActions` with a pair of
        // `.accessibilityAction(named:)` keeps the set and its order unambiguous.
        //
        // Directions is GUARDED on the same URL the button is guarded on: a rotor
        // must never offer an action that does nothing. Both sides read that rule
        // from `DayScheduleLogic`, so they cannot drift apart.
        .accessibilityActions {
            Button(isComplete ? "Mark not done" : "Mark done", action: onToggleComplete)
            if let url = DayScheduleLogic.directionsURL(for: item) {
                Button("Directions") { openURL(url) }
            }
            Button("Details", action: onDetails)
        }
    }

    // MARK: - The clock scale

    private var gutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let time = DayScheduleLogic.gutterTime(for: item) {
                Text(time.value)
                    .font(.sansSemibold(DayType.body))
                    .monospacedDigit()

                if let meridiem = time.meridiem {
                    Text(meridiem)
                        .font(.sansSemibold(DayType.body))
                }
            }
        }
        .foregroundStyle(DaySchedulePalette.muted)
        .multilineTextAlignment(.trailing)
        // The numeral's cap height lines up with the eyebrow's. It used to take an
        // optical nudge (15 against a 14pt card padding) because the two ran at
        // different sizes; on the shared scale they are the same face at the same
        // 13pt, so the alignment is now just the card's own top padding.
        .padding(.top, DayScheduleMetrics.cardPadding)
        .frame(width: DayScheduleMetrics.gutterWidth, alignment: .trailing)
        // The gap to the spine, the spine's own hairline, and the gap to the card.
        .padding(
            .trailing,
            DayScheduleMetrics.spineInset
                + DayScheduleMetrics.spineWidth
                + DayScheduleMetrics.cardInset
        )
    }

    // MARK: - VoiceOver

    private var accessibilityLabel: String {
        let statSentence = stats
            .map { "\($0.label.lowercased()) \($0.value)" }
            .joined(separator: ", ")

        return [
            item.eyebrow,
            item.title,
            DayScheduleLogic.subtitle(for: item),
            statSentence.isEmpty ? nil : statSentence,
            isComplete ? "Done" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}
