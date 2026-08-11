//
//  HorizonDay.swift
//  BlockParty
//
//  Maps the day's DayItems onto the horizon rail: which items become stubs
//  in which lane, which spill into the overflow markers, and what the
//  footer counts say. Pure — the view layer only draws what this decides.
//
//  Two count regimes, deliberately different:
//  · The FOOTER counts always cover the whole town day, midnight to
//    midnight — all-day items and items outside the window included.
//  · STUBS exist only inside the active window. In the night window,
//    tomorrow's small-hours items render at reduced opacity past the
//    midnight hairline (fixture-proven; the production fetch currently
//    stops at today — flagged in the build report).
//

import CoreGraphics
import Foundation

nonisolated struct HorizonStub: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date?
    let isYours: Bool
    let category: EventCategory
    /// Night window only: starts after the midnight hairline → drawn at 40%.
    let isTomorrow: Bool
}

/// A stub after layout: x/width resolved against the axis, overlap insets
/// applied so same-lane neighbors stay countable.
nonisolated struct HorizonPlacedStub: Equatable, Identifiable {
    var id: String { stub.id }
    let stub: HorizonStub
    let x: CGFloat
    let width: CGFloat
}

nonisolated struct HorizonDay: Equatable {
    let yourStubs: [HorizonStub]
    let publicStubs: [HorizonStub]
    /// Whole-day counts, midnight to midnight. Never narrowed to the window.
    let yoursCount: Int
    let openCount: Int
    /// Today's timed items whose start falls outside the active window.
    let earlierCount: Int
    let laterCount: Int

    init(items: [DayItem], axis: TimeAxis, now: Date, calendar: Calendar = Town.calendar) {
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        // Defensive future-date guard at the module boundary: an item earns a
        // place only by overlapping the town's today (the shipped Aug-30 bug
        // shape) or by sitting inside the visible window (tomorrow's small
        // hours during the night window). Everything else is dropped whole.
        let admitted = items.filter { item in
            let spanEnd = item.end ?? item.start
            let overlapsToday = item.start < todayEnd && spanEnd >= todayStart
            let insideWindow = axis.fraction(for: item.start) != nil
            return overlapsToday || insideWindow
        }

        let today = admitted.filter { item in
            let spanEnd = item.end ?? item.start
            return item.start < todayEnd && spanEnd >= todayStart
        }
        yoursCount = today.filter { $0.source == .committed }.count
        openCount = today.filter { $0.source == .wholeTown }.count

        // Stubs: timed items whose start sits inside the window. All-day and
        // multi-day-running items live in the counts, not on the rail.
        let stubEligible = admitted.filter { !$0.isAllDay && !$0.isMultiDay }
        let midnight = axis.midnight
        let inWindow = stubEligible
            .filter { axis.fraction(for: $0.start) != nil }
            .sorted { $0.start < $1.start }
            .map { item in
                HorizonStub(
                    id: item.id,
                    start: item.start,
                    end: item.end,
                    isYours: item.source == .committed,
                    category: item.event.category,
                    isTomorrow: midnight.map { item.start >= $0 } ?? false
                )
            }

        yourStubs = inWindow.filter(\.isYours)

        // Public lane caps at 14; keep the 14 nearest to now.
        let publicLane = inWindow.filter { !$0.isYours }
        if publicLane.count > HorizonMetrics.publicLaneCap {
            let nearest = publicLane
                .sorted { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
                .prefix(HorizonMetrics.publicLaneCap)
            let kept = Set(nearest.map(\.id))
            publicStubs = publicLane.filter { kept.contains($0.id) }
        } else {
            publicStubs = publicLane
        }

        // Overflow: today's timed items that missed the window. A festival
        // already running since an earlier day is not "earlier today" — only
        // items that start today count toward the markers.
        let overflowEligible = today.filter {
            !$0.isAllDay && !$0.isMultiDay && axis.fraction(for: $0.start) == nil
        }
        earlierCount = overflowEligible.filter { $0.start < axis.start }.count
        laterCount = overflowEligible.filter { $0.start >= axis.end }.count
    }

    /// Lays a lane out left to right. Where two stubs overlap horizontally,
    /// the later one is inset to leave a 1 pt gap so they stay countable.
    static func layout(
        _ stubs: [HorizonStub], axis: TimeAxis, minWidth: CGFloat
    ) -> [HorizonPlacedStub] {
        var placed: [HorizonPlacedStub] = []
        var previousRight: CGFloat = -.greatestFiniteMagnitude
        for stub in stubs {
            guard let idealX = axis.x(for: stub.start) else { continue }
            let duration = stub.end.map { $0.timeIntervalSince(stub.start) } ?? 0
            let width = max(minWidth, CGFloat(duration / 3600) * axis.pointsPerHour)
            let x = idealX < previousRight
                ? previousRight + HorizonMetrics.overlapInset
                : idealX
            placed.append(HorizonPlacedStub(stub: stub, x: x, width: width))
            previousRight = x + width
        }
        return placed
    }
}
