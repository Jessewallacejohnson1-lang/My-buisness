//
//  TownFeedScroll.swift
//  Block Party — the social feed in a scroll of its own.
//
//  The feed itself LIVES IN THE TOWN TAB, inside `TownView`'s scroll under
//  `TownBar` — see `TownFeedColumn`. This wrapper exists so the column can be
//  mounted full-screen from a launch flag with no bar, no auth and no network.
//

import SwiftUI

struct TownFeedScroll: View {
    var items: [TownFeedItem]

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                TownFeedColumn(items: items)

                // Clears the floating tab bar, which is a ZStack sibling rather than
                // a safe-area inset — the same 96 the other tab scrollers reserve.
                Color.clear.frame(height: 96)
            }
        }
    }
}

#if DEBUG
/// `-town-feed-preview` — the feed full-screen over fixtures, no auth, no network.
///
/// Pair with `-town-feed-state mixed|postings|events|empty`. The state argument is
/// not a convenience: this setup can drive no scroll, so without it only what comes
/// first is ever reachable for a screenshot.
struct TownFeedPreview: View {
    var body: some View {
        TownFeedScroll(items: Self.items)
    }

    private static var items: [TownFeedItem] {
        switch Self.state {
        case "postings": return TownFixtures.postings().map { .posting($0) }
        case "events":   return TownFixtures.events()
        case "empty":    return []
        default:         return TownFixtures.all()
        }
    }

    private static var state: String {
        LaunchFlags.value(.townFeedState) ?? "mixed"
    }
}
#endif
