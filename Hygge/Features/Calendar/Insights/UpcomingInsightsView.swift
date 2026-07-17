//
//  UpcomingInsightsView.swift
//  Hygge — the Upcoming face of the Calendar tab, a PERSONAL town dashboard whose
//  layout & motion are ported 1:1 from the reference recording but whose content
//  is real, forward-looking, personal calendar data (see InsightsData):
//    · a swipeable spotlight wheel (your event first, then the town's),
//    · "Your Year Ahead" — a 12-month chart of events matching your interests,
//    · a bento of three onboarding-interest categories (tap to expand, doorway
//      into that day's detail),
//    · a mini month grid (neutral dots = town happenings, coral = your days).
//  Countdown framing is reserved for the spotlight; captions stay quiet, forward,
//  and honest — every zero reads as zero.
//

import SwiftUI

struct UpcomingInsightsView: View {
    let data: InsightsData
    /// Opens a given day's detail — routed by CalendarView to the same day sheet
    /// the grid face uses (the interest-bento "Next" doorway calls this).
    var onOpenDay: ((String) -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    section("Coming up") {
                        SpotlightWheel(pages: data.spotlight)
                    }
                    section("At a glance") {
                        VStack(spacing: InsightsPalette.cardGap) {
                            VStack(alignment: .leading, spacing: 6) {
                                EntriesStatCard(line1: "Your Year", line2: "Ahead",
                                                count: data.yearTotal,
                                                monthData: data.months.map { ($0.letter, $0.yours, $0.town) },
                                                markerIndex: data.yearMarkerIndex,
                                                expandable: false)
                                caption(data.yearCaption)
                            }
                            BentoStatGrid(tiles: data.bento, onOpenDay: onOpenDay)
                        }
                    }
                    section("Calendar") {
                        VStack(alignment: .leading, spacing: 6) {
                            InsightsMiniCalendar(title: data.grid.title,
                                                 leadingBlanks: data.grid.leadingBlanks,
                                                 dayCount: data.grid.dayCount,
                                                 dayCounts: data.grid.counts,
                                                 mineDays: data.grid.mineDays,
                                                 todayDay: data.grid.todayDay)
                            caption(data.gridCaption)
                        }
                    }
                    .id("calendar")
                    Color.clear.frame(height: 96)   // clear the tab bar / compose disc
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .background(InsightsPalette.canvas)
            .onAppear { debugScrollIfNeeded(proxy) }
        }
    }

    /// DEBUG-only: `-insights-scroll-calendar` scrolls to the mini-month card on
    /// launch so its two dot kinds can be screenshotted headlessly. No effect in release.
    private func debugScrollIfNeeded(_ proxy: ScrollViewProxy) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-insights-scroll-calendar") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("calendar", anchor: .bottom) }
        }
        #endif
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

    /// A quiet, forward caption under a card — the significance sentence / next-day
    /// line. Never an imperative, never a "missed" count.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.sansMedium(13))
            .foregroundStyle(Hue.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }
}

#if DEBUG
#Preview {
    UpcomingInsightsView(data: .sample)
}
#endif
