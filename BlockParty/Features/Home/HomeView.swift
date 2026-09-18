//
//  HomeView.swift
//  Block Party — compatibility shell for the Today tab.
//
//  MainTabsView and the DEBUG briefing preview keep their established HomeView
//  entry point. The actual screen composition, loading, reveal, analytics, and
//  refresh behavior now live in FeedView behind the module registry.
//

import SwiftUI

struct HomeView: View {
    var onCompose: (() -> Void)?
    var onMenu: (() -> Void)?
    var menuOpen = false
    var profileShown = false
    /// The Today top bar's map button — passed straight through to the shell, which
    /// owns the map presentation. A no-op in the DEBUG briefing preview, which mounts
    /// this screen with no shell above it.
    ///
    /// Declared HERE, where `onOpenActivities` used to sit: `RootView` calls the
    /// memberwise init positionally, and Swift requires declaration order.
    var onOpenMap: () -> Void = {}
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        FeedView(
            auth: auth,
            onOpenMap: onOpenMap,
            profileShown: profileShown
        )
    }
}
