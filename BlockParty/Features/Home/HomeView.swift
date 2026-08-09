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
    @Binding var expandedPlace: Place?
    var cardNS: Namespace.ID

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        FeedView(
            auth: auth,
            onMenu: onMenu,
            menuOpen: menuOpen,
            profileShown: profileShown
        )
    }
}
