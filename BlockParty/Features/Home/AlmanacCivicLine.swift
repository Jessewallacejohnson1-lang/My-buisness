//
//  AlmanacCivicLine.swift
//  Block Party — relevance and copy for the optional civic masthead line.
//

import Foundation

nonisolated enum AlmanacCivicLine {
    /// Garbage becomes daily-edition news within two days of collection. The
    /// pickup date and recycling parity remain owned by GarbageSchedule.
    private static let pickupHorizonDays = 2

    /// School closings own this slot when supplied because they are more urgent.
    /// There is no school-closing source yet; AlmanacSection injects nil at the
    /// clearly marked integration seam until one exists.
    static func text(
        on date: Date,
        pickupWeekday: Int,
        schoolClosing: String?,
        calendar: Calendar
    ) -> String? {
        if let schoolClosing = trimmed(schoolClosing) { return schoolClosing }

        let pickup = GarbageSchedule.nextPickup(
            after: date,
            pickupWeekday: pickupWeekday,
            calendar: calendar
        )
        guard pickup.daysFromToday <= pickupHorizonDays else { return nil }

        let service = pickup.isRecyclingWeek ? "Recycling" : "Trash"
        if pickup.daysFromToday == 0 { return "\(service) pickup today" }

        let binNight = calendar.date(byAdding: .day, value: -1, to: pickup.date) ?? pickup.date
        let weekday = weekdayName(binNight, calendar: calendar)
        if pickup.isRecyclingWeek {
            return "Recycling week — bins out \(weekday) night"
        }
        return "Trash pickup — bins out \(weekday) night"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
