//
//  HomeView.swift
//  Block Party — compatibility shell for the Town tab.
//
//  MainTabsView keeps its established HomeView entry point. The screen itself —
//  loading, refresh and the top bar — lives in FeedView.
//

import SwiftUI

struct HomeView: View {
    /// The Town top bar's map button — passed straight through to the shell, which
    /// owns the map presentation.
    var onOpenMap: () -> Void = {}
    /// The bar's other two controls, added 2026-09-20 alongside the map.
    var onOpenFriends: () -> Void = {}
    var onOpenNotifications: () -> Void = {}
    /// The wordmark's menu: the Town's own page or its City's (follows 04).
    var onOpenPage: (TownPageKind) -> Void = { _ in }
    /// The shell's Town feed, kept across tab switches.
    var townFeed: TownFeed
    /// The shell's Event of the day, Daily's, on top of the feed (BP app event-card 03).
    var eventOfTheDay: EventOfTheDay
    /// Search's places, for the feed's places to try (town-feed 23).
    var places: (String) -> SearchItem? = { _ in nil }

    var body: some View {
        FeedView(
            onOpenFriends: onOpenFriends,
            onOpenMap: onOpenMap,
            onOpenNotifications: onOpenNotifications,
            onOpenPage: onOpenPage,
            townFeed: townFeed,
            eventOfTheDay: eventOfTheDay,
            places: places
        )
    }
}
