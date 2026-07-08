//
//  CalendarModel.swift
//  Hygge — a year of month grids fed by ONE range query: per-day event counts,
//  the upcoming agenda, and whether anything is live right now. Per-day detail
//  (the sheet) still loads on demand.
//
//  Failure discipline: a failed load never wipes data that's already on screen
//  (stale beats blank for a town calendar) and never masquerades as "empty" —
//  the view gets an explicit `failed` / `dayFailed` to show quiet error copy.
//

import Foundation
import Combine

@MainActor
final class CalendarModel: ObservableObject {
    @Published var counts: [String: Int] = [:]   // YYYY-MM-DD → happenings that day
    @Published var upcoming: [AgendaEvent] = []  // today onward, date+time order
    @Published var liveNow = false               // something is happening this minute
    @Published var loaded = false
    @Published var failed = false                // first load failed — nothing to show

    @Published var dayEvents: [TimelineEvent] = []
    @Published var loadingDay = false
    @Published var dayFailed = false
    private var dayRequest: String?              // guards against out-of-order responses

    /// Day keys are Gregorian YYYY-MM-DD (the DB's dialect) — pin the calendar so
    /// a device set to Buddhist/Japanese doesn't produce keys like "2569-07-06".
    static var gregorian: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    /// First of the current month → last day of (current + monthsAhead). One
    /// request lights every grid and fills the agenda — no per-month fan-out.
    func load(_ api: CommunityAPI, monthsAhead: Int = 11) async {
        let cal = Self.gregorian
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: Date())),
              let lastMonth = cal.date(byAdding: .month, value: monthsAhead, to: first),
              let lastDayCount = cal.range(of: .day, in: .month, for: lastMonth)?.count
        else { return }
        let lc = cal.dateComponents([.year, .month], from: lastMonth)
        let from = DateHelpers.localDate(first)
        let to = String(format: "%04d-%02d-%02d", lc.year ?? 0, lc.month ?? 0, lastDayCount)

        do {
            let events = try await api.getEventsForRange(from: from, to: to)
            var perDay: [String: Int] = [:]
            for e in events { perDay[e.eventDate, default: 0] += 1 }
            counts = perDay

            let today = DateHelpers.localDate()
            upcoming = events.filter { $0.eventDate >= today }
            liveNow = events.contains { $0.eventDate == today && DateHelpers.isLiveNow($0.startTime) }
            failed = false
            loaded = true
        } catch {
            // Keep whatever is already on screen; only flag when there's nothing.
            if !loaded { failed = true }
        }
    }

    func loadDay(_ api: CommunityAPI, date: String) async {
        loadingDay = true
        dayFailed = false
        dayRequest = date
        do {
            let events = try await api.getEventsByDate(date)
            guard dayRequest == date else { return }   // a newer tap won the race
            dayEvents = events
        } catch {
            guard dayRequest == date else { return }
            dayEvents = []
            dayFailed = true
        }
        loadingDay = false
    }
}
