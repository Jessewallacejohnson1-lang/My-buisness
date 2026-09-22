//
//  DailyView.swift
//  Block Party — the social feed in a scroll of its own.
//
//  The feed itself LIVES IN THE TOWN TAB, inside `FeedView`'s scroll under
//  `TodayTopBar` — see `DailyFeedColumn`. This wrapper exists so the column can be
//  mounted full-screen from a launch flag with no bar, no auth and no network.
//

import SwiftUI

struct DailyView: View {
    var items: [DailyFeedItem]

    @State private var now = Date()

    /// What the feed shows today.
    ///
    /// There is no backend for it yet, so a release build gets an empty array and
    /// lands on the empty state — which is the truth, and reads as onboarding
    /// rather than as breakage. DEBUG gets the fixtures. When the reads exist, this
    /// is the one property that changes.
    static var currentItems: [DailyFeedItem] {
        #if DEBUG
        return DailyFixtures.all()
        #else
        return []
        #endif
    }

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                DailyFeedColumn(items: items, now: now)

                // Clears the floating tab bar, which is a ZStack sibling rather than
                // a safe-area inset — the same 96 the other tab scrollers reserve.
                Color.clear.frame(height: 96)
            }
            .refreshable { now = Date() }
        }
    }
}

#if DEBUG
/// `-daily-feed-preview` — the feed full-screen over fixtures, no auth, no network.
///
/// Pair with `-daily-feed-state mixed|postings|events|empty`. The state argument is
/// not a convenience: this setup can drive no scroll, so without it only whatever
/// the ranker puts first is ever reachable for a screenshot.
struct DailyFeedPreview: View {
    var body: some View {
        DailyView(items: Self.items)
    }

    private static var items: [DailyFeedItem] {
        switch Self.state {
        case "postings": return DailyFixtures.postings().map { .posting($0) }
        case "events":   return DailyFixtures.events()
        case "empty":    return []
        default:         return DailyFixtures.all()
        }
    }

    private static var state: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-daily-feed-state"), i + 1 < args.count
        else { return "mixed" }
        return args[i + 1]
    }
}
#endif
