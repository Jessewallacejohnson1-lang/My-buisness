//
//  TabReadiness.swift
//  Hygge — plumbing that lets the root tab shell know when the *current* tab has
//  finished loading, so it can cover a not-yet-rendered tab with `TabLoadingCover`
//  and lift it the instant the tab is ready.
//
//  Each tab's root view publishes its readiness up the tree with `.tabReady(…)`
//  (a SwiftUI preference). `MainTabsView` reads the combined value and hands it to
//  `TabLoadingHost`, which owns the show/hide choreography:
//
//    • appearDelay — a tab that loads faster than this never shows the cover, so a
//      quick switch doesn't flash a loading screen (emil: don't animate the common,
//      fast path).
//    • minVisible — once shown, the cover stays up at least this long, so a tab that
//      finishes a hair later doesn't produce a jarring 1-frame flicker.
//    • the exit is a single Motion.smooth opacity fade — the content is already
//      rendered underneath, so it settles in rather than popping.
//

import SwiftUI

// MARK: - Readiness preference

/// True ⇒ the current tab's content is fully loaded. Defaults to `true` so a tab
/// that never opts in (or an empty tree mid-transition) is treated as ready and
/// shows no cover. Multiple reporters combine with AND — not ready until all are.
struct TabReadyPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

extension View {
    /// Publish this view's tab-readiness to the root shell. Call once on a tab's
    /// root, e.g. `.tabReady(model.loaded)`.
    func tabReady(_ ready: Bool) -> some View {
        preference(key: TabReadyPreferenceKey.self, value: ready)
    }
}

// MARK: - Host / choreography

struct TabLoadingHost: View {
    /// Readiness of the active tab (from `TabReadyPreferenceKey`).
    let isReady: Bool
    /// Identity of the active tab. A change re-arms the timing for the new tab.
    let resetKey: AnyHashable
    var title: String = "Just a second"

    // The branded rainbow cover is reserved for genuinely long waits — first
    // sign-in, a cold boot, a network stall — NOT routine tab switches (those get
    // the per-tab skeleton instead). So the cover only appears once a load has run
    // past `appearDelay` (~3s); anything faster is handled entirely by the skeleton
    // underneath and never sees this screen. Once shown it holds `minVisible` so it
    // can't flicker, and the exit is quicker than the entrance.
    private static let appearDelay: Duration = .seconds(3)
    private static let minVisible: TimeInterval = 0.5
    /// Hard cap: if readiness never arrives (a failed load whose model can't report
    /// ready, e.g. an offline Mapbox style that never paints), lift the cover anyway
    /// so it can't hang forever and mask the tab's own error state.
    private static let maxVisible: Duration = .seconds(6)
    private static let enter: Animation = .smooth(duration: 0.30)
    private static let exit: Animation = .easeOut(duration: 0.22)

    @State private var showing = false
    @State private var shownAt: Date?

    var body: some View {
        ZStack {
            if showing {
                TabLoadingCover(title: title)
                    .transition(.opacity)
            }
        }
        .task(id: Gate(ready: isReady, key: resetKey)) { await run() }
    }

    /// task(id:) restarts (cancelling the prior run) whenever readiness OR the tab
    /// changes — that cancellation is what makes the appear-delay race safe.
    private struct Gate: Equatable { let ready: Bool; let key: AnyHashable }

    @MainActor private func run() async {
        if isReady {
            guard showing else { showing = false; return }
            let elapsed = Date().timeIntervalSince(shownAt ?? Date())
            let remaining = Self.minVisible - elapsed
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                if Task.isCancelled { return }
            }
            withAnimation(Self.exit) { showing = false }
        } else {
            try? await Task.sleep(for: Self.appearDelay)
            if Task.isCancelled { return }
            shownAt = Date()
            withAnimation(Self.enter) { showing = true }
            AccessibilityNotification.Announcement(title).post()
            // Safety net — force-lift if readiness never comes (see `maxVisible`).
            try? await Task.sleep(for: Self.maxVisible)
            if Task.isCancelled { return }
            withAnimation(Self.exit) { showing = false }
        }
    }
}
