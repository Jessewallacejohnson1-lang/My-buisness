//
//  DayNowLine.swift
//  Block Party — where the day has got to.
//
//  The one live thing on the page: an orange rule across the timeline with a dot
//  riding the spine, sitting between the rows that have started and the ones that
//  have not. Its label takes the gutter, in the same column as the clock times, so
//  it reads as another entry on the scale rather than as an annotation floating
//  over the cards.
//
//  The orange is `DaySchedulePalette.now`, which is the same hue as the default
//  category gradient's top stop — the page never carries two oranges.
//

import SwiftUI

struct DayNowLine: View {
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(DayScheduleLogic.nowLabel(now))
                .font(.sansSemibold(11))
                .monospacedDigit()
                .foregroundStyle(DaySchedulePalette.now)
                .lineLimit(1)
                .frame(width: DayScheduleMetrics.gutterWidth, alignment: .trailing)
                .padding(.trailing, DayScheduleMetrics.spineInset)

            Rectangle()
                .fill(DaySchedulePalette.now)
                .frame(height: DayScheduleMetrics.nowLineHeight)
                .overlay(alignment: .leading) {
                    // Centred on the 1pt spine rather than butted against it.
                    Circle()
                        .fill(DaySchedulePalette.now)
                        .frame(
                            width: DayScheduleMetrics.nowDotSize,
                            height: DayScheduleMetrics.nowDotSize
                        )
                        .offset(
                            x: -(DayScheduleMetrics.nowDotSize
                                - DayScheduleMetrics.spineWidth) / 2
                        )
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayScheduleLogic.nowSpoken(now))
    }
}
