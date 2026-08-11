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
    /// A feed route that leaves the Today tab — passed straight through to the shell,
    /// which owns tab selection. Nil in the DEBUG briefing preview, which mounts this
    /// screen with no tab shell above it.
    var onOpenActivities: ((ActivitiesRequest) -> Void)?
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        FeedView(
            auth: auth,
            onMenu: onMenu,
            menuOpen: menuOpen,
            profileShown: profileShown,
            onOpenActivities: onOpenActivities
        )
    }
}
