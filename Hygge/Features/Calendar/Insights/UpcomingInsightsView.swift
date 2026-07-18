//
//  UpcomingInsightsView.swift
//  Hygge — the Upcoming face of the Calendar tab, an "Insights" dashboard whose
//  layout & motion are ported 1:1 from a reference recording but whose content
//  is real forward-looking town-calendar data (see InsightsData): how soon the
//  next happening is, the year-ahead distribution, near-term windows, and the
//  live current-month grid.
//

import SwiftUI

struct UpcomingInsightsView: View {
    let data: InsightsData

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                section("Coming up") {
                    StreakHeroCard(title: "Up Next", value: data.heroValue,
                                   unit: data.heroUnit, subtitle: data.heroSubtitle)
                }
                section("At a glance") {
                    VStack(spacing: InsightsPalette.cardGap) {
                        EntriesStatCard(line1: "The Year", line2: "Ahead",
                                        count: data.entriesTotal,
                                        monthData: data.months.map { ($0.letter, $0.count) },
                                        markerIndex: 0, expandable: false)
                        BentoStatGrid(stats: data.bento)
                    }
                }
                section("Calendar") {
                    InsightsMiniCalendar(title: data.grid.title,
                                         leadingBlanks: data.grid.leadingBlanks,
                                         dayCount: data.grid.dayCount,
                                         dayCounts: data.grid.counts,
                                         todayDay: data.grid.todayDay)
                }
                Color.clear.frame(height: 96)   // clear the tab bar / compose disc
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .background(InsightsPalette.canvas)
    }

    /// A gray section label with its content below.
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.sansMedium(14))
                .foregroundStyle(InsightsPalette.sectionLabel)
            content()
        }
    }
}

#Preview {
    UpcomingInsightsView(data: .sample)
}
