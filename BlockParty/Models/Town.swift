//
//  Town.swift
//  Block Party — the one town this app is for: Saint Joseph, Minnesota.
//
//  The app is single-town by design, so "where" and "what time is it there" are
//  constants, not state. Anything that is true of the PLACE rather than of the
//  device belongs here — most importantly the clock: the St. Cloud library's
//  hours and the St. Joseph garbage route run on America/Chicago no matter where
//  the phone is, so town-fixed date math must read `Town.calendar`, never
//  `Calendar.current`.
//
//  nonisolated: immutable place constants (the module defaults to MainActor
//  isolation), so the Utility Row's pure `nonisolated` date math can take
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

    static let latitude = 45.565
    static let longitude = -94.3186

    /// The town's civic clock. Fixed: a traveling user still gets the town's
    /// pickup day and the town library's hours, not their hotel's.
    static let timeZone = TimeZone(identifier: "America/Chicago")!

    /// `Calendar.current` with ONLY the timezone replaced.
    ///
    /// Deliberately does NOT override `firstWeekday` or `locale`: those belong to
    /// the user, and `GarbageSchedule` compares the holiday shift by week-OFFSET
    /// precisely so it stays correct for any `firstWeekday` (see the 2028
    /// Thanksgiving regression test). Pinning them here would silently change the
    /// user's week for no gain.
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = timeZone
        return cal
    }

    /// What day it is HERE, as the "YYYY-MM-DD" that `club_events.event_date`
    /// stores. Same shape as `DateHelpers.localDate()` but anchored to the town
    /// rather than the device, so a neighbour reading this from an airport still
    /// gets St. Joseph's date.
    ///
    /// Formatted from components rather than a `DateFormatter` so it cannot pick
    /// up a locale's calendar (a non-Gregorian device calendar would otherwise
    /// produce a year PostgREST does not understand).
    static func day(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
