//
//  InsightsMiniCalendar.swift
//  Hygge — the white "Calendar" mini month card for the Insights face.
//
//  Reference-faithful first pass (fixed placeholder content, matched 1:1 to the
//  reference recording). In the resting frames only the header is above the fold
//  (title + weekday row); the full March 2026 grid is rendered so the card reads
//  correctly once scrolled. Real calendar data + navigation are wired in a
//  follow-up. March 1, 2026 falls on a Sunday, so there are no leading blanks.
//

import SwiftUI

struct InsightsMiniCalendar: View {
    // Fixed placeholder content, sampled from the reference frame.
    private let title = "March 2026"
    private let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private let dayCount = 31          // March
    private let leadingBlanks = 0      // March 1, 2026 is a Sunday

    private let cardPadding: CGFloat = 18
    private let cellHeight: CGFloat = 40
    private let navDiameter: CGFloat = 34
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private let dayColor = Color(hex: 0x3A3A42)

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

    // MARK: - Day grid (1…31)

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: cellHeight)
            }
            ForEach(1...dayCount, id: \.self) { day in
                Text("\(day)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(dayColor)
                    .frame(maxWidth: .infinity, minHeight: cellHeight)
            }
        }
    }
}

#Preview {
    InsightsMiniCalendar()
        .padding()
        .background(InsightsPalette.canvas)
}
