//
//  CalendarView.swift
//  Hygge — month grid with real event dots; tap a day for its events.
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = CalendarModel()
    @State private var selectedDate: String?

    private let cal = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("What's coming up?")
                    .font(.display(28))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, 8)

                monthCard
                    .hyggeCard(padding: 16)

                Text("Tap a day to see what's happening.")
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink3)

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 18)
        }
        .background(Hue.canvas)
        .task { await model.loadMonth(api, year: year, month: month) }
        .sheet(item: Binding(get: { selectedDate.map { DayKey(date: $0) } },
                             set: { selectedDate = $0?.date })) { key in
            DaySheet(date: key.date, events: model.dayEvents, loading: model.loadingDay)
        }
    }

    private var monthCard: some View {
        VStack(spacing: 14) {
            Text(monthTitle)
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.mono(11)).foregroundStyle(Hue.ink3).frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(1...daysInMonth, id: \.self) { day in dayCell(day) }
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let ymd = String(format: "%04d-%02d-%02d", year, month, day)
        let isToday = day == todayDay
        let hasEvents = (model.counts[ymd] ?? 0) > 0
        return Button {
            Haptics.selection()
            selectedDate = ymd
            Task { await model.loadDay(api, date: ymd) }
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.mono(14)).monospacedDigit()
                    .foregroundStyle(isToday ? .white : Hue.ink)
                    .frame(width: 34, height: 34)
                    .background(isToday ? Hue.accent : Color.clear)
                    .clipShape(Circle())
                Circle()
                    .fill(hasEvents ? Hue.accent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date math

    private var firstOfMonth: Date { cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date() }
    private var daysInMonth: Int { cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30 }
    private var leadingBlanks: Int { cal.component(.weekday, from: firstOfMonth) - 1 }
    private var todayDay: Int { cal.component(.day, from: Date()) }
    private var year: Int { cal.component(.year, from: Date()) }
    private var month: Int { cal.component(.month, from: Date()) }
    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: Date())
    }
}

/// Identifiable wrapper so a YYYY-MM-DD string drives a .sheet(item:).
private struct DayKey: Identifiable { let date: String; var id: String { date } }

struct DaySheet: View {
    let date: String
    let events: [TimelineEvent]
    let loading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(DateHelpers.prettyDate(date))
                    .font(.displaySemi(22))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, 8)

                if loading {
                    ProgressView().tint(Hue.ink3).frame(maxWidth: .infinity).padding(.top, 30)
                } else if events.isEmpty {
                    VStack(spacing: 6) {
                        Text("A clear day")
                            .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                        Text("Nothing on the calendar for this day yet.")
                            .font(.sans(13)).foregroundStyle(Hue.ink2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    ForEach(events) { EventRow(event: $0, date: date) }

                    InlineAction(
                        icon: "calendar.badge.plus",
                        label: "Add to your calendar",
                        doneLabel: "Added to your calendar",
                        actionText: "Add",
                        perform: { try await CalendarExport.addDay(date: date, events: events) }
                    )
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
        }
        .background(Hue.canvas)
        .presentationDragIndicator(.visible)
    }
}
