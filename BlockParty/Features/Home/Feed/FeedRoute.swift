//
//  FeedRoute.swift
//  Block Party — every destination reachable from a Today feed module.
//
//  Every route presents a sheet over the feed and owns its own destination.
//

import SwiftUI

enum FeedRoute: Identifiable, Hashable {
    case civicTab
    case editInterests
    /// One upcoming event, opened from its Your Day card. The event travels with
    /// the route so the detail screen paints the facts the card already had before
    /// any network call — there is nothing to re-fetch just to show a title.
    case event(UpcomingEvent)

    nonisolated var id: Self { self }

    /// The sheet this route presents.
    @MainActor
    var destination: AnyView? {
        switch self {
        case .civicTab:
            AnyView(CivicTabDestination())
        case .editInterests:
            AnyView(FeedInterestEditorDestination())
        case .event(let event):
            AnyView(FeedEventDetailDestination(event: event))
        }
    }
}
