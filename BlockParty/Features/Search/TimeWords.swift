//
//  TimeWords.swift
//  Block Party — the words in a search that say when, and the words that say nothing (BP app search-helpful 06).
//  "tonight", "tomorrow", "saturday", "friday night", "this weekend", "this week" and "things to do" pick the
//  hours whose Events show; "open now" picks the places open now, and "now" the Events on now. "near me", "best",
//  "where to" say nothing a town's search can use, so a row is found by the words left ("pizza near me" is "pizza").
//  Times are the Town's clock (`Town.calendar`), passed in.
//
//  Pure, synchronous and local: no network.
//

import Foundation

nonisolated enum TimeWords {
    struct Read: Equatable {
        /// The words left once the time and filler words are out; empty for "tonight" alone.
        var words: String
        /// The hours whose Events show; nil when no time word was typed.
        var hours: Range<Date>? = nil
        /// "open now": only the places open now.
        var openNow = false
        /// Whether any word was taken out, so `words` differs from what was typed.
        var took = false
    }

    /// Said before 5 PM, "night" starts at 5 PM; "tonight" runs to 5 the next morning.
    static let evening = 17
    static let morning = 5

    /// Words that say nothing about what is wanted. Whole words and phrases, longest first.
    static let filler = ["near me", "nearby", "near", "around here", "in town", "where can i", "where to", "where",
                         "best", "good", "great", "top", "friendly", "find"]

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    static func read(_ typed: String, now: Date, calendar: Calendar) -> Read {
        var words = " " + typed.lowercased().filter { !"'’`".contains($0) }
            .map { $0.isLetter || $0.isNumber || $0 == "&" ? $0 : " " }
            .split(separator: " ").joined(separator: " ") + " "
        var took = false
        func take(_ phrase: String) -> Bool {
            guard words.contains(" \(phrase) ") else { return false }
            words = words.replacingOccurrences(of: " \(phrase) ", with: " ")
            took = true
            return true
        }
        let today = calendar.startOfDay(for: now)
        func at(_ day: Int, _ hour: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }
        func from(_ start: Date, to end: Date) -> Range<Date> { max(start, now) ..< max(end, now) }
        let hourNow = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) - 1   // 0 is Sunday

        var read = Read(words: "")
        // "things to do" alone is this week; with another time word, that time ("things to do tonight").
        let todo = take("things to do") || take("stuff to do") || take("what to do")
        if take("open now") || take("open right now") {
            read.openNow = true
        } else if take("right now") || take("now") {
            read.hours = now ..< now
        } else if take("this weekend") || take("weekend") {
            let friday = (5 - weekday + 7) % 7
            read.hours = weekday == 6 || weekday == 0
                ? from(now, to: at(weekday == 6 ? 2 : 1))
                : from(at(friday, evening), to: at(friday + 3))
        } else if take("this week") {
            read.hours = from(now, to: at(7))
        } else if take("tonight") {
            read.hours = hourNow < morning ? from(now, to: at(0, morning)) : from(at(0, evening), to: at(1, morning))
        } else if take("today") {
            read.hours = from(now, to: at(1))
        } else if take("tomorrow night") {
            read.hours = from(at(1, evening), to: at(2, morning))
        } else if take("tomorrow") {
            read.hours = from(at(1), to: at(2))
        } else {
            for (i, day) in weekdays.enumerated() {
                let night = take("\(day) night") || take("\(day) nights")
                guard night || take(day) || take(day + "s") else { continue }
                let days = (i - weekday + 7) % 7
                read.hours = night ? from(at(days, evening), to: at(days + 1, morning)) : from(at(days), to: at(days + 1))
                _ = take("this") || take("on") || take("next")   // "this saturday", "on friday"
                break
            }
        }
        if todo && read.hours == nil && !read.openNow { read.hours = from(now, to: at(7)) }
        for phrase in filler { while take(phrase) {} }
        read.words = words.trimmingCharacters(in: .whitespaces)
        read.took = took
        return read
    }

    /// Whether an Event belongs in `hours` ("now" is the empty range at `now`): a timed one when it starts in them, or
    /// when the hours start now and it's on; an all-day one when its day is in them, a night's hours past midnight
    /// left out ("tonight" isn't tomorrow's all-day fair); one over a few days when it's on in them (a weekend
    /// festival is Saturday's). Longer ones count only by their start, so a month-long exhibit isn't "tonight".
    static func fits(start: Date, end: Date, timed: Bool, in hours: Range<Date>, now: Date, calendar: Calendar) -> Bool {
        let days = { (n: Int) in calendar.date(byAdding: .day, value: n, to: start) ?? start }
        if end > days(1) {
            return hours.contains(start)
                || (end <= days(4) && (hours.isEmpty ? start <= now : start < hours.upperBound) && end > hours.lowerBound)
        }
        if !timed {
            let night = calendar.component(.hour, from: hours.upperBound) == morning
            let last = night ? calendar.startOfDay(for: hours.upperBound) : hours.upperBound
            return !hours.isEmpty && start < last && end > hours.lowerBound
        }
        return hours.contains(start) || (hours.lowerBound <= now && start <= now && end > now)
    }
}
