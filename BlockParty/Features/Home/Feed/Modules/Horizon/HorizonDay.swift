//
//  HorizonDay.swift
//  BlockParty
//
//  Maps the day's DayItems onto the horizon strip: which items become
//  stubs in which lane and what the footer counts say. Pure — the view
//  layer only draws what this decides.
//
//  Two regimes, deliberately different:
//  · The FOOTER counts always cover the whole town day, midnight to
//    midnight — all-day and multi-day-running items included.
//  · STUBS are today's timed items. The strip is a whole-day tape, so
//    every one of them has a place on it; only all-day and multi-day
//    items live in the counts without a mark.
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
    /// Whole-day counts, midnight to midnight.
    let yoursCount: Int
    let openCount: Int
    /// The items whose stubs are actually ON the rail (both lanes, after
    /// the public cap), start-sorted and kept whole — the scrub's magnet,
    /// event line and bubble all read THIS one set, so "on an event" means
    /// the same thing everywhere and never points at an undrawn stub.
    let markedItems: [DayItem]

    init(items: [DayItem], now: Date) {
        // The town's today has exactly one definition — the same half-open
        // interval the tape's day bounds use.
        let todayInterval = YourDayLogic.todayInterval(now: now)
        let overlapsToday: (DayItem) -> Bool = { item in
            item.start < todayInterval.end && (item.end ?? item.start) >= todayInterval.start
        }

        // Defensive future-date guard at the module boundary: overlapping
        // today is the only admission test (the shipped Aug-30 bug shape
        // stays excluded).
        let today = items.filter(overlapsToday)
        yoursCount = today.filter { $0.source == .committed }.count
        openCount = today.filter { $0.source == .wholeTown }.count

        // Stubs: today's timed items. The tape covers the whole day, so
        // there is no window filter and no overflow — off-screen items are
        // reached by scrubbing. All-day and multi-day-running items live
        // in the counts, not on the rail.
        let timedItems = today
            .filter { !$0.isAllDay && !$0.isMultiDay }
            .sorted { $0.start < $1.start }
        let timed = timedItems
            .map { item in
                HorizonStub(
                    id: item.id,
                    start: item.start,
                    end: item.end,
                    isYours: item.source == .committed,
                    category: item.event.category
                )
            }

        yourStubs = timed.filter(\.isYours)

        // Public lane caps at 14; keep the 14 nearest to now.
        let publicLane = timed.filter { !$0.isYours }
        if publicLane.count > HorizonMetrics.publicLaneCap {
            let nearest = publicLane
                .sorted { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
                .prefix(HorizonMetrics.publicLaneCap)
            let kept = Set(nearest.map(\.id))
            publicStubs = publicLane.filter { kept.contains($0.id) }
        } else {
            publicStubs = publicLane
        }

        let drawn = Set(yourStubs.map(\.id)).union(publicStubs.map(\.id))
        markedItems = timedItems.filter { drawn.contains($0.id) }
    }

    /// A stub is past once its stated end — or, when end_at is NULL (every
    /// live row today), the app-wide assumed two-hour duration — is behind
    /// now. Same window that ends a map pin's pulse and flips isComplete.
    static func isPast(_ stub: HorizonStub, now: Date) -> Bool {
        (stub.end ?? stub.start.addingTimeInterval(2 * 3600)) < now
    }

    // MARK: The scrub's bottom line + on-an-event bubble

    /// What the card's bottom line shows for a scrub position (spec):
    /// the event at/next-after scrubTime when its clock hour holds one,
    /// "Nothing at this hour" through a gap, "That's the day" past the
    /// last event, and the resting copy on a day with nothing timed.
    enum ScrubLine: Equatable {
        case event(DayItem)
        case quietHour
        case dayDone
        case resting
    }

    func scrubLine(at time: Date, calendar: Calendar = Town.calendar) -> ScrubLine {
        guard let last = markedItems.last else { return .resting }
        if let hour = calendar.dateInterval(of: .hour, for: time) {
            // Half-open on purpose (DateInterval.contains is closed): a
            // 3:00 event belongs to the 3 o'clock hour alone.
            let inHour = markedItems.filter { $0.start >= hour.start && $0.start < hour.end }
            // Dense hours pick the nearest — the magnet lands the marker
            // exactly on a start, so "at" wins ties naturally.
            if let nearest = inHour.min(by: {
                abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time))
            }) {
                return .event(nearest)
            }
        }
        return time > last.start ? .dayDone : .quietHour
    }

    /// The item the scrub is ON — deliberately the magnet's own ±8-min
    /// condition space, so the bubble appears exactly where a release
    /// would land the marker on the event.
    func onEventItem(at time: Date) -> DayItem? {
        markedItems
            .min { abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time)) }
            .flatMap {
                abs($0.start.timeIntervalSince(time)) <= ScrubModel.magnetWindow ? $0 : nil
            }
    }

    /// Lays a lane out left to right in STRIP coordinates. Where two stubs
    /// overlap horizontally, the later one is inset to leave a 1 pt gap so
    /// they stay countable. No edge clamping — on a sliding tape a stub's
    /// position is its time; the card's edge fade and clip do the trimming.
    static func layout(
        _ stubs: [HorizonStub], axis: TimeAxis, minWidth: CGFloat
    ) -> [HorizonPlacedStub] {
        var placed: [HorizonPlacedStub] = []
        var previousRight: CGFloat = -.greatestFiniteMagnitude
        for stub in stubs {
            let idealX = axis.x(for: stub.start)
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
