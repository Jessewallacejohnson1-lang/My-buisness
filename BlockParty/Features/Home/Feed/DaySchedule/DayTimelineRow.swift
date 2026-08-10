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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
            DayDetailCard(
                item: item,
                isComplete: isComplete,
                stats: stats,
                namespace: namespace,
                morphs: morphs,
                onToggleComplete: onToggleComplete,
                onDetails: onDetails
            )
        }
        // A past row recedes rather than disappears — the day still happened.
        .opacity(state == .completed ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: isComplete ? "Mark not done" : "Mark done", onToggleComplete)
        .accessibilityAction(named: "Details", onDetails)
    }

    // MARK: - The clock scale

    private var gutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let time = DayScheduleLogic.gutterTime(for: item) {
                Text(time.value)
                    .font(.sansSemibold(13))
                    .monospacedDigit()

                if let meridiem = time.meridiem {
                    Text(meridiem)
                        .font(.sansSemibold(13))
                }
            }
        }
        .foregroundStyle(DaySchedulePalette.muted)
        .multilineTextAlignment(.trailing)
        // Nudged down so the numeral's cap height lines up with the eyebrow's,
        // rather than its ascender lining up with the card's top edge.
        .padding(.top, 15)
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
