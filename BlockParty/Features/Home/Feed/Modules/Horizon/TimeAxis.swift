//
//  TimeAxis.swift
//  BlockParty
//
//  The one type that owns the horizon strip's time → x mapping. The strip
//  is a TAPE covering the whole town day, midnight to midnight, laid out
//  at a fixed density: 12 visible hours across the card's inner width.
//  Strip-local positions never change all day — the view slides the whole
//  tape with ONE offset so the moment under the card's permanently
//  centered marker is `center` (now at rest, scrubTime while scrubbing).
//
//  This replaced the fixed 7a–10p window: a scrubbable tape reaches every
//  hour of the day, so the "+N earlier/later" overflow markers and their
//  label-suppression rules retired with it.
//

import CoreGraphics
import Foundation

nonisolated struct TimeAxis: Equatable {
    struct Tick: Equatable {
        let date: Date
        let x: CGFloat
        let isLabeled: Bool
        let label: String?
    }

    /// Today, midnight to next midnight — the same half-open town day the
    /// footer counts use.
    let dayStart: Date
    let dayEnd: Date
    /// The card's inner width, which is also the visible 12 h window.
    let width: CGFloat
    private let calendar: Calendar

    init(now: Date, width: CGFloat, calendar: Calendar = Town.calendar) {
        self.width = width
        self.calendar = calendar
        let interval = YourDayLogic.todayInterval(now: now)
        self.dayStart = interval.start
        self.dayEnd = interval.end
    }

    // MARK: - Mapping

    /// Fixed density: 12 hours across the card, ~30 pt/hour at standard
    /// width, so a minute is ~0.5 pt and the ±8 min event magnet is real.
    var pointsPerHour: CGFloat {
        width / HorizonMetrics.visibleHours
    }

    /// Strip-local x for a date: 0 at midnight, growing rightward. Total —
    /// every moment (including rubber-banded overshoot past the day's
    /// edges) has a position on the tape.
    func x(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * pointsPerHour
    }

    /// The one moving part: slide the whole tape by this offset and
    /// `center` sits exactly under the card's centered marker.
    func stripOffset(centering center: Date) -> CGFloat {
        width / 2 - x(for: center)
    }

    // MARK: - Ticks and labels

    /// A tick every two clock hours across the whole day, labeled on the
    /// four-hour grid: 12a · 4a · 8a · 12p · 4p · 8p · 12a. Off-card ticks
    /// are cheap (13 total) and simply slide into view with the strip.
    func ticks() -> [Tick] {
        var all: [Tick] = stride(from: 0, to: 24, by: 2).compactMap { hour in
            // bySettingHour, not byAdding — a 2 PM tick must be 2 by the
            // wall clock even on a DST-change day (the townInstant rule).
            guard
                let date = calendar.date(
                    bySettingHour: hour, minute: 0, second: 0, of: dayStart)
            else { return nil }
            return tick(for: date, hour: hour)
        }
        // 24:00 is next midnight — out of bySettingHour's reach, but the
        // day interval already knows it.
        all.append(tick(for: dayEnd, hour: 24))
        return all
    }

    private func tick(for date: Date, hour: Int) -> Tick {
        let labeled = hour % 4 == 0
        return Tick(
            date: date,
            x: x(for: date),
            isLabeled: labeled,
            label: labeled ? Self.hourLabel(hour: hour % 24) : nil
        )
    }

    /// Lowercase, no minutes, no space: 12a · 8a · 12p · 9p.
    static func hourLabel(hour: Int) -> String {
        let meridiem = hour < 12 ? "a" : "p"
        var display = hour % 12
        if display == 0 { display = 12 }
        return "\(display)\(meridiem)"
    }
}
