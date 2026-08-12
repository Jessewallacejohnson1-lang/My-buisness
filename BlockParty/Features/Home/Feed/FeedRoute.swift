//
//  FeedRoute.swift
//  Block Party — every destination reachable from a Today feed module.
//
//  TWO KINDS OF ROUTE. Most present a sheet over the feed and own their own
//  destination. `.activities` does not: tab selection belongs to `MainTabsView`, so
//  `FeedView` hands that one up to the shell — the same lane `TownMenuAction`'s tab
//  rows already use — and it lands as an ordinary tab change rather than a modal.
//  `destination` is nil for exactly that kind.
//

import SwiftUI

enum FeedRoute: Identifiable, Hashable {
    case civicTab
    case editInterests
    /// One upcoming event, opened from its Your Day card. The event travels with
    /// the route so the detail screen paints the facts the card already had before
    /// any network call — there is nothing to re-fetch just to show a title.
    case event(UpcomingEvent)
    /// The Activities tab, opened on a filter + timeframe. Fulfilled by the shell,
    /// not presented here.
    case activities(ActivitiesRequest)

    nonisolated var id: Self { self }

    /// The Activities state this route is asking the shell for, or nil when the
    /// route presents its own destination in place.
    nonisolated var activitiesRequest: ActivitiesRequest? {
        guard case .activities(let request) = self else { return nil }
        return request
    }

    /// The sheet this route presents, or nil for a route the shell fulfils itself.
    @MainActor
    var destination: AnyView? {
        switch self {
        case .civicTab:
            AnyView(CivicTabDestination())
        case .editInterests:
            AnyView(FeedInterestEditorDestination())
        case .event(let event):
            AnyView(FeedEventDetailDestination(event: event))
        case .activities:
            nil
        }
    }
}
