//
//  TimeAxis.swift
//  BlockParty
//
//  The one type that owns the horizon rail's time → x mapping. The rail is
//  a FIXED window — 7:00 AM to 10:00 PM town time, the waking day — so the
//  axis, hour labels and stub positions never change all day. Items outside
//  the window clamp to the overflow markers; edge-pinned marks (the now
//  marker, bloom, solar dots) use the clamped mapping. The SKY above keeps
//  full solar behavior — only the ruler is pinned.
//
//  This replaced the solar sunrise→sunset / sunset→sunrise window pair: at
//  9 PM the old design collapsed all of today into "+16 earlier" while the
//  text said "5 plans today" — the picture contradicted the words.
//

import CoreGraphics
import Foundation

nonisolated struct TimeAxis: Equatable {
    /// Labels never sit within this distance of a rail edge — the edges
    /// belong to the sunrise/sunset dots.
    static let edgeExclusion: CGFloat = 14

    struct Tick: Equatable {
        let date: Date
        let x: CGFloat
        let isLabeled: Bool
        let label: String?
    }

    let start: Date
    let end: Date
    let width: CGFloat
    private let calendar: Calendar

    init(now: Date, width: CGFloat, calendar: Calendar = Town.calendar) {
        self.width = width
        self.calendar = calendar
        // bySettingHour, not byAdding — 7 AM must be 7 by the wall clock
        // even on a DST-change day (the townInstant rule).
        let dayStart = calendar.startOfDay(for: now)
        self.start = calendar.date(
            bySettingHour: HorizonMetrics.axisStartHour, minute: 0, second: 0, of: dayStart
        ) ?? dayStart
        self.end = calendar.date(
            bySettingHour: HorizonMetrics.axisEndHour, minute: 0, second: 0, of: dayStart
        ) ?? dayStart
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

    /// 0…1 fraction clamped to the window — for marks that pin to the
    /// edges rather than vanish (now marker, bloom, solar dots).
    func clampedFraction(for date: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / span, 0), 1)
    }

    func clampedX(for date: Date) -> CGFloat {
        CGFloat(clampedFraction(for: date)) * width
    }

    var pointsPerHour: CGFloat {
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return 0 }
        return width / CGFloat(hours)
    }

    // MARK: - Ticks and labels

    /// A tick every two clock hours strictly inside the window, labeled on
    /// the four-hour grid: 8a · 12p · 4p · 8p — exactly four, all day.
    func ticks() -> [Tick] {
        var firstEven = HorizonMetrics.axisStartHour + 1
        if firstEven % 2 != 0 { firstEven += 1 }
        let dayStart = calendar.startOfDay(for: start)
        return stride(from: firstEven, to: HorizonMetrics.axisEndHour, by: 2)
            .compactMap { hour in
                guard
                    let date = calendar.date(
                        bySettingHour: hour, minute: 0, second: 0, of: dayStart),
                    let tickX = x(for: date)
                else { return nil }
                let onGrid = hour % 4 == 0
                let nearEdge =
                    tickX < Self.edgeExclusion || tickX > width - Self.edgeExclusion
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
}
