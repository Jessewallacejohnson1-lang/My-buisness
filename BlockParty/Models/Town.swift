//
//  Town.swift
//  Block Party — the one town this app is for: Saint Joseph, Minnesota.
//
//  The app is single-town by design, so "where" and "what time is it there" are
//  constants, not state. Anything that is true of the PLACE rather than of the
//  device belongs here — most importantly the clock: the town's day runs on
//  America/Chicago no matter where the phone is, so town-fixed date math must read `Town.calendar`, never
//  `Calendar.current`.
//
//  nonisolated: immutable place constants (the module defaults to MainActor
//  isolation), so pure `nonisolated` date math can take
//  `Town.calendar` as a DEFAULT ARGUMENT without tripping the "main
//  actor-isolated … cannot be referenced from a nonisolated context" warning —
//  see the CLAUDE.md MainActor-default-arg gotcha.
//

import Foundation

nonisolated enum Town {
    /// Short name — the header title and the map's home label.
    static let name = "Saint Joseph"

    /// Long form, for the places that name the state.
    static let display = "St. Joseph, Minnesota"

    /// How a message to a friend names it: "St. Joseph's events" (friends 05).
    static let everyday = "St. Joseph"

    /// What neighbours call it: Daily's first topic is "Best of St. Joe".
    static let nickname = "St. Joe"

    /// The Town's own round logo, top right on Daily: Joetown's for St. Joseph (Jesse's file).
    static let logo = "TownLogo"

    static let latitude = 45.565
    static let longitude = -94.3186

    /// The town's civic clock. Fixed: a traveling user still gets the town's day,
    /// not their hotel's.
    static let timeZone = TimeZone(identifier: "America/Chicago")!

    /// `Calendar.current` with ONLY the timezone replaced.
    ///
    /// Deliberately does NOT override `firstWeekday` or `locale`: those belong to
    /// the user. Pinning them here would silently change the user's week for no gain.
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = timeZone
        return cal
    }

    /// Gregorian in the Town's zone, built once: every sum over Town days and hours.
    /// Unlike `calendar` it ignores the phone's own calendar and week start.
    static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }()

    /// What day it is HERE, as the "YYYY-MM-DD" that `club_events.event_date`
    /// stores, anchored to the town rather than the device, so a neighbour reading
    /// this from an airport still gets St. Joseph's date.
    ///
    /// Formatted from components rather than a `DateFormatter` so it cannot pick
    /// up a locale's calendar (a non-Gregorian device calendar would otherwise
    /// produce a year PostgREST does not understand).
    static func day(_ date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Town midnight on a "YYYY-MM-DD" date column; nil when it isn't one.
    static func midnight(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole Town days from `from`'s day to `to`'s: 1 for any time tomorrow.
    static func days(from: Date, to: Date) -> Int {
        gregorian.dateComponents([.day], from: gregorian.startOfDay(for: from),
                                 to: gregorian.startOfDay(for: to)).day ?? 0
    }

    /// "7 PM", "7:30 PM", "Noon", "Midnight", in the Town's time.
    static func clock(_ date: Date) -> String {
        let c = gregorian.dateComponents([.hour, .minute], from: date)
        return clock(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// The same, from minutes after midnight.
    static func clock(minutes: Int) -> String {
        switch minutes {
        case 0: return "Midnight"
        case 12 * 60: return "Noon"
        default:
            let hour = minutes / 60, minute = minutes % 60
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            let meridiem = hour < 12 ? "AM" : "PM"
            return minute == 0 ? "\(hour12) \(meridiem)" : String(format: "%d:%02d %@", hour12, minute, meridiem)
        }
    }

    /// `date` written from a date template ("EEE", "MMMd", "EEEEMMMMd"), in English, in the
    /// Town's time.
    static func format(_ date: Date, _ template: String) -> String {
        if let formatter = formatters.object(forKey: template as NSString) { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters.setObject(formatter, forKey: template as NSString)
        return formatter.string(from: date)
    }

    /// One formatter per template, kept: the You tab's Calendar writes 49 dates each time it
    /// draws, and building a formatter is the slow part. NSCache is safe from any thread.
    private static let formatters = NSCache<NSString, DateFormatter>()
}
