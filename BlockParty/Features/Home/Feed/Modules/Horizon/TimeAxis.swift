//
//  TimeAxis.swift
//  BlockParty
//
//  The one type that owns the horizon rail's time → x mapping. The rail is
//  not a fixed span: it shows the day window (sunrise → sunset) or the night
//  window (sunset → next sunrise), whichever contains now, using the real
//  solar times unrounded. Everything on the rail — stubs, ticks, labels,
//  sunrise/sunset dots, the now line, the midnight hairline — asks this
//  type for its x.
//

import CoreGraphics
import Foundation

nonisolated struct TimeAxis: Equatable {
    enum WindowKind: Equatable {
        case day
        case night
    }

    /// Labels never sit within this distance of a rail edge — the edges
    /// belong to the sunrise/sunset dots.
    static let edgeExclusion: CGFloat = 14
    /// Windows shorter than 4 h or longer than 20 h are bad data (missing
    /// Open-Meteo response, polar user); fall back to fixed 6-to-6.
    static let minimumWindowHours: Double = 4
    static let maximumWindowHours: Double = 20
    /// The label ladder targets at most this many labeled hours.
    static let maximumLabels = 7

    struct Tick: Equatable {
        let date: Date
        let x: CGFloat
        let isLabeled: Bool
        let label: String?
    }

    let start: Date
    let end: Date
    let kind: WindowKind
    let width: CGFloat
    /// True when the solar window was degenerate and the fixed 6-to-6
    /// fallback is in force. The view layer logs this.
    let usedFallbackWindow: Bool
    private let calendar: Calendar

    init(now: Date, sunrise: Date?, sunset: Date?, width: CGFloat, calendar: Calendar = Town.calendar) {
        self.width = width
        self.calendar = calendar

        let sky = SolarSky(now: now, sunrise: sunrise, sunset: sunset, calendar: calendar)
        let rise = sky.sunrise
        let set = sky.sunset

        let isDayWindow = now >= rise && now < set
        var start: Date
        var end: Date
        if isDayWindow {
            start = rise
            end = set
        } else if now < rise {
            start = set.addingTimeInterval(-24 * 3600)
            end = rise
        } else {
            start = set
            end = rise.addingTimeInterval(24 * 3600)
        }

        let hours = end.timeIntervalSince(start) / 3600
        if hours < Self.minimumWindowHours || hours > Self.maximumWindowHours {
            // Never render a window that can't be read.
            let sixAM = Self.clockDate(hour: 6, on: now, calendar: calendar)
            let sixPM = Self.clockDate(hour: 18, on: now, calendar: calendar)
            if now >= sixAM && now < sixPM {
                start = sixAM
                end = sixPM
                self.kind = .day
            } else if now < sixAM {
                start = sixPM.addingTimeInterval(-24 * 3600)
                end = sixAM
                self.kind = .night
            } else {
                start = sixPM
                end = sixAM.addingTimeInterval(24 * 3600)
                self.kind = .night
            }
            self.usedFallbackWindow = true
        } else {
            self.kind = isDayWindow ? .day : .night
            self.usedFallbackWindow = false
        }
        self.start = start
        self.end = end
    }

    // MARK: - Mapping

    /// x in points for a date, nil outside the window.
    func x(for date: Date) -> CGFloat? {
        guard let f = fraction(for: date) else { return nil }
        return CGFloat(f) * width
    }

    /// 0…1 fraction along the window, nil outside.
    func fraction(for date: Date) -> Double? {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return nil }
        let f = date.timeIntervalSince(start) / span
        guard f >= 0, f <= 1 else { return nil }
        return f
    }

    var pointsPerHour: CGFloat {
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return 0 }
        return width / CGFloat(hours)
    }

    /// Town midnight inside a night window, if the window crosses one.
    var midnight: Date? {
        guard kind == .night else { return nil }
        let candidate = calendar.startOfDay(for: end)
        guard candidate > start, candidate < end else { return nil }
        return candidate
    }

    // MARK: - Ticks and labels

    /// The smallest interval from {1h, 2h, 3h} whose clock-hour grid puts at
    /// most 7 labels inside the window.
    ///
    /// Deviation from the spec's literal `floor(windowHours / i) <= 7`
    /// formula, which undercounts by one (a k-hour span holds up to
    /// floor(k/i)+1 grid points) and would pick 2 h for a June day, yielding
    /// 8 labels. Counting actual grid hours honors the ≤ 7 goal the formula
    /// was reaching for, and reproduces both worked examples in the spec.
    var labelInterval: Int {
        for interval in [1, 2, 3] {
            if gridHours(interval: interval).count <= Self.maximumLabels {
                return interval
            }
        }
        return 3
    }

    /// One tick per clock hour across the window. Labeled hours follow the
    /// ladder; any label within 14 pt of a rail edge is dropped.
    func ticks() -> [Tick] {
        let interval = labelInterval
        return clockHours().compactMap { date in
            guard let tickX = x(for: date) else { return nil }
            let hour = calendar.component(.hour, from: date)
            let onGrid = hour % interval == 0
            let nearEdge = tickX < Self.edgeExclusion || tickX > width - Self.edgeExclusion
            let labeled = onGrid && !nearEdge
            return Tick(
                date: date,
                x: tickX,
                isLabeled: labeled,
                label: labeled ? Self.hourLabel(hour: hour) : nil
            )
        }
    }

    /// Lowercase, no minutes, no space: 12a · 8a · 12p · 9p.
    static func hourLabel(hour: Int) -> String {
        let meridiem = hour < 12 ? "a" : "p"
        var display = hour % 12
        if display == 0 { display = 12 }
        return "\(display)\(meridiem)"
    }

    /// Every clean clock hour strictly inside the window.
    private func clockHours() -> [Date] {
        var hours: [Date] = []
        var probe = start
        // First clean hour at or after start (exclusive of an exact-start hour:
        // edges belong to the dots, and the 14pt drop would kill it anyway).
        if let first = calendar.nextDate(
            after: probe, matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            probe = first
        }
        while probe < end {
            hours.append(probe)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: probe) else { break }
            probe = next
        }
        return hours
    }

    private func gridHours(interval: Int) -> [Date] {
        clockHours().filter { calendar.component(.hour, from: $0) % interval == 0 }
    }

    private static func clockDate(hour: Int, on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }
}
