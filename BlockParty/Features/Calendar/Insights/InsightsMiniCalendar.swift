//
//  InsightsMiniCalendar.swift
//  Block Party — the white "Calendar" mini month card for the Insights face.
//
//  Reference-faithful first pass (fixed placeholder content, matched 1:1 to the
//  reference recording). In the resting frames only the header is above the fold
//  (title + weekday row); the full March 2026 grid is rendered so the card reads
//  correctly once scrolled. Real calendar data + navigation are wired in a
//  follow-up. March 1, 2026 falls on a Sunday, so there are no leading blanks.
//

import SwiftUI

struct InsightsMiniCalendar: View {
    // Data-driven month content (defaults reproduce the March 2026 first pass).
    var title: String = "March 2026"
    var leadingBlanks: Int = 0
    var dayCount: Int = 31
    var dayCounts: [Int] = Array(repeating: 0, count: 31)   // per day 1…dayCount; >0 means that day has happenings
    var todayDay: Int? = nil                                 // day-of-month that is "today", if in this month

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private let cardPadding: CGFloat = 18
    private let cellHeight: CGFloat = 40
    private let navDiameter: CGFloat = 34
    private let todayCircleDiameter: CGFloat = 30
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private let dayColor = Hue.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            weekdayRow
            dayGrid
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: InsightsPalette.cardRadius, style: .continuous)
                .fill(InsightsPalette.calendarCard)
        )
        .insightsCardShadow()
    }

    // MARK: - Header (title + tap chevron, and ‹ › month nav)

    private var header: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(InsightsPalette.calendarTitle)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(InsightsPalette.calendarNav)
                .padding(.leading, 5)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                navButton("chevron.left")
                navButton("chevron.right")
            }
        }
    }

    private func navButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(InsightsPalette.calendarNav)
            .frame(width: navDiameter, height: navDiameter)
            .background(
                Circle().fill(InsightsPalette.calendarNav.opacity(0.10))
            )
    }

    // MARK: - Weekday header row

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .medium))
                    .kerning(0.5)
                    .foregroundStyle(InsightsPalette.weekday)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day grid (data-driven month)

    private var dayGrid: some View {
        // Single ForEach over slots (leading blanks + days) avoids LazyVGrid
        // integer-id collisions between the blank range and the day range.
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<(leadingBlanks + dayCount), id: \.self) { slot in
                if slot < leadingBlanks {
                    Color.clear.frame(height: cellHeight)
                } else {
                    dayCell(slot - leadingBlanks + 1)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let hasEvents = day - 1 < dayCounts.count && dayCounts[day - 1] > 0

        if day == todayDay {
            Text("\(day)")
                .font(.system(size: 15, weight: .semibold))
                // `InsightsPalette.todayFill` is `Hue.ink`, which inverts.
                .foregroundStyle(Hue.surface)
                .frame(width: todayCircleDiameter, height: todayCircleDiameter)
                .background(Circle().fill(InsightsPalette.todayFill))
                .frame(maxWidth: .infinity, minHeight: cellHeight)
        } else if hasEvents {
            Text("\(day)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(InsightsPalette.eventDay)
                .frame(maxWidth: .infinity, minHeight: cellHeight)
        } else {
            // Empty days recede to secondary ink. Without an accent colour a weight
            // step alone at 15pt does not separate "has happenings" from "empty",
            // and these cells carry no accessibility label, so VoiceOver cannot
            // recover the distinction either. Mirrors the same fix in CalendarView.
            Text("\(day)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Hue.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: cellHeight)
        }
    }
}

#Preview {
    InsightsMiniCalendar()
        .padding()
        .background(InsightsPalette.canvas)
}
