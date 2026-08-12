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
//  · STUBS exist only inside the fixed 7a–10p window; today's items
//    outside it clamp to the earlier/later overflow markers.
//

import CoreGraphics
import Foundation

nonisolated struct HorizonStub: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date?
    let isYours: Bool
    let category: EventCategory
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

    init(items: [DayItem], axis: TimeAxis, now: Date) {
        // The town's today has exactly one definition — the same half-open
        // interval the rail builder uses.
        let todayInterval = YourDayLogic.todayInterval(now: now)
        let overlapsToday: (DayItem) -> Bool = { item in
            item.start < todayInterval.end && (item.end ?? item.start) >= todayInterval.start
        }

        // Defensive future-date guard at the module boundary: the fixed
        // window sits inside the town day, so overlapping today is the only
        // admission test (the shipped Aug-30 bug shape stays excluded).
        let today = items.filter(overlapsToday)
        yoursCount = today.filter { $0.source == .committed }.count
        openCount = today.filter { $0.source == .wholeTown }.count

        // Stubs: timed items whose start sits inside the window. All-day and
        // multi-day-running items live in the counts, not on the rail.
        let inWindow = today
            .filter { !$0.isAllDay && !$0.isMultiDay }
            .filter { axis.fraction(for: $0.start) != nil }
            .sorted { $0.start < $1.start }
            .map { item in
                HorizonStub(
                    id: item.id,
                    start: item.start,
                    end: item.end,
                    isYours: item.source == .committed,
                    category: item.event.category
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
