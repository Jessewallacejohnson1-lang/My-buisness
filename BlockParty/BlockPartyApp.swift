//
//  BlockPartyApp.swift
//  Block Party — a hyper-local community app for St. Joseph, MN.
//
//  Native SwiftUI build, ported from the Expo / React Native app.
//

import SwiftUI
import MapboxMaps

@main
struct BlockPartyApp: App {
    @StateObject private var auth = AuthStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        registerBlockPartyFonts()
        MapboxOptions.accessToken = MAPBOX_ACCESS_TOKEN
        // A PostgREST 401 (token rejected server-side) refreshes the session, or
        // signs out and routes back to Login if the refresh token is dead too —
        // instead of the user silently retrying a dead token forever.
        SupabaseHTTP.onUnauthorized = {
            Task { @MainActor in await AuthStore.shared.handleUnauthorized() }
        }
    }

    var body: some Scene {
        WindowGroup {
            // No launch splash since 2026-09-18 (Jesse's call): the window shows the
            // real destination on the first frame, and session restore swaps Login
            // for the tabs underneath it.
            RootView()
                .environmentObject(auth)
                .task {
                    await auth.restore()
                    // The quiet anonymous account, made only once restore has found
                    // there is no stored session.
                    await auth.ensureAccount()
                }
                .task { await PlaceSeeder.seedIfRequested() }   // DEBUG: -seed-places one-time POI seed
        }
        .onChange(of: scenePhase) { _, phase in
            // Offline at first launch: try again when the app comes back.
            if phase == .active { Task { await auth.ensureAccount() } }
        }
    }
}
