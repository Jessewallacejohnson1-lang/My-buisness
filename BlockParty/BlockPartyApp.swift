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
            RootView()
                .environmentObject(auth)
                .task { await auth.restore() }
                .task { await PlaceSeeder.seedIfRequested() }   // DEBUG: -seed-places one-time POI seed
        }
    }
}
