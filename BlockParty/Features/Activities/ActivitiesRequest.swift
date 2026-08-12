//
//  ActivitiesRequest.swift
//  Block Party — the state the Activities tab opens on, asked for from outside it.
//
//  Activities has always been able to start on a chip and a date window; until now
//  the ONLY way to ask was a DEBUG launch argument, so anything in the app wanting
//  "what's happening today" had nowhere to send a neighbour. This is that entry
//  point, and it is deliberately NOT `#if DEBUG`.
//
//  ONE RESOLUTION, NOT TWO. `opening(_:)` is the single place a filter + timeframe
//  becomes the view's opening state: an explicit request wins, else the DEBUG flags,
//  else the resting discovery layout. So `-explore-filter events -explore-timeframe
//  today` and a real navigation land on exactly the same screen — which is what
//  makes the flags evidence for the route rather than a parallel implementation.
//
//  `nonisolated` (the module defaults to MainActor): this is a plain value carried
//  by `FeedRoute`, whose `id` and `Hashable` conformance are nonisolated.
//

import Foundation

nonisolated struct ActivitiesRequest: Hashable {
    var filter: ActivitiesView.Filter
    var timeFrame: ActivitiesView.TimeFrame

    /// A plain tab tap: nothing filtered, no date window — the discovery layout.
    static let resting = ActivitiesRequest(filter: .all, timeFrame: .upcoming)

    /// "See what's happening in St. Joe" — today's events.
    ///
    /// `.events` rather than `.all`, because the timeframe is applied to events only
    /// and `.all` renders the undated discovery layout: asking for `.all` + `.today`
    /// would silently drop the "today" half of the request.
    static let happeningToday = ActivitiesRequest(filter: .events, timeFrame: .today)

    /// What the screen opens on. Nil means nobody asked, so the DEBUG flags get
    /// their turn and the resting state has the last word.
    static func opening(_ request: ActivitiesRequest?) -> ActivitiesRequest {
        request ?? debugRequested() ?? .resting
    }
}

#if DEBUG
extension ActivitiesRequest {
    /// `-explore-filter events|clubs|trails|parks|saved` and
    /// `-explore-timeframe today|week|month|upcoming` — the headless way to
    /// screenshot a filtered Activities. Either flag may appear alone; the other
    /// half then falls back to the resting state, exactly as it did when these two
    /// were parsed separately inside the view.
    ///
    /// Takes the arguments rather than reading `ProcessInfo` internally so a test
    /// can prove the flags and a real request resolve to the same value.
    nonisolated static func debugRequested(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ActivitiesRequest? {
        let filter = debugFilter(arguments)
        let timeFrame = debugTimeFrame(arguments)
        guard filter != nil || timeFrame != nil else { return nil }
        return ActivitiesRequest(
            filter: filter ?? resting.filter,
            timeFrame: timeFrame ?? resting.timeFrame
        )
    }

    nonisolated private static func debugFilter(_ arguments: [String]) -> ActivitiesView.Filter? {
        guard let flag = arguments.firstIndex(of: "-explore-filter"),
              flag + 1 < arguments.count
        else { return nil }
        return ActivitiesView.Filter(rawValue: arguments[flag + 1].capitalized)
    }

    nonisolated private static func debugTimeFrame(_ arguments: [String]) -> ActivitiesView.TimeFrame? {
        guard let flag = arguments.firstIndex(of: "-explore-timeframe"),
              flag + 1 < arguments.count
        else { return nil }
        switch arguments[flag + 1] {
        case "today":    return .today
        case "week":     return .week
        case "month":    return .month
        case "upcoming": return .upcoming
        default:         return nil
        }
    }
}
#else
extension ActivitiesRequest {
    /// Release has no launch-argument entry point — only the real one above.
    nonisolated static func debugRequested() -> ActivitiesRequest? { nil }
}
#endif
