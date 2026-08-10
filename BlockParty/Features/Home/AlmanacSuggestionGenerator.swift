//
//  AlmanacSuggestionGenerator.swift
//  Block Party — pure, deterministic fallback copy for the Daily Almanac.
//
//  The generator knows nothing about URLSession or CommunityAPI. Callers inject
//  real RSVP and local-subject snapshots, which keeps this logic deterministic
//  and unit-testable while the view remains responsible for fetching live data.
//

import Foundation

nonisolated enum AlmanacSuggestionGenerator {
    nonisolated struct RSVP: Equatable, Sendable {
        let id: String
        let title: String
        let eventDate: String
        let startTime: String?
        let location: String?
    }

    nonisolated enum SubjectKind: Equatable, Sendable {
        case trail
        case park
        case food
        case business
        case landmark
        case place
    }

    nonisolated struct Subject: Equatable, Sendable {
        let id: String
        let name: String
        let kind: SubjectKind
    }

    nonisolated struct Inputs: Equatable, Sendable {
        let townDate: String
        let userKey: String
        let rsvps: [RSVP]
        let subjects: [Subject]
    }

    /// A real RSVP always wins. Otherwise the town date advances through the
    /// injected local catalogue, offset by a stable per-user seed. The secondary
    /// template rotation keeps even a one-subject catalogue different tomorrow.
    static func suggestion(for inputs: Inputs) -> String? {
        let day = dayOrdinal(inputs.townDate)
        let userSeed = stableHash(inputs.userKey)

        if let rsvp = firstUpcomingRSVP(in: inputs) {
            let template = positiveModulo(day + Int(userSeed % 3), 3)
            return rsvpLine(rsvp, townDate: inputs.townDate, template: template)
        }

        let subjects = uniqueSubjects(inputs.subjects)
        guard !subjects.isEmpty else { return nil }

        let subjectIndex = positiveModulo(day + Int(userSeed % UInt64(subjects.count)), subjects.count)
        let template = positiveModulo(day + Int((userSeed / UInt64(subjects.count)) % 2), 2)
        return localLine(subjects[subjectIndex], template: template)
    }

    private static func firstUpcomingRSVP(in inputs: Inputs) -> RSVP? {
        inputs.rsvps
            .filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && ($0.eventDate.isEmpty || $0.eventDate >= inputs.townDate)
            }
            .sorted {
                if $0.eventDate != $1.eventDate { return $0.eventDate < $1.eventDate }
                if ($0.startTime ?? "") != ($1.startTime ?? "") {
                    return ($0.startTime ?? "") < ($1.startTime ?? "")
                }
                return $0.id < $1.id
            }
            .first
    }

    private static func rsvpLine(_ rsvp: RSVP, townDate: String, template: Int) -> String {
        let title = rsvp.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var details = relativeDay(rsvp.eventDate, townDate: townDate)
        if let time = trimmed(rsvp.startTime) { details += ", \(time)" }
        if let location = trimmed(rsvp.location) { details += " at \(location)" }

        switch template {
        case 0: return "You’re set for \(title) \(details)."
        case 1: return "Keep \(title) on your calendar \(details)."
        default: return "\(title) is your next plan \(details)."
        }
    }

    private static func localLine(_ subject: Subject, template: Int) -> String {
        switch (subject.kind, template) {
        case (.trail, 0):
            return "Take a short walk on \(subject.name) today."
        case (.trail, _):
            return "Put \(subject.name) on today’s walking route."
        case (.park, 0):
            return "Make room for a short walk at \(subject.name) today."
        case (.park, _):
            return "Take ten quiet minutes at \(subject.name) today."
        case (.food, 0):
            return "Make \(subject.name) one of today’s stops."
        case (.food, _):
            return "Stop by \(subject.name) if you’re out today."
        case (.business, 0):
            return "Put \(subject.name) on today’s errand route."
        case (.business, _):
            return "Keep \(subject.name) in mind for today’s errands."
        case (.landmark, 0):
            return "Take a closer look at \(subject.name) today."
        case (.landmark, _):
            return "Walk a block around \(subject.name) today."
        case (.place, 0):
            return "Put \(subject.name) on today’s route."
        case (.place, _):
            return "See where \(subject.name) fits into today."
        }
    }

    private static func uniqueSubjects(_ subjects: [Subject]) -> [Subject] {
        var names = Set<String>()
        return subjects
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.id != $1.id { return $0.id < $1.id }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .filter { names.insert($0.name.lowercased()).inserted }
    }

    private static func relativeDay(_ eventDate: String, townDate: String) -> String {
        guard let event = parseTownDate(eventDate), let today = parseTownDate(townDate) else {
            return "soon"
        }
        let difference = townCalendar.dateComponents([.day], from: today, to: event).day
        switch difference {
        case 0: return "today"
        case 1: return "tomorrow"
        default:
            let formatter = DateFormatter()
            formatter.calendar = townCalendar
            formatter.locale = Locale(identifier: "en_US")
            formatter.timeZone = Town.timeZone
            formatter.dateFormat = "EEEE"
            return formatter.string(from: event)
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dayOrdinal(_ townDate: String) -> Int {
        guard let date = parseTownDate(townDate) else { return Int(stableHash(townDate) % 10_000) }
        return townCalendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    private static func parseTownDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return townCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    /// Swift's `hashValue` is randomized per process; this hash stays stable.
    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 5_381
        for byte in value.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return hash
    }

    private static let townCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = Town.timeZone
        return calendar
    }()

}
