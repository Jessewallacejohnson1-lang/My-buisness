//
//  CalendarModel.swift
//  Hygge — month event-count dots + per-day event lists.
//

import Foundation
import Combine

@MainActor
final class CalendarModel: ObservableObject {
    @Published var counts: [String: Int] = [:]
    @Published var dayEvents: [TimelineEvent] = []
    @Published var loadingDay = false

    func loadMonth(_ api: CommunityAPI, year: Int, month: Int) async {
        counts = (try? await api.getMonthEventCounts(year: year, month: month)) ?? [:]
    }

    func loadDay(_ api: CommunityAPI, date: String) async {
        loadingDay = true
        dayEvents = (try? await api.getEventsByDate(date)) ?? []
        loadingDay = false
    }
}
