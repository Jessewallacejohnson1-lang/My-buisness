//
//  UpcomingInsightsView.swift
//  Hygge — the Upcoming face of the Calendar tab, rebuilt as an "Insights"
//  dashboard ported 1:1 from a reference recording (streak hero · stats
//  entries + bento · month calendar). FIRST pass = reference placeholder
//  content matched frame-by-frame; real calendar data is wired in a follow-up.
//

import SwiftUI

struct UpcomingInsightsView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                section("Streaks") {
                    StreakHeroCard()
                }
                section("Stats") {
                    VStack(spacing: InsightsPalette.cardGap) {
                        EntriesStatCard()
                        BentoStatGrid()
                    }
                }
                section("Calendar") {
                    InsightsMiniCalendar()
                }
                Color.clear.frame(height: 96)   // clear the tab bar / compose disc
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .background(InsightsPalette.canvas)
    }

    /// A gray section label with its content below — "Streaks" / "Stats" / "Calendar".
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
    UpcomingInsightsView()
}
